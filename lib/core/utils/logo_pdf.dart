import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

/// Decodifica un logo guardado en base64 y lo reduce a un tamaño chico antes
/// de meterlo en un PDF.
///
/// Los logos que sube el usuario pueden ser fotos de varios megapixeles tal
/// cual salen del teléfono. Procesar esa imagen a resolución completa con
/// `package:image` (que es puro Dart, sin aceleración de hardware) puede
/// tardar muchísimo — sobre todo corriendo en modo debug — y como es trabajo
/// síncrono bloquea la UI entera mientras tanto, dando la sensación de que
/// la app se colgó. En el PDF el logo nunca se dibuja a más de unos 60px, así
/// que no hace falta conservar más resolución que esa.
pw.MemoryImage? decodificarLogoPdf(String base64, {int maxDimension = 160}) {
  if (base64.isEmpty) return null;
  try {
    final bytes = base64Decode(base64);
    final decodificada = img.decodeImage(bytes);
    if (decodificada == null) return null;

    final necesitaReducir = decodificada.width > maxDimension || decodificada.height > maxDimension;
    final imagenFinal = necesitaReducir
        ? img.copyResize(
            decodificada,
            width: decodificada.width >= decodificada.height ? maxDimension : null,
            height: decodificada.height > decodificada.width ? maxDimension : null,
          )
        : decodificada;

    return pw.MemoryImage(Uint8List.fromList(img.encodePng(imagenFinal)));
  } catch (_) {
    return null;
  }
}
