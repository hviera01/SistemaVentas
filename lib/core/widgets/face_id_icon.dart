import 'package:flutter/material.dart';

/// Ícono de Face ID dibujado a mano (marco con las 4 esquinas + cara
/// minimalista), igual al glifo que usa Apple: no existe un Material Icon
/// equivalente, así que se dibuja con CustomPainter en vez de aproximarlo
/// con un ícono genérico (como Icons.face_retouching_natural, que no se
/// parece).
class FaceIdIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double grosorTrazo;

  const FaceIdIcon({super.key, this.size = 24, required this.color, this.grosorTrazo = 7});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _FaceIdIconPainter(color: color, grosorTrazo: grosorTrazo),
    );
  }
}

class _FaceIdIconPainter extends CustomPainter {
  final Color color;
  final double grosorTrazo;

  _FaceIdIconPainter({required this.color, required this.grosorTrazo});

  @override
  void paint(Canvas canvas, Size size) {
    // Todo el dibujo se arma sobre un lienzo lógico de 100x100 y se escala
    // al tamaño real pedido, para que el ícono se vea igual sin importar en
    // qué tamaño se use.
    final escala = size.width / 100;
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosorTrazo * escala
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path esquina() {
      return Path()
        ..moveTo(10 * escala, 34 * escala)
        ..lineTo(10 * escala, 20 * escala)
        ..quadraticBezierTo(10 * escala, 10 * escala, 20 * escala, 10 * escala)
        ..lineTo(34 * escala, 10 * escala);
    }

    // Las 4 esquinas del marco son la misma forma rotada 90°/180°/270°
    // alrededor del centro, en vez de repetir las coordenadas 4 veces.
    final centro = Offset(size.width / 2, size.height / 2);
    for (final grados in [0, 90, 180, 270]) {
      canvas.save();
      canvas.translate(centro.dx, centro.dy);
      canvas.rotate(grados * 3.14159265 / 180);
      canvas.translate(-centro.dx, -centro.dy);
      canvas.drawPath(esquina(), trazo);
      canvas.restore();
    }

    // Ojos: dos trazos verticales cortos.
    canvas.drawLine(Offset(38 * escala, 42 * escala), Offset(38 * escala, 50 * escala), trazo);
    canvas.drawLine(Offset(62 * escala, 42 * escala), Offset(62 * escala, 50 * escala), trazo);

    // Nariz: baja y dobla apenas a la derecha en la punta.
    final nariz = Path()
      ..moveTo(50 * escala, 42 * escala)
      ..lineTo(50 * escala, 60 * escala)
      ..lineTo(56 * escala, 63 * escala);
    canvas.drawPath(nariz, trazo);

    // Boca: una curva de sonrisa.
    final boca = Path()
      ..moveTo(37 * escala, 70 * escala)
      ..quadraticBezierTo(50 * escala, 81 * escala, 63 * escala, 70 * escala);
    canvas.drawPath(boca, trazo);
  }

  @override
  bool shouldRepaint(covariant _FaceIdIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.grosorTrazo != grosorTrazo;
}
