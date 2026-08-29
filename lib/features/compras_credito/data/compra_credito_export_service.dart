import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'compra_credito_model.dart';
import 'abono_compra_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_pdf.dart';
import '../../negocio/data/negocio_model.dart';

/// Una fila ya calculada del Estado de Cuenta (ver
/// EstadoCuentaProveedorDialog) — el PDF no recalcula nada, solo dibuja lo
/// que la pantalla ya armó, para no duplicar la lógica de cargos/abonos por
/// día/saldo corriendo en dos lugares.
class FilaEstadoCuenta {
  final DateTime fecha;
  final bool esCargo;
  final String titulo;
  final String subtitulo;
  final double monto;
  final String usuarios;
  final double saldoDespues;

  FilaEstadoCuenta({
    required this.fecha,
    required this.esCargo,
    required this.titulo,
    required this.subtitulo,
    required this.monto,
    required this.usuarios,
    required this.saldoDespues,
  });
}

class CompraCreditoExportService {
  static const _colorMarca = PdfColor.fromInt(0xFFC62828);
  static const _colorVerde = PdfColor.fromInt(0xFF16A34A);
  static const _colorGrisTexto = PdfColor.fromInt(0xFF4B4F58);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF6F7FA);
  static const _colorBorde = PdfColor.fromInt(0xFFE0E2E8);

  Future<Uint8List> generarPdfEstadoCuenta({
    required String nombreProveedor,
    required List<FilaEstadoCuenta> filas,
    required double totalFacturado,
    required double totalAbonado,
    required double saldoActual,
    required NegocioModel negocio,
  }) async {
    final doc = pw.Document();
    final logo = decodificarLogoPdf(negocio.logoColorBase64);
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final formatoGenerado = DateFormat('dd/MM/yyyy HH:mm');
    final ahora = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (context.pageNumber == 1) ...[
              _encabezadoEstadoCuenta(negocio, logo, nombreProveedor),
              pw.SizedBox(height: 14),
              _resumenTotalesPdf(totalFacturado, totalAbonado, saldoActual),
              pw.SizedBox(height: 12),
            ],
            _filaHeaderTablaEstadoCuenta(),
          ],
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generado el ${formatoGenerado.format(ahora)}   ·   Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          for (var i = 0; i < filas.length; i++) _filaTablaEstadoCuenta(filas[i], formatoFecha, impar: i.isOdd),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _encabezadoEstadoCuenta(NegocioModel negocio, pw.MemoryImage? logo, String nombreProveedor) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Image(logo, height: 50, width: 50),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(negocio.nombre.isEmpty ? 'MI NEGOCIO' : negocio.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
              pw.SizedBox(height: 3),
              if (negocio.direccion.isNotEmpty) pw.Text(negocio.direccion, style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto)),
              pw.Text(
                [
                  if (negocio.rtn.isNotEmpty) 'RTN: ${negocio.rtn}',
                  if (negocio.telefono.isNotEmpty) 'Tel: ${negocio.telefono}',
                ].join('   ·   '),
                style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto),
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(color: _colorMarca, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('ESTADO DE CUENTA', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text(nombreProveedor, style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _resumenTotalesPdf(double totalFacturado, double totalAbonado, double saldoActual) {
    return pw.Row(
      children: [
        pw.Expanded(child: _cajaTotalPdf('TOTAL FACTURADO', formatearMoneda(totalFacturado), const PdfColor.fromInt(0xFF3B4252))),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _cajaTotalPdf('TOTAL ABONADO', formatearMoneda(totalAbonado), _colorVerde)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _cajaTotalPdf('SALDO PENDIENTE ACTUAL', formatearMoneda(saldoActual), _colorMarca)),
      ],
    );
  }

  pw.Widget _cajaTotalPdf(String etiqueta, String valor, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(etiqueta, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 2),
          pw.Text(valor, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ],
      ),
    );
  }

  pw.Widget _filaHeaderTablaEstadoCuenta() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const pw.BoxDecoration(color: _colorMarca),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 2, child: pw.Text('FECHA', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          pw.Expanded(flex: 5, child: pw.Text('MOVIMIENTO', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          pw.Expanded(flex: 3, child: pw.Text('USUARIO(S)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          pw.Expanded(flex: 2, child: pw.Text('CARGO', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          pw.Expanded(flex: 2, child: pw.Text('ABONO', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          pw.Expanded(flex: 2, child: pw.Text('SALDO', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
        ],
      ),
    );
  }

  pw.Widget _filaTablaEstadoCuenta(FilaEstadoCuenta f, DateFormat formatoFecha, {required bool impar}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: impar ? _colorGrisClaro : PdfColors.white,
        border: const pw.Border(bottom: pw.BorderSide(color: _colorBorde, width: 0.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 2, child: pw.Text(formatoFecha.format(f.fecha), style: const pw.TextStyle(fontSize: 8))),
          pw.Expanded(
            flex: 5,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(f.titulo, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                if (f.subtitulo.isNotEmpty) pw.Text(f.subtitulo, style: const pw.TextStyle(fontSize: 7.5, color: _colorGrisTexto)),
              ],
            ),
          ),
          pw.Expanded(flex: 3, child: pw.Text(f.usuarios, style: const pw.TextStyle(fontSize: 8))),
          pw.Expanded(flex: 2, child: pw.Text(f.esCargo ? formatearMoneda(f.monto) : '-', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _colorMarca))),
          pw.Expanded(flex: 2, child: pw.Text(!f.esCargo ? formatearMoneda(f.monto) : '-', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _colorVerde))),
          pw.Expanded(flex: 2, child: pw.Text(formatearMoneda(f.saldoDespues), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }

  Uint8List generarExcel(List<CompraCreditoModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['ComprasCredito'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha de Registro'),
      xls.TextCellValue('Número de Documento'),
      xls.TextCellValue('Número de Factura'),
      xls.TextCellValue('Proveedor'),
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
        xls.TextCellValue(c.noFactura),
        xls.TextCellValue(c.nombreProveedor),
        xls.TextCellValue(formatearMoneda(c.montoTotal)),
        xls.TextCellValue(formatearMoneda(c.saldoPendiente)),
        xls.TextCellValue(c.fechaVencimiento != null ? formato.format(c.fechaVencimiento!) : '-'),
        xls.TextCellValue(c.liquidada ? 'Liquidada' : 'Deuda'),
        xls.TextCellValue(c.vencida ? 'Vencida' : 'Vigente'),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> generarPdfListado(List<CompraCreditoModel> lista) async {
    final formato = DateFormat('dd/MM/yyyy');
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Compras a Crédito', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFC62828))),
            pw.SizedBox(height: 4),
            pw.Text('Total de créditos: ${lista.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Fecha Registro', 'No. Documento', 'No. Factura', 'Proveedor', 'Monto Total', 'Saldo Pendiente', 'Vencimiento', 'Estado', 'Vencida'],
            data: lista.map((c) {
              return [
                c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-',
                c.numeroDocumento,
                c.noFactura,
                c.nombreProveedor,
                formatearMoneda(c.montoTotal),
                formatearMoneda(c.saldoPendiente),
                c.fechaVencimiento != null ? formato.format(c.fechaVencimiento!) : '-',
                c.liquidada ? 'Liquidada' : 'Deuda',
                c.vencida ? 'Vencida' : 'Vigente',
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

  Future<Uint8List> generarPdfRecibo(CompraCreditoModel compra, AbonoCompraModel abono, NegocioModel negocio) async {
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
              if (negocio.direccion.isNotEmpty)
                pw.Center(child: pw.Text(negocio.direccion, style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center)),
              if (negocio.telefono.isNotEmpty)
                pw.Center(child: pw.Text('Tel: ${negocio.telefono}', style: const pw.TextStyle(fontSize: 7.5))),
              if (negocio.rtn.isNotEmpty)
                pw.Center(child: pw.Text('RTN: ${negocio.rtn}', style: const pw.TextStyle(fontSize: 7.5))),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Center(child: pw.Text('RECIBO DE ABONO A PROVEEDOR', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 6),
              pw.Text('Fecha: ${abono.fecha != null ? formatoFecha.format(abono.fecha!) : '-'}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('No. Factura: ${compra.noFactura}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Proveedor: ${compra.nombreProveedor}', style: const pw.TextStyle(fontSize: 8)),
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
