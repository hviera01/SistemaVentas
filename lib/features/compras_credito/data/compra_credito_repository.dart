import 'package:cloud_firestore/cloud_firestore.dart';
import 'compra_credito_model.dart';
import 'abono_compra_model.dart';
import 'compra_credito_import_service.dart';
import '../../../core/utils/formato_moneda.dart';

class DistribucionAbono {
  final CompraCreditoModel compra;
  final double montoAplicado;
  final double saldoResultante;

  DistribucionAbono({required this.compra, required this.montoAplicado, required this.saldoResultante});
}

class ResumenImportacionComprasCredito {
  final int creados;
  final int proveedoresCreados;

  ResumenImportacionComprasCredito({required this.creados, required this.proveedoresCreados});
}

class CompraCreditoRepository {
  final _db = FirebaseFirestore.instance;
  final _col = FirebaseFirestore.instance.collection('comprasCredito');
  final _colProveedores = FirebaseFirestore.instance.collection('proveedores');

  String _generarNumeroDocumento() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return ahora.substring(ahora.length - 8);
  }

  Stream<List<CompraCreditoModel>> obtenerCompras() {
    return _col.orderBy('fechaRegistro', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => CompraCreditoModel.fromMap(d.id, d.data())).toList();
    });
  }

  Stream<List<AbonoCompraModel>> obtenerAbonos(String idCompra) {
    return _col.doc(idCompra).collection('abonosCompra').orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => AbonoCompraModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crearCreditoManual({
    required String idProveedor,
    required String documentoProveedor,
    required String nombreProveedor,
    required String numeroDocumento,
    required String noFactura,
    required double montoTotal,
    required double saldoPendiente,
    required DateTime fechaVencimiento,
  }) async {
    await _col.add({
      'idProveedor': idProveedor,
      'documentoProveedor': documentoProveedor.isEmpty ? 'N/A' : documentoProveedor,
      'nombreProveedor': nombreProveedor,
      'numeroDocumento': numeroDocumento.isEmpty ? _generarNumeroDocumento() : numeroDocumento,
      'noFactura': noFactura,
      'montoTotal': redondearMoneda(montoTotal),
      'saldoPendiente': redondearMoneda(saldoPendiente),
      'fechaRegistro': FieldValue.serverTimestamp(),
      'fechaVencimiento': Timestamp.fromDate(fechaVencimiento),
      'manual': true,
    });
  }

  Future<void> registrarAbono({
    required String idCompra,
    required String idProveedor,
    required String nombreProveedor,
    required double saldoAnterior,
    required double montoAbonado,
    required double interes,
    required String metodoPago,
    required String numeroRecibo,
    required String usuario,
    required DateTime fecha,
  }) async {
    // Redondear a centavos antes de guardar: sin esto, restas sucesivas de
    // `double` binario dejan saldos como 0.0000000000018 en vez de 0 exacto,
    // que la app muestra como "L.0.00" pero que técnicamente sigue siendo
    // > 0 -así una factura ya pagada queda marcada "Debe" para siempre hasta
    // que alguien note el error visualmente y tenga que forzarla con un
    // abono simbólico (caso real: proveedor Ventura, 2026-08-29)-.
    if (montoAbonado > saldoAnterior + interes + 0.01) {
      throw Exception('El abono (${formatearMoneda(montoAbonado)}) supera el saldo disponible en esa factura (${formatearMoneda(saldoAnterior + interes)})');
    }
    final nuevoSaldo = redondearMoneda((saldoAnterior - montoAbonado + interes).clamp(0, double.infinity).toDouble());
    final batch = _db.batch();
    batch.update(_col.doc(idCompra), {'saldoPendiente': nuevoSaldo});
    final abonoRef = _col.doc(idCompra).collection('abonosCompra').doc();
    batch.set(abonoRef, {
      'idCompra': idCompra,
      'idProveedor': idProveedor,
      'nombreProveedor': nombreProveedor,
      'fecha': Timestamp.fromDate(fecha),
      'montoAbonado': redondearMoneda(montoAbonado),
      'saldoAnterior': redondearMoneda(saldoAnterior),
      'interes': redondearMoneda(interes),
      'saldoPendiente': nuevoSaldo,
      'metodoPago': metodoPago,
      'numeroRecibo': numeroRecibo,
      'usuario': usuario,
    });
    await batch.commit();
  }

  /// Recalcula, en orden cronológico, el saldoAnterior/saldoPendiente de cada
  /// abono restante de una compra y el saldoPendiente final de la compra —
  /// se usa después de editar o eliminar un abono, porque cada abono depende
  /// del resultado del anterior (una cadena), así que tocar uno de en medio
  /// deja mal a todos los que vienen después si no se recorre de nuevo desde
  /// el montoTotal. Lanza una excepción si algún paso da negativo antes de
  /// redondear/limitar a 0 (significa que ese abono, con los datos nuevos,
  /// pagaría más de lo que había pendiente en ese momento).
  Future<void> _recalcularCadenaAbonos(String idCompra, double montoTotal) async {
    final abonosSnap = await _col.doc(idCompra).collection('abonosCompra').orderBy('fecha').get();
    final batch = _db.batch();
    var saldo = redondearMoneda(montoTotal);
    for (final doc in abonosSnap.docs) {
      final data = doc.data();
      final montoAbonado = (data['montoAbonado'] ?? 0).toDouble();
      final interes = (data['interes'] ?? 0).toDouble();
      final saldoAnterior = saldo;
      final crudo = saldoAnterior - montoAbonado + interes;
      if (crudo < -0.01) {
        throw Exception('El abono de ${formatearMoneda(montoAbonado)} superaría el saldo disponible en ese momento (${formatearMoneda(saldoAnterior + interes)})');
      }
      saldo = redondearMoneda(crudo.clamp(0, double.infinity).toDouble());
      batch.update(doc.reference, {'saldoAnterior': redondearMoneda(saldoAnterior), 'saldoPendiente': saldo});
    }
    batch.update(_col.doc(idCompra), {'saldoPendiente': saldo});
    await batch.commit();
  }

  Future<void> eliminarAbono({required String idCompra, required String idAbono, required double montoTotal}) async {
    await _col.doc(idCompra).collection('abonosCompra').doc(idAbono).delete();
    await _recalcularCadenaAbonos(idCompra, montoTotal);
  }

  Future<void> editarAbono({
    required String idCompra,
    required String idAbono,
    required double montoTotal,
    required double montoAbonado,
    required double interes,
    required DateTime fecha,
    required String metodoPago,
    required String numeroRecibo,
  }) async {
    await _col.doc(idCompra).collection('abonosCompra').doc(idAbono).update({
      'montoAbonado': redondearMoneda(montoAbonado),
      'interes': redondearMoneda(interes),
      'fecha': Timestamp.fromDate(fecha),
      'metodoPago': metodoPago,
      'numeroRecibo': numeroRecibo,
    });
    await _recalcularCadenaAbonos(idCompra, montoTotal);
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  Future<List<CompraCreditoModel>> obtenerComprasPorProveedor(String idProveedor) async {
    final snap = await _col.where('idProveedor', isEqualTo: idProveedor).get();
    return snap.docs.map((d) => CompraCreditoModel.fromMap(d.id, d.data())).toList();
  }

  Future<List<AbonoCompraModel>> obtenerAbonosPorProveedor(String idProveedor) async {
    final snap = await _db.collectionGroup('abonosCompra').where('idProveedor', isEqualTo: idProveedor).get();
    return snap.docs.map((d) => AbonoCompraModel.fromMap(d.id, d.data())).toList();
  }

  /// Crea en lote los créditos de compra de una importación desde Excel.
  /// Cada fila se agrega como un crédito manual nuevo (no empareja con
  /// créditos existentes). Los proveedores que no existan todavía por nombre
  /// se crean automáticamente, igual que las categorías al importar productos.
  Future<ResumenImportacionComprasCredito> importarCreditos(List<FilaImportacionCompraCredito> filas) async {
    final proveedoresSnap = await _colProveedores.get();
    final idProveedorPorNombre = <String, String>{};
    final rtnPorId = <String, String>{};
    for (final d in proveedoresSnap.docs) {
      final nombre = (d.data()['razonSocial'] as String? ?? '').trim().toLowerCase();
      if (nombre.isNotEmpty) idProveedorPorNombre[nombre] = d.id;
      rtnPorId[d.id] = (d.data()['rtn'] as String? ?? '');
    }

    var creados = 0, proveedoresCreados = 0;
    var batch = _db.batch();
    var operacionesEnBatch = 0;

    Future<void> descargarBatch() async {
      if (operacionesEnBatch == 0) return;
      await batch.commit();
      batch = _db.batch();
      operacionesEnBatch = 0;
    }

    for (final fila in filas.where((f) => f.valido)) {
      final nombreNorm = fila.nombreProveedor.trim().toLowerCase();
      var idProveedor = idProveedorPorNombre[nombreNorm];
      if (idProveedor == null) {
        final ref = _colProveedores.doc();
        batch.set(ref, {
          'rtn': '',
          'razonSocial': fila.nombreProveedor.trim(),
          'correo': '',
          'telefono': '',
          'estado': true,
          'fechaRegistro': FieldValue.serverTimestamp(),
        });
        idProveedor = ref.id;
        idProveedorPorNombre[nombreNorm] = idProveedor;
        rtnPorId[idProveedor] = '';
        proveedoresCreados++;
        operacionesEnBatch++;
      }

      final ref = _col.doc();
      batch.set(ref, {
        'idProveedor': idProveedor,
        'documentoProveedor': rtnPorId[idProveedor]?.isNotEmpty == true ? rtnPorId[idProveedor] : 'N/A',
        'nombreProveedor': fila.nombreProveedor,
        'numeroDocumento': fila.numeroDocumento.isEmpty ? fila.numeroFila.toString() : fila.numeroDocumento,
        'noFactura': fila.noFactura,
        'montoTotal': fila.montoTotal,
        'saldoPendiente': fila.saldoPendiente,
        'fechaRegistro': fila.fechaRegistro != null ? Timestamp.fromDate(fila.fechaRegistro!) : FieldValue.serverTimestamp(),
        'fechaVencimiento': Timestamp.fromDate(fila.fechaVencimiento),
        'manual': true,
      });
      creados++;
      operacionesEnBatch++;
      if (operacionesEnBatch >= 400) await descargarBatch();
    }
    await descargarBatch();

    return ResumenImportacionComprasCredito(creados: creados, proveedoresCreados: proveedoresCreados);
  }

  /// Calcula cómo se repartiría [monto] entre las facturas pendientes de un proveedor,
  /// pagando primero las que vencen antes. No escribe nada todavía.
  List<DistribucionAbono> calcularDistribucion(List<CompraCreditoModel> comprasProveedor, double monto) {
    final pendientes = comprasProveedor.where((c) => !c.liquidada).toList()
      ..sort((a, b) {
        if (a.fechaVencimiento == null && b.fechaVencimiento == null) return 0;
        if (a.fechaVencimiento == null) return 1;
        if (b.fechaVencimiento == null) return -1;
        return a.fechaVencimiento!.compareTo(b.fechaVencimiento!);
      });

    var restante = redondearMoneda(monto);
    final resultado = <DistribucionAbono>[];
    for (final compra in pendientes) {
      if (restante <= 0) break;
      final aplicado = restante >= compra.saldoPendiente ? compra.saldoPendiente : restante;
      resultado.add(DistribucionAbono(compra: compra, montoAplicado: aplicado, saldoResultante: redondearMoneda(compra.saldoPendiente - aplicado)));
      restante = redondearMoneda(restante - aplicado);
    }
    return resultado;
  }

  Future<void> registrarAbonoGeneral({
    required List<DistribucionAbono> distribucion,
    required String metodoPago,
    required String usuario,
    required DateTime fecha,
  }) async {
    for (final item in distribucion) {
      if (item.montoAplicado > item.compra.saldoPendiente + 0.01) {
        throw Exception('El monto asignado a la factura ${item.compra.noFactura} supera su saldo pendiente');
      }
    }
    final batch = _db.batch();
    for (final item in distribucion) {
      batch.update(_col.doc(item.compra.id), {'saldoPendiente': item.saldoResultante});
      final abonoRef = _col.doc(item.compra.id).collection('abonosCompra').doc();
      batch.set(abonoRef, {
        'idCompra': item.compra.id,
        'idProveedor': item.compra.idProveedor,
        'nombreProveedor': item.compra.nombreProveedor,
        'fecha': Timestamp.fromDate(fecha),
        'montoAbonado': item.montoAplicado,
        'saldoAnterior': item.compra.saldoPendiente,
        'interes': 0,
        'saldoPendiente': item.saldoResultante,
        'metodoPago': metodoPago,
        'numeroRecibo': '',
        'usuario': usuario,
        'esAbonoGeneral': true,
      });
    }
    await batch.commit();
  }

  Future<List<AbonoCompraModel>> obtenerAbonosPorRango(DateTime inicio, DateTime finInclusive) async {
    final snap = await _db
        .collectionGroup('abonosCompra')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .get();
    return snap.docs.map((d) => AbonoCompraModel.fromMap(d.id, d.data())).toList();
  }
}
