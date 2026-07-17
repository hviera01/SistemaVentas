import 'package:cloud_firestore/cloud_firestore.dart';
import 'venta_credito_model.dart';
import 'abono_model.dart';

class VentaCreditoRepository {
  final _db = FirebaseFirestore.instance;
  final _col = FirebaseFirestore.instance.collection('ventasCredito');

  String _generarNumeroDocumento() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return ahora.substring(ahora.length - 8);
  }

  Stream<List<VentaCreditoModel>> obtenerCreditos() {
    return _col.orderBy('fechaRegistro', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => VentaCreditoModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// El documento de `ventasCredito` de una venta a crédito se crea con el
  /// mismo id que la venta (ver `VentaRepository.registrarVenta`), así que se
  /// puede ir directo a buscarlo por id en vez de filtrar toda la colección.
  Future<VentaCreditoModel?> obtenerPorId(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return VentaCreditoModel.fromMap(snap.id, snap.data()!);
  }

  Stream<List<AbonoModel>> obtenerAbonos(String idCredito) {
    return _col.doc(idCredito).collection('abonos').orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => AbonoModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crearCreditoManual({
    required String documentoCliente,
    required String nombreCliente,
    required String numeroDocumento,
    required double montoTotal,
    required double saldoPendiente,
    required DateTime fechaVencimiento,
  }) async {
    await _col.add({
      'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
      'nombreCliente': nombreCliente,
      'numeroDocumento': numeroDocumento.isEmpty ? _generarNumeroDocumento() : numeroDocumento,
      'montoTotal': montoTotal,
      'saldoPendiente': saldoPendiente,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'fechaVencimiento': Timestamp.fromDate(fechaVencimiento),
    });
  }

  Future<void> registrarAbono({
    required String idCredito,
    required double saldoAnterior,
    required double montoAbonado,
    required double interes,
    required String metodoPago,
    required String numeroRecibo,
    required String usuario,
  }) async {
    final nuevoSaldo = (saldoAnterior - montoAbonado + interes).clamp(0, double.infinity).toDouble();
    final batch = _db.batch();
    batch.update(_col.doc(idCredito), {'saldoPendiente': nuevoSaldo});
    final abonoRef = _col.doc(idCredito).collection('abonos').doc();
    batch.set(abonoRef, {
      'fecha': FieldValue.serverTimestamp(),
      'montoAbonado': montoAbonado,
      'saldoAnterior': saldoAnterior,
      'interes': interes,
      'saldoPendiente': nuevoSaldo,
      'metodoPago': metodoPago,
      'numeroRecibo': numeroRecibo,
      'usuario': usuario,
    });
    await batch.commit();
  }

  Future<void> unirFacturas({
    required List<VentaCreditoModel> facturas,
    required String documentoCliente,
    required String nombreCliente,
    required DateTime fechaVencimiento,
  }) async {
    final total = facturas.fold<double>(0, (s, f) => s + f.saldoPendiente);
    final batch = _db.batch();
    for (final factura in facturas) {
      batch.update(_col.doc(factura.id), {'saldoPendiente': 0, 'fusionada': true});
    }
    final nuevaRef = _col.doc();
    batch.set(nuevaRef, {
      'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
      'nombreCliente': nombreCliente,
      'numeroDocumento': _generarNumeroDocumento(),
      'montoTotal': total,
      'saldoPendiente': total,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'fechaVencimiento': Timestamp.fromDate(fechaVencimiento),
    });
    await batch.commit();
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  Future<List<AbonoModel>> obtenerAbonosPorRango(DateTime inicio, DateTime finInclusive) async {
    final snap = await _db
        .collectionGroup('abonos')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .get();
    return snap.docs.map((d) => AbonoModel.fromMap(d.id, d.data())).toList();
  }
}
