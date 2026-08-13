import 'package:cloud_firestore/cloud_firestore.dart';
import 'cliente_model.dart';

class ClienteRepository {
  final _col = FirebaseFirestore.instance.collection('clientes');

  Stream<List<ClienteModel>> obtenerClientes() {
    return _col.orderBy('nombreCompleto').snapshots().map((snap) {
      return snap.docs.map((d) => ClienteModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear({
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
  }) async {
    if (dni.isNotEmpty) {
      final existe = await _col.where('dni', isEqualTo: dni).limit(1).get();
      if (existe.docs.isNotEmpty) {
        throw Exception('Ya existe un cliente con ese DNI');
      }
    }
    await _col.add({
      'dni': dni,
      'nombreCompleto': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
  }

  Future<void> actualizar({
    required String id,
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
  }) async {
    if (dni.isNotEmpty) {
      final existe = await _col.where('dni', isEqualTo: dni).limit(2).get();
      final duplicado = existe.docs.any((d) => d.id != id);
      if (duplicado) {
        throw Exception('Ya existe un cliente con ese DNI');
      }
    }
    await _col.doc(id).update({
      'dni': dni,
      'nombreCompleto': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }
}
