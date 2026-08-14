import 'dart:convert';
import 'package:image/image.dart' as img;

// Mismo criterio de caché que logo_pdf.dart (decodificar+redimensionar con
// `package:image` es lo más lento de armar un ticket, y el logo casi nunca
// cambia), pero acá se guarda la imagen ya decodificada -no re-encodeada a
// PNG- porque es justo lo que espera `Generator.image()` de esc_pos_utils_plus.
final _cache = <String, img.Image?>{};

/// Decodifica el logo B/N del negocio (ver NegocioModel.logoBnBase64, ya
/// convertido a blanco y negro al subirlo) para imprimirlo por ESC/POS en el
/// ticket térmico (ver venta_ticket_escpos_service.dart). [maxDimension] se
/// mantiene chico a propósito: una impresora de 80mm no tiene más de ~576
/// puntos de ancho, así que no hace falta más resolución que esa.
img.Image? decodificarLogoEscPos(String base64, {int maxDimension = 300}) {
  if (base64.isEmpty) return null;
  final clave = '$maxDimension:${base64.length}:${base64.substring(0, base64.length < 64 ? base64.length : 64)}';
  if (_cache.containsKey(clave)) return _cache[clave];
  try {
    final bytes = base64Decode(base64);
    final decodificada = img.decodeImage(bytes);
    if (decodificada == null) {
      _cache[clave] = null;
      return null;
    }
    // Recorta el margen en blanco/transparente que suele venir de fábrica
    // alrededor del logo: sin esto, ese margen queda impreso como espacio
    // muerto entre el logo y el nombre del negocio, aunque en el código no
    // se haya puesto ningún espacio de más entre los dos.
    final recortada = img.trim(decodificada);
    final necesitaReducir = recortada.width > maxDimension || recortada.height > maxDimension;
    final redimensionada = necesitaReducir
        ? img.copyResize(
            recortada,
            width: recortada.width >= recortada.height ? maxDimension : null,
            height: recortada.height > recortada.width ? maxDimension : null,
          )
        : recortada;
    // Generator.image() de esc_pos_utils_plus convierte a blanco/negro con
    // un umbral simple (gris > 127 = blanco, si no negro), sin difuminar el
    // error de redondeo -en un logo con degradados o bordes suavizados
    // (cualquier logo típico, no un dibujo de un solo color plano) eso sale
    // "rayado"/con bandas feas en el papel-. Ditherizando acá primero con
    // Floyd-Steinberg (el mismo truco que usan las impresoras de fotos en
    // blanco y negro) el resultado ya queda en solo negro/blanco puro
    // *distribuido en un patrón de puntos* que se ve mucho más limpio y
    // fotográfico impreso, en vez de manchado.
    final imagenFinal = img.ditherImage(redimensionada, quantizer: img.BinaryQuantizer(), kernel: img.DitherKernel.floydSteinberg);
    _cache[clave] = imagenFinal;
    return imagenFinal;
  } catch (_) {
    _cache[clave] = null;
    return null;
  }
}
