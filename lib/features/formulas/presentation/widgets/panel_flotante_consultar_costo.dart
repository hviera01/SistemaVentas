import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/consultar_costo_screen.dart';

/// Controla un panel flotante de Consultar Costo insertado directo en el
/// Overlay de la pantalla que lo abre (Venta, Colores) -pedido explícito
/// del dueño: "no en pantalla completa" y "que se pueda minimizar para
/// hacer otra cosa". No usa Navigator/showDialog: un diálogo modal normal
/// destruye el State del contenido al cerrarlo (perdiendo lo que el cajero
/// tenía cargado) y su "tocar afuera" solo sabe cerrar del todo, no
/// minimizar. Acá:
/// - [abrir] inserta el panel una sola vez; si ya está abierto (minimizado
///   o no), lo vuelve a mostrar en vez de crear uno nuevo.
/// - [minimizar] lo oculta pero mantiene su contenido vivo -Consultar Costo
///   con lo que se tenía cargado, gracias a Visibility(maintainState:true)-
///   así que volver a abrirlo lo deja tal cual estaba.
/// - [cerrar] sí lo descarta del todo (el "X" del panel).
/// - Tocar afuera del panel (la zona oscurecida) minimiza, no cierra -mismo
///   pedido explícito.
/// Quien use este controlador tiene que llamar [dispose] cuando su propia
/// pantalla se destruye, para no dejar el panel flotando sin dueño.
class ConsultarCostoFlotanteController {
  OverlayEntry? _entrada;
  final ValueNotifier<bool> minimizado = ValueNotifier(false);

  bool get abiertoOMinimizado => _entrada != null;

  void abrir(BuildContext context) {
    if (_entrada != null) {
      minimizado.value = false;
      return;
    }
    minimizado.value = false;
    _entrada = OverlayEntry(builder: (context) => PanelFlotanteConsultarCosto(controlador: this));
    Overlay.of(context).insert(_entrada!);
  }

  void minimizarPanel() => minimizado.value = true;

  void restaurarPanel() => minimizado.value = false;

  void cerrar() {
    _entrada?.remove();
    _entrada = null;
  }

  void dispose() {
    _entrada?.remove();
    _entrada = null;
    minimizado.dispose();
  }
}

class PanelFlotanteConsultarCosto extends StatelessWidget {
  final ConsultarCostoFlotanteController controlador;

  const PanelFlotanteConsultarCosto({super.key, required this.controlador});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controlador.minimizado,
      builder: (context, minimizado, _) {
        return Stack(
          children: [
            // maintainState:true es lo que hace que ConsultarCostoScreen
            // nunca se destruya mientras el panel exista -minimizar solo
            // deja de pintarlo/tocarlo, no lo saca del árbol.
            Visibility(
              visible: !minimizado,
              maintainState: true,
              child: Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: controlador.minimizarPanel,
                        child: Container(color: Colors.black.withValues(alpha: 0.4)),
                      ),
                    ),
                    Center(
                      // Absorbe el tap para que tocar DENTRO del panel no
                      // burbujee hasta el GestureDetector de arriba y lo
                      // minimice sin querer.
                      child: GestureDetector(onTap: () {}, child: _panel(context)),
                    ),
                  ],
                ),
              ),
            ),
            if (minimizado) _chipRestaurar(context),
          ],
        );
      },
    );
  }

  Widget _panel(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width - 48 < 820 ? tamano.width - 48 : 820.0;
    final alto = tamano.height - 48 < 760 ? tamano.height - 48 : 760.0;
    return SizedBox(
      width: ancho,
      height: alto,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(child: Text('Consultar Costo', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.remove), tooltip: 'Minimizar', onPressed: controlador.minimizarPanel),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: controlador.cerrar),
                ],
              ),
            ),
            const Expanded(child: ConsultarCostoScreen(esDialogo: false)),
          ],
        ),
      ),
    );
  }

  Widget _chipRestaurar(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        color: const Color(0xFFC62828),
        borderRadius: BorderRadius.circular(30),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: controlador.restaurarPanel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calculate_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Consultar Costo', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
