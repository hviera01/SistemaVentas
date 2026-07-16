import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'venta_credito_model.dart';
import 'abono_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_pdf.dart';
import '../../negocio/data/negocio_model.dart';

class VentaCreditoExportService {
  Uint8List generarExcel(List<VentaCreditoModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['VentasCredito'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha de Registro'),
      xls.TextCellValue('No. Factura'),
      xls.TextCellValue('Cliente'),
      xls.TextCellValue('Monto Total'),
      xls.TextCellValue('Saldo Pendiente'),
      xls.TextCellValue('Fecha de Vencimiento'),
      xls.TextCellValue('Estado'),
      xls.TextCellValue('Vencida'),
    ]);

    for (final c in lista) {
      hoja.appendRow([
        xls.TextCellValue(c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-'),
        xls.TextCellValue(c.numeroDocumento),
        xls.TextCellValue(c.nombreCliente),
        xls.TextCellValue(formatearMoneda(c.montoTotal)),
        xls.TextCellValue(formatearMoneda(c.saldoPendiente)),
        xls.TextCellValue(c.fechaVencimiento != null ? formato.format(c.fechaVencimiento!) : '-'),
        xls.TextCellValue(c.liquidada ? 'Liquidada' : 'Debe'),
        xls.TextCellValue(c.vencida ? 'Vencida' : 'Vigente'),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> generarPdfListado(List<VentaCreditoModel> lista) async {
    final formato = DateFormat('dd/MM/yyyy');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Ventas a Crédito', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFC62828))),
            pw.SizedBox(height: 4),
            pw.Text('Total de créditos: ${lista.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Fecha Registro', 'No. Factura', 'Cliente', 'Monto Total', 'Saldo Pendiente', 'Vencimiento', 'Estado', 'Vencida'],
            data: lista.map((c) {
              return [
                c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-',
                c.numeroDocumento,
                c.nombreCliente,
                formatearMoneda(c.montoTotal),
                formatearMoneda(c.saldoPendiente),
                c.fechaVencimiento != null ? formato.format(c.fechaVencimiento!) : '-',
                c.liquidada ? 'Liquidada' : 'Debe',
                c.vencida ? 'Vencida' : 'Vigente',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFC62828)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F6FA)),
            border: null,
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generarPdfRecibo(VentaCreditoModel credito, AbonoModel abono, NegocioModel negocio) async {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final doc = pw.Document();

    final logo = decodificarLogoPdf(negocio.logoBnBase64);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 10),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) pw.Center(child: pw.Image(logo, height: 50)),
              if (negocio.nombre.isNotEmpty)
                pw.Center(child: pw.Text(negocio.nombre, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
              if (negocio.eslogan.isNotEmpty)
                pw.Center(child: pw.Text(negocio.eslogan, style: const pw.TextStyle(fontSize: 8))),
              if (negocio.direccion.isNotEmpty)
                pw.Center(child: pw.Text(negocio.direccion, style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center)),
              if (negocio.telefono.isNotEmpty)
                pw.Center(child: pw.Text('Tel: ${negocio.telefono}', style: const pw.TextStyle(fontSize: 7.5))),
              if (negocio.rtn.isNotEmpty)
                pw.Center(child: pw.Text('RTN: ${negocio.rtn}', style: const pw.TextStyle(fontSize: 7.5))),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Center(child: pw.Text('RECIBO DE ABONO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 6),
              pw.Text('Fecha: ${abono.fecha != null ? formatoFecha.format(abono.fecha!) : '-'}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('No. Factura: ${credito.numeroDocumento}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Cliente: ${credito.nombreCliente}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 6),
              pw.Divider(),
              _filaRecibo('Saldo anterior', formatearMoneda(abono.saldoAnterior)),
              _filaRecibo('Monto abonado', formatearMoneda(abono.montoAbonado)),
              _filaRecibo('Interés', formatearMoneda(abono.interes)),
              pw.Divider(),
              _filaRecibo('Saldo pendiente', formatearMoneda(abono.saldoPendiente), negrita: true),
              pw.SizedBox(height: 6),
              pw.Text('Método de pago: ${abono.metodoPago}', style: const pw.TextStyle(fontSize: 8)),
              if (abono.numeroRecibo.isNotEmpty) pw.Text('No. Recibo: ${abono.numeroRecibo}', style: const pw.TextStyle(fontSize: 8)),
              if (abono.usuario.isNotEmpty) pw.Text('Atendido por: ${abono.usuario}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('¡Gracias por su pago!', style: const pw.TextStyle(fontSize: 8))),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _filaRecibo(String etiqueta, String valor, {bool negrita = false}) {
    final estilo = pw.TextStyle(fontSize: 8.5, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiqueta, style: estilo),
          pw.Text(valor, style: estilo),
        ],
      ),
    );
  }
}
