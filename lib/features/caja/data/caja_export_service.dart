import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'cierre_caja_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_pdf.dart';
import '../../negocio/data/negocio_model.dart';

class CajaExportService {
  static const _colorMarca = PdfColor.fromInt(0xFFC62828);
  static const _colorGrisTexto = PdfColor.fromInt(0xFF4B4F58);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF2F3F7);

  Future<Uint8List> generarTicketCierre(CierreCajaModel cierre, NegocioModel negocio) async {
    final doc = pw.Document();
    final logo = decodificarLogoPdf(negocio.logoBnBase64);
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    const fSmall = 7.5;
    const fNormal = 8.0;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 10),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) pw.Center(child: pw.Image(logo, height: 50)),
              if (negocio.nombre.isNotEmpty)
                pw.Center(child: pw.Text(negocio.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 6),
              _separador(),
              pw.Center(child: pw.Text('CIERRE DE CAJA', style: pw.TextStyle(fontSize: fNormal + 1, fontWeight: pw.FontWeight.bold))),
              _separador(),
              pw.Text('Desde: ${formatoFecha.format(cierre.fechaInicio)}', style: const pw.TextStyle(fontSize: fNormal)),
              pw.Text('Hasta: ${formatoFecha.format(cierre.fechaFin)}', style: const pw.TextStyle(fontSize: fNormal)),
              pw.Text('Usuario: ${cierre.usuarioResponsable}', style: const pw.TextStyle(fontSize: fNormal)),
              _separador(),
              _filaTicket('Monto inicial efectivo:', cierre.montoInicial, fNormal),
              _filaTicket('Ingreso efectivo:', cierre.ingresosEfectivo, fNormal),
              _filaTicket('Ingreso tarjeta:', cierre.ingresosTarjeta, fNormal),
              _filaTicket('Ingreso transferencia:', cierre.ingresosTransferencia, fNormal),
              _filaTicket('Egreso efectivo:', cierre.egresosEfectivo, fNormal),
              _filaTicket('Egreso transferencia:', cierre.egresosTransferencia, fNormal),
              _separador(),
              _filaTicket('Total efectivo:', cierre.totalCalculadoEfectivo, fNormal, negrita: true),
              _filaTicket('Total transferencia:', cierre.totalTransferencia, fNormal, negrita: true),
              _filaTicket('Gran total:', cierre.granTotal, fNormal, negrita: true),
              _filaTicket('Total real efectivo:', cierre.totalReal, fNormal, negrita: true),
              _filaTicket('Diferencia:', cierre.diferencia, fNormal, negrita: true),
              _separador(),
              if (cierre.observaciones.isNotEmpty) ...[
                pw.Text('Observaciones:', style: pw.TextStyle(fontSize: fSmall, fontWeight: pw.FontWeight.bold)),
                pw.Text(cierre.observaciones, style: const pw.TextStyle(fontSize: fSmall)),
                _separador(),
              ],
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text('REPORTE CIERRE DE CAJA', style: pw.TextStyle(fontSize: fSmall, fontWeight: pw.FontWeight.bold))),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generarPdfCierre(CierreCajaModel cierre, NegocioModel negocio) async {
    final doc = pw.Document();
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(negocio.nombre.isEmpty ? 'MI NEGOCIO' : negocio.nombre.toUpperCase(),
                      style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: pw.BoxDecoration(color: _colorMarca, borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Text('CIERRE DE CAJA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Desde: ${formatoFecha.format(cierre.fechaInicio)}', style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(child: pw.Text('Hasta: ${formatoFecha.format(cierre.fechaFin)}', style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(child: pw.Text('Usuario: ${cierre.usuarioResponsable}', style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.SizedBox(height: 16),
              _tablaResumen(cierre),
              pw.SizedBox(height: 16),
              if (cierre.observaciones.isNotEmpty) ...[
                pw.Text('Observaciones', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _colorGrisTexto)),
                pw.SizedBox(height: 4),
                pw.Text(cierre.observaciones, style: const pw.TextStyle(fontSize: 10)),
              ],
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _tablaResumen(CierreCajaModel cierre) {
    final filas = [
      ['Monto inicial efectivo', cierre.montoInicial],
      ['Ingreso efectivo', cierre.ingresosEfectivo],
      ['Ingreso tarjeta', cierre.ingresosTarjeta],
      ['Ingreso transferencia', cierre.ingresosTransferencia],
      ['Egreso efectivo', cierre.egresosEfectivo],
      ['Egreso transferencia', cierre.egresosTransferencia],
      ['Total efectivo (calculado)', cierre.totalCalculadoEfectivo],
      ['Total transferencia', cierre.totalTransferencia],
      ['Gran total', cierre.granTotal],
      ['Total real efectivo', cierre.totalReal],
      ['Diferencia', cierre.diferencia],
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E2E8), width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _colorGrisClaro),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Concepto', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Monto', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
          ],
        ),
        for (final fila in filas)
          pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(fila[0] as String, style: const pw.TextStyle(fontSize: 10))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(formatearMoneda(fila[1] as double), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
            ],
          ),
      ],
    );
  }

  pw.Widget _separador() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(thickness: 0.7),
    );
  }

  pw.Widget _filaTicket(String etiqueta, double valor, double tamano, {bool negrita = false}) {
    final estilo = pw.TextStyle(fontSize: tamano, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(etiqueta, style: estilo),
        pw.Text(formatearMoneda(valor), style: estilo),
      ],
    );
  }
}
