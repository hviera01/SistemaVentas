// Genera assets/images/logo_redondo.png (recorte circular con transparencia
// real del logo cuadrado) a partir de assets/images/logo.jpg, para usarlo
// como ícono de la app en Windows (que sí soporta transparencia en el
// .ico). Se corre una sola vez a mano:
// `dart run tool/generar_logo_redondo.dart`.
//
// OJO: no alcanza con copyResizeCropSquare(..., radius: ...) sola — el JPEG
// de origen no tiene canal alfa, y esa función hereda el número de canales
// de la imagen de origen, así que las esquinas "transparentes" terminaban
// siendo negro sólido y opaco en vez de transparentes (por eso el ícono de
// Windows salía con un marco negro feo). Acá se arma la imagen circular a
// mano, en una imagen RGBA nueva de 4 canales, para que la transparencia
// sea real.
import 'dart:io';
import 'dart:math' show sqrt;
import 'package:image/image.dart' as img;

void main() {
  final bytes = File('assets/images/logo.jpg').readAsBytesSync();
  final original = img.decodeJpg(bytes);
  if (original == null) {
    stderr.writeln('No se pudo leer assets/images/logo.jpg');
    exit(1);
  }
  const tamano = 512;
  final cuadrado = img.copyResizeCropSquare(original, size: tamano);
  final circular = img.Image(width: tamano, height: tamano, numChannels: 4);
  const cx = tamano / 2;
  const cy = tamano / 2;
  const radio = tamano / 2;
  for (var y = 0; y < tamano; y++) {
    for (var x = 0; x < tamano; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final distancia = sqrt(dx * dx + dy * dy);
      final origen = cuadrado.getPixel(x, y);
      if (distancia <= radio - 1) {
        circular.setPixelRgba(x, y, origen.r, origen.g, origen.b, 255);
      } else if (distancia <= radio + 1) {
        // Un pixel de antialiasing en el borde para que no se vea dentado.
        final alfa = (((radio + 1 - distancia) / 2) * 255).clamp(0, 255).round();
        circular.setPixelRgba(x, y, origen.r, origen.g, origen.b, alfa);
      } else {
        circular.setPixelRgba(x, y, 255, 255, 255, 0);
      }
    }
  }
  File('assets/images/logo_redondo.png').writeAsBytesSync(img.encodePng(circular));
  // ignore: avoid_print
  print('Listo: assets/images/logo_redondo.png');
}
