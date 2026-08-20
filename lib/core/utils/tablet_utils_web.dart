import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// iPadOS Safari se identifica a sí mismo como macOS de escritorio (Apple lo
// hace a propósito desde iPadOS 13, para que los sitios le sirvan la versión
// de escritorio); Flutter hereda ese engaño y `defaultTargetPlatform` da
// TargetPlatform.macOS en un iPad, no iOS -por eso esTabletTactil no puede
// confiar solo en esa señal-. `navigator.maxTouchPoints` sí distingue: en un
// Mac de verdad (sin pantalla táctil) da 0; en un iPad da un número > 0. Ver
// el mismo estilo de interop directo (sin paquetes) en beep_web.dart y
// webauthn_web.dart.
bool esDispositivoTactil() {
  try {
    final navigator = globalContext.getProperty('navigator'.toJS) as JSObject;
    final maxTouchPoints = navigator.getProperty('maxTouchPoints'.toJS);
    if (maxTouchPoints == null) return false;
    return (maxTouchPoints as JSNumber).toDartDouble > 0;
  } catch (_) {
    return false;
  }
}
