import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/device_id.dart';
import 'dispositivo_model.dart';

class DispositivoRepository {
  final _col = FirebaseFirestore.instance.collection('dispositivos');

  /// Se llama al iniciar sesión (ver AppShell.initState): actualiza (o crea,
  /// la primera vez) el registro de este equipo con la versión instalada y
  /// quién inició sesión ahora. No bloquea el arranque de la app si falla
  /// -es solo informativo para el módulo de Dispositivos, nunca debe impedir
  /// que alguien pueda seguir usando la app-.
  Future<void> reportar({required int versionApp, required String usuario}) async {
    try {
      final id = await obtenerIdDispositivo();
      await _col.doc(id).set({
        'plataforma': obtenerPlataforma(),
        'versionApp': versionApp,
        'usuario': usuario,
        'ultimaConexion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silencioso a propósito: ver comentario arriba.
    }
  }

  Stream<List<DispositivoModel>> obtenerDispositivos() {
    return _col.orderBy('ultimaConexion', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => DispositivoModel.fromMap(d.id, d.data())).toList();
    });
  }
}
