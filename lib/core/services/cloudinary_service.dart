import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Sube fotos de producto a Cloudinary (plan gratis) usando un upload
/// preset "unsigned": no hace falta guardar la API secret en la app, el
/// preset ya define qué se puede subir. Ver tool/reporte_whatsapp para otro
/// ejemplo de integración externa sin credenciales sensibles en el cliente.
class CloudinaryService {
  static const _cloudName = 'jzlwbtwt';
  static const _uploadPreset = 'd0hcezcz';

  Future<String> subirImagen(Uint8List bytes, String nombreArchivo) async {
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: nombreArchivo));
    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw Exception('No se pudo subir la foto (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['secure_url'] as String;
  }
}
