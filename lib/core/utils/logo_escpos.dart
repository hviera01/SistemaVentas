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
    final ditherizada = img.ditherImage(redimensionada, quantizer: img.BinaryQuantizer(), kernel: img.DitherKernel.floydSteinberg);
    // ditherImage devuelve una imagen "indexada" (cada píxel guarda 0 o 1,
    // no un color de verdad) — Generator.image() de esc_pos_utils_plus no
    // sabe leer eso (invert/resize/etc. operan raro sobre una paleta) y
    // terminaba imprimiendo el logo en blanco, sin nada. .convert() sin
    // withPalette "aplana" la paleta a píxeles RGB reales (negro/blanco
    // sólido), que es lo que esc_pos_utils_plus sí sabe procesar.
    final imagenFinal = ditherizada.convert(numChannels: 3);
    _cache[clave] = imagenFinal;
    return imagenFinal;
  } catch (_) {
    _cache[clave] = null;
    return null;
  }
}

/// Logo como UN SOLO bloque raster ESC/POS (GS v 0) -mismo arreglo que el
/// sistema de Danli Autoparts (RepuestosPOS)-. Generator.image() de
/// esc_pos_utils_plus lo manda en franjas de 24 puntos (ESC *) y muchas
/// térmicas dejan una línea en blanco entre franja y franja: eso era lo que
/// salía "rayado" en el logo de la factura. Con un raster de una sola pieza
/// la impresora lo dibuja continuo. [imagen] ya viene en negro/blanco puro
/// (ver decodificarLogoEscPos), así que acá solo se empaqueta 1 bit por
/// punto (1 = negro). Lo deja centrado y vuelve a alinear a la izquierda.
List<int> rasterEscPos(img.Image imagen) {
  final ancho = imagen.width;
  final alto = imagen.height;
  final anchoBytes = (ancho + 7) ~/ 8;
  final datos = List<int>.filled(anchoBytes * alto, 0);
  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      final p = imagen.getPixel(x, y);
      final luminancia = p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
      final opaco = imagen.numChannels < 4 || p.a > 127;
      if (opaco && luminancia < 128) {
        datos[y * anchoBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return [
    0x1B, 0x61, 0x01, // centrar
    0x1D, 0x76, 0x30, 0x00, // GS v 0, modo normal
    anchoBytes & 0xFF, (anchoBytes >> 8) & 0xFF,
    alto & 0xFF, (alto >> 8) & 0xFF,
    ...datos,
    0x1B, 0x61, 0x00, // volver a alinear a la izquierda
  ];
}