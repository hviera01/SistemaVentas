import 'package:flutter/widgets.dart';

/// Route no-modal para paneles flotantes minimizables (Consultar Costo,
/// Calculadora de Rendimiento -ver sus controladores en
/// features/formulas y features/ventas-.
///
/// A propósito NO se usa PageRouteBuilder/ModalRoute: ModalRoute inserta
/// SIEMPRE, además del contenido, una OverlayEntry de "barrera modal"
/// propia y separada (ver ModalRoute.createOverlayEntries/buildModalBarrier
/// en el SDK de Flutter) -invisible cuando barrierColor es null, pero que
/// de todos modos absorbe TODOS los toques de la pantalla completa mientras
/// la Route siga en el Navigator, sin importar nada de lo que el contenido
/// haga (el Opacity/IgnorePointer que cada panel arma según [minimizado] es
/// otra OverlayEntry, la de más arriba; la barrera de Flutter va DEBAJO,
/// sigue ahí igual). Como estos paneles se "minimizan" ocultando/
/// deshabilitando su contenido SIN sacar la Route del Navigator -para no
/// perder lo que el cajero tenía cargado, ver ConsultarCostoFlotanteController-
/// esa barrera invisible se quedaba capturando todos los toques de TODA la
/// app mientras el panel seguía "abierto" aunque minimizado: eso era el
/// congelamiento real reportado ("se congela todo el sistema" al
/// minimizar) -no un cuelgue del hilo de UI, sino un barrera transparente de
/// pantalla completa que nunca se quitaba-. Ya se había intentado arreglar
/// dos veces por dentro del contenido (Visibility→Offstage primero,
/// Opacity+IgnorePointer+ExcludeSemantics después) y ninguna de las dos
/// tocaba esta barrera, que es responsabilidad exclusiva de ModalRoute, no
/// del widget de contenido.
///
/// [TransitionRoute] (la clase de la que hereda ModalRoute) no arma esa
/// barrera -createOverlayEntries() acá se implementa directo, con una sola
/// OverlayEntry: la del contenido-, así que extender esta clase en vez de
/// ModalRoute la evita de raíz. Se sigue empujando al Navigator RAÍZ igual
/// que antes (ver ConsultarCostoFlotanteController.abrir), así que el orden
/// correcto frente a Buscar Producto/Buscar Fórmula -corregido en v111- no
/// se toca: esa garantía es por ser una Route más del mismo Navigator, no
/// por ser ModalRoute.
class RoutePanelFlotante extends TransitionRoute<void> {
  RoutePanelFlotante({required this.builder});

  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration => Duration.zero;

  // Sin gesto de "volver" para descartar el panel -mismo criterio que
  // barrierDismissible:false en el PageRouteBuilder que esto reemplaza.
  @override
  bool get popGestureEnabled => false;

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return [OverlayEntry(builder: builder)];
  }
}
