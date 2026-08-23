import 'package:cloud_firestore/cloud_firestore.dart';
import 'reporte_repository.dart';
import 'reporte_financiero_model.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';
import 'historico_venta_service.dart';
import '../../ventas/data/item_venta_model.dart';
import '../../compras/data/item_compra_model.dart';
import '../../productos/data/producto_model.dart';
import '../../egresos/data/egreso_repository.dart';
import '../../egresos/data/egreso_model.dart';
import '../../compras_credito/data/compra_credito_repository.dart';
import '../../compras_credito/data/abono_compra_model.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';
import '../../ventas_credito/data/abono_model.dart';
import '../../caja/data/cierre_caja_repository.dart';
import '../../compras_credito/data/compra_credito_model.dart';
import '../../clientes/data/cliente_model.dart';

/// Cuánto del efectivo estimado se sugiere reservar como colchón de
/// seguridad antes de recomendar pagos a proveedores.
const _colchonSeguridadPorcentaje = 0.20;

/// Porcentaje del efectivo cobrado en el periodo que, como referencia
/// alternativa, se sugiere destinar a pagos a proveedores.
const _porcentajeVentasParaProveedores = 0.35;

const _topN = 10;

/// Días sin comprar a partir de los cuales un cliente activo se considera
/// inactivo (CRM Fase 3). El script de Node que manda el reporte por
/// WhatsApp (tool/reporte_whatsapp/reporte.js) mirra este mismo número a
/// mano -mantenerlos sincronizados si este valor cambia-.
const _diasUmbralClienteInactivo = 90;

/// Detalle de ventas/compras agrupado por id de documento padre, resuelto
/// desde una sola query de collectionGroup (ver [ReporteFinancieroRepository._detallePorRango]).
typedef _DetalleRapido = ({Map<String, List<ItemVentaModel>> ventas, Map<String, List<ItemCompraModel>> compras});

class ReporteFinancieroRepository {
  final _db = FirebaseFirestore.instance;
  final _reporteRepository = ReporteRepository();
  final _egresoRepository = EgresoRepository();
  final _compraCreditoRepository = CompraCreditoRepository();
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _cierreCajaRepository = CierreCajaRepository();
  final _historicoService = HistoricoVentaService();

  // La serie mensual y el efectivo estimado no dependen del rango que el
  // usuario elija en el reporte (son "últimos 6 meses" y "desde el último
  // cierre de caja" respectivamente), así que antes se recalculaban desde
  // cero en cada búsqueda aunque el usuario solo hubiera cambiado el rango
  // principal. Se cachean un rato corto para no repetir esas consultas.
  static const _vigenciaCache = Duration(minutes: 5);
  List<PuntoMensual>? _serieMensualCache;
  DateTime? _serieMensualCacheEn;
  double? _efectivoEstimadoCache;
  DateTime? _efectivoEstimadoCacheEn;

  Future<List<ItemVentaModel>> _detalleVenta(ReporteVentaModel venta) async {
    if (venta.esHistorica) return _historicoService.obtenerDetalleDeVenta(venta.id);
    final snap = await _db.collection('ventas').doc(venta.id).collection('detalle').get();
    return snap.docs.map((d) => ItemVentaModel.fromMap(d.data())).toList();
  }

  Future<List<ItemCompraModel>> _detalleCompra(String idCompra) async {
    final snap = await _db.collection('compras').doc(idCompra).collection('detalle').get();
    return snap.docs.map((d) => ItemCompraModel.fromMap(d.data())).toList();
  }

  /// Trae en una sola consulta (collectionGroup sobre 'detalle', filtrado por
  /// el campo 'fecha' que se guarda en cada línea) el detalle de todas las
  /// ventas y compras del rango, evitando leer la subcolección de cada
  /// documento uno por uno. Si el rango toca fechas del sistema anterior
  /// (antes del 2026-07-17), se le agrega también ese detalle histórico en
  /// una sola llamada al Worker — mismo criterio, sin N llamadas.
  Future<_DetalleRapido> _detallePorRango(DateTime inicio, DateTime finInclusive) async {
    final snapFuture = _db
        .collectionGroup('detalle')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .get();
    final historicoFuture = _historicoService.obtenerDetallePorRango(inicio, finInclusive);

    final snap = await snapFuture;
    final porVenta = <String, List<ItemVentaModel>>{};
    final porCompra = <String, List<ItemCompraModel>>{};
    for (final doc in snap.docs) {
      final docPadre = doc.reference.parent.parent;
      if (docPadre == null) continue;
      final coleccionRaiz = docPadre.parent.id;
      if (coleccionRaiz == 'ventas') {
        porVenta.putIfAbsent(docPadre.id, () => []).add(ItemVentaModel.fromMap(doc.data()));
      } else if (coleccionRaiz == 'compras') {
        porCompra.putIfAbsent(docPadre.id, () => []).add(ItemCompraModel.fromMap(doc.data()));
      }
    }
    porVenta.addAll(await historicoFuture);
    return (ventas: porVenta, compras: porCompra);
  }

  /// Junta el detalle rápido con un respaldo documento-por-documento solo
  /// para los que quedaron fuera (registrados antes de que 'detalle'
  /// empezara a guardar su propia fecha, o ventas históricas que por algún
  /// motivo no vinieron en el bloque de `_detallePorRango`). A medida que
  /// pase el tiempo esta lista de respaldo se vuelve vacía.
  Future<List<List<ItemVentaModel>>> _resolverDetalleVentas(List<ReporteVentaModel> ventas, Map<String, List<ItemVentaModel>> rapido) async {
    final faltantes = ventas.where((v) => !rapido.containsKey(v.id)).toList();
    final detalleFaltante = await Future.wait(faltantes.map((v) => _detalleVenta(v)));
    final porId = {for (var i = 0; i < faltantes.length; i++) faltantes[i].id: detalleFaltante[i]};
    return [for (final v in ventas) rapido[v.id] ?? porId[v.id] ?? const []];
  }

  Future<List<List<ItemCompraModel>>> _resolverDetalleCompras(List<ReporteCompraModel> compras, Map<String, List<ItemCompraModel>> rapido) async {
    final faltantes = compras.where((c) => !rapido.containsKey(c.id)).toList();
    final detalleFaltante = await Future.wait(faltantes.map((c) => _detalleCompra(c.id)));
    final porId = {for (var i = 0; i < faltantes.length; i++) faltantes[i].id: detalleFaltante[i]};
    return [for (final c in compras) rapido[c.id] ?? porId[c.id] ?? const []];
  }

  Future<double> _efectivoEstimado() async {
    final cacheEn = _efectivoEstimadoCacheEn;
    if (_efectivoEstimadoCache != null && cacheEn != null && DateTime.now().difference(cacheEn) < _vigenciaCache) {
      return _efectivoEstimadoCache!;
    }
    final estado = await _cierreCajaRepository.obtenerEstadoCaja();
    final hoy = DateTime.now();
    final finInclusive = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59);
    final totales = await _cierreCajaRepository.calcularTotales(estado.fechaDesde, finInclusive);
    final resultado = estado.montoInicial + totales.ingresosEfectivo - totales.egresosEfectivo;
    _efectivoEstimadoCache = resultado;
    _efectivoEstimadoCacheEn = DateTime.now();
    return resultado;
  }

  /// Reconstruye el flujo de efectivo con datos que ya se pidieron para el
  /// resto del reporte, en vez de recalcular todo el libro financiero de
  /// nuevo (mismo criterio que `CierreCajaRepository.calcularTotales`).
  FlujoEfectivo _calcularFlujo({
    required List<ReporteVentaModel> ventasContado,
    required List<ReporteCompraModel> comprasContado,
    required List<AbonoModel> abonosVenta,
    required List<AbonoCompraModel> abonosCompra,
    required List<EgresoModel> egresos,
  }) {
    double ingresosEfectivo = 0, ingresosTarjeta = 0, ingresosTransferencia = 0;
    double egresosEfectivo = 0, egresosTransferencia = 0;

    void sumarIngreso(String metodoPago, double monto) {
      switch (metodoPago) {
        case 'Efectivo':
          ingresosEfectivo += monto;
          break;
        case 'Tarjeta':
          ingresosTarjeta += monto;
          break;
        case 'Transferencia':
          ingresosTransferencia += monto;
          break;
      }
    }

    void sumarEgreso(String metodoPago, double monto) {
      switch (metodoPago) {
        case 'Efectivo':
          egresosEfectivo += monto;
          break;
        case 'Transferencia':
          egresosTransferencia += monto;
          break;
      }
    }

    for (final v in ventasContado) {
      if (v.metodoPago == 'Mixto' && v.pagosMixtos.isNotEmpty) {
        for (final pago in v.pagosMixtos) {
          sumarIngreso(pago.metodoPago, pago.monto);
        }
      } else {
        sumarIngreso(v.metodoPago, v.totalAPagar);
      }
    }
    for (final c in comprasContado) {
      sumarEgreso(c.metodoPago, c.montoTotal);
    }
    for (final a in abonosVenta) {
      sumarIngreso(a.metodoPago, a.montoAbonado);
    }
    for (final a in abonosCompra) {
      sumarEgreso(a.metodoPago, a.montoAbonado);
    }
    for (final e in egresos) {
      sumarEgreso(e.metodoPago, e.monto);
    }

    return FlujoEfectivo(
      ingresosEfectivo: ingresosEfectivo,
      ingresosTarjeta: ingresosTarjeta,
      ingresosTransferencia: ingresosTransferencia,
      egresosEfectivo: egresosEfectivo,
      egresosTransferencia: egresosTransferencia,
    );
  }

  Future<ReporteFinancieroData> obtenerReporte(DateTime inicio, DateTime finInclusive) async {
    // Todo lo que no depende de nada más se dispara en paralelo de una vez;
    // recién se espera por cada resultado donde hace falta.
    final ventasHeadersFuture = _reporteRepository.obtenerReporteVentas(inicio, finInclusive);
    final comprasHeadersFuture = _reporteRepository.obtenerReporteCompras(inicio, finInclusive);
    final detalleRapidoFuture = _detallePorRango(inicio, finInclusive);
    final egresosPeriodoFuture = _egresoRepository.obtenerEgresosPorRango(inicio, finInclusive);
    final abonosVentaFuture = _ventaCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive);
    final abonosCompraFuture = _compraCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive);
    final productosFuture = _db.collection('productos').get();
    // Solo interesan para sumar saldoPendiente (cuentas por cobrar/pagar), así
    // que se filtran del lado del servidor los créditos ya saldados en vez de
    // traer la colección completa (con historial largo, la mayoría termina
    // pagada) y descartarlos recién en el cliente.
    final ventasCreditoFuture = _db.collection('ventasCredito').where('saldoPendiente', isGreaterThan: 0).get();
    final comprasCreditoFuture = _db.collection('comprasCredito').where('saldoPendiente', isGreaterThan: 0).get();
    final serieMensualFuture = _obtenerSerieMensual();
    final efectivoEstimadoFuture = _efectivoEstimado();
    final hace3Meses = DateTime(DateTime.now().year, DateTime.now().month - 2, 1);
    final egresosUltimos3MesesFuture = _egresoRepository.obtenerEgresosPorRango(hace3Meses, DateTime.now());
    // Solo clientes activos: un cliente inactivo (estado=false, ya dado de
    // baja) no tiene sentido incluirlo en "clientes inactivos" -eso es para
    // clientes vigentes que se dejaron de aparecer, no para los ya dados de
    // baja a propósito-. Filtro simple de un solo campo, sin índice extra.
    final clientesActivosFuture = _db.collection('clientes').where('estado', isEqualTo: true).get();

    final ventasHeaders = await ventasHeadersFuture;
    final comprasHeaders = await comprasHeadersFuture;
    final detalleRapido = await detalleRapidoFuture;
    final egresosPeriodo = await egresosPeriodoFuture;
    final abonosVenta = await abonosVentaFuture;
    final abonosCompra = await abonosCompraFuture;
    final productosSnap = await productosFuture;
    final ventasCreditoSnap = await ventasCreditoFuture;
    final comprasCreditoSnap = await comprasCreditoFuture;
    final serieMensual = await serieMensualFuture;
    final efectivoEstimado = await efectivoEstimadoFuture;
    final egresosUltimos3Meses = await egresosUltimos3MesesFuture;
    final clientesActivosSnap = await clientesActivosFuture;

    final ventasValidas = ventasHeaders.where((v) => v.esActiva && !v.esCotizacion).toList();
    final comprasValidas = comprasHeaders.where((c) => c.esActiva).toList();

    final detalleVentasPorVenta = await _resolverDetalleVentas(ventasValidas, detalleRapido.ventas);
    final detalleComprasPorCompra = await _resolverDetalleCompras(comprasValidas, detalleRapido.compras);
    final itemsVenta = detalleVentasPorVenta.expand((items) => items).toList();
    final itemsCompra = detalleComprasPorCompra.expand((items) => items).toList();

    final gananciaPorVenta = <GananciaPorVenta>[
      for (var i = 0; i < ventasValidas.length; i++)
        GananciaPorVenta(
          idVenta: ventasValidas[i].id,
          numeroDocumento: ventasValidas[i].numeroDocumento,
          fecha: ventasValidas[i].fechaRegistro,
          cliente: ventasValidas[i].nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : ventasValidas[i].nombreCliente,
          ventas: ventasValidas[i].totalAPagar,
          // El costo de tinte real (ver ItemVentaModel.costoTinteTotal) se
          // suma SEPARADO de precioCompraUsado -pedido explícito del dueño:
          // "quiero ver el costo de tinte separado, no mezclado"- pero acá
          // sí entra en el total de costo/ganancia de la venta, igual que
          // cualquier otro costo real.
          costo: detalleVentasPorVenta[i].fold<double>(0, (s, item) => s + item.precioCompraUsado * item.cantidad + item.costoTinteTotal),
        ),
    ]..sort((a, b) => (b.fecha ?? DateTime(2000)).compareTo(a.fecha ?? DateTime(2000)));

    final ventasPeriodo = ventasValidas.fold<double>(0, (s, v) => s + v.totalAPagar);
    final comprasPeriodo = comprasValidas.fold<double>(0, (s, c) => s + c.montoTotal);
    final costoVentas = itemsVenta.fold<double>(0, (s, i) => s + i.precioCompraUsado * i.cantidad + i.costoTinteTotal);
    final utilidadBruta = ventasPeriodo - costoVentas;

    final gastosPeriodo = egresosPeriodo.fold<double>(0, (s, e) => s + e.monto);
    final utilidadNeta = utilidadBruta - gastosPeriodo;

    final flujoEfectivo = _calcularFlujo(
      ventasContado: ventasValidas.where((v) => v.condicion == 'Contado').toList(),
      comprasContado: comprasValidas.where((c) => c.condicion != 'Credito').toList(),
      abonosVenta: abonosVenta,
      abonosCompra: abonosCompra,
      egresos: egresosPeriodo,
    );

    final topVendidosPorCantidad = _rankearPorCantidad(itemsVenta.map((i) => (i.idProducto, i.nombreProducto, i.cantidad)));
    final topCompradosPorCantidad = _rankearPorCantidad(itemsCompra.map((i) => (i.idProducto, i.nombreProducto, i.cantidad)));
    final topGananciaPorProducto = _rankearGanancia(itemsVenta);

    final productos = productosSnap.docs.map((d) => ProductoModel.fromMap(d.id, d.data())).toList();
    final idsConVenta = itemsVenta.map((i) => i.idProducto).toSet();
    final productosSinVenta = productos
        .where((p) => p.estado && !idsConVenta.contains(p.id))
        .map((p) => ProductoSinVenta(idProducto: p.id, nombreProducto: p.nombre, stock: p.stock, valorInventario: p.stock * p.precioCompra))
        .toList()
      ..sort((a, b) => b.valorInventario.compareTo(a.valorInventario));
    final inventarioACosto = productos.where((p) => p.estado).fold<double>(0, (s, p) => s + p.stock * p.precioCompra);

    final ventasPorUsuario = _agruparPorUsuario(ventasValidas);

    final totalAbonosComprasCredito = abonosCompra.fold<double>(0, (s, a) => s + a.montoAbonado);
    final abonosPorProveedor = _agruparAbonosPorProveedor(abonosCompra);

    final reservaGastosFijos = egresosUltimos3Meses.fold<double>(0, (s, e) => s + e.monto) / 3;
    final colchon = efectivoEstimado * _colchonSeguridadPorcentaje;
    final sugeridoPorCaja = (efectivoEstimado - reservaGastosFijos - colchon).clamp(0, double.infinity).toDouble();
    final sugeridoPorVentas = flujoEfectivo.ingresosEfectivo * _porcentajeVentasParaProveedores;

    final recomendacionPago = RecomendacionPago(
      efectivoEstimado: efectivoEstimado,
      reservaGastosFijos: reservaGastosFijos,
      sugeridoPorCaja: sugeridoPorCaja,
      ingresoEfectivoCobrado: flujoEfectivo.ingresosEfectivo,
      sugeridoPorVentas: sugeridoPorVentas,
    );

    final cuentasPorCobrar = ventasCreditoSnap.docs.fold<double>(0, (s, d) => s + ((d.data()['saldoPendiente'] ?? 0) as num).toDouble().clamp(0, double.infinity));
    final cuentasPorPagar = comprasCreditoSnap.docs.fold<double>(0, (s, d) => s + ((d.data()['saldoPendiente'] ?? 0) as num).toDouble().clamp(0, double.infinity));

    final balanceGeneral = BalanceGeneral(
      inventarioACosto: inventarioACosto,
      cuentasPorCobrar: cuentasPorCobrar,
      efectivoEstimado: efectivoEstimado,
      cuentasPorPagar: cuentasPorPagar,
    );

    final diasPeriodo = (finInclusive.difference(inicio).inHours / 24).ceil().clamp(1, 100000);
    final inteligenciaNegocio = InteligenciaNegocioData(
      pronosticoVentas: _calcularPronostico(serieMensual),
      sugerenciasCompra: _calcularSugerenciasCompra(
        productos: productos,
        itemsVenta: itemsVenta,
        comprasValidas: comprasValidas,
        detalleComprasPorCompra: detalleComprasPorCompra,
        comprasCreditoDocs: comprasCreditoSnap.docs,
        diasPeriodo: diasPeriodo,
      ),
      rotacionInventario: inventarioACosto <= 0 ? 0 : costoVentas / inventarioACosto,
      clientesTop: _agruparClientesTop(ventasValidas),
      ticketPromedio: ventasValidas.isEmpty ? 0 : ventasPeriodo / ventasValidas.length,
      valorStockMuerto: productosSinVenta.fold<double>(0, (s, p) => s + p.valorInventario),
      ventasNoRegistradas: _agruparVentasSinCliente(ventasValidas),
      clientesInactivos: _calcularClientesInactivos(clientesActivosSnap.docs.map((d) => ClienteModel.fromMap(d.id, d.data())).toList()),
    );

    return ReporteFinancieroData(
      inicio: inicio,
      fin: finInclusive,
      ventasPeriodo: ventasPeriodo,
      comprasPeriodo: comprasPeriodo,
      costoVentas: costoVentas,
      utilidadBruta: utilidadBruta,
      gastosPeriodo: gastosPeriodo,
      utilidadNeta: utilidadNeta,
      flujoEfectivo: flujoEfectivo,
      serieMensual: serieMensual,
      gananciaPorVenta: gananciaPorVenta,
      topVendidosPorCantidad: topVendidosPorCantidad,
      topCompradosPorCantidad: topCompradosPorCantidad,
      topGananciaPorProducto: topGananciaPorProducto,
      productosSinVenta: productosSinVenta,
      ventasPorUsuario: ventasPorUsuario,
      totalAbonosComprasCredito: totalAbonosComprasCredito,
      abonosPorProveedor: abonosPorProveedor,
      recomendacionPago: recomendacionPago,
      balanceGeneral: balanceGeneral,
      inteligenciaNegocio: inteligenciaNegocio,
    );
  }

  /// Regresión lineal simple (mínimos cuadrados) sobre la serie mensual ya
  /// calculada para "Comparación Mensual", proyectando un mes más. Con
  /// menos de 3 puntos la pendiente no es confiable, así que se usa
  /// directamente el promedio como estimado.
  PronosticoVentas _calcularPronostico(List<PuntoMensual> serie) {
    final montos = serie.map((p) => p.totalVentas).toList();
    final promedio = montos.isEmpty ? 0.0 : montos.reduce((a, b) => a + b) / montos.length;
    if (montos.length < 3) {
      return PronosticoVentas(montoEstimado: promedio, promedioUltimosMeses: promedio, tendenciaMensual: 0, metodo: 'Promedio simple');
    }
    final n = montos.length;
    final xs = List<int>.generate(n, (i) => i);
    final mediaX = xs.reduce((a, b) => a + b) / n;
    final mediaY = promedio;
    var numerador = 0.0;
    var denominador = 0.0;
    for (var i = 0; i < n; i++) {
      numerador += (xs[i] - mediaX) * (montos[i] - mediaY);
      denominador += (xs[i] - mediaX) * (xs[i] - mediaX);
    }
    final pendiente = denominador == 0 ? 0.0 : numerador / denominador;
    final interseccion = mediaY - pendiente * mediaX;
    final estimado = (pendiente * n + interseccion).clamp(0, double.infinity).toDouble();
    return PronosticoVentas(montoEstimado: estimado, promedioUltimosMeses: promedio, tendenciaMensual: pendiente, metodo: 'Regresión lineal (últimos $n meses)');
  }

  /// Cuánta deuda vencida (y total) tiene cada proveedor ahora mismo, para
  /// no sugerir comprarle más a uno que ya está muy atrasado. Reusa los
  /// mismos documentos de `comprasCredito` con saldo pendiente que ya se
  /// pidieron para el Balance General — no dispara consultas nuevas.
  Map<String, ({double vencida, double total})> _estadoCuentaPorProveedor(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final resultado = <String, ({double vencida, double total})>{};
    for (final doc in docs) {
      final credito = CompraCreditoModel.fromMap(doc.id, doc.data());
      if (credito.idProveedor.isEmpty) continue;
      final actual = resultado[credito.idProveedor] ?? (vencida: 0.0, total: 0.0);
      resultado[credito.idProveedor] = (
        vencida: actual.vencida + (credito.vencida ? credito.saldoPendiente : 0),
        total: actual.total + credito.saldoPendiente,
      );
    }
    return resultado;
  }

  /// Productos activos cuyo stock, a la velocidad de venta que tuvieron en
  /// el rango del reporte, se agotaría pronto (menos de [_diasUmbralReposicion]
  /// días). Se pondera con el estado de cuenta del proveedor más reciente
  /// conocido para cada producto (la compra más nueva del rango que lo
  /// incluya). Todo con datos ya pedidos para el resto del reporte.
  static const _diasUmbralReposicion = 14;

  List<SugerenciaCompra> _calcularSugerenciasCompra({
    required List<ProductoModel> productos,
    required List<ItemVentaModel> itemsVenta,
    required List<ReporteCompraModel> comprasValidas,
    required List<List<ItemCompraModel>> detalleComprasPorCompra,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> comprasCreditoDocs,
    required int diasPeriodo,
  }) {
    // Proveedor más reciente conocido por producto: comprasValidas ya viene
    // ordenado de más nueva a más vieja (ver ReporteRepository.obtenerReporteCompras),
    // así que la primera compra que mencione un producto es la más reciente.
    final proveedorPorProducto = <String, (String idProveedor, String nombre)>{};
    for (var i = 0; i < comprasValidas.length && i < detalleComprasPorCompra.length; i++) {
      final compra = comprasValidas[i];
      if (compra.idProveedor.isEmpty) continue;
      for (final item in detalleComprasPorCompra[i]) {
        proveedorPorProducto.putIfAbsent(item.idProducto, () => (compra.idProveedor, compra.razonSocial));
      }
    }

    final estadoProveedores = _estadoCuentaPorProveedor(comprasCreditoDocs);

    final cantidadVendidaPorProducto = <String, double>{};
    for (final item in itemsVenta) {
      cantidadVendidaPorProducto[item.idProducto] = (cantidadVendidaPorProducto[item.idProducto] ?? 0) + item.cantidad;
    }

    final sugerencias = <SugerenciaCompra>[];
    for (final producto in productos) {
      if (!producto.estado) continue;
      final vendida = cantidadVendidaPorProducto[producto.id];
      if (vendida == null || vendida <= 0) continue;
      final ventaDiaria = vendida / diasPeriodo;
      if (ventaDiaria <= 0) continue;
      final diasParaAgotarse = producto.stock / ventaDiaria;
      if (diasParaAgotarse >= _diasUmbralReposicion) continue;

      final proveedorInfo = proveedorPorProducto[producto.id];
      final estado = proveedorInfo == null ? null : estadoProveedores[proveedorInfo.$1];

      sugerencias.add(SugerenciaCompra(
        idProducto: producto.id,
        nombreProducto: producto.nombre,
        stockActual: producto.stock,
        ventaDiariaPromedio: ventaDiaria,
        diasParaAgotarse: diasParaAgotarse,
        proveedor: proveedorInfo?.$2,
        deudaVencidaProveedor: estado?.vencida ?? 0,
        proveedorAlDia: (estado?.vencida ?? 0) <= 0,
      ));
    }
    sugerencias.sort((a, b) => a.diasParaAgotarse.compareTo(b.diasParaAgotarse));
    return sugerencias.take(_topN).toList();
  }

  /// Agrupa por [ReporteVentaModel.idCliente] (vínculo real, CRM Fase 1)
  /// cuando la venta lo trae; si no -ventas de antes de ese vínculo, o hechas
  /// sin cliente elegido-, cae al agrupamiento anterior por el texto de
  /// nombreCliente (normalizado a mayúsculas/sin espacios de sobra, para no
  /// separar "Juan Perez" de "juan perez " en dos filas distintas). El
  /// nombre que se muestra es el de la primera venta de cada grupo -no hace
  /// falta releer el registro de Clientes solo para esto-.
  List<ClienteTop> _agruparClientesTop(List<ReporteVentaModel> ventas) {
    final totalPorClave = <String, double>{};
    final conteoPorClave = <String, int>{};
    final nombrePorClave = <String, String>{};
    for (final v in ventas) {
      final nombre = v.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : v.nombreCliente;
      if (nombre.toUpperCase() == 'CONSUMIDOR FINAL') continue;
      final idCliente = v.idCliente;
      final clave = (idCliente != null && idCliente.isNotEmpty) ? 'id:$idCliente' : 'nombre:${nombre.trim().toUpperCase()}';
      totalPorClave[clave] = (totalPorClave[clave] ?? 0) + v.totalAPagar;
      conteoPorClave[clave] = (conteoPorClave[clave] ?? 0) + 1;
      nombrePorClave.putIfAbsent(clave, () => nombre);
    }
    final lista = totalPorClave.keys
        .map((clave) => ClienteTop(cliente: nombrePorClave[clave] ?? '', totalComprado: totalPorClave[clave] ?? 0, cantidadCompras: conteoPorClave[clave] ?? 0))
        .toList()
      ..sort((a, b) => b.totalComprado.compareTo(a.totalComprado));
    return lista.take(_topN).toList();
  }

  /// Ventas con un nombre tipeado que no quedó vinculado a un cliente real
  /// (sin idCliente) — agrupadas por nombre normalizado, ordenadas por
  /// frecuencia (no por monto): el objetivo es detectar compradores
  /// frecuentes sin registrar, no a quién más le vendieron una sola vez.
  List<VentaSinCliente> _agruparVentasSinCliente(List<ReporteVentaModel> ventas) {
    final totalPorClave = <String, double>{};
    final conteoPorClave = <String, int>{};
    final nombrePorClave = <String, String>{};
    for (final v in ventas) {
      final idCliente = v.idCliente;
      if (idCliente != null && idCliente.isNotEmpty) continue;
      final nombre = v.nombreCliente.trim();
      if (nombre.isEmpty || nombre.toUpperCase() == 'CONSUMIDOR FINAL') continue;
      final clave = nombre.toUpperCase();
      totalPorClave[clave] = (totalPorClave[clave] ?? 0) + v.totalAPagar;
      conteoPorClave[clave] = (conteoPorClave[clave] ?? 0) + 1;
      nombrePorClave.putIfAbsent(clave, () => nombre);
    }
    final lista = totalPorClave.keys
        .map((clave) => VentaSinCliente(nombre: nombrePorClave[clave] ?? clave, cantidadVentas: conteoPorClave[clave] ?? 0, totalComprado: totalPorClave[clave] ?? 0))
        .toList()
      ..sort((a, b) => b.cantidadVentas.compareTo(a.cantidadVentas));
    return lista.take(_topN).toList();
  }

  /// Clientes activos (ya filtrados por estado=true en la consulta) con más
  /// de [_diasUmbralClienteInactivo] días desde su última compra -o que
  /// nunca han comprado (fechaUltimaCompra null), que también cuentan como
  /// inactivos-. Todo en memoria, sin consulta ni índice adicional (la fecha
  /// de última compra ya viene denormalizada en cada ClienteModel desde CRM
  /// Fase 1 — ver VentaRepository.registrarVenta).
  List<ClienteInactivo> _calcularClientesInactivos(List<ClienteModel> clientesActivos) {
    final ahora = DateTime.now();
    final inactivos = <ClienteInactivo>[];
    for (final c in clientesActivos) {
      final ultimaCompra = c.fechaUltimaCompra;
      if (ultimaCompra == null) {
        inactivos.add(ClienteInactivo(nombreCompleto: c.nombreCompleto, ultimaCompra: null, diasSinComprar: null));
        continue;
      }
      final dias = ahora.difference(ultimaCompra).inDays;
      if (dias > _diasUmbralClienteInactivo) {
        inactivos.add(ClienteInactivo(nombreCompleto: c.nombreCompleto, ultimaCompra: ultimaCompra, diasSinComprar: dias));
      }
    }
    // Los que nunca han comprado van al final: no hay "hace cuántos días" que
    // ordenar ahí, y los más urgentes de recuperar son los que sí compraron
    // pero hace más tiempo.
    inactivos.sort((a, b) {
      if (a.diasSinComprar == null && b.diasSinComprar == null) return 0;
      if (a.diasSinComprar == null) return 1;
      if (b.diasSinComprar == null) return -1;
      return b.diasSinComprar!.compareTo(a.diasSinComprar!);
    });
    return inactivos;
  }

  List<RankingProducto> _rankearPorCantidad(Iterable<(String, String, double)> lineas) {
    final porProducto = <String, RankingProducto>{};
    for (final (idProducto, nombre, cantidad) in lineas) {
      final actual = porProducto[idProducto];
      porProducto[idProducto] = RankingProducto(
        idProducto: idProducto,
        nombreProducto: nombre,
        cantidad: (actual?.cantidad ?? 0) + cantidad,
        monto: 0,
      );
    }
    final lista = porProducto.values.toList()..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return lista.take(_topN).toList();
  }

  List<RankingProducto> _rankearGanancia(List<ItemVentaModel> items) {
    final ingresoPorProducto = <String, double>{};
    final costoPorProducto = <String, double>{};
    final cantidadPorProducto = <String, double>{};
    final nombrePorProducto = <String, String>{};
    for (final item in items) {
      ingresoPorProducto[item.idProducto] = (ingresoPorProducto[item.idProducto] ?? 0) + item.subtotal;
      costoPorProducto[item.idProducto] = (costoPorProducto[item.idProducto] ?? 0) + item.precioCompraUsado * item.cantidad + item.costoTinteTotal;
      cantidadPorProducto[item.idProducto] = (cantidadPorProducto[item.idProducto] ?? 0) + item.cantidad;
      nombrePorProducto[item.idProducto] = item.nombreProducto;
    }
    final lista = ingresoPorProducto.keys
        .map((id) => RankingProducto(
              idProducto: id,
              nombreProducto: nombrePorProducto[id] ?? '',
              cantidad: cantidadPorProducto[id] ?? 0,
              monto: (ingresoPorProducto[id] ?? 0) - (costoPorProducto[id] ?? 0),
            ))
        .toList()
      ..sort((a, b) => b.monto.compareTo(a.monto));
    return lista.take(_topN).toList();
  }

  List<VentasPorUsuario> _agruparPorUsuario(List<ReporteVentaModel> ventas) {
    final totalPorUsuario = <String, double>{};
    final conteoPorUsuario = <String, int>{};
    for (final v in ventas) {
      final usuario = v.usuarioRegistro.isEmpty ? 'Sin usuario' : v.usuarioRegistro;
      totalPorUsuario[usuario] = (totalPorUsuario[usuario] ?? 0) + v.totalAPagar;
      conteoPorUsuario[usuario] = (conteoPorUsuario[usuario] ?? 0) + 1;
    }
    final lista = totalPorUsuario.keys
        .map((u) => VentasPorUsuario(usuario: u, totalVentas: totalPorUsuario[u] ?? 0, cantidadTransacciones: conteoPorUsuario[u] ?? 0))
        .toList()
      ..sort((a, b) => b.totalVentas.compareTo(a.totalVentas));
    return lista;
  }

  List<AbonoPorProveedor> _agruparAbonosPorProveedor(List<AbonoCompraModel> abonos) {
    final totalPorProveedor = <String, double>{};
    for (final a in abonos) {
      final proveedor = a.nombreProveedor.isEmpty ? 'N/A' : a.nombreProveedor;
      totalPorProveedor[proveedor] = (totalPorProveedor[proveedor] ?? 0) + a.montoAbonado;
    }
    final lista = totalPorProveedor.entries.map((e) => AbonoPorProveedor(proveedor: e.key, total: e.value)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }

  Future<List<PuntoMensual>> _obtenerSerieMensual() async {
    final cacheEn = _serieMensualCacheEn;
    if (_serieMensualCache != null && cacheEn != null && DateTime.now().difference(cacheEn) < _vigenciaCache) {
      return _serieMensualCache!;
    }
    final resultado = await _calcularSerieMensual();
    _serieMensualCache = resultado;
    _serieMensualCacheEn = DateTime.now();
    return resultado;
  }

  Future<List<PuntoMensual>> _calcularSerieMensual() async {
    final hoy = DateTime.now();
    final primerMesDeLaSerie = DateTime(hoy.year, hoy.month - 5, 1);
    final finRango = DateTime(hoy.year, hoy.month + 1, 1).subtract(const Duration(seconds: 1));

    final ventas = await _reporteRepository.obtenerReporteVentas(primerMesDeLaSerie, finRango);
    final compras = await _reporteRepository.obtenerReporteCompras(primerMesDeLaSerie, finRango);
    final ventasValidas = ventas.where((v) => v.esActiva && !v.esCotizacion);
    final comprasValidas = compras.where((c) => c.esActiva);

    final ventasPorMes = <String, double>{};
    for (final v in ventasValidas) {
      final fecha = v.fechaRegistro;
      if (fecha == null) continue;
      final clave = '${fecha.year}-${fecha.month}';
      ventasPorMes[clave] = (ventasPorMes[clave] ?? 0) + v.totalAPagar;
    }
    final comprasPorMes = <String, double>{};
    for (final c in comprasValidas) {
      final fecha = c.fechaRegistro;
      if (fecha == null) continue;
      final clave = '${fecha.year}-${fecha.month}';
      comprasPorMes[clave] = (comprasPorMes[clave] ?? 0) + c.montoTotal;
    }

    final serie = <PuntoMensual>[];
    for (var i = 0; i < 6; i++) {
      final mes = DateTime(primerMesDeLaSerie.year, primerMesDeLaSerie.month + i, 1);
      final clave = '${mes.year}-${mes.month}';
      serie.add(PuntoMensual(mes: mes, totalVentas: ventasPorMes[clave] ?? 0, totalCompras: comprasPorMes[clave] ?? 0));
    }
    return serie;
  }
}
