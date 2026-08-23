import 'kiosk_identidad_stub.dart' if (dart.library.html) 'kiosk_identidad_web.dart' as impl;

/// Ver kiosk_identidad_web.dart: hace que un acceso directo de kiosco
/// ("?formulas=1", "?costos=1", ver main.dart) se vea como una app aparte
/// -título propio de la pestaña- en vez de mezclarse con "Sistema Ventas".
/// [titulo] es cosmético nada más (ver la nota grande en kiosk_identidad_web.dart
/// sobre por qué el ícono de instalación propio se resolvió aparte, con una
/// página estática, y no depende de esto).
void aplicarIdentidadKiosk(String titulo) => impl.aplicarIdentidadKiosk(titulo);
