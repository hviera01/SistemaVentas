import 'package:cloud_firestore/cloud_firestore.dart';
import 'compra_model.dart';
import 'item_compra_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../productos/data/lote_costo_repository.dart';

class CompraRepository {
  final _db = FirebaseFirestore.instance;
  final _colCompras = FirebaseFirestore.instance.collection('compras');
  final _colContadores = FirebaseFirestore.instance.collection('contadores');
  final _colComprasCredito = FirebaseFirestore.instance.collection('comprasCredito');
  final _lotes = LoteCostoRepository();

  String _formatearCorrelativo(int numero) => numero.toString().padLeft(8, '0');

  Future<CompraModel> registrarCompra({
    required String noFactura,
    required String idProveedor,
    required String documentoProveedor,
    required String razonSocial,
    required String condicion,
    required String metodoPago,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    double descuentoGlobalPorcentaje = 0,
    double descuentoTotalMonto = 0,
    double isvPorcentaje = 15,
    double ajusteManual = 0,
    required List<ItemCompraModel> items,
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
  }) async {
    final contadorRef = _colContadores.doc('compra');
    final compraRef = _colCompras.doc();

    late String numeroDocumento;

    // Timeout corto (el default del SDK es 30s): en cajas con internet
    // lento/intermitente es mejor que se vea rápido que falló y se pueda
    // reintentar, a que la pantalla quede "cargando" media hora.
    await _db.runTransaction((transaction) async {
      final contadorSnap = await transaction.get(contadorRef);
      final actual = ((contadorSnap.data()?['ultimo'] ?? 0) as num).toInt();
      final nuevo = actual + 1;
      numeroDocumento = _formatearCorrelativo(nuevo);

      // Lecturas en paralelo (Future.wait) en vez de una por una: con varios
      // productos en la compra, esperar cada round-trip en serie hacía que
      // registrar una compra se sintiera colgado con internet lento.
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        items.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < items.length; i++) {
        stocksActuales[items[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      transaction.set(contadorRef, {'ultimo': nuevo}, SetOptions(merge: true));

      transaction.set(compraRef, {
        'tipoDocumento': 'Factura',
        'numeroDocumento': numeroDocumento,
        'noFactura': noFactura,
        'idProveedor': idProveedor,
        'documentoProveedor': documentoProveedor,
        'razonSocial': razonSocial,
        'condicion': condicion,
        'metodoPago': metodoPago,
        'subtotal': subtotal,
        'descuentoGlobalPorcentaje': descuentoGlobalPorcentaje,
        'descuentoTotalMonto': descuentoTotalMonto,
        'isvPorcentaje': isvPorcentaje,
        'impuesto': impuesto,
        'ajusteManual': ajusteManual,
        'totalAPagar': totalAPagar,
        'fechaRegistro': Timestamp.fromDate(fechaRegistro),
        'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento) : null,
        'estado': 'Activa',
        'usuarioRegistro': usuario,
        'cantidadProductos': items.fold<double>(0, (s, i) => s + i.cantidad),
      });

      for (final item in items) {
        final itemRef = compraRef.collection('detalle').doc();
        // 'fecha' permite consultar el detalle de todas las compras de un
        // rango con una sola query (collectionGroup) en vez de tener que
        // leer la subcolección de cada compra una por una.
        transaction.set(itemRef, {...item.toMap(), 'fecha': Timestamp.fromDate(fechaRegistro)});
      }

      if (condicion == 'Credito') {
        transaction.set(_colComprasCredito.doc(compraRef.id), {
          'idProveedor': idProveedor,
          'documentoProveedor': documentoProveedor.isEmpty ? 'N/A' : documentoProveedor,
          'nombreProveedor': razonSocial,
          'numeroDocumento': numeroDocumento,
          'noFactura': noFactura,
          'montoTotal': totalAPagar,
          'saldoPendiente': totalAPagar,
          'fechaRegistro': Timestamp.fromDate(fechaRegistro),
          'fechaVencimiento': Timestamp.fromDate(fechaVencimiento ?? fechaRegistro),
          'manual': false,
        });
      }

      for (final item in items) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stocksActuales[item.idProducto] ?? 0;
        final stockNuevo = stockActual + item.cantidad;

        // Costo vigente del producto: precio unitario menos el descuento de
        // línea (importe gravado), más el ISV de esta compra.
        final precioFinalConIsv = redondearMoneda(item.precioCompra * (1 - item.descuentoPorcentaje / 100) * (1 + isvPorcentaje / 100));

        final Map<String, dynamic> actualizacion = {'stock': stockNuevo, 'precioCompra': precioFinalConIsv};
        if (item.precioVentaNuevo != null) {
          actualizacion['precioVenta'] = item.precioVentaNuevo!;
        }
        transaction.update(ref, actualizacion);

        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Compra $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });

        final historialPrecioRef = ref.collection('historialPreciosCompra').doc();
        transaction.set(historialPrecioRef, {
          'idCompra': compraRef.id,
          'precioCompra': precioFinalConIsv,
          'precioUnitario': item.precioCompra,
          'descuentoPorcentaje': item.descuentoPorcentaje,
          'isvPorcentaje': isvPorcentaje,
          'cantidad': item.cantidad,
          'numeroDocumento': numeroDocumento,
          'noFactura': noFactura,
          'proveedor': razonSocial,
          'usuario': usuario,
          'fecha': FieldValue.serverTimestamp(),
        });

        // Lote de costo propio para esta compra: es lo que permite que,
        // si el mismo producto se compró antes a otro precio, cada venta
        // futura consuma el costo real del lote que le toca (FIFO) en vez
        // de un costo único por producto.
        _lotes.crearLote(
          transaction,
          item.idProducto,
          cantidad: item.cantidad,
          costoUnitario: precioFinalConIsv,
          fecha: fechaRegistro,
          origen: 'compra',
          idCompra: compraRef.id,
        );
      }
    }, timeout: const Duration(seconds: 12));

    return CompraModel(
      id: compraRef.id,
      tipoDocumento: 'Factura',
      numeroDocumento: numeroDocumento,
      noFactura: noFactura,
      idProveedor: idProveedor,
      documentoProveedor: documentoProveedor,
      razonSocial: razonSocial,
      condicion: condicion,
      metodoPago: metodoPago,
      subtotal: subtotal,
      descuentoGlobalPorcentaje: descuentoGlobalPorcentaje,
      descuentoTotalMonto: descuentoTotalMonto,
      isvPorcentaje: isvPorcentaje,
      impuesto: impuesto,
      ajusteManual: ajusteManual,
      totalAPagar: totalAPagar,
      fechaRegistro: fechaRegistro,
      fechaVencimiento: fechaVencimiento,
      estado: 'Activa',
      usuarioRegistro: usuario,
      cantidadProductos: items.fold<double>(0, (s, i) => s + i.cantidad),
      detalle: items,
    );
  }

  Future<CompraModel?> obtenerCompraPorId(String id) async {
    final snap = await _colCompras.doc(id).get();
    if (!snap.exists) return null;
    final detalleSnap = await _colCompras.doc(id).collection('detalle').get();
    final items = detalleSnap.docs.map((d) => ItemCompraModel.fromMap(d.data())).toList();
    return CompraModel.fromMap(id, snap.data()!, items);
  }

  /// Busca por número de documento (correlativo interno, ej. "00000123") o
  /// por número de factura (el que trae la factura física del proveedor).
  /// El número de documento se normaliza quitando ceros a la izquierda antes
  /// de comparar, así "123" encuentra "00000123" sin que el usuario tenga que
  /// escribir el correlativo completo con ceros.
  Future<CompraModel?> obtenerCompraPorNumeroDocumento(String numeroDocumento) async {
    final texto = numeroDocumento.trim();
    if (texto.isEmpty) return null;

    final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;

    if (soloDigitos.isNotEmpty) {
      final sinCeros = soloDigitos.replaceFirst(RegExp(r'^0+'), '');
      final correlativo = _formatearCorrelativo(int.parse(sinCeros.isEmpty ? '0' : sinCeros));
      final porDocumento = await _colCompras.where('numeroDocumento', isEqualTo: correlativo).limit(1).get();
      if (porDocumento.docs.isNotEmpty) doc = porDocumento.docs.first;
    }

    if (doc == null) {
      final porFactura = await _colCompras.where('noFactura', isEqualTo: texto).limit(1).get();
      if (porFactura.docs.isNotEmpty) doc = porFactura.docs.first;
    }

    if (doc == null) return null;
    final detalleSnap = await doc.reference.collection('detalle').get();
    final items = detalleSnap.docs.map((d) => ItemCompraModel.fromMap(d.data())).toList();
    return CompraModel.fromMap(doc.id, doc.data(), items);
  }

  /// Anula una compra: la marca como 'Anulada', descuenta del inventario el
  /// stock que había sumado, y si era una compra a crédito sin abonos,
  /// elimina su registro en `comprasCredito`.
  Future<void> anularCompra({
    required String id,
    required String usuario,
    String motivo = '',
  }) async {
    final compraSnap = await _colCompras.doc(id).get();
    if (!compraSnap.exists) {
      throw Exception('No se encontró la compra');
    }
    final data = compraSnap.data()!;
    if (data['estado'] == 'Anulada') {
      throw Exception('Esta compra ya está anulada');
    }
    final condicion = data['condicion'] as String? ?? '';
    final numeroDocumento = data['numeroDocumento'] as String? ?? '';

    final detalleSnap = await _colCompras.doc(id).collection('detalle').get();
    final items = detalleSnap.docs.map((d) => ItemCompraModel.fromMap(d.data())).toList();

    var creditoExiste = false;
    if (condicion == 'Credito') {
      final creditoSnap = await _colComprasCredito.doc(id).get();
      if (creditoSnap.exists) {
        creditoExiste = true;
        final montoTotal = ((creditoSnap.data()?['montoTotal'] ?? 0) as num).toDouble();
        final saldoPendiente = ((creditoSnap.data()?['saldoPendiente'] ?? 0) as num).toDouble();
        if (saldoPendiente < montoTotal) {
          throw Exception('No se puede anular: esta compra a crédito ya tiene abonos registrados');
        }
      }
    }

    // Ubicar (fuera de la transacción, ya que es una query y no una lectura
    // por referencia) el lote que generó esta compra en cada producto, para
    // poder descontarle lo que corresponda al anularla.
    final loteRefPorProducto = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final item in items) {
      final query = await _lotes.colLotes(item.idProducto).where('idCompra', isEqualTo: id).limit(1).get();
      if (query.docs.isNotEmpty) loteRefPorProducto[item.idProducto] = query.docs.first.reference;
    }

    await _db.runTransaction((transaction) async {
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        items.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < items.length; i++) {
        stocksActuales[items[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      // Misma regla de "todas las lecturas antes que cualquier escritura":
      // se leen ahora (transaccionalmente) los lotes ya ubicados arriba.
      final loteSnapsPorProducto = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in loteRefPorProducto.entries) {
        loteSnapsPorProducto[entry.key] = await transaction.get(entry.value);
      }

      transaction.update(_colCompras.doc(id), {
        'estado': 'Anulada',
        'usuarioAnulacion': usuario,
        'motivoAnulacion': motivo,
        'fechaAnulacion': FieldValue.serverTimestamp(),
      });

      if (creditoExiste) {
        transaction.delete(_colComprasCredito.doc(id));
      }

      for (final item in items) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stocksActuales[item.idProducto] ?? 0;
        final stockNuevo = stockActual - item.cantidad;
        transaction.update(ref, {'stock': stockNuevo});

        // Caso borde documentado: si ya se vendió parte de este lote antes
        // de anular la compra, no se puede "des-vender" retroactivamente —
        // se descuenta como máximo lo que le queda al lote.
        final loteSnap = loteSnapsPorProducto[item.idProducto];
        if (loteSnap != null && loteSnap.exists) {
          final restanteActual = ((loteSnap.data()?['cantidadRestante'] ?? 0) as num).toDouble();
          final nuevoRestante = restanteActual - item.cantidad;
          transaction.update(loteSnap.reference, {'cantidadRestante': nuevoRestante < 0 ? 0.0 : nuevoRestante});
        }

        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Anulación de compra $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });
      }
    }, timeout: const Duration(seconds: 12));
  }
}
