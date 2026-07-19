import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Sesiones cortas para usar el celular como lector de código de barras de
/// una venta que se está armando en la PC: la PC genera un código, lo
/// muestra como QR, y cada código que el celular escanea (sin necesidad de
/// iniciar sesión en la app) se manda a la subcolección `eventos` de esa
/// sesión, que la PC escucha en vivo.
class EscaneoRemotoRepository {
  final _col = FirebaseFirestore.instance.collection('escaneosRemotos');

  // Sin caracteres ambiguos (0/O, 1/I/L) para que sea fácil de leer/tipear a
  // mano si hiciera falta.
  static const _caracteres = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String generarCodigo() {
    final azar = Random.secure();
    return List.generate(6, (_) => _caracteres[azar.nextInt(_caracteres.length)]).join();
  }

  Future<void> crearSesion(String codigo) async {
    await _col.doc(codigo).set({'creadoEn': FieldValue.serverTimestamp()});
  }

  Future<bool> existeSesion(String codigo) async {
    final snap = await _col.doc(codigo).get();
    return snap.exists;
  }

  /// El celular se suscribe a esto (en vez de solo comprobar una vez al
  /// abrir) para enterarse al instante si la sesión terminó de verdad
  /// (`eliminarSesion`, al tocar "Finalizar escaneo" o cerrar la pestaña de
  /// venta): recién ahí el celular deja de mandar códigos, aunque la cámara
  /// siga abierta.
  Stream<bool> existeSesionEnVivo(String codigo) {
    return _col.doc(codigo).snapshots().map((snap) => snap.exists);
  }

  /// El celular marca esto apenas confirma la sesión y muestra la cámara,
  /// para que la PC sepa que ya se emparejó y pueda cerrar solo la ventanita
  /// del QR (sin necesidad de que el usuario la cierre a mano).
  Future<void> marcarConectado(String codigo) async {
    await _col.doc(codigo).set({'conectado': true, 'conectadoEn': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Stream<bool> escucharConectado(String codigo) {
    return _col.doc(codigo).snapshots().map((snap) => (snap.data()?['conectado'] as bool?) ?? false);
  }

  Future<void> enviarCodigo(String codigoSesion, String codigoEscaneado) async {
    await _col.doc(codigoSesion).collection('eventos').add({
      'codigo': codigoEscaneado,
      'fecha': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> escucharEventos(String codigoSesion) {
    return _col.doc(codigoSesion).collection('eventos').orderBy('fecha').snapshots();
  }

  /// Se llama al cerrar el diálogo de escaneo en la PC: borra la sesión y
  /// sus eventos para no dejar basura acumulándose en Firestore.
  Future<void> eliminarSesion(String codigo) async {
    final eventos = await _col.doc(codigo).collection('eventos').get();
    for (final doc in eventos.docs) {
      await doc.reference.delete();
    }
    await _col.doc(codigo).delete();
  }
}
