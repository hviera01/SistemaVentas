import 'package:cloud_firestore/cloud_firestore.dart';

/// Le permite a la PC principal (la que tiene la impresora térmica
/// conectada) avisar que está viva mientras la app está abierta, para que
/// una venta hecha desde el celular sepa si vale la pena pedirle que
/// imprima en el momento en vez de dejarla directamente pendiente.
///
/// Firestore no tiene una noción nativa de presencia (a diferencia de
/// Realtime Database con `onDisconnect`), así que se simula con un latido
/// periódico: si el último latido es reciente, se asume que la PC sigue
/// conectada. Ver AppShell (quien envía el latido) y RegistrarVentaScreen
/// (quien lo consulta antes de pedir impresión en vivo).
class PresenciaImpresionRepository {
  static const umbralConectada = Duration(seconds: 40);

  final _doc = FirebaseFirestore.instance.collection('presenciaImpresion').doc('pcPrincipal');

  Future<void> enviarLatido() async {
    try {
      await _doc.set({'ultimoLatido': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {
      // Best-effort: si falla (sin internet justo en ese instante), el
      // próximo latido -unos segundos después- lo vuelve a intentar.
    }
  }

  /// Lee del servidor (no del caché local) para no dar un falso "conectada"
  /// con un latido viejo que quedó guardado en el caché de otro dispositivo.
  Future<bool> estaConectada() async {
    try {
      final snap = await _doc.get(const GetOptions(source: Source.server));
      final ts = snap.data()?['ultimoLatido'] as Timestamp?;
      if (ts == null) return false;
      return DateTime.now().difference(ts.toDate()) < umbralConectada;
    } catch (_) {
      return false;
    }
  }
}
