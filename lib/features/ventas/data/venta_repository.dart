import 'package:cloud_firestore/cloud_firestore.dart';
import 'venta_model.dart';
import 'venta_en_espera_model.dart';
import 'item_venta_model.dart';
import '../../../core/utils/formato_moneda.dart';

class VentaRepository {
  final _db = FirebaseFirestore.instance;
  final _colVentas = FirebaseFirestore.instance.collection('ventas');
  final _colEspera = FirebaseFirestore.instance.collection('ventasEnEspera');
  final _colContadores = FirebaseFirestore.instance.collection('contadores');
  final _colVentasCredito = FirebaseFirestore.instance.collection('ventasCredito');

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

  /// Solo para mostrar una vista previa del próximo número (no lo consume).
  Future<int> obtenerProximoCorrelativo(String tipoDocumento) async {
    final snap = await _colContadores.doc(_claveContador(tipoDocumento)).get();
    final actual = ((snap.data()?['ultimo'] ?? 0) as num).toInt();
    return actual + 1;
  }

  Future<VentaModel> registrarVenta({
    required String tipoDocumento,
    required String condicion,
    required String metodoPago,
    required String documentoCliente,
    required String nombreCliente,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    required String oc,
    required String regExonerado,
    required String regSag,
    double descuentoGlobal = 0,
    required List<ItemVentaModel> items,
    required double montoPago,
    required double montoCambio,
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
  }) async {
    final claveContador = _claveContador(tipoDocumento);
    final contadorRef = _colContadores.doc(claveContador);
    final ventaRef = _colVentas.doc();
    final itemsADescontar = items.where((i) => !i.reembasado).toList();

    late String numeroDocumento;

    // Timeout corto (el default del SDK es 30s): en cajas con internet
    // lento/intermitente es mejor que el cajero vea rápido que falló y
    // pueda reintentar, a que la pantalla quede "cargando" media hora.
    await _db.runTransaction((transaction) async {
      final contadorSnap = await transaction.get(contadorRef);
      final actual = ((contadorSnap.data()?['ultimo'] ?? 0) as num).toInt();
      final nuevo = actual + 1;
      numeroDocumento = _formatearCorrelativo(tipoDocumento, nuevo);

      // Las lecturas se disparan todas a la vez (Future.wait) en vez de una
      // por una: con varios productos en la venta, esperar cada round-trip
      // en serie es lo que hacía que registrar una venta se sintiera colgado
      // en cajas con internet lento.
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        itemsADescontar.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < itemsADescontar.length; i++) {
        stocksActuales[itemsADescontar[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      transaction.set(contadorRef, {'ultimo': nuevo}, SetOptions(merge: true));

      transaction.set(ventaRef, {
        'tipoDocumento': tipoDocumento,
        'numeroDocumento': numeroDocumento,
        'documentoCliente': documentoCliente,
        'nombreCliente': nombreCliente,
        'metodoPago': metodoPago,
        'montoPago': montoPago,
        'montoCambio': montoCambio,
        'subtotal': subtotal,
        'impuesto': impuesto,
        'totalAPagar': totalAPagar,
        'condicion': condicion,
        'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento) : null,
        'fechaRegistro': Timestamp.fromDate(fechaRegistro),
        'estado': 'Activa',
        'usuarioRegistro': usuario,
        'cantidadProductos': items.fold<double>(0, (s, i) => s + i.cantidad),
        'oc': oc,
        'regExonerado': regExonerado,
        'regSag': regSag,
        'descuentoGlobal': descuentoGlobal,
      });

      for (final item in items) {
        final itemRef = ventaRef.collection('detalle').doc();
        // 'fecha' permite consultar el detalle de todas las ventas de un
        // rango con una sola query (collectionGroup) en vez de tener que
        // leer la subcolección de cada venta una por una.
        transaction.set(itemRef, {...item.toMap(), 'fecha': Timestamp.fromDate(fechaRegistro)});
      }

      if (condicion == 'Credito') {
        transaction.set(_colVentasCredito.doc(ventaRef.id), {
          'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
          'nombreCliente': nombreCliente,
          'numeroDocumento': numeroDocumento,
          'montoTotal': totalAPagar,
          'saldoPendiente': totalAPagar,
          'fechaRegistro': Timestamp.fromDate(fechaRegistro),
          'fechaVencimiento': Timestamp.fromDate(fechaVencimiento ?? fechaRegistro),
        });
      }

      for (final item in itemsADescontar) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stocksActuales[item.idProducto] ?? 0;
        final stockNuevo = stockActual - item.cantidad;
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

    return VentaModel(
      id: ventaRef.id,
      tipoDocumento: tipoDocumento,
      numeroDocumento: numeroDocumento,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      metodoPago: metodoPago,
      montoPago: montoPago,
      montoCambio: montoCambio,
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
      descuentoGlobal: descuentoGlobal,
      detalle: items,
    );
  }

  Future<VentaModel?> obtenerVentaPorId(String id) async {
    final snap = await _colVentas.doc(id).get();
    if (!snap.exists) return null;
    final detalleSnap = await _colVentas.doc(id).collection('detalle').get();
    final items = detalleSnap.docs.map((d) => ItemVentaModel.fromMap(d.data())).toList();
    return VentaModel.fromMap(id, snap.data()!, items);
  }

  Future<VentaModel?> obtenerVentaPorNumeroDocumento(String numeroDocumento) async {
    final texto = numeroDocumento.trim();
    if (texto.isEmpty) return null;
    final query = await _colVentas.where('numeroDocumento', isEqualTo: texto).limit(1).get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    final detalleSnap = await doc.reference.collection('detalle').get();
    final items = detalleSnap.docs.map((d) => ItemVentaModel.fromMap(d.data())).toList();
    return VentaModel.fromMap(doc.id, doc.data(), items);
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
    final items = detalleSnap.docs.map((d) => ItemVentaModel.fromMap(d.data())).toList();

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

    final itemsARestaurar = items.where((i) => !i.reembasado).toList();

    await _db.runTransaction((transaction) async {
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        itemsARestaurar.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < itemsARestaurar.length; i++) {
        stocksActuales[itemsARestaurar[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
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

      for (final item in itemsARestaurar) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stocksActuales[item.idProducto] ?? 0;
        final stockNuevo = stockActual + item.cantidad;
        transaction.update(ref, {'stock': stockNuevo});
        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Anulación de venta $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });
      }
    }, timeout: const Duration(seconds: 12));
  }

  Stream<List<VentaEnEsperaModel>> obtenerVentasEnEspera() {
    return _colEspera.orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => VentaEnEsperaModel.fromMap(d.id, d.data())).toList();
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
