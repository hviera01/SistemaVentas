import 'kiosk_identidad_stub.dart' if (dart.library.html) 'kiosk_identidad_web.dart' as impl;

/// Ver kiosk_identidad_web.dart: hace que "?formulas=1" se reconozca como
/// una app aparte (nombre e ícono de instalación propios) en vez de
/// mezclarse con "Sistema Ventas".
void aplicarIdentidadKiosk() => impl.aplicarIdentidadKiosk();
