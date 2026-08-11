import 'package:cloud_firestore/cloud_firestore.dart';
import 'promocion_model.dart';

/// Colección chica (se arman a mano, no crecen como las ventas) y se
/// consulta en vivo durante una venta en curso (ver buscar_producto_dialog y
/// registrar_venta_screen) para detectar promociones aplicables al
/// instante — por eso usa `.snapshots()` igual que productos/categorías/
/// clientes, no `.get()` puntual (ver auditoría de costos de Firestore:
/// esta colección entra en el mismo caso ya protegido de "reactividad
/// genuina durante una venta en curso", no en el de reportes/históricos).
class PromocionRepository {
  final _col = FirebaseFirestore.instance.collection('promociones');

  Stream<List<PromocionModel>> obtenerPromociones() {
    return _col.orderBy('creadoEn', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => PromocionModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear(PromocionModel promocion) async {
    await _col.add(promocion.toMap());
  }

  Future<void> actualizar(PromocionModel promocion) async {
    await _col.doc(promocion.id).update(promocion.toMap());
  }

  Future<void> alternarActivo(String id, bool activo) async {
    await _col.doc(id).update({'activo': activo});
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }
}
