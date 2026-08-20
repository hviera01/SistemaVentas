import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// true en una tablet táctil (Android/iOS, ancho de pantalla de tablet
/// -shortestSide >= 600, el mismo criterio que usa Android para distinguir
/// tablet de celular-), false en celular (angosto), en PC/escritorio (no es
/// Android/iOS) o en web de escritorio. Usado por CampoTecladoCompacto
/// (ver core/widgets/campo_teclado_compacto.dart) para saber cuándo mostrar
/// el teclado propio en pantalla en vez del teclado nativo.
bool esTabletTactil(BuildContext context) {
  final esTactil = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  if (!esTactil) return false;
  return MediaQuery.sizeOf(context).shortestSide >= 600;
}
