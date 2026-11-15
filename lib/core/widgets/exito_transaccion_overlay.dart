import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class EventoExito {
  final int id;
  final String mensaje;

  const EventoExito(this.id, this.mensaje);
}

class ExitoTransaccion {
  ExitoTransaccion._();

  static final ValueNotifier<EventoExito?> eventos = ValueNotifier(null);
  static int _contador = 0;

  static void mostrar(String mensaje) {
    eventos.value = EventoExito(++_contador, mensaje);
  }
}

/// Check verde en el centro de la pantalla al terminar una operación
/// (venta, compra, guardar, editar, eliminar, confirmar...) -pedido
/// explícito del dueño-: confirma de un vistazo que se realizó, sin
/// interrumpir el flujo. No necesita BuildContext: lo dibuja el host que
/// vive encima del Navigator (ver AnimacionImpresionHost), así que sale
/// aunque la pantalla que lo pidió ya se haya cerrado y por encima de
/// cualquier diálogo.
void mostrarExito([String mensaje = 'Transacción realizada correctamente']) {
  ExitoTransaccion.mostrar(mensaje);
}

void mostrarExitoTransaccion(
  BuildContext context, {
  String mensaje = 'Transacción realizada correctamente',
}) {
  ExitoTransaccion.mostrar(mensaje);
}

class EscenaExito extends StatelessWidget {
  final Animation<double> animacion;
  final String mensaje;

  const EscenaExito({
    super.key,
    required this.animacion,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    // La tarjeta (fondo, sombra, texto) no cambia durante la animación: va
    // en su propia capa para que en cada frame solo se componga (escala y
    // opacidad), sin volver a dibujar la sombra difusa. Solo el trazo del
    // check se redibuja, también en su propia capa.
    final tarjeta = RepaintBoundary(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
          decoration: BoxDecoration(
            color: AppColors.superficie,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: RepaintBoundary(
                  child: CustomPaint(painter: _CheckPainter(animacion)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.texto,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Proporciones para una duración total de ~2.2s (ver _duracionExito en
    // AnimacionImpresionHost): entra en ~220ms, el check se dibuja en
    // ~350ms, queda quieto para poder leerlo y sale en ~260ms.
    // Sin Center: lo ubica el host, centrado solo o al lado de la impresora.
    return AnimatedBuilder(
      animation: animacion,
      child: tarjeta,
      builder: (context, hijo) {
        final t = animacion.value;
        final entrada = Curves.easeOutBack.transform((t / 0.1).clamp(0.0, 1.0));
        final aparicion = Curves.easeOut.transform((t / 0.1).clamp(0.0, 1.0));
        final salida = Curves.easeIn.transform(
          ((t - 0.88) / 0.12).clamp(0.0, 1.0),
        );
        final opacidad = (aparicion * (1 - salida)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacidad,
          child: Transform.scale(scale: entrada.clamp(0.0, 1.2), child: hijo),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  final Animation<double> animacion;

  _CheckPainter(this.animacion) : super(repaint: animacion);

  double get progreso => Curves.easeOut.transform(
    ((animacion.value - 0.05) / 0.16).clamp(0.0, 1.0),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    canvas.drawCircle(
      centro,
      size.width / 2,
      Paint()..color = const Color(0xFF1E9E5A),
    );
    final trazo = Path()
      ..moveTo(centro.dx - 15, centro.dy + 1)
      ..lineTo(centro.dx - 5, centro.dy + 12)
      ..lineTo(centro.dx + 16, centro.dy - 11);
    final metrica = trazo.computeMetrics().first;
    canvas.drawPath(
      metrica.extractPath(0, metrica.length * progreso),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.animacion != animacion;
}
