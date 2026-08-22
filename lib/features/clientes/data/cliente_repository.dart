import 'package:cloud_firestore/cloud_firestore.dart';
import 'cliente_model.dart';

class ClienteRepository {
  final _col = FirebaseFirestore.instance.collection('clientes');

  Stream<List<ClienteModel>> obtenerClientes() {
    return _col.orderBy('nombreCompleto').snapshots().map((snap) {
      return snap.docs.map((d) => ClienteModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<ClienteModel?> obtenerPorId(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return ClienteModel.fromMap(snap.id, snap.data()!);
  }

  Future<void> crear({
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
    String? idReferidor,
  }) async {
    if (dni.isNotEmpty) {
      final existe = await _col.where('dni', isEqualTo: dni).limit(1).get();
      if (existe.docs.isNotEmpty) {
        throw Exception('Ya existe un cliente con ese DNI');
      }
    }
    // Doc nuevo: no hay fechaUltimaCompra previa que pisar, así que acá sí
    // alcanza con toMap() completo (idReferidor sí es editable desde el
    // formulario, a diferencia de fechaUltimaCompra).
    final datos = ClienteModel(id: '', dni: dni, nombreCompleto: nombreCompleto, direccion: direccion, telefono: telefono, estado: estado, idReferidor: idReferidor).toMap();
    await _col.add({...datos, 'fechaRegistro': FieldValue.serverTimestamp()});
  }

  Future<void> actualizar({
    required String id,
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
    String? idReferidor,
  }) async {
    if (dni.isNotEmpty) {
      final existe = await _col.where('dni', isEqualTo: dni).limit(2).get();
      final duplicado = existe.docs.any((d) => d.id != id);
      if (duplicado) {
        throw Exception('Ya existe un cliente con ese DNI');
      }
    }
    // A propósito NO se usa ClienteModel.toMap() completo acá: este método
    // es el que dispara el formulario de "Editar cliente" (o "Completar
    // datos" desde la venta), que no conoce ni edita fechaUltimaCompra -si
    // se mandara el toMap() completo con ese campo en null, se borraría la
    // fecha de última compra que registró la venta cada vez que alguien
    // solo corrige el teléfono-. idReferidor sí es editable desde el
    // formulario (selector "¿Quién lo refirió?"), así que sí se incluye acá
    // explícitamente -incluyendo cuando viene null, que es "Ninguno" y debe
    // poder limpiar un referidor ya asignado-.
    await _col.doc(id).update({
      'dni': dni,
      'nombreCompleto': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
      'idReferidor': idReferidor,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }
}
