import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';
import '../../../core/utils/formato_moneda.dart';

class ReporteExportService {
  Uint8List generarExcelVentas(List<ReporteVentaModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['ReporteVentas'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Tipo Documento'),
      xls.TextCellValue('No. Documento'),
      xls.TextCellValue('Total a Pagar'),
      xls.TextCellValue('Cant. Productos'),
      xls.TextCellValue('Método de Pago'),
      xls.TextCellValue('Usuario'),
      xls.TextCellValue('Documento Cliente'),
      xls.TextCellValue('Cliente'),
      xls.TextCellValue('Impuesto'),
      xls.TextCellValue('Condición'),
      xls.TextCellValue('Vencimiento'),
      xls.TextCellValue('Estado'),
    ]);

    for (final v in lista) {
      hoja.appendRow([
        xls.TextCellValue(v.fechaRegistro != null ? formato.format(v.fechaRegistro!) : '-'),
        xls.TextCellValue(v.tipoDocumento),
        xls.TextCellValue(v.numeroDocumento),
        xls.TextCellValue(formatearMoneda(v.totalAPagar)),
        xls.TextCellValue(v.cantidadProductos.toString()),
        xls.TextCellValue(v.metodoPago),
        xls.TextCellValue(v.usuarioRegistro),
        xls.TextCellValue(v.documentoCliente),
        xls.TextCellValue(v.nombreCliente),
        xls.TextCellValue(formatearMoneda(v.impuesto)),
        xls.TextCellValue(v.condicion),
        xls.TextCellValue(v.fechaVencimiento != null ? formato.format(v.fechaVencimiento!) : '-'),
        xls.TextCellValue(v.estado),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Uint8List generarExcelCompras(List<ReporteCompraModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['ReporteCompras'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Tipo Documento'),
      xls.TextCellValue('No. Factura'),
      xls.TextCellValue('No. Documento'),
      xls.TextCellValue('Monto Total'),
      xls.TextCellValue('Cant. Productos'),
      xls.TextCellValue('Usuario'),
      xls.TextCellValue('Documento Proveedor'),
      xls.TextCellValue('Proveedor'),
      xls.TextCellValue('Condición'),
      xls.TextCellValue('Método de Pago'),
      xls.TextCellValue('Vencimiento'),
      xls.TextCellValue('Impuesto'),
      xls.TextCellValue('Descuento'),
      xls.TextCellValue('Ajuste'),
    ]);

    for (final c in lista) {
      hoja.appendRow([
        xls.TextCellValue(c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-'),
        xls.TextCellValue(c.tipoDocumento),
        xls.TextCellValue(c.noFactura),
        xls.TextCellValue(c.numeroDocumento),
        xls.TextCellValue(formatearMoneda(c.montoTotal)),
        xls.TextCellValue(c.cantidadProductos.toString()),
        xls.TextCellValue(c.usuarioRegistro),
        xls.TextCellValue(c.documentoProveedor),
        xls.TextCellValue(c.razonSocial),
        xls.TextCellValue(c.condicion),
        xls.TextCellValue(c.metodoPago),
        xls.TextCellValue(c.fechaVencimiento != null ? formato.format(c.fechaVencimiento!) : '-'),
        xls.TextCellValue(formatearMoneda(c.impuesto)),
        xls.TextCellValue(formatearMoneda(c.descuentoTotalMonto)),
        xls.TextCellValue(formatearMoneda(c.ajusteManual)),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> generarPdfVentas(List<ReporteVentaModel> lista) async {
    final formato = DateFormat('dd/MM/yyyy');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Reporte de Ventas', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFC62828))),
            pw.SizedBox(height: 4),
            pw.Text('Total de registros: ${lista.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Tipo', 'No. Documento', 'Total', 'Cant.', 'Pago', 'Usuario', 'Cliente', 'Condición', 'Estado'],
            data: lista.map((v) {
              return [
                v.fechaRegistro != null ? formato.format(v.fechaRegistro!) : '-',
                v.tipoDocumento,
                v.numeroDocumento,
                formatearMoneda(v.totalAPagar),
                v.cantidadProductos.toString(),
                v.metodoPago,
                v.usuarioRegistro,
                v.nombreCliente,
                v.condicion,
                v.estado,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFC62828)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EAF0)),
            border: null,
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generarPdfCompras(List<ReporteCompraModel> lista) async {
    final formato = DateFormat('dd/MM/yyyy');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Reporte de Compras', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFC62828))),
            pw.SizedBox(height: 4),
            pw.Text('Total de registros: ${lista.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Tipo', 'No. Factura', 'Proveedor', 'Monto Total', 'Cant.', 'Pago', 'Condición', 'Usuario', 'Descuento', 'Ajuste'],
            data: lista.map((c) {
              return [
                c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-',
                c.tipoDocumento,
                c.noFactura,
                c.razonSocial,
                formatearMoneda(c.montoTotal),
                c.cantidadProductos.toString(),
                c.metodoPago,
                c.condicion,
                c.usuarioRegistro,
                formatearMoneda(c.descuentoTotalMonto),
                formatearMoneda(c.ajusteManual),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFC62828)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EAF0)),
            border: null,
          ),
        ],
      ),
    );
    return doc.save();
  }
}
