import 'xlsx_reparar.dart';
import 'exportador_stub.dart'
    if (dart.library.html) 'exportador_web.dart'
    if (dart.library.io) 'exportador_io.dart' as impl;

Future<void> guardarOCompartirArchivo(List<int> bytes, String nombreArchivo) {
  final bytesFinal = nombreArchivo.toLowerCase().endsWith('.xlsx') ? repararRutasXlsx(bytes) : bytes;
  return impl.guardarArchivo(bytesFinal, nombreArchivo);
}
