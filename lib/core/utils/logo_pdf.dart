import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

// Cache del logo ya decodificado y redimensionado, por tamaño pedido: el
// decode+resize con `package:image` (puro Dart, sin aceleración de hardware)
// es lo más lento de armar un ticket, sobre todo en la versión web — y como
// el logo casi nunca cambia, no tiene sentido repetir ese trabajo en cada
// venta que se imprime. Se guarda el PNG ya chico (liviano) en vez del
// `pw.MemoryImage`, y se arma uno nuevo a partir de esos bytes en cada
// llamada (eso sí es instantáneo).
final _cachePng = <String, Uint8List?>{};

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
  final clave = '$maxDimension:${base64.length}:${base64.substring(0, base64.length < 64 ? base64.length : 64)}';
  if (_cachePng.containsKey(clave)) {
    final cacheado = _cachePng[clave];
    return cacheado == null ? null : pw.MemoryImage(cacheado);
  }
  try {
    final bytes = base64Decode(base64);
    final decodificada = img.decodeImage(bytes);
    if (decodificada == null) {
      _cachePng[clave] = null;
      return null;
    }

    final necesitaReducir = decodificada.width > maxDimension || decodificada.height > maxDimension;
    final imagenFinal = necesitaReducir
        ? img.copyResize(
            decodificada,
            width: decodificada.width >= decodificada.height ? maxDimension : null,
            height: decodificada.height > decodificada.width ? maxDimension : null,
          )
        : decodificada;

    final png = Uint8List.fromList(img.encodePng(imagenFinal));
    _cachePng[clave] = png;
    return pw.MemoryImage(png);
  } catch (_) {
    _cachePng[clave] = null;
    return null;
  }
}
