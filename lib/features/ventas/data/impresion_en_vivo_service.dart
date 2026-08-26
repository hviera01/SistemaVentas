import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import '../../negocio/data/negocio_model.dart';
import '../../../core/services/impresora_usb_windows_service.dart';
import '../../../core/services/impresora_red_service.dart';
import 'venta_export_service.dart';
import 'venta_model.dart';
import 'venta_ticket_escpos_service.dart';

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
  final _servicioTicketEscPos = VentaTicketEscPosService();
  final _servicioImpresoraRed = ImpresoraRedService();

  /// [forzarCopia] respeta la elección "Copia"/"Original" que se haya hecho
  /// del lado del celular al pedir esta reimpresión en vivo (ver
  /// VentaModel.solicitudImpresionEsCopia). null (default, una venta recién
  /// confirmada) es distinto de false: null imprime ORIGINAL y además COPIA
  /// si el negocio tiene esa opción activada; false fuerza una sola hoja
  /// ORIGINAL sin importar esa configuración (ver generarPdfFactura y
  /// VentaTicketEscPosService.generarTicket, que respeta el mismo criterio).
  /// Devuelve true si logró imprimir.
  Future<bool> imprimirSilencioso(VentaModel venta, NegocioModel negocio, {bool? forzarCopia}) async {
    if (negocio.impresoraTermicaUrl.isEmpty) return false;
    // En Windows se manda el ticket como ESC/POS crudo por USB en vez de
    // como PDF (ver el mismo cambio y su comentario grande en
    // venta_export_service.dart / registrar_venta_screen.dart).
    if (!kIsWeb && Platform.isWindows) {
      try {
        final bytes = await _servicioTicketEscPos.generarTicket(venta, negocio, forzarCopia: forzarCopia);
        return ImpresoraUsbWindowsService().imprimir(nombreImpresora: negocio.impresoraTermicaNombre, bytes: bytes);
      } catch (_) {
        return false;
      }
    }
    try {
      final impresora = Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
      await Printing.directPrintPdf(
        printer: impresora,
        onLayout: (formato) => _servicioExport.generarPdfFactura(venta, negocio, forzarCopia: forzarCopia, formatoImpresora: formato),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mismo criterio que [imprimirSilencioso] pero para la guía de envío
  /// (solicitudImpresionGuiaEnvio, ver AppShell). A diferencia del recibo,
  /// la guía no tiene versión PDF (ver VentaTicketEscPosService.
  /// generarGuiaEnvio, es ESC/POS puro): en Windows va por USB directo, en
  /// el resto de escritorio por la impresora de red configurada -sin
  /// fallback a `printing` porque no hay PDF que mandarle-. Devuelve true
  /// si logró imprimir.
  Future<bool> imprimirGuiaSilencioso(VentaModel venta, NegocioModel negocio, {bool grande = false}) async {
    try {
      final bytes = await _servicioTicketEscPos.generarGuiaEnvio(venta, negocio, grande: grande);
      if (!kIsWeb && Platform.isWindows) {
        if (negocio.impresoraTermicaNombre.isEmpty) return false;
        return ImpresoraUsbWindowsService().imprimir(nombreImpresora: negocio.impresoraTermicaNombre, bytes: bytes);
      }
      if (negocio.impresoraRedIp.isEmpty) return false;
      return await _servicioImpresoraRed.imprimir(ip: negocio.impresoraRedIp, puerto: negocio.impresoraRedPuerto, bytes: bytes);
    } catch (_) {
      return false;
    }
  }
}
