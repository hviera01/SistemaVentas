import 'package:http/http.dart' as http;

/// Versión web: el navegador ya valida certificados correctamente (incluida
/// la cadena incompleta que Cloudinary a veces manda), así que no hace falta
/// ningún ajuste — ver cliente_fotos_io.dart para el porqué en Windows/Android.
http.Client crearClienteFotos() => http.Client();
