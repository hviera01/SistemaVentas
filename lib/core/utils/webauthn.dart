// Face ID/Touch ID desde el navegador (WebAuthn), usado solo en el login en
// web móvil (ver LoginScreen: _esWebMovil). No hace ninguna llamada de red
// ni verificación de servidor -esta app no tiene backend de WebAuthn, ver
// el comentario grande en webauthn_web.dart-: es un candado local nada
// más, que gatea el login normal (código+clave) guardado en este
// navegador.
import 'webauthn_stub.dart' if (dart.library.html) 'webauthn_web.dart' as impl;

/// true si este navegador soporta pedir Face ID/Touch ID (autenticador de
/// plataforma). En cualquier plataforma que no sea web (APK, Windows)
/// siempre da false: ver webauthn_stub.dart.
Future<bool> webAuthnDisponible() => impl.autenticadorPlataformaDisponible();

/// Registra un credencial de Face ID/Touch ID para este navegador/celular.
/// Devuelve su id en base64url (para guardar localmente y volver a pedirlo
/// después, ver webAuthnVerificar) o null si el usuario canceló el diálogo
/// del sistema o el navegador no lo soporta.
Future<String?> webAuthnRegistrar({required String usuarioId, required String usuarioNombre}) =>
    impl.registrarCredencial(usuarioId: usuarioId, usuarioNombre: usuarioNombre);

/// Pide Face ID/Touch ID contra el credencial ya registrado (ver
/// webAuthnRegistrar). true si el usuario lo confirmó; false si canceló, si
/// el navegador lo rechazó (por ejemplo, se borró el Face ID del celular),
/// o cualquier otro error.
Future<bool> webAuthnVerificar(String credencialIdBase64Url) => impl.verificarCredencial(credencialIdBase64Url);
