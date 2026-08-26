import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'venta_model.dart';
import 'venta_en_espera_model.dart';
import 'item_venta_model.dart';
import 'pago_detalle_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/texto_utils.dart';
import '../../productos/data/lote_costo_repository.dart';
import '../../productos/data/tinte_lookup.dart';

/// Los ítems de una venta se guardan en la subcolección 'detalle' con un id
/// autogenerado (no correlativo), así que Firestore no garantiza devolverlos
/// en el mismo orden en que se registraron -de ahí que la reimpresión podía
/// salir con las líneas revueltas-. Cada ítem lleva un campo 'orden' (su
/// posición al momento de guardar) y esta función reordena la lectura según
/// ese campo. Los documentos viejos sin 'orden' (de antes de este cambio) se
/// dejan tal como los devolvió Firestore, al final de los que sí lo tienen.
List<QueryDocumentSnapshot<Map<String, dynamic>>> _ordenarDetalle(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final conIndice = docs.asMap().entries.toList();
  conIndice.sort((a, b) {
    final ordenA = a.value.data()['orden'] as int?;
    final ordenB = b.value.data()['orden'] as int?;
    if (ordenA == null && ordenB == null) return a.key.compareTo(b.key);
    if (ordenA == null) return 1;
    if (ordenB == null) return -1;
    return ordenA.compareTo(ordenB);
  });
  return conIndice.map((e) => e.value).toList();
}

class VentaRepository {
  final _db = FirebaseFirestore.instance;
  final _colVentas = FirebaseFirestore.instance.collection('ventas');
  final _colEspera = FirebaseFirestore.instance.collection('ventasEnEspera');
  final _lotes = LoteCostoRepository();
  final _colContadores = FirebaseFirestore.instance.collection('contadores');
  final _colVentasCredito = FirebaseFirestore.instance.collection('ventasCredito');
  final _colPendientesReposicion = FirebaseFirestore.instance.collection('pendientesReposicion');
  final _colClientes = FirebaseFirestore.instance.collection('clientes');

  /// Cuando la venta no trae un `idCliente` real (el cajero no usó el
  /// buscador de cliente) pero sí escribió un nombre, se busca un cliente ya
  /// registrado con ese mismo nombre para vincular la venta a él -sin
  /// duplicar-, o si no existe, se crea uno mínimo (solo nombre y, si lo
  /// hay, documento) y se vincula al nuevo registro. Así ninguna venta con
  /// nombre queda "suelta" sin cliente vinculado (ver plan de CRM,
  /// Fase 1 punto 2).
  ///
  /// Comparación por igualdad sobre 'nombreNormalizado' (mayúsculas/tildes/
  /// espacios de más colapsados, ver texto_utils.normalizarNombreCliente),
  /// NO sobre 'nombreCompleto' tal cual está guardado -antes sí comparaba
  /// contra ese campo con igualdad EXACTA: como el nombre tipeado acá
  /// siempre llega en mayúsculas (mayusculasInputFormatter), un cliente ya
  /// registrado con otra capitalización -por ejemplo, cargado antes de que
  /// existiera ese formateo, o corregido a mano en Firestore- no calzaba
  /// nunca, y la venta terminaba creando un cliente DUPLICADO en vez de
  /// vincular al que ya existía (bug real, confirmado por el dueño: una
  /// venta de un cliente que YA tenía registrado seguía apareciendo como
  /// "sin cliente" en el reporte financiero). ClienteRepository.crear/
  /// actualizar mantienen 'nombreNormalizado' al día en cada alta/edición
  /// desde la UI; los clientes ya existentes en Firestore antes de que ese
  /// campo existiera se respaldan aparte (ver el script de backfill que
  /// corrió el coordinador sobre la colección 'clientes' en producción).
  /// Sigue sin traer toda la colección 'clientes' a memoria en cada venta
  /// (ver el comentario original): es una consulta indexada de un solo
  /// campo, tan barata como la anterior.
  Future<String?> _resolverIdCliente({
    required String? idClienteExistente,
    required String nombreCliente,
    required String documentoCliente,
  }) async {
    if (idClienteExistente != null && idClienteExistente.isNotEmpty) return idClienteExistente;
    final nombre = nombreCliente.trim();
    if (nombre.isEmpty || nombre.toUpperCase() == 'CONSUMIDOR FINAL') return null;

    final nombreNormalizado = normalizarNombreCliente(nombre);
    final existente = await _colClientes.where('nombreNormalizado', isEqualTo: nombreNormalizado).limit(1).get();
    if (existente.docs.isNotEmpty) return existente.docs.first.id;

    final documento = documentoCliente.trim();
    final nuevo = await _colClientes.add({
      'dni': (documento.isEmpty || documento == 'N/A') ? '' : documento,
      'nombreCompleto': nombre,
      'nombreNormalizado': nombreNormalizado,
      'direccion': '',
      'telefono': '',
      'estado': true,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
    return nuevo.id;
  }

  String _claveContador(String tipoDocumento) {
    switch (tipoDocumento) {
      case 'Cotizacion':
        return 'cotizacion';
      case 'VentaSinFacturar':
        return 'ventaSinFacturar';
      default:
        return 'venta';
    }
  }

  String _formatearCorrelativo(String tipoDocumento, int numero) {
    if (tipoDocumento == 'VentaSinFacturar') {
      return numero.toString().padLeft(4, '0');
    }
    return numero.toString().padLeft(8, '0');
  }

  /// Expande cada línea de combo en un ítem "virtual" por componente de su
  /// receta (cantidad = cantidad del componente × cantidad vendida del
  /// combo), usando la receta congelada en el momento de la venta -no la
  /// receta actual del combo, que pudo haber cambiado desde entonces-. Las
  /// líneas normales pasan sin cambios. Esto es lo que permite reusar el
  /// mismo código de descuento/reposición de stock que ya usan los productos
  /// normales, en vez de un flujo paralelo para combos.
  List<ItemVentaModel> _expandirComponentes(List<ItemVentaModel> items) {
    final expandido = <ItemVentaModel>[];
    for (final item in items) {
      if (!item.esCombo) {
        expandido.add(item);
        continue;
      }
      for (final c in item.componentes) {
        expandido.add(ItemVentaModel(
          idProducto: c.idProducto,
          idCategoria: c.idCategoria,
          nombreProducto: c.nombreProducto,
          precioVenta: 0,
          cantidad: c.cantidad * item.cantidad,
          subtotal: 0,
          precioCompraUsado: c.precioCompraUsado,
        ));
      }
    }
    return expandido;
  }

  /// Junta, agrupado por producto de tinte (idProductoTinte), todos los usos
  /// de tinte de TODAS las líneas de la venta -Escenario A/B, ver
  /// TinteConsumidoSnapshot y CodigosColorDialog- en un solo ítem "virtual"
  /// por producto de tinte (cantidad = suma de cuartos de todas las líneas
  /// que usan ese mismo tinte). Se agrega así -no un ítem virtual por cada
  /// uso- porque el bloque de descuento de stock más abajo (compartido con
  /// productos normales y componentes de combo) lee el stock ANTES de
  /// descontar y no acumula bien un mismo idProducto que aparezca dos veces
  /// en la lista a descontar (cada aparición pisaría el descuento de la
  /// anterior en vez de sumarse) -con dos líneas de color distinto usando el
  /// mismo tinte en la misma venta, esto evita que la segunda pise a la
  /// primera-. Entradas sin producto de inventario resuelto (colorante sin
  /// match, ver tinte_lookup.dart) o con cuartos <= 0 se ignoran -no hay
  /// nada que descontar-.
  List<ItemVentaModel> _agregarTintesParaDescuento(List<ItemVentaModel> items) {
    final cuartosPorProducto = <String, double>{};
    final nombrePorProducto = <String, String>{};
    for (final item in items) {
      for (final t in item.tintesConsumidos) {
        if (t.idProductoTinte.isEmpty || t.cuartosConsumidos <= 0) continue;
        cuartosPorProducto[t.idProductoTinte] = (cuartosPorProducto[t.idProductoTinte] ?? 0) + t.cuartosConsumidos;
        nombrePorProducto.putIfAbsent(t.idProductoTinte, () => t.nombreProductoTinte);
      }
    }
    return [
      for (final entry in cuartosPorProducto.entries)
        ItemVentaModel(
          idProducto: entry.key,
          idCategoria: idCategoriaTintes,
          nombreProducto: nombrePorProducto[entry.key] ?? '',
          precioVenta: 0,
          cantidad: entry.value,
          subtotal: 0,
          precioCompraUsado: 0,
        ),
    ];
  }

  /// Reemplaza el costo ESTIMADO de cada tinte consumido (calculado por
  /// CostoTinteService antes de confirmar la venta) por el costo FIFO real
  /// -mismo criterio que ya aplica registrarVenta con precioCompraUsado de
  /// productos normales-. Entradas sin producto resuelto (idProductoTinte
  /// vacío) quedan tal cual, no hay costo real que calcular para esas.
  List<TinteConsumidoSnapshot> _tintesConCostoReal(List<TinteConsumidoSnapshot> tintes, Map<String, double> costoUnitarioPorTinteProducto) {
    return [
      for (final t in tintes)
        if (t.idProductoTinte.isEmpty)
          t
        else
          TinteConsumidoSnapshot(
            colorante: t.colorante,
            idProductoTinte: t.idProductoTinte,
            nombreProductoTinte: t.nombreProductoTinte,
            cuartosConsumidos: t.cuartosConsumidos,
            costoUnitario: costoUnitarioPorTinteProducto[t.idProductoTinte] ?? t.costoUnitario,
            costoTotal: (costoUnitarioPorTinteProducto[t.idProductoTinte] ?? t.costoUnitario) * t.cuartosConsumidos,
          ),
    ];
  }

  /// Igual que _agregarTintesParaDescuento pero para anularVenta: agrupa por
  /// producto de tinte la cantidad a RESTAURAR, con el costo unitario
  /// promedio ponderado de lo que de verdad se consumió en esta venta (ya el
  /// costo FIFO REAL, escrito por registrarVenta -ver _tintesConCostoReal-,
  /// no un estimado) -para que el lote de "ajuste" que crea la restauración
  /// quede al costo correcto.
  List<ItemVentaModel> _agregarTintesParaRestaurar(List<ItemVentaModel> items) {
    final cuartosPorProducto = <String, double>{};
    final costoTotalPorProducto = <String, double>{};
    final nombrePorProducto = <String, String>{};
    for (final item in items) {
      for (final t in item.tintesConsumidos) {
        if (t.idProductoTinte.isEmpty || t.cuartosConsumidos <= 0) continue;
        cuartosPorProducto[t.idProductoTinte] = (cuartosPorProducto[t.idProductoTinte] ?? 0) + t.cuartosConsumidos;
        costoTotalPorProducto[t.idProductoTinte] = (costoTotalPorProducto[t.idProductoTinte] ?? 0) + t.costoTotal;
        nombrePorProducto.putIfAbsent(t.idProductoTinte, () => t.nombreProductoTinte);
      }
    }
    return [
      for (final entry in cuartosPorProducto.entries)
        ItemVentaModel(
          idProducto: entry.key,
          idCategoria: idCategoriaTintes,
          nombreProducto: nombrePorProducto[entry.key] ?? '',
          precioVenta: 0,
          cantidad: entry.value,
          subtotal: 0,
          precioCompraUsado: entry.value > 0 ? (costoTotalPorProducto[entry.key] ?? 0) / entry.value : 0,
        ),
    ];
  }

  /// Próximo número que le tocaría a la próxima Factura/Boleta (comparten
  /// el mismo contador 'venta', ver _claveContador). Para uso en Negocio,
  /// donde se puede consultar y fijar manualmente antes de empezar a
  /// facturar (por ejemplo, para continuar la numeración de un talonario
  /// físico en vez de arrancar siempre desde 1).
  Future<int> obtenerProximoNumeroFactura() async {
    final snap = await _colContadores.doc('venta').get();
    final actual = ((snap.data()?['ultimo'] ?? 0) as num).toInt();
    return actual + 1;
  }

  Future<void> establecerProximoNumeroFactura(int proximoNumero) async {
    final nuevoUltimo = proximoNumero - 1;
    await _colContadores.doc('venta').set({'ultimo': nuevoUltimo < 0 ? 0 : nuevoUltimo}, SetOptions(merge: true));
  }

  /// Reserva (consume) el próximo número de Factura/Boleta de la secuencia
  /// oficial sin crear una venta real — para la "Factura consolidada" que
  /// se imprime desde Ver facturas unidas: no hay stock que descontar ni
  /// crédito nuevo que registrar (esos ya existen de las facturas que se
  /// unieron), pero igual necesita un número de factura de verdad, no uno
  /// inventado, para no repetirse con la próxima venta real.
  Future<String> reservarProximoNumeroFactura() async {
    final contadorRef = _colContadores.doc('venta');
    return _db.runTransaction((transaction) async {
      final snap = await transaction.get(contadorRef);
      final actual = ((snap.data()?['ultimo'] ?? 0) as num).toInt();
      final nuevo = actual + 1;
      transaction.set(contadorRef, {'ultimo': nuevo}, SetOptions(merge: true));
      return _formatearCorrelativo('Factura', nuevo);
    });
  }

  Future<VentaModel> registrarVenta({
    required String tipoDocumento,
    required String condicion,
    required String metodoPago,
    required String documentoCliente,
    required String nombreCliente,
    // Vínculo real al registro de 'clientes' (viene de BuscarClienteDialog,
    // ver carrito.idCliente). Si viene null pero hay nombreCliente, se
    // resuelve/crea uno solo -ver _resolverIdCliente-.
    String? idCliente,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    required String oc,
    required String regExonerado,
    required String regSag,
    String observaciones = '',
    double descuentoGlobal = 0,
    required List<ItemVentaModel> items,
    required double montoPago,
    required double montoCambio,
    List<PagoDetalle> pagosMixtos = const [],
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
    // Categorías marcadas para no controlar existencia (servicios, pintura
    // preparada, etc.): sus productos no bajan del inventario al venderse.
    // Se recibe ya resuelta desde la UI (que ya tiene las categorías
    // cargadas en memoria vía su stream) en vez de volver a consultarlas
    // acá: hacerlo adentro agregaba una ida y vuelta extra a Firestore justo
    // antes de cada venta, y el registro de venta tiene que sentirse casi
    // instantáneo.
    Set<String> categoriasSinControlStock = const {},
  }) async {
    final claveContador = _claveContador(tipoDocumento);
    final contadorRef = _colContadores.doc(claveContador);
    final ventaRef = _colVentas.doc();
    final itemsADescontar = _expandirComponentes(items).where((i) => !i.reembasado && !categoriasSinControlStock.contains(i.idCategoria)).toList();
    // El tinte se descuenta siempre que se haya cargado (Escenario A/B), sin
    // importar si la categoría del producto VENDIDO controla stock o no
    // -pedido explícito: "quiero que el stock de tinte se descuente de
    // verdad"-, así que no pasa por el mismo filtro de arriba.
    final tintesADescontar = _agregarTintesParaDescuento(items);
    // Mismos productos únicos que se calculan de nuevo adentro de la
    // transacción (ver más abajo) -se necesita también acá afuera para
    // sincronizar precioCompra después de que la transacción confirme, ver
    // el comentario grande junto al await final de este método.
    final idsProductoUnicosParaSync = [...itemsADescontar, ...tintesADescontar].map((i) => i.idProducto).toSet().toList();

    // Se resuelve ANTES de entrar a la transacción: es una consulta (y,
    // eventualmente, una creación de cliente) que Firestore no permite hacer
    // dentro de una transacción (Transaction.get solo acepta referencias a
    // documentos puntuales, no queries). Una cotización todavía no es una
    // venta concretada, así que no dispara el auto-registro de clientes -si
    // ya traía un idCliente elegido a mano, ese sí se respeta igual-.
    final idClienteResuelto = tipoDocumento == 'Cotizacion'
        ? idCliente
        : await _resolverIdCliente(idClienteExistente: idCliente, nombreCliente: nombreCliente, documentoCliente: documentoCliente);

    late String numeroDocumento;
    late Map<ItemVentaModel, double> costosFifo;
    late Map<String, double> costoUnitarioPorTinteProducto;

    // Timeout corto (el default del SDK es 30s): en cajas con internet
    // lento/intermitente es mejor que el cajero vea rápido que falló y
    // pueda reintentar, a que la pantalla quede "cargando" media hora.
    await _db.runTransaction((transaction) async {
      // Todas las lecturas de la transacción (contador, stock de cada
      // producto, y los lotes de costo de cada producto distinto) se
      // disparan juntas, en vez de esperar unas antes de lanzar las otras:
      // eso ahorra idas y vueltas completas a Firestore en cada venta, que
      // es justo lo que la hacía sentir lenta (sobre todo en cajas con
      // internet móvil) — tiene que sentirse instantánea. Los lotes se leen
      // con una consulta simple (no transaccional, ver consultarLotes) que
      // no depende de nada más, así que se lanza en paralelo con el resto
      // en vez de esperar a que terminen el contador y el stock primero.
      // itemsADescontarTotal junta los productos/componentes de combo
      // normales con los tintes reales consumidos (ver
      // _agregarTintesParaDescuento) para que ambos pasen por el mismo
      // bloque de lectura/descuento de stock y costeo FIFO de acá abajo.
      //
      // BUG corregido: cuando el mismo idProducto aparece en más de una
      // línea de itemsADescontarTotal -dos líneas SEPARADAS del carrito para
      // el mismo producto (no una sola línea con cantidad mayor), el mismo
      // producto vendido a la vez como línea normal Y usado como ingrediente
      // de tinte de otra línea, o dos combos distintos que comparten un
      // componente- antes se leía/descontaba/escribía el stock UNA VEZ POR
      // LÍNEA: 'stocksActuales' se llenaba con la lectura original y nunca
      // se actualizaba entre líneas, y cada línea hacía su propio
      // transaction.update(ref, {stock: ...}) sobre la MISMA referencia de
      // producto -Firestore no suma updates repetidos sobre un mismo doc
      // dentro de una transacción, el último pisa a los anteriores-, así que
      // solo la última línea de ese producto quedaba reflejada y el stock
      // real terminaba más alto de lo que debía después de la venta. La
      // corrección: se agrupa la cantidad total por idProducto ANTES de
      // leer/consumir/escribir, y de ahí en adelante todo el bloque (lectura
      // de stock, consumo FIFO de lotes, y más abajo la escritura de
      // 'stock'/'historial') trabaja por producto único, no por línea. El
      // costo FIFO resultante (promedio ponderado de TODO lo consumido de
      // ese producto en esta venta) se reparte de vuelta a cada línea
      // original como su precioCompraUsado -ver más abajo-: al ser el mismo
      // costo unitario para todas las líneas de un mismo producto,
      // multiplicado por la cantidad propia de cada línea en los reportes,
      // el reparto queda automáticamente ponderado por esa cantidad.
      final itemsADescontarTotal = [...itemsADescontar, ...tintesADescontar];
      final idsProductoUnicos = itemsADescontarTotal.map((i) => i.idProducto).toSet().toList();
      final cantidadTotalPorProducto = <String, double>{};
      for (final item in itemsADescontarTotal) {
        cantidadTotalPorProducto[item.idProducto] = (cantidadTotalPorProducto[item.idProducto] ?? 0) + item.cantidad;
      }
      final futureResultados = Future.wait([
        transaction.get(contadorRef),
        ...idsProductoUnicos.map((id) => transaction.get(_db.collection('productos').doc(id))),
      ]);
      final futureLotes = Future.wait(idsProductoUnicos.map((id) => _lotes.consultarLotes(id)));

      final resultados = await futureResultados;
      final contadorSnap = resultados[0];
      final snapsStock = resultados.sublist(1);

      final actual = ((contadorSnap.data()?['ultimo'] ?? 0) as num).toInt();
      final nuevo = actual + 1;
      numeroDocumento = _formatearCorrelativo(tipoDocumento, nuevo);

      final stocksActuales = <String, double>{};
      final precioCompraActual = <String, double>{};
      for (var i = 0; i < idsProductoUnicos.length; i++) {
        final data = snapsStock[i].data();
        stocksActuales[idsProductoUnicos[i]] = ((data?['stock'] ?? 0) as num).toDouble();
        precioCompraActual[idsProductoUnicos[i]] = ((data?['precioCompra'] ?? 0) as num).toDouble();
      }

      // Costeo FIFO: se consume UNA sola vez por producto único, por la
      // cantidad TOTAL agrupada (ver cantidadTotalPorProducto arriba), en
      // vez de una vez por línea -así dos líneas del mismo producto
      // comparten el mismo estado de lotes sin contar dos veces la misma
      // capacidad, y el costo resultante es el promedio real de todo lo
      // consumido de ese producto en esta venta.
      final queriesLotes = await futureLotes;
      final estadoLotesPorProducto = <String, EstadoLotesProducto>{
        for (var i = 0; i < idsProductoUnicos.length; i++) idsProductoUnicos[i]: _lotes.inicializarEstado(queriesLotes[i]),
      };
      final costoUnitarioPorProducto = <String, double>{
        for (final idProducto in idsProductoUnicos)
          idProducto: _lotes.consumir(
            estadoLotesPorProducto[idProducto]!,
            cantidadTotalPorProducto[idProducto] ?? 0,
            costoFallback: precioCompraActual[idProducto] ?? 0,
          ),
      };
      // Se reparte el costo unitario agregado de vuelta a cada línea de
      // itemsADescontar (no a itemsADescontarTotal: los tintes se reparten
      // aparte, ver costoUnitarioPorTinteProducto abajo) para que
      // precioCompraUsado de cada línea siga siendo su costo real, ya
      // ponderado por su propia cantidad al multiplicarse en los reportes.
      costosFifo = <ItemVentaModel, double>{
        for (final item in itemsADescontar) item: costoUnitarioPorProducto[item.idProducto] ?? 0,
      };
      // Costo FIFO real por producto de tinte (uno solo por idProducto, ver
      // _agregarTintesParaDescuento): se usa abajo para reescribir el costo
      // ESTIMADO que traía cada TinteConsumidoSnapshot con el real.
      costoUnitarioPorTinteProducto = <String, double>{
        for (final tv in tintesADescontar) tv.idProducto: costoUnitarioPorProducto[tv.idProducto] ?? precioCompraActual[tv.idProducto] ?? 0,
      };

      transaction.set(contadorRef, {'ultimo': nuevo}, SetOptions(merge: true));

      transaction.set(ventaRef, {
        'tipoDocumento': tipoDocumento,
        'numeroDocumento': numeroDocumento,
        'documentoCliente': documentoCliente,
        'nombreCliente': nombreCliente,
        'idCliente': idClienteResuelto,
        'metodoPago': metodoPago,
        'montoPago': montoPago,
        'montoCambio': montoCambio,
        'pagosMixtos': PagoDetalle.listaToMaps(pagosMixtos),
        'subtotal': subtotal,
        'impuesto': impuesto,
        'totalAPagar': totalAPagar,
        'condicion': condicion,
        'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento) : null,
        // 'fechaRegistro' es la fecha de negocio (el cajero la puede elegir
        // con el selector de fecha, para atrasar una factura, por ejemplo),
        // no necesariamente cuándo se creó de verdad el registro. 'creadoEn'
        // sí es siempre el momento real, puesto por el servidor: se usa
        // para ordenar el Reporte de Ventas por orden de creación (ver
        // ReporteRepository.obtenerReporteVentas) sin importar qué fecha de
        // negocio se haya elegido.
        'fechaRegistro': Timestamp.fromDate(fechaRegistro),
        'creadoEn': FieldValue.serverTimestamp(),
        'estado': 'Activa',
        'usuarioRegistro': usuario,
        'cantidadProductos': items.fold<double>(0, (s, i) => s + i.cantidad),
        'oc': oc,
        'regExonerado': regExonerado,
        'regSag': regSag,
        'observaciones': observaciones,
        'descuentoGlobal': descuentoGlobal,
        'pendienteImpresion': false,
      });

      for (final entry in items.asMap().entries) {
        final item = entry.value;
        final itemRef = ventaRef.collection('detalle').doc();
        final costoReal = costosFifo[item];
        final itemAGuardar = (costoReal != null || item.tintesConsumidos.isNotEmpty)
            ? item.copyWith(precioCompraUsado: costoReal ?? item.precioCompraUsado, tintesConsumidos: _tintesConCostoReal(item.tintesConsumidos, costoUnitarioPorTinteProducto))
            : item;
        // 'fecha' permite consultar el detalle de todas las ventas de un
        // rango con una sola query (collectionGroup) en vez de tener que
        // leer la subcolección de cada venta una por una. 'orden' es la
        // posición de la línea en el carrito, para que la reimpresión
        // respete el mismo orden con el que se registró (ver _ordenarDetalle).
        // 'idCliente' se agrega acá (no es parte de ItemVentaModel: es
        // contexto de la venta completa, no de la línea) para que una
        // consulta collectionGroup('detalle').where('idCliente', ...) -ver
        // Detalle de Cliente- encuentre el historial de códigos de color sin
        // tener que hacer join con la venta.
        transaction.set(itemRef, {...itemAGuardar.toMap(), 'fecha': Timestamp.fromDate(fechaRegistro), 'orden': entry.key, 'idCliente': idClienteResuelto});

        // "Venta anticipada": deja un registro para que la próxima compra de
        // este producto lo empareje solo (ver CompraRepository.registrarCompra
        // y PendienteReposicionRepository). No aplica a combos -su costo
        // depende de sus componentes, no de una compra directa del combo
        // mismo- ni a cotizaciones, que todavía no son una venta concretada.
        if (tipoDocumento != 'Cotizacion' && itemAGuardar.pendienteCompra && !itemAGuardar.esCombo) {
          transaction.set(_colPendientesReposicion.doc(), {
            'idVenta': ventaRef.id,
            'numeroDocumentoVenta': numeroDocumento,
            'idItemDetalle': itemRef.id,
            'idProducto': itemAGuardar.idProducto,
            'nombreProducto': itemAGuardar.nombreProducto,
            'idCategoria': itemAGuardar.idCategoria,
            'cantidadOriginal': itemAGuardar.cantidad,
            'cantidadPendiente': itemAGuardar.cantidad,
            'costoRegistrado': itemAGuardar.precioCompraUsado,
            'fechaRegistro': Timestamp.fromDate(fechaRegistro),
            'estado': 'Pendiente',
            'usuario': usuario,
          });
        }
      }

      if (condicion == 'Credito') {
        transaction.set(_colVentasCredito.doc(ventaRef.id), {
          'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
          'nombreCliente': nombreCliente,
          'idCliente': idClienteResuelto,
          'numeroDocumento': numeroDocumento,
          'montoTotal': totalAPagar,
          'saldoPendiente': totalAPagar,
          'fechaRegistro': Timestamp.fromDate(fechaRegistro),
          'fechaVencimiento': Timestamp.fromDate(fechaVencimiento ?? fechaRegistro),
        });
      }

      // Denormalizado para detectar clientes inactivos sin recorrer todas
      // sus ventas (Fase 3 del CRM). No aplica a cotizaciones -no son una
      // compra real todavía-. merge:true porque este mismo doc de cliente
      // puede tener otros campos (dni, teléfono, etc.) que no se deben tocar.
      if (idClienteResuelto != null && tipoDocumento != 'Cotizacion') {
        transaction.set(_colClientes.doc(idClienteResuelto), {'fechaUltimaCompra': Timestamp.fromDate(fechaRegistro)}, SetOptions(merge: true));
      }

      // Un solo update/historial por producto único, por la cantidad TOTAL
      // agrupada (cantidadTotalPorProducto) -no uno por línea-: escribir
      // 'stock' más de una vez sobre la misma referencia dentro de la misma
      // transacción no suma, la última escritura pisa a las anteriores, así
      // que antes de este fix una segunda línea del mismo producto perdía
      // el descuento de la primera (ver nota completa más arriba).
      for (final idProducto in idsProductoUnicos) {
        final ref = _db.collection('productos').doc(idProducto);
        final stockActual = stocksActuales[idProducto] ?? 0;
        final cantidadTotal = cantidadTotalPorProducto[idProducto] ?? 0;
        // Nunca queda en negativo: si ya estaba en 0 (por ejemplo, se vendió
        // a propósito sin existencia disponible) el piso es 0, no un número
        // negativo que después confunda los reportes de inventario.
        final stockNuevo = (stockActual - cantidadTotal) < 0 ? 0.0 : stockActual - cantidadTotal;
        transaction.update(ref, {'stock': stockNuevo});
        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Venta $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });
      }

      for (final estado in estadoLotesPorProducto.values) {
        _lotes.aplicarEstado(transaction, estado);
      }

      // Historial de precio de venta por producto: no aplica a cotizaciones,
      // que todavía no son una venta concretada.
      if (tipoDocumento != 'Cotizacion') {
        for (final item in items) {
          final ref = _db.collection('productos').doc(item.idProducto);
          final precioConIsv = redondearMoneda(item.precioVenta * (1 - item.descuentoPorcentaje / 100) * 1.15);
          final historialVentaRef = ref.collection('historialVentas').doc();
          transaction.set(historialVentaRef, {
            'idVenta': ventaRef.id,
            'precioVenta': precioConIsv,
            'precioUnitario': item.precioVenta,
            'descuentoPorcentaje': item.descuentoPorcentaje,
            'cantidad': item.cantidad,
            'tipoDocumento': tipoDocumento,
            'numeroDocumento': numeroDocumento,
            'cliente': nombreCliente,
            'usuario': usuario,
            'fecha': FieldValue.serverTimestamp(),
          });
        }
      }
    }, timeout: const Duration(seconds: 12));

    // Sincroniza productos.precioCompra con el lote que el FIFO va a
    // consumir a continuación, ya con los lotes de esta venta confirmados
    // -ver el doc grande de LoteCostoRepository.sincronizarPrecioCompraActivo
    // para el porqué de por qué esto va DESPUÉS de la transacción y no
    // adentro-. Best-effort: si falla, la venta ya se registró bien (lo que
    // importa) y precioCompra simplemente queda con el valor anterior hasta
    // la próxima operación que sí sincronice.
    unawaited(Future.wait(idsProductoUnicosParaSync.map((id) => _lotes.sincronizarPrecioCompraActivo(id))).catchError((_) => <void>[]));

    return VentaModel(
      id: ventaRef.id,
      tipoDocumento: tipoDocumento,
      numeroDocumento: numeroDocumento,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      idCliente: idClienteResuelto,
      metodoPago: metodoPago,
      montoPago: montoPago,
      montoCambio: montoCambio,
      pagosMixtos: pagosMixtos,
      subtotal: subtotal,
      impuesto: impuesto,
      totalAPagar: totalAPagar,
      condicion: condicion,
      fechaVencimiento: fechaVencimiento,
      fechaRegistro: fechaRegistro,
      estado: 'Activa',
      usuarioRegistro: usuario,
      cantidadProductos: items.fold<double>(0, (s, i) => s + i.cantidad),
      oc: oc,
      regExonerado: regExonerado,
      regSag: regSag,
      observaciones: observaciones,
      descuentoGlobal: descuentoGlobal,
      detalle: items.map((item) {
        final costoReal = costosFifo[item];
        return (costoReal != null || item.tintesConsumidos.isNotEmpty)
            ? item.copyWith(precioCompraUsado: costoReal ?? item.precioCompraUsado, tintesConsumidos: _tintesConCostoReal(item.tintesConsumidos, costoUnitarioPorTinteProducto))
            : item;
      }).toList(),
    );
  }

  // Best-effort: es solo una bandera de conveniencia para ubicar después
  // ventas sin imprimir, así que si el documento ya no existe (por ejemplo,
  // una venta vieja que quedó en el caché local de un dispositivo después de
  // vaciar la base de datos) no debe reventar con un error feo en pantalla.
  Future<void> marcarPendienteImpresion(String id, bool valor) async {
    try {
      await _colVentas.doc(id).update({'pendienteImpresion': valor});
    } on FirebaseException catch (e) {
      if (e.code != 'not-found' && e.code != 'invalid-argument') rethrow;
    }
  }

  // Best-effort, mismo criterio que marcarPendienteImpresion. [esCopia]
  // viaja junto con la solicitud para que la PC sepa si esta reimpresión en
  // particular debe salir como "copia" u "original" (ver
  // DetalleVentaScreen._reimprimir y ImpresionEnVivoService). Se deja en
  // null (default) para una venta recién confirmada, que no tiene una
  // elección explícita de original/copia — ver VentaModel.
  // solicitudImpresionEsCopia.
  Future<void> marcarSolicitudImpresionEnVivo(String id, bool valor, {bool? esCopia}) async {
    try {
      await _colVentas.doc(id).update({'solicitudImpresionEnVivo': valor, 'solicitudImpresionEsCopia': esCopia});
    } on FirebaseException catch (e) {
      if (e.code != 'not-found' && e.code != 'invalid-argument') rethrow;
    }
  }

  /// Ventas pendientes de impresión que además le están pidiendo a la PC
  /// principal que la imprima automáticamente apenas la detecte (ver
  /// AppShell). Sin `orderBy` por el mismo motivo que
  /// obtenerVentasPendientesImpresion.
  Stream<List<VentaModel>> obtenerVentasConSolicitudImpresionEnVivo() {
    return _colVentas.where('solicitudImpresionEnVivo', isEqualTo: true).snapshots().map((snap) {
      return snap.docs.map((d) => VentaModel.fromMap(d.id, d.data(), const [])).toList();
    });
  }

  Future<VentaModel?> obtenerVentaPorId(String id) async {
    // Las dos lecturas no dependen una de la otra (el id ya se conoce de
    // entrada), así que se disparan juntas en vez de esperar el documento
    // antes de recién ahí pedir el detalle: ahorra una vuelta completa a
    // Firestore.
    final futureVenta = _colVentas.doc(id).get();
    final futureDetalle = _colVentas.doc(id).collection('detalle').get();
    final snap = await futureVenta;
    if (!snap.exists) return null;
    final detalleSnap = await futureDetalle;
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemVentaModel.fromMap(d.data())).toList();
    return VentaModel.fromMap(id, snap.data()!, items);
  }

  /// Solo el detalle (items) de una venta, sin volver a leer el documento
  /// principal: para cuando ya se tiene el resto de la venta por otro lado
  /// (por ejemplo, de un stream) y solo hace falta completarla con el
  /// detalle antes de imprimir — ver VentaModel.copyWith y AppShell.
  Future<List<ItemVentaModel>> obtenerDetalleVenta(String id) async {
    final detalleSnap = await _colVentas.doc(id).collection('detalle').get();
    return _ordenarDetalle(detalleSnap.docs).map((d) => ItemVentaModel.fromMap(d.data())).toList();
  }

  Future<VentaModel?> obtenerVentaPorNumeroDocumento(String numeroDocumento) async {
    final texto = numeroDocumento.trim();
    if (texto.isEmpty) return null;
    final query = await _colVentas.where('numeroDocumento', isEqualTo: texto).limit(1).get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    final detalleSnap = await doc.reference.collection('detalle').get();
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemVentaModel.fromMap(d.data())).toList();
    return VentaModel.fromMap(doc.id, doc.data(), items);
  }

  /// Busca ventas por número de documento sin que el usuario tenga que
  /// escribir los ceros de relleno (por ejemplo "5" en vez de "00000005"):
  /// arma las variantes rellenadas posibles -8 dígitos para Factura/Boleta/
  /// Cotización, 4 para Venta Sin Facturar (ver _formatearCorrelativo)- y
  /// las busca todas. Si se indica [tipoDocumento] filtra además por ese
  /// tipo: hace falta porque Factura/Boleta y Cotización usan contadores
  /// separados pero el mismo relleno de 8 dígitos, así que un mismo número
  /// bien podría coincidir con una Factura Y una Cotización a la vez. Cada
  /// candidato se busca con una consulta de igualdad simple (no `whereIn`)
  /// para no depender de un índice compuesto.
  Future<List<VentaModel>> buscarVentasPorNumeroDocumento(String texto, {String? tipoDocumento}) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) return [];

    final candidatos = <String>{limpio};
    if (RegExp(r'^\d+$').hasMatch(limpio)) {
      candidatos.add(limpio.padLeft(8, '0'));
      candidatos.add(limpio.padLeft(4, '0'));
    }

    final snaps = await Future.wait(candidatos.map((c) => _colVentas.where('numeroDocumento', isEqualTo: c).get()));
    final docs = snaps.expand((s) => s.docs).toList();

    final resultados = <VentaModel>[];
    for (final doc in docs) {
      if (tipoDocumento != null && tipoDocumento.isNotEmpty && doc.data()['tipoDocumento'] != tipoDocumento) continue;
      final detalleSnap = await doc.reference.collection('detalle').get();
      final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemVentaModel.fromMap(d.data())).toList();
      resultados.add(VentaModel.fromMap(doc.id, doc.data(), items));
    }
    resultados.sort((a, b) => (b.fechaRegistro ?? DateTime(0)).compareTo(a.fechaRegistro ?? DateTime(0)));
    return resultados;
  }

  /// Anula una venta: la marca como 'Anulada', repone al inventario el stock
  /// de los productos que no fueron reembasados, y si era una venta a
  /// crédito sin abonos, elimina su registro en `ventasCredito`.
  Future<void> anularVenta({
    required String id,
    required String usuario,
    String motivo = '',
  }) async {
    final ventaSnap = await _colVentas.doc(id).get();
    if (!ventaSnap.exists) {
      throw Exception('No se encontró la venta');
    }
    final data = ventaSnap.data()!;
    if (data['estado'] == 'Anulada') {
      throw Exception('Esta venta ya está anulada');
    }
    final condicion = data['condicion'] as String? ?? '';
    final numeroDocumento = data['numeroDocumento'] as String? ?? '';

    final detalleSnap = await _colVentas.doc(id).collection('detalle').get();
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemVentaModel.fromMap(d.data())).toList();

    var creditoExiste = false;
    if (condicion == 'Credito') {
      final creditoSnap = await _colVentasCredito.doc(id).get();
      if (creditoSnap.exists) {
        creditoExiste = true;
        final montoTotal = ((creditoSnap.data()?['montoTotal'] ?? 0) as num).toDouble();
        final saldoPendiente = ((creditoSnap.data()?['saldoPendiente'] ?? 0) as num).toDouble();
        if (saldoPendiente < montoTotal) {
          throw Exception('No se puede anular: esta venta a crédito ya tiene abonos registrados');
        }
      }
    }

    final itemsExpandidos = _expandirComponentes(items);
    final idsCategoriaRestaurar = itemsExpandidos.map((i) => i.idCategoria).where((id) => id.isNotEmpty).toSet();
    final categoriasSinControlStockRestaurar = <String>{};
    if (idsCategoriaRestaurar.isNotEmpty) {
      final snapsCategorias = await Future.wait(idsCategoriaRestaurar.map((id) => _db.collection('categorias').doc(id).get()));
      for (final snap in snapsCategorias) {
        if (snap.exists && (snap.data()?['controlaStock'] ?? true) == false) {
          categoriasSinControlStockRestaurar.add(snap.id);
        }
      }
    }
    final itemsARestaurarBase = itemsExpandidos.where((i) => !i.reembasado && !categoriasSinControlStockRestaurar.contains(i.idCategoria)).toList();
    // El tinte consumido en cada línea (ver TinteConsumidoSnapshot) se
    // restaura siempre, con el mismo criterio que su descuento en
    // registrarVenta -sin importar si la categoría del producto vendido
    // controla stock-, y agregado por producto de tinte (ver
    // _agregarTintesParaDescuento) para no toparse con el mismo problema de
    // "no acumula bien un idProducto repetido" del bloque de restauración de
    // abajo. Usa 'items' (el detalle real de la venta, no el expandido de
    // combos) porque tintesConsumidos vive en la línea original.
    final itemsARestaurar = [...itemsARestaurarBase, ..._agregarTintesParaRestaurar(items)];

    // Si esta venta tenía líneas "pendientes de compra" (venta anticipada)
    // que todavía no se habían emparejado con ninguna compra, hay que
    // cancelarlas: si no, quedarían esperando para siempre a una compra que
    // ya no le corresponde a nada real (la venta que las originó ya no existe).
    final pendientesSnap = await _colPendientesReposicion.where('idVenta', isEqualTo: id).where('estado', isEqualTo: 'Pendiente').get();

    // Si la venta se borró del servidor pero seguía "existiendo" en el
    // caché local (por ejemplo, después de vaciar la base de datos desde
    // otro dispositivo), la comprobación de arriba pasa igual porque lee del
    // caché, y recién acá, al hablar con el servidor de verdad, aparece el
    // error. Se traduce a un mensaje claro en vez de mostrar el texto crudo
    // de Firestore.
    try {
      await _anularVentaTransaccion(
        id: id,
        usuario: usuario,
        motivo: motivo,
        numeroDocumento: numeroDocumento,
        creditoExiste: creditoExiste,
        itemsARestaurar: itemsARestaurar,
        pendientesReposicionRefs: pendientesSnap.docs.map((d) => d.reference).toList(),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'invalid-argument') {
        throw Exception('No se pudo anular: la venta ya no existe en el servidor (puede que se haya borrado desde otro dispositivo)');
      }
      rethrow;
    }
    // Mismo criterio que registrarVenta: sincroniza precioCompra con el
    // lote activo de cada producto restaurado, ya con el lote nuevo de esta
    // anulación (ver _anularVentaTransaccion, crea uno a costo promedio) y
    // los stocks restaurados confirmados. Best-effort.
    unawaited(Future.wait(itemsARestaurar.map((i) => i.idProducto).toSet().map((id) => _lotes.sincronizarPrecioCompraActivo(id))).catchError((_) => <void>[]));
  }

  Future<void> _anularVentaTransaccion({
    required String id,
    required String usuario,
    required String motivo,
    required String numeroDocumento,
    required bool creditoExiste,
    required List<ItemVentaModel> itemsARestaurar,
    required List<DocumentReference<Map<String, dynamic>>> pendientesReposicionRefs,
  }) async {
    // Mismo bug (y misma corrección) que registrarVenta: si itemsARestaurar
    // trae más de una línea con el mismo idProducto -la venta original tenía
    // dos líneas separadas del mismo producto-, agrupar por producto único
    // ANTES de leer/escribir evita que una segunda línea pise (en vez de
    // sumarse a) la restauración de stock de la primera -acá el efecto sería
    // reponer MENOS de lo que corresponde, en vez de de más-.
    final idsProductoUnicos = itemsARestaurar.map((i) => i.idProducto).toSet().toList();
    final cantidadTotalPorProducto = <String, double>{};
    final costoTotalPorProducto = <String, double>{};
    for (final item in itemsARestaurar) {
      cantidadTotalPorProducto[item.idProducto] = (cantidadTotalPorProducto[item.idProducto] ?? 0) + item.cantidad;
      costoTotalPorProducto[item.idProducto] = (costoTotalPorProducto[item.idProducto] ?? 0) + item.cantidad * item.precioCompraUsado;
    }

    await _db.runTransaction((transaction) async {
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        idsProductoUnicos.map((idProducto) => transaction.get(_db.collection('productos').doc(idProducto))),
      );
      for (var i = 0; i < idsProductoUnicos.length; i++) {
        stocksActuales[idsProductoUnicos[i]] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      transaction.update(_colVentas.doc(id), {
        'estado': 'Anulada',
        'usuarioAnulacion': usuario,
        'motivoAnulacion': motivo,
        'fechaAnulacion': FieldValue.serverTimestamp(),
      });

      if (creditoExiste) {
        transaction.delete(_colVentasCredito.doc(id));
      }

      for (final ref in pendientesReposicionRefs) {
        transaction.update(ref, {'estado': 'Cancelado', 'fechaCompletado': FieldValue.serverTimestamp()});
      }

      for (final idProducto in idsProductoUnicos) {
        final ref = _db.collection('productos').doc(idProducto);
        final stockActual = stocksActuales[idProducto] ?? 0;
        final cantidadTotal = cantidadTotalPorProducto[idProducto] ?? 0;
        final stockNuevo = stockActual + cantidadTotal;
        transaction.update(ref, {'stock': stockNuevo});
        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Anulación de venta $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });

        // El stock repuesto vuelve como un lote nuevo, al costo real que
        // tenía esa venta (ya sea el costo de fábrica o el ya calculado por
        // FIFO). Es más simple y igual de correcto hacia adelante que tratar
        // de deshacer el consumo exacto de lotes de la venta original. Si
        // había más de una línea del mismo producto (posiblemente a costos
        // distintos, en ventas viejas de antes de este fix), se repone en UN
        // solo lote al costo promedio ponderado por cantidad de todas ellas
        // -equivalente en total a reponer uno por línea, pero consistente
        // con que el stock también se repone agrupado, no línea por línea.
        final costoUnitarioPromedio = cantidadTotal > 0 ? (costoTotalPorProducto[idProducto] ?? 0) / cantidadTotal : 0.0;
        _lotes.crearLote(
          transaction,
          idProducto,
          cantidad: cantidadTotal,
          costoUnitario: costoUnitarioPromedio,
          fecha: DateTime.now(),
          origen: 'ajuste',
        );
      }
    }, timeout: const Duration(seconds: 12));
  }

  Stream<List<VentaEnEsperaModel>> obtenerVentasEnEspera() {
    return _colEspera.orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => VentaEnEsperaModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// Ventas guardadas pero sin imprimir (típicamente hechas desde el
  /// celular sin la impresora a mano). Sin `orderBy` a propósito -filtrar
  /// por `pendienteImpresion` y además ordenar por fecha pediría un índice
  /// compuesto en Firestore- así que el orden se resuelve acá en memoria.
  Stream<List<VentaModel>> obtenerVentasPendientesImpresion() {
    return _colVentas.where('pendienteImpresion', isEqualTo: true).snapshots().map((snap) {
      final ventas = snap.docs.map((d) => VentaModel.fromMap(d.id, d.data(), const [])).toList();
      ventas.sort((a, b) => (b.fechaRegistro ?? DateTime(0)).compareTo(a.fechaRegistro ?? DateTime(0)));
      return ventas;
    });
  }

  Future<String> guardarVentaEnEspera(VentaEnEsperaModel sesion) async {
    final ref = await _colEspera.add(sesion.toMap());
    return ref.id;
  }

  Future<void> actualizarVentaEnEspera(String id, VentaEnEsperaModel sesion) async {
    await _colEspera.doc(id).update(sesion.toMap());
  }

  Future<void> eliminarVentaEnEspera(String id) async {
    await _colEspera.doc(id).delete();
  }
}
