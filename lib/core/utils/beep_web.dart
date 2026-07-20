import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Beep corto (onda seno ~880Hz, 150ms) generado con la Web Audio API del
/// navegador, sin necesitar ningún archivo de audio ni paquete adicional.
/// Es la implementación que de verdad importa acá: EscaneoRemotoScreen se
/// abre siempre desde el navegador del celular (el link del QR apunta a la
/// versión web en GitHub Pages), nunca desde la app nativa.
@JS('window.AudioContext')
external JSFunction? get _audioContextCtor;

@JS('window.webkitAudioContext')
external JSFunction? get _webkitAudioContextCtor;

void beep() {
  try {
    final ctor = _audioContextCtor ?? _webkitAudioContextCtor;
    if (ctor == null) return;
    final ctx = ctor.callAsConstructor<JSObject>();
    final oscilador = (ctx.callMethod('createOscillator'.toJS) as JSObject);
    final ganancia = (ctx.callMethod('createGain'.toJS) as JSObject);
    (oscilador.getProperty('frequency'.toJS) as JSObject).setProperty('value'.toJS, 880.toJS);
    oscilador.callMethod('connect'.toJS, ganancia);
    ganancia.callMethod('connect'.toJS, ctx.getProperty('destination'.toJS));
    (ganancia.getProperty('gain'.toJS) as JSObject).setProperty('value'.toJS, 0.15.toJS);
    oscilador.callMethod('start'.toJS);
    final ahora = (ctx.getProperty('currentTime'.toJS) as JSNumber).toDartDouble;
    oscilador.callMethod('stop'.toJS, (ahora + 0.15).toJS);
  } catch (_) {
    // El navegador puede bloquear el audio hasta la primera interacción del
    // usuario, o no soportar Web Audio API: no es crítico, se ignora.
  }
}
