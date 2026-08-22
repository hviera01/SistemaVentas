import 'package:cloud_firestore/cloud_firestore.dart';
import 'cliente_model.dart';
import 'cliente_historial_model.dart';
import 'cliente_repository.dart';
import '../../ventas/data/venta_model.dart';
import '../../ventas/data/item_venta_model.dart';
import '../../ventas_credito/data/venta_credito_model.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';

/// Cuántas ventas recientes se muestran en Detalle de Cliente (no todo el
/// historial: es una lista para escanear de un vistazo, no un reporte).
const _maxVentasRecientes = 10;
const _maxHistorialColores = 20;
const _maxProductosTop = 3;

/// Todas las consultas para "Detalle de Cliente" (ver DetalleClienteScreen),
/// agregadas en un solo objeto inmutable. Mismo patrón de "disparar todo en
/// paralelo, agregar en Dart" que ReporteFinancieroRepository.
class ClienteHistorialRepository {
  final _db = FirebaseFirestore.instance;
  final _colVentas = FirebaseFirestore.instance.collection('ventas');
  final _colVentasCredito = FirebaseFirestore.instance.collection('ventasCredito');
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _clienteRepository = ClienteRepository();

  Future<ClienteHistorialData> obtener(ClienteModel cliente) async {
    final nombre = cliente.nombreCompleto.trim();
    final dni = cliente.dni.trim();
    final idReferidor = cliente.idReferidor;

    // Todo lo que no depende de nada más se dispara junto.
    final ventasPorIdFuture = _colVentas.where('idCliente', isEqualTo: cliente.id).get();
    final ventasPorNombreFuture = nombre.isEmpty ? null : _colVentas.where('nombreCliente', isEqualTo: nombre).get();
    // Créditos: por idCliente (confiable, el mismo vínculo real que ventas) +
    // respaldo por DNI para créditos viejos que hayan quedado sin idCliente.
    // Antes esto SOLO buscaba por DNI -si el cliente no tenía DNI cargado
    // (frecuente, es un campo opcional), la pantalla de Detalle de Cliente
    // mostraba "no tiene historial de crédito" aunque sí tuviera, como pasó
    // con un cliente real al probarlo-.
    final creditosPorIdFuture = _colVentasCredito.where('idCliente', isEqualTo: cliente.id).get();
    final creditosPorDniFuture = dni.isEmpty || dni == 'N/A' ? null : _colVentasCredito.where('documentoCliente', isEqualTo: dni).get();
    // Historial de códigos de color (y, con los mismos datos, "qué compra
    // más"): un solo collectionGroup por idCliente -ver comentario en
    // VentaRepository.registrarVenta sobre por qué 'idCliente' se guarda en
    // cada línea de 'detalle'-. Solo encuentra líneas de ventas registradas
    // DESPUÉS de que existiera el vínculo real; no hay forma de saber qué
    // colores se usaron en ventas viejas emparejadas solo por nombre.
    final detalleFuture = _db.collectionGroup('detalle').where('idCliente', isEqualTo: cliente.id).get();
    // Quién lo refirió: una sola lectura puntual, no un stream -acá solo
    // hace falta el nombre/teléfono en el momento de abrir la pantalla-. Un
    // referidor es ahora un ClienteModel más (con esReferidor == true, ver
    // fusión del módulo 'referidores' dentro de clientes), así que se
    // resuelve con ClienteRepository.obtenerPorId igual que cualquier otro
    // cliente.
    final referidorFuture = (idReferidor == null || idReferidor.isEmpty) ? null : _clienteRepository.obtenerPorId(idReferidor);

    final ventasPorIdSnap = await ventasPorIdFuture;
    final ventasPorNombreSnap = await ventasPorNombreFuture;
    final creditosPorIdSnap = await creditosPorIdFuture;
    final creditosPorDniSnap = await creditosPorDniFuture;
    final detalleSnap = await detalleFuture;
    final referidor = await referidorFuture;

    // ---- Ventas: por idCliente (confiable) + respaldo por nombre (ventas
    // viejas, de antes del vínculo real) de-duplicadas por id de documento.
    final ventasMap = <String, VentaModel>{};
    final emparejadaSoloPorNombre = <String, bool>{};
    for (final doc in ventasPorIdSnap.docs) {
      ventasMap[doc.id] = VentaModel.fromMap(doc.id, doc.data(), const []);
      emparejadaSoloPorNombre[doc.id] = false;
    }
    var hayEmparejadasPorNombre = false;
    if (ventasPorNombreSnap != null) {
      for (final doc in ventasPorNombreSnap.docs) {
        if (ventasMap.containsKey(doc.id)) continue;
        ventasMap[doc.id] = VentaModel.fromMap(doc.id, doc.data(), const []);
        emparejadaSoloPorNombre[doc.id] = true;
        hayEmparejadasPorNombre = true;
      }
    }

    final ventasValidas = ventasMap.values.where((v) => v.estado == 'Activa' && v.tipoDocumento != 'Cotizacion').toList()
      ..sort((a, b) => (b.fechaRegistro ?? DateTime(2000)).compareTo(a.fechaRegistro ?? DateTime(2000)));

    final creditosMap = <String, VentaCreditoModel>{};
    for (final d in creditosPorIdSnap.docs) {
      creditosMap[d.id] = VentaCreditoModel.fromMap(d.id, d.data());
    }
    if (creditosPorDniSnap != null) {
      for (final d in creditosPorDniSnap.docs) {
        creditosMap.putIfAbsent(d.id, () => VentaCreditoModel.fromMap(d.id, d.data()));
      }
    }
    final creditos = creditosMap.values.toList()
      ..sort((a, b) => (b.fechaRegistro ?? DateTime(2000)).compareTo(a.fechaRegistro ?? DateTime(2000)));

    // ---- Resumen de compras ----
    final totalComprado = ventasValidas.fold<double>(0, (s, v) => s + v.totalAPagar);
    final cantidadCompras = ventasValidas.length;
    final ticketPromedio = cantidadCompras == 0 ? 0.0 : totalComprado / cantidadCompras;
    final fechas = ventasValidas.map((v) => v.fechaRegistro).whereType<DateTime>().toList();
    final primeraCompra = fechas.isEmpty ? null : fechas.reduce((a, b) => a.isBefore(b) ? a : b);
    final ultimaCompra = fechas.isEmpty ? null : fechas.reduce((a, b) => a.isAfter(b) ? a : b);

    final ventasRecientes = ventasValidas
        .take(_maxVentasRecientes)
        .map((v) => VentaResumenCliente(
              id: v.id,
              numeroDocumento: v.numeroDocumento,
              fecha: v.fechaRegistro,
              monto: v.totalAPagar,
              metodoPago: v.metodoPago,
              condicion: v.condicion,
              emparejadaPorNombre: emparejadaSoloPorNombre[v.id] ?? false,
            ))
        .toList();

    // ---- Método de pago preferido (mismo idioma que
    // ReporteFinancieroRepository._agruparPorUsuario: contar y quedarse con
    // el de mayor conteo) ----
    final conteoMetodoPago = <String, int>{};
    for (final v in ventasValidas) {
      final metodo = v.metodoPago.isEmpty ? 'N/A' : v.metodoPago;
      conteoMetodoPago[metodo] = (conteoMetodoPago[metodo] ?? 0) + 1;
    }
    String? metodoPagoPreferido;
    var maxConteoMetodo = 0;
    conteoMetodoPago.forEach((metodo, conteo) {
      if (conteo > maxConteoMetodo) {
        maxConteoMetodo = conteo;
        metodoPagoPreferido = metodo;
      }
    });

    // ---- Códigos de color + "qué compra más" (misma consulta, dos usos) ----
    final numeroDocumentoPorVenta = {for (final v in ventasMap.values) v.id: v.numeroDocumento};
    final lineas = detalleSnap.docs.map((d) {
      final item = ItemVentaModel.fromMap(d.data());
      final fecha = (d.data()['fecha'] as Timestamp?)?.toDate();
      final idVenta = d.reference.parent.parent?.id;
      return (item: item, fecha: fecha, idVenta: idVenta);
    }).toList();

    final historialColores = lineas
        .where((l) => l.item.codigosColor.isNotEmpty)
        .map((l) => ColorHistorialItem(
              fecha: l.fecha,
              nombreProducto: l.item.nombreProducto,
              codigosColor: l.item.codigosColor,
              numeroDocumento: (l.idVenta != null ? numeroDocumentoPorVenta[l.idVenta] : null) ?? '',
            ))
        .toList()
      ..sort((a, b) => (b.fecha ?? DateTime(2000)).compareTo(a.fecha ?? DateTime(2000)));

    final cantidadPorProducto = <String, double>{};
    for (final l in lineas) {
      if (l.item.nombreProducto.isEmpty) continue;
      cantidadPorProducto[l.item.nombreProducto] = (cantidadPorProducto[l.item.nombreProducto] ?? 0) + l.item.cantidad;
    }
    final productosTop = cantidadPorProducto.entries.map((e) => ProductoTopCliente(nombreProducto: e.key, cantidad: e.value)).toList()
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));

    // ---- Puntualidad histórica de crédito: de los abonos de los créditos
    // ya cargados (no dispara una consulta nueva pesada, solo un fetch chico
    // de abonos por cada crédito de este cliente, que normalmente son pocos).
    int? abonosATiempo;
    int? abonosAtrasados;
    if (creditos.isNotEmpty) {
      final abonosPorCredito = await Future.wait(creditos.map((c) => _ventaCreditoRepository.obtenerAbonosUnaVez(c.id)));
      var aTiempo = 0;
      var atrasados = 0;
      for (var i = 0; i < creditos.length; i++) {
        final vencimiento = creditos[i].fechaVencimiento;
        if (vencimiento == null) continue;
        for (final abono in abonosPorCredito[i]) {
          if (abono.fecha == null) continue;
          if (abono.fecha!.isAfter(vencimiento)) {
            atrasados++;
          } else {
            aTiempo++;
          }
        }
      }
      if (aTiempo + atrasados > 0) {
        abonosATiempo = aTiempo;
        abonosAtrasados = atrasados;
      }
    }

    return ClienteHistorialData(
      // Historial COMPLETO de créditos (pagados y no pagados) -antes se
      // filtraba acá mismo con `.where((c) => !c.liquidada)`, lo que hacía
      // desaparecer de Detalle de Cliente cualquier crédito ya liquidado
      // (bug reportado por el dueño probando con un cliente real que tenía
      // crédito pagado y no le aparecía nada). Los flags derivados
      // (hayCreditoVencido, etc.) ahora se calculan sobre esta lista
      // completa dentro de ClienteHistorialData.
      creditos: creditos,
      abonosATiempo: abonosATiempo,
      abonosAtrasados: abonosAtrasados,
      totalComprado: totalComprado,
      cantidadCompras: cantidadCompras,
      ticketPromedio: ticketPromedio,
      primeraCompra: primeraCompra,
      ultimaCompra: ultimaCompra,
      ventasRecientes: ventasRecientes,
      metodoPagoPreferido: metodoPagoPreferido,
      productosTop: productosTop.take(_maxProductosTop).toList(),
      historialColores: historialColores.take(_maxHistorialColores).toList(),
      hayVentasEmparejadasPorNombre: hayEmparejadasPorNombre,
      referidor: referidor,
    );
  }
}
