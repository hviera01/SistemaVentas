/// Versión sin operación para plataformas donde `dart:ffi`/`package:win32`
/// no existen (Web, la que importa esto en tiempo de compilación). Nunca se
/// llega a invocar de verdad: ActualizacionService.descargarEInstalar ya
/// está detrás de un chequeo `ActualizacionService.aplica`
/// (`!kIsWeb && (Platform.isWindows || Platform.isAndroid)`), y esta función
/// en particular solo se llama del lado de Windows. Ver
/// lanzador_instalador_windows.dart.
bool lanzarInstaladorElevado(String ruta) => false;
