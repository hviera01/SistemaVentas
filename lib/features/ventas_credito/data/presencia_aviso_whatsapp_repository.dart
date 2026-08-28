import 'package:cloud_firestore/cloud_firestore.dart';

/// Igual que PresenciaImpresionRepository, pero para saber si el proceso
/// Node `tool/aviso_creditos_whatsapp/escuchar.js` está corriendo en la PC
/// principal -es quien de verdad manda el WhatsApp cuando se toca "Enviar
/// estado de cuenta por WhatsApp"; la app Flutter solo deja marcado el
/// pedido en el crédito (ver VentaCreditoRepository.solicitarAvisoWhatsApp).
/// Sin esta señal, si nadie dejó `escuchar.js` corriendo, el botón "funciona"
/// (no tira error) pero no manda nada y no hay forma de saber por qué.
class PresenciaAvisoWhatsappRepository {
  static const umbralConectada = Duration(seconds: 40);

  final _doc = FirebaseFirestore.instance.collection('presenciaAvisoWhatsapp').doc('escuchador');

  /// Lee del servidor (no del caché local) para no dar un falso "conectado"
  /// con un latido viejo que quedó guardado en caché.
  Future<bool> estaConectado() async {
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
