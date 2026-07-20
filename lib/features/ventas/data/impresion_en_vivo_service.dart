import 'package:printing/printing.dart';
import '../../negocio/data/negocio_model.dart';
import 'venta_export_service.dart';
import 'venta_model.dart';

/// Imprime automáticamente, sin ningún diálogo ni confirmación, una venta
/// que llegó como "solicitud de impresión en vivo" desde el celular (ver
/// PresenciaImpresionRepository y VentaRepository.
/// obtenerVentasConSolicitudImpresionEnVivo). Solo tiene sentido en la PC
/// principal, en modo escritorio nativo (Windows/macOS/Linux): es la única
/// plataforma donde `printing` puede mandar un PDF directo a una impresora
/// del sistema operativo sin abrir ningún diálogo.
///
/// Si no hay impresora térmica configurada, o si falla el intento, no se
/// insiste ni se avisa con un diálogo: la venta ya había quedado marcada
/// `pendienteImpresion` desde que se creó, así que sigue disponible ahí
/// para resolverla a mano (ver VentasPendientesImpresionDialog).
class ImpresionEnVivoService {
  final _servicioExport = VentaExportService();

  /// Devuelve true si logró imprimir.
  Future<bool> imprimirSilencioso(VentaModel venta, NegocioModel negocio) async {
    if (negocio.impresoraTermicaUrl.isEmpty) return false;
    try {
      final impresora = Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
      await Printing.directPrintPdf(
        printer: impresora,
        onLayout: (formato) => _servicioExport.generarPdfFactura(venta, negocio, formatoImpresora: formato),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
