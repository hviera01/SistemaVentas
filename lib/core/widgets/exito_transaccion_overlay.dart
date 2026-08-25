import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Check verde chico en el centro de la pantalla al terminar una venta o
/// compra -pedido explícito del dueño-: confirma de un vistazo que la
/// transacción se realizó, sin interrumpir el flujo (no bloquea nada, se
/// desvanece solo). Usa un OverlayEntry en vez de un diálogo a propósito:
/// no depende de un Navigator ni compite con otros diálogos que puedan
/// abrirse justo después (ej. el de imprimir), y con [IgnorePointer] el
/// cajero puede seguir tocando la pantalla de abajo mientras se desvanece.
void mostrarExitoTransaccion(BuildContext context, {String mensaje = 'Transacción realizada correctamente'}) {
  final overlayState = Overlay.maybeOf(context);
  if (overlayState == null) return;
  late OverlayEntry entrada;
  entrada = OverlayEntry(builder: (context) => _ExitoTransaccionOverlay(mensaje: mensaje, onFin: () => entrada.remove()));
  overlayState.insert(entrada);
}

class _ExitoTransaccionOverlay extends StatefulWidget {
  final String mensaje;
  final VoidCallback onFin;

  const _ExitoTransaccionOverlay({required this.mensaje, required this.onFin});

  @override
  State<_ExitoTransaccionOverlay> createState() => _ExitoTransaccionOverlayState();
}

class _ExitoTransaccionOverlayState extends State<_ExitoTransaccionOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;
  late final Animation<double> _escala;
  late final Animation<double> _opacidad;

  @override
  void initState() {
    super.initState();
    _controlador = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _escala = CurvedAnimation(parent: _controlador, curve: Curves.easeOutBack);
    _opacidad = CurvedAnimation(parent: _controlador, curve: Curves.easeOut);
    _controlador.forward();
    Future.delayed(const Duration(milliseconds: 1300), () async {
      if (!mounted) return;
      await _controlador.reverse();
      widget.onFin();
    });
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _opacidad,
            child: ScaleTransition(
              scale: _escala,
              // Material(type: transparency): este widget se inserta con un
              // OverlayEntry crudo, no con showDialog/MaterialPageRoute -
              // esos SIEMPRE envuelven su contenido en un Material por
              // dentro, pero un OverlayEntry a mano no. Sin esto, el Text de
              // abajo no encuentra un ancestro Material y Flutter lo marca
              // con un subrayado amarillo doble -pedido explícito del
              // dueño: "esas remarcaciones de amarillo no me gustan", eso
              // es justo lo que eran, no un dato mal calculado.
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(color: Color(0xFF1E9E5A), shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.mensaje,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
