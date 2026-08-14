import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Envío de tickets ESC/POS crudos directo a una impresora térmica USB en
/// Windows (por su nombre en el sistema, ej. "POS-80"), sin pasar por el
/// pipeline de impresión de PDF de Windows: ese camino (ver
/// `Printing.directPrintPdf` en venta_export_service.dart) depende del
/// driver de la impresora, y algunos modelos tienen un tope de tamaño de
/// página fijo (por ejemplo, uno registrado como "80 x 210mm") que recorta
/// o reescala cualquier factura más larga que eso, sin importar qué altura
/// declare el PDF.
///
/// Acá se usa la API de spooler de Windows en modo "RAW" (`OpenPrinter` +
/// `StartDocPrinter` con datatype "RAW" + `WritePrinter`): los bytes le
/// llegan a la impresora tal cual, sin que Windows los interprete como una
/// página con tamaño fijo. Es el mismo principio que ya usa
/// `ImpresoraRedService` para la impresión por red/celular (que no tiene
/// límite de largo) — acá es la versión para cuando la impresora está
/// conectada por USB en vez de por red.
class ImpresoraUsbWindowsService {
  /// Nunca lanza: devuelve `false` ante cualquier error (impresora
  /// desconectada, nombre inválido, spooler ocupado, etc.) para que quien
  /// llama decida qué hacer sin bloquear el flujo de la venta.
  bool imprimir({required String nombreImpresora, required List<int> bytes}) {
    if (nombreImpresora.trim().isEmpty || bytes.isEmpty) return false;

    final phPrinter = calloc<IntPtr>();
    final nombrePtr = nombreImpresora.toNativeUtf16();
    var hPrinter = 0;
    var docIniciado = false;
    var paginaIniciada = false;

    try {
      if (OpenPrinter(nombrePtr, phPrinter, nullptr) == 0) return false;
      hPrinter = phPrinter.value;

      final docInfo = calloc<DOC_INFO_1>();
      final docNamePtr = 'Ticket de venta'.toNativeUtf16();
      final dataTypePtr = 'RAW'.toNativeUtf16();
      try {
        docInfo.ref.pDocName = docNamePtr;
        docInfo.ref.pOutputFile = nullptr;
        docInfo.ref.pDatatype = dataTypePtr;
        if (StartDocPrinter(hPrinter, 1, docInfo) == 0) return false;
        docIniciado = true;
      } finally {
        calloc.free(docInfo);
        calloc.free(docNamePtr);
        calloc.free(dataTypePtr);
      }

      if (StartPagePrinter(hPrinter) == 0) return false;
      paginaIniciada = true;

      final buffer = calloc<Uint8>(bytes.length);
      final bytesEscritos = calloc<Uint32>();
      try {
        for (var i = 0; i < bytes.length; i++) {
          buffer[i] = bytes[i];
        }
        final ok = WritePrinter(hPrinter, buffer.cast(), bytes.length, bytesEscritos);
        return ok != 0 && bytesEscritos.value == bytes.length;
      } finally {
        calloc.free(buffer);
        calloc.free(bytesEscritos);
      }
    } catch (_) {
      return false;
    } finally {
      if (paginaIniciada) EndPagePrinter(hPrinter);
      if (docIniciado) EndDocPrinter(hPrinter);
      if (hPrinter != 0) ClosePrinter(hPrinter);
      calloc.free(phPrinter);
      calloc.free(nombrePtr);
    }
  }
}
