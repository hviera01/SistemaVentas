// `dart:ffi`/`package:win32` (usados para ShellExecute, ver
// lanzador_instalador_windows_io.dart) no existen en Web -el build de Web
// ni siquiera compila si algo los importa, sin importar que el código esté
// detrás de un chequeo de plataforma en tiempo de ejecución-. Mismo patrón
// que impresora_usb_windows_service.dart: en Web (y cualquier otra
// plataforma sin dart:io) se usa un stub que nunca se llega a invocar de
// verdad.
export 'lanzador_instalador_windows_stub.dart' if (dart.library.io) 'lanzador_instalador_windows_io.dart';
