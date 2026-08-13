/// Implementación para Android/Windows/etc. (no web): WebAuthn es una API
/// de navegador, así que acá no hay nada que ofrecer. Face ID en la app
/// nativa (APK) tendría que resolverse con local_auth, no con esto -no es
/// lo que se pidió, así que se deja fuera-.
Future<bool> autenticadorPlataformaDisponible() async => false;

Future<String?> registrarCredencial({required String usuarioId, required String usuarioNombre}) async => null;

Future<bool> verificarCredencial(String credencialIdBase64Url) async => false;
