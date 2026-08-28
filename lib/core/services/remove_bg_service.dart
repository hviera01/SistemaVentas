import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Quita el fondo de una foto de producto usando la API gratis de
/// remove.bg -pedido explícito del dueño-. El plan gratis da 50 imágenes
/// por mes, en resolución "preview" (hasta 0.25 megapixeles, de sobra para
/// una miniatura de producto en la app); pasado ese número, esta llamada
/// falla hasta el próximo mes -no hay forma de evitarlo desde acá, es un
/// límite del plan gratis-.
class RemoveBgService {
  // Clave de la cuenta gratis de remove.bg del dueño (remove.bg/api →
  // Dashboard → API Key). Igual que CloudinaryService, va embebida en la
  // app -mismo criterio de riesgo ya aceptado en este proyecto-.
  static const _apiKey = 'ZAXf2NGiNNAwYcCd8Ghu4TUt';

  /// [imagenUrl] tiene que ser una URL pública (ej. la de Cloudinary donde
  /// ya está subida la foto) — remove.bg la descarga directo, no hace falta
  /// mandarle los bytes. Devuelve el PNG resultante (con transparencia)
  /// listo para volver a subir a Cloudinary.
  Future<Uint8List> quitarFondo(String imagenUrl) async {
    final res = await http.post(
      Uri.parse('https://api.remove.bg/v1.0/removebg'),
      headers: {'X-Api-Key': _apiKey},
      body: {
        'image_url': imagenUrl,
        // 'preview' fuerza la variante gratis (0.25MP) — sin esto remove.bg
        // devolvería full resolución y gastaría un crédito pago de verdad.
        'size': 'preview',
        'format': 'png',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('remove.bg respondió ${res.statusCode}: ${res.body}');
    }
    return res.bodyBytes;
  }
}
