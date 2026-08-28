import 'package:cloud_firestore/cloud_firestore.dart';

/// Igual que PresenciaImpresionRepository, pero para saber si la tarea
/// programada `tool/aviso_creditos_whatsapp/escuchar.js` sigue corriendo en
/// la PC principal -es quien de verdad manda el WhatsApp cuando se toca
/// "Enviar estado de cuenta por WhatsApp"; la app Flutter solo deja marcado
/// el pedido en el crédito (ver VentaCreditoRepository.solicitarAvisoWhatsApp).
/// Sin esta señal, si la tarea programada se desactivó o dejó de correr, el
/// botón "funciona" (no tira error) pero no manda nada y no hay forma de
/// saber por qué.
///
/// A diferencia de PresenciaImpresionRepository (la PC manda un latido cada
/// 25s MIENTRAS la app está abierta), acá `escuchar.js` NO se queda
/// corriendo: el Programador de Tareas de Windows lo dispara, manda su
/// latido, y termina -pensado para correr cada 2 minutos (ver README de esa
/// carpeta)-, así que el umbral tiene que ser bastante mayor a ese intervalo
/// para no marcar "desconectado" solo porque todavía no le tocó la próxima
/// corrida.
class PresenciaAvisoWhatsappRepository {
  static const umbralConectada = Duration(minutes: 4);

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
