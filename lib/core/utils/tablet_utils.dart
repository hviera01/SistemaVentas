import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'tablet_utils_stub.dart' if (dart.library.html) 'tablet_utils_web.dart' as impl;

/// true en una tablet táctil, false en celular (angosto), en PC/escritorio o
/// en web de escritorio. Ancho de pantalla de tablet -shortestSide >= 600,
/// el mismo criterio que usa Android para distinguir tablet de celular- más
/// alguna señal de que el dispositivo es táctil:
/// - Android/iOS nativo o vía navegador: `defaultTargetPlatform` ya alcanza.
/// - iPad con Safari: iPadOS se identifica como macOS de escritorio (no
///   iOS), así que ahí hace falta la segunda señal de tablet_utils_web.dart
///   (navigator.maxTouchPoints) para no confundirlo con un Mac de verdad.
/// Usado por CampoTecladoCompacto (ver core/widgets/campo_teclado_compacto.dart)
/// para saber cuándo mostrar el teclado propio en pantalla en vez del
/// teclado nativo.
bool esTabletTactil(BuildContext context) {
  if (MediaQuery.sizeOf(context).shortestSide < 600) return false;
  if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) return true;
  if (kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) return impl.esDispositivoTactil();
  return false;
}
