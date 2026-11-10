import 'dart:async';
import 'dart:io';
import '../widgets/animacion_impresion.dart' show AnimacionImpresion;

/// Envío de tickets ESC/POS a una impresora térmica de red (socket TCP,
/// puerto 9100 típico). Es la única vía de impresión térmica que funciona
/// desde el celular: el paquete `printing` solo puede listar/usar
/// impresoras del sistema operativo en Windows/macOS/Linux, no en
/// Android/iOS, y agregar Bluetooth requeriría permisos y una pantalla de
/// emparejamiento nativa que no todos los equipos van a poder usar.
///
/// No usada en la web: `dart:io Socket` no está disponible ahí (por eso las
/// llamadas de este servicio se deben evitar con `kIsWeb` desde donde se usan).
class ImpresoraRedService {
  static const _timeoutConexion = Duration(seconds: 5);

  /// Nunca lanza: devuelve `false` ante cualquier error (IP incorrecta,
  /// impresora apagada, fuera de la red, etc.) para que quien llama decida
  /// qué hacer (marcar pendiente de impresión, avisar, etc.) sin que la
  /// venta se bloquee.
  Future<bool> imprimir({required String ip, required int puerto, required List<int> bytes}) async {
    if (bytes.length > 4) AnimacionImpresion.mostrar();
    if (ip.trim().isEmpty) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(ip.trim(), puerto, timeout: _timeoutConexion);
      socket.add(bytes);
      await socket.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      unawaited(socket?.close());
    }
  }
}
