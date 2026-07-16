import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

class PdfPreviewDialog extends StatefulWidget {
  final String titulo;
  final Future<Uint8List> Function() generarPdf;
  final String nombreArchivo;
  final Printer? impresora;

  const PdfPreviewDialog({super.key, required this.titulo, required this.generarPdf, required this.nombreArchivo, this.impresora});

  @override
  State<PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<PdfPreviewDialog> {
  bool _imprimiendo = false;

  Future<void> _imprimirDirecto() async {
    final impresora = widget.impresora;
    if (impresora == null) return;
    setState(() => _imprimiendo = true);
    try {
      await Printing.directPrintPdf(printer: impresora, onLayout: (format) => widget.generarPdf());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo imprimir en la impresora configurada')));
      }
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 760 ? tamano.width - 24 : 640.0;
    final altoDialog = tamano.height < 700 ? tamano.height - 60 : 720.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: kIsWeb ? null : altoDialog,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: kIsWeb ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            if (widget.impresora != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _imprimiendo ? null : _imprimirDirecto,
                  icon: _imprimiendo
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_outlined, size: 18),
                  label: Text(
                    _imprimiendo ? 'Imprimiendo...' : 'Imprimir en ${widget.impresora!.name}',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // En la web, la vista previa dentro del diálogo necesita cargar
            // pdf.js desde un CDN externo (unpkg.com) la primera vez, sin
            // límite de tiempo: si esa carga falla o tarda (red restringida,
            // CDN caído), el diálogo queda "cargando" para siempre. Para no
            // depender de eso, en web se ofrece descargar/imprimir directo
            // (no necesita pdf.js) en vez de mostrar la vista previa en pantalla.
            if (kIsWeb) _accionesWeb() else _vistaPreviaNativa(),
          ],
        ),
      ),
    );
  }

  Widget _vistaPreviaNativa() {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: PdfPreview(
          build: (format) => widget.generarPdf(),
          pdfFileName: widget.nombreArchivo,
          canChangeOrientation: false,
          canChangePageFormat: false,
          allowPrinting: true,
          allowSharing: true,
          useActions: true,
        ),
      ),
    );
  }

  Widget _accionesWeb() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.picture_as_pdf_outlined, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 10),
        Text('El documento está listo', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              final bytes = await widget.generarPdf();
              await Printing.sharePdf(bytes: bytes, filename: widget.nombreArchivo);
            },
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text('Descargar PDF', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Printing.layoutPdf(onLayout: (format) => widget.generarPdf(), name: widget.nombreArchivo),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text('Ver / imprimir', style: GoogleFonts.poppins(fontSize: 13)),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ],
    );
  }
}
