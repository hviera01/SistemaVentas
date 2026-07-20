import 'beep_stub.dart' if (dart.library.html) 'beep_web.dart' as impl;

/// Sonido corto + vibración de confirmación al escanear un código (ver
/// EscaneoRemotoScreen y BarcodeScannerScreen): ayuda a notar en el momento
/// que un código se mandó, para no volver a pasar el mismo producto sin
/// darse cuenta. No lanza si el navegador bloquea el audio (por ejemplo,
/// antes de la primera interacción del usuario con la página): la
/// confirmación visual en pantalla sigue funcionando igual.
void reproducirBeep() => impl.beep();
