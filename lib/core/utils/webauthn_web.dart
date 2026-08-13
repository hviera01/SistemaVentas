import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

// WebAuthn (Face ID/Touch ID desde el navegador) vía interop directo con la
// API del navegador, sin ningún paquete adicional -mismo estilo que
// beep_web.dart, que ya usa dart:js_interop + dart:js_interop_unsafe para
// hablar con Web Audio API-.
//
// Importante: esto NO es un login "passkey" de verdad contra un servidor.
// Esta app no usa Firebase Auth ni tiene backend propio para WebAuthn (el
// login es código+clave contra Firestore, ver AuthRepository), así que acá
// no se verifica ninguna firma del lado del servidor. Face ID solo se usa
// como candado local: sirve para confirmar "sos el mismo dueño del celular
// que activó esto", y si lo confirma, se reusa el código+clave que ya se
// guardaron (ver webauthn.dart y LoginScreen) para hacer el login normal de
// siempre. Quien tenga acceso a ejecutar JavaScript en este sitio (por
// ejemplo, un XSS) podría leer esas credenciales guardadas sin pasar por
// Face ID -la promesa de esta función es solo evitar que la clave quede
// tipeada a la vista cada vez, no una bóveda a prueba de todo-.

JSObject get _navigator => globalContext.getProperty('navigator'.toJS) as JSObject;

Future<bool> autenticadorPlataformaDisponible() async {
  try {
    final publicKeyCredential = globalContext.getProperty('PublicKeyCredential'.toJS);
    if (publicKeyCredential == null) return false;
    final credentials = _navigator.getProperty('credentials'.toJS);
    if (credentials == null) return false;
    final promesa = (publicKeyCredential as JSObject).callMethod('isUserVerifyingPlatformAuthenticatorAvailable'.toJS) as JSPromise<JSAny?>;
    final resultado = await promesa.toDart;
    return (resultado as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

Uint8List _bytesAleatorios(int cantidad) {
  final aleatorio = Random.secure();
  return Uint8List.fromList(List.generate(cantidad, (_) => aleatorio.nextInt(256)));
}

Future<String?> registrarCredencial({required String usuarioId, required String usuarioNombre}) async {
  try {
    final credentials = _navigator.getProperty('credentials'.toJS) as JSObject?;
    if (credentials == null) return null;

    final rp = JSObject()..setProperty('name'.toJS, 'Super Color'.toJS);

    final user = JSObject()
      ..setProperty('id'.toJS, _bytesAleatorios(16).toJS)
      ..setProperty('name'.toJS, usuarioId.toJS)
      ..setProperty('displayName'.toJS, usuarioNombre.toJS);

    final parametroES256 = JSObject()
      ..setProperty('type'.toJS, 'public-key'.toJS)
      ..setProperty('alg'.toJS, (-7).toJS);
    final parametroRS256 = JSObject()
      ..setProperty('type'.toJS, 'public-key'.toJS)
      ..setProperty('alg'.toJS, (-257).toJS);

    final seleccionAutenticador = JSObject()
      ..setProperty('authenticatorAttachment'.toJS, 'platform'.toJS)
      ..setProperty('userVerification'.toJS, 'required'.toJS)
      ..setProperty('residentKey'.toJS, 'preferred'.toJS);

    final publicKey = JSObject()
      ..setProperty('challenge'.toJS, _bytesAleatorios(32).toJS)
      ..setProperty('rp'.toJS, rp)
      ..setProperty('user'.toJS, user)
      ..setProperty('pubKeyCredParams'.toJS, [parametroES256, parametroRS256].toJS)
      ..setProperty('authenticatorSelection'.toJS, seleccionAutenticador)
      ..setProperty('timeout'.toJS, 60000.toJS)
      ..setProperty('attestation'.toJS, 'none'.toJS);

    final opciones = JSObject()..setProperty('publicKey'.toJS, publicKey);

    final promesa = credentials.callMethod('create'.toJS, opciones) as JSPromise<JSAny?>;
    final credencial = await promesa.toDart as JSObject?;
    if (credencial == null) return null;

    final rawId = credencial.getProperty('rawId'.toJS) as JSArrayBuffer;
    return _base64UrlDesdeBuffer(rawId);
  } catch (_) {
    // El usuario canceló el diálogo de Face ID, el navegador no soporta
    // WebAuthn, o cualquier otro motivo: no hay credencial, se cae de vuelta
    // al login manual (ver LoginScreen).
    return null;
  }
}

Future<bool> verificarCredencial(String credencialIdBase64Url) async {
  try {
    final credentials = _navigator.getProperty('credentials'.toJS) as JSObject?;
    if (credentials == null) return false;

    final credencialId = _bytesDesdeBase64Url(credencialIdBase64Url);
    final allowCredential = JSObject()
      ..setProperty('type'.toJS, 'public-key'.toJS)
      ..setProperty('id'.toJS, credencialId.toJS);

    final publicKey = JSObject()
      ..setProperty('challenge'.toJS, _bytesAleatorios(32).toJS)
      ..setProperty('allowCredentials'.toJS, [allowCredential].toJS)
      ..setProperty('userVerification'.toJS, 'required'.toJS)
      ..setProperty('timeout'.toJS, 60000.toJS);

    final opciones = JSObject()..setProperty('publicKey'.toJS, publicKey);

    final promesa = credentials.callMethod('get'.toJS, opciones) as JSPromise<JSAny?>;
    final resultado = await promesa.toDart;
    return resultado != null;
  } catch (_) {
    // Cancelado, no coincide el credencial (por ejemplo, se borró el Face
    // ID del teléfono), o cualquier otro error: no verificado.
    return false;
  }
}

String _base64UrlDesdeBuffer(JSArrayBuffer buffer) {
  final bytes = buffer.toDart.asUint8List();
  return _base64Url(bytes);
}

// Implementación mínima de base64url (RFC 4648 §5, sin relleno) para no
// depender de dart:convert acá: ArrayBuffer/Uint8Array son justo lo que ya
// se maneja en este archivo, y así se evita mezclar dos formas de trabajar
// con bytes.
const _alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

String _base64Url(Uint8List bytes) {
  final buffer = StringBuffer();
  var i = 0;
  while (i + 3 <= bytes.length) {
    final n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    buffer
      ..write(_alfabeto[(n >> 18) & 0x3F])
      ..write(_alfabeto[(n >> 12) & 0x3F])
      ..write(_alfabeto[(n >> 6) & 0x3F])
      ..write(_alfabeto[n & 0x3F]);
    i += 3;
  }
  final restantes = bytes.length - i;
  if (restantes == 1) {
    final n = bytes[i] << 16;
    buffer
      ..write(_alfabeto[(n >> 18) & 0x3F])
      ..write(_alfabeto[(n >> 12) & 0x3F]);
  } else if (restantes == 2) {
    final n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    buffer
      ..write(_alfabeto[(n >> 18) & 0x3F])
      ..write(_alfabeto[(n >> 12) & 0x3F])
      ..write(_alfabeto[(n >> 6) & 0x3F]);
  }
  return buffer.toString();
}

Uint8List _bytesDesdeBase64Url(String texto) {
  final valores = {for (var i = 0; i < _alfabeto.length; i++) _alfabeto[i]: i};
  final bytes = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final char in texto.split('')) {
    final valor = valores[char];
    if (valor == null) continue;
    buffer = (buffer << 6) | valor;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xFF);
    }
  }
  return Uint8List.fromList(bytes);
}
