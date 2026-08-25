import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/widgets/route_panel_flotante.dart';
import '../screens/consultar_costo_screen.dart';

/// Controla un panel flotante de Consultar Costo (Venta, Colores) -pedido
/// explícito del dueño: "no en pantalla completa" y "que se pueda
/// minimizar para hacer otra cosa". No usa showDialog normal: un diálogo
/// modal destruye el State del contenido al cerrarlo (perdiendo lo que el
/// cajero tenía cargado) y su "tocar afuera" solo sabe cerrar del todo, no
/// minimizar.
///
/// Se implementa empujando una Route transparente (RoutePanelFlotante, ver
/// core/widgets/route_panel_flotante.dart, opaque:false) al Navigator RAÍZ,
/// no insertando un OverlayEntry suelto a mano -eso fue lo que se probó
/// primero y causaba que "Buscar producto"/"Buscar fórmula" (abiertos con
/// showDialog DESDE ADENTRO de este panel) terminaran renderizando DETRÁS
/// del panel: showDialog usa por defecto el Navigator raíz para apilar sus
/// diálogos, y un OverlayEntry insertado a mano no participa de ese mismo
/// orden -Flutter solo garantiza que una Route nueva quede arriba de las
/// Routes anteriores DEL MISMO Navigator, no arriba de cualquier
/// OverlayEntry suelto que haya por ahí-. Al ser también una Route de ese
/// mismo Navigator, cualquier diálogo que se abra después (sea de este
/// panel o de la pantalla de atrás) queda ordenado correctamente arriba,
/// con las mismas reglas de siempre. RoutePanelFlotante en particular (y no
/// PageRouteBuilder/ModalRoute) es lo que evita el congelamiento de toda la
/// app al minimizar -ver el doc grande de esa clase para el porqué exacto-.
///
/// - [abrir] empuja el panel una sola vez; si ya está abierto (minimizado
///   o no), lo vuelve a mostrar en vez de crear uno nuevo.
/// - [minimizar] lo oculta pero mantiene su contenido vivo -Consultar Costo
///   con lo que se tenía cargado, ver PanelFlotanteConsultarCosto.build- Y
///   deja de capturar toques (así se puede seguir usando la pantalla de
///   atrás mientras el panel sigue "abierto" técnicamente, solo invisible).
/// - [cerrar] sí lo descarta del todo (el "X" del panel): saca la Route del
///   Navigator, ahí sí se pierde el State.
/// - Tocar afuera del panel (la zona oscurecida) minimiza, no cierra -mismo
///   pedido explícito.
/// Quien use este controlador tiene que llamar [dispose] cuando su propia
/// pantalla se destruye, para no dejar la Route huérfana.
class ConsultarCostoFlotanteController {
  RoutePanelFlotante? _route;
  final ValueNotifier<bool> minimizado = ValueNotifier(false);

  void abrir(BuildContext context) {
    if (_route != null) {
      minimizado.value = false;
      return;
    }
    minimizado.value = false;
    final route = RoutePanelFlotante(
      builder: (context) => PanelFlotanteConsultarCosto(controlador: this),
    );
    _route = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() => _route = null);
  }

  void minimizarPanel() => minimizado.value = true;

  void restaurarPanel() => minimizado.value = false;

  void cerrar() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void dispose() {
    cerrar();
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
            // Positioned.fill tiene que ser hijo DIRECTO del Stack -ver la
            // nota grande más abajo sobre por qué ya no se usa Visibility/
            // Offstage acá (el "Stack Overflow" que eso causaba ya está
            // resuelto de otra forma, no hacía falta Visibility para nada).
            //
            // ExcludeSemantics + IgnorePointer + Opacity en vez de
            // Visibility(maintainState:true) -que por dentro envuelve en un
            // Offstage, que mantiene el subárbol completo "vivo" en layout/
            // semántica/DOM- mantiene el State del panel (lo que el cajero
            // tenía cargado) sin pintarlo ni dejarlo tocable mientras está
            // minimizado. IMPORTANTE: esto por sí solo NO alcanzaba para
            // arreglar el congelamiento de toda la app al minimizar -se
            // probó y el dueño confirmó que seguía pasando incluso con este
            // cambio-. La causa real era otra, más abajo en la pila: la
            // Route en la que vive este panel. El fix definitivo está en
            // cómo [ConsultarCostoFlotanteController.abrir] empuja la Route
            // -ver RoutePanelFlotante en core/widgets/route_panel_flotante.dart-.
            Positioned.fill(
              child: ExcludeSemantics(
                excluding: minimizado,
                child: IgnorePointer(
                  ignoring: minimizado,
                  child: Opacity(
                    opacity: minimizado ? 0 : 1,
                    // Material(type: transparency): esta Route se empuja con
                    // PageRouteBuilder genérico, no con MaterialPageRoute -
                    // ese sí envuelve su contenido en un Material solo, este
                    // no-, así que sin esto el texto de adentro (Consultar
                    // Costo entero) no encuentra un ancestro Material y sale
                    // con el subrayado amarillo doble de Flutter -pedido
                    // explícito del dueño, eso era lo que veía, no un dato
                    // mal calculado.
                    child: Material(
                      type: MaterialType.transparency,
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
