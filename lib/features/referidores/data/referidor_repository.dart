import 'package:cloud_firestore/cloud_firestore.dart';
import 'referidor_model.dart';

class ReferidorRepository {
  final _col = FirebaseFirestore.instance.collection('referidores');

  Stream<List<ReferidorModel>> obtenerReferidores() {
    return _col.orderBy('nombreCompleto').snapshots().map((snap) {
      return snap.docs.map((d) => ReferidorModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// Usado desde Detalle de Cliente para resolver el nombre/teléfono del
  /// referidor a partir de ClienteModel.idReferidor (no hay stream propio
  /// ahí, es una lectura puntual).
  Future<ReferidorModel?> obtenerPorId(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return ReferidorModel.fromMap(snap.id, snap.data()!);
  }

  // Sin chequeo de unicidad (a diferencia de ProveedorRepository con el
  // RTN): un referidor es solo un contacto (pintor/contratista), no tiene un
  // campo tipo RTN que deba ser único.
  Future<void> crear({
    required String nombreCompleto,
    required String telefono,
    required String direccion,
    required bool estado,
  }) async {
    await _col.add({
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'direccion': direccion,
      'estado': estado,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
  }

  Future<void> actualizar({
    required String id,
    required String nombreCompleto,
    required String telefono,
    required String direccion,
    required bool estado,
  }) async {
    await _col.doc(id).update({
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'direccion': direccion,
      'estado': estado,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }
}
