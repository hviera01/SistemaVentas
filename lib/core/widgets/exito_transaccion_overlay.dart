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
  final double t;
  final String mensaje;

  const EscenaExito({super.key, required this.t, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final entrada = Curves.easeOutBack.transform((t / 0.2).clamp(0.0, 1.0));
    final aparicion = Curves.easeOut.transform((t / 0.2).clamp(0.0, 1.0));
    final salida = Curves.easeIn.transform(((t - 0.8) / 0.2).clamp(0.0, 1.0));
    final opacidad = (aparicion * (1 - salida)).clamp(0.0, 1.0);
    final check = Curves.easeOut.transform(((t - 0.1) / 0.3).clamp(0.0, 1.0));

    return Center(
      child: Opacity(
          opacity: opacidad,
          child: Transform.scale(
            scale: entrada.clamp(0.0, 1.2),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 26,
                ),
                decoration: BoxDecoration(
                  color: AppColors.superficie,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: CustomPaint(painter: _CheckPainter(check)),
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
          ),
        ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progreso;

  _CheckPainter(this.progreso);

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
  bool shouldRepaint(_CheckPainter old) => old.progreso != progreso;
}
