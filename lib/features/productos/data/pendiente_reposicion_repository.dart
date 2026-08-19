import 'package:cloud_firestore/cloud_firestore.dart';
import 'pendiente_reposicion_model.dart';

class PendienteReposicionRepository {
  final _col = FirebaseFirestore.instance.collection('pendientesReposicion');

  /// Solo las que siguen esperando compra, la más vieja primero -mismo
  /// orden en el que CompraRepository.registrarCompra las va a repartir-.
  Stream<List<PendienteReposicionModel>> obtenerPendientes() {
    return _col.where('estado', isEqualTo: 'Pendiente').orderBy('fechaRegistro').snapshots().map((snap) {
      return snap.docs.map((d) => PendienteReposicionModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// El negocio decide a mano que esto ya no va a esperar una compra (se
  /// resolvió de otra forma, o fue un error al marcarla). No borra el
  /// documento -queda como 'Cancelado' para no perder el rastro-, pero deja
  /// de aparecer en [obtenerPendientes] y de competir por futuras compras.
  Future<void> cancelar(String id) async {
    await _col.doc(id).update({'estado': 'Cancelado', 'fechaCompletado': FieldValue.serverTimestamp()});
  }
}
