import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'item_pedido_model.dart';
import '../../negocio/data/negocio_model.dart';
import '../../proveedores/data/proveedor_model.dart';
import '../../../core/utils/logo_pdf.dart';

class PedidoExportService {
  static const _colorMarca = PdfColor.fromInt(0xFFC62828);
  static const _colorGrisTexto = PdfColor.fromInt(0xFF4B4F58);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF2F3F7);

  Future<Uint8List> generarPdf({
    required NegocioModel negocio,
    required ProveedorModel? proveedor,
    required String observaciones,
    required List<ItemPedidoModel> items,
    required DateTime fecha,
  }) async {
    final doc = pw.Document();
    final logo = decodificarLogoPdf(negocio.logoColorBase64);
    final formatoDia = DateFormat('dd/MM/yyyy');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _encabezado(negocio, logo),
              pw.SizedBox(height: 18),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _colorMarca, width: 1.4))),
                child: pw.Text('PEDIDO DE COMPRA', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: _bloqueProveedor(proveedor)),
                  pw.SizedBox(width: 16),
                  pw.Text('Fecha: ${formatoDia.format(fecha)}', style: const pw.TextStyle(fontSize: 9.5, color: _colorGrisTexto)),
                ],
              ),
              if (observaciones.trim().isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text('Observaciones: ${observaciones.trim()}', style: const pw.TextStyle(fontSize: 9.5, color: _colorGrisTexto)),
              ],
              pw.SizedBox(height: 16),
              _tablaItems(items),
              pw.SizedBox(height: 16),
              pw.Text('Total de productos solicitados: ${items.length}', style: const pw.TextStyle(fontSize: 9.5, color: _colorGrisTexto)),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _encabezado(NegocioModel negocio, pw.MemoryImage? logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Image(logo, height: 54, width: 54),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(negocio.nombre.isEmpty ? 'MI NEGOCIO' : negocio.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
              if (negocio.direccion.isNotEmpty) pw.Text(negocio.direccion, style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto)),
              pw.Text(
                [
                  if (negocio.rtn.isNotEmpty) 'RTN: ${negocio.rtn}',
                  if (negocio.telefono.isNotEmpty) 'Tel: ${negocio.telefono}',
                ].join('   '),
                style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _bloqueProveedor(ProveedorModel? proveedor) {
    if (proveedor == null) {
      return pw.Text('Proveedor: (sin especificar)', style: const pw.TextStyle(fontSize: 9.5, color: _colorGrisTexto));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Para: ${proveedor.razonSocial}', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        if (proveedor.rtn.isNotEmpty) pw.Text('RTN: ${proveedor.rtn}', style: const pw.TextStyle(fontSize: 9, color: _colorGrisTexto)),
        if (proveedor.telefono.isNotEmpty) pw.Text('Tel: ${proveedor.telefono}', style: const pw.TextStyle(fontSize: 9, color: _colorGrisTexto)),
        if (proveedor.correo.isNotEmpty) pw.Text('Correo: ${proveedor.correo}', style: const pw.TextStyle(fontSize: 9, color: _colorGrisTexto)),
      ],
    );
  }

  pw.Widget _tablaItems(List<ItemPedidoModel> items) {
    return pw.TableHelper.fromTextArray(
      headers: ['Código', 'Producto', 'Cantidad solicitada'],
      data: [for (final i in items) [i.codigo.isEmpty ? '-' : i.codigo, i.nombreProducto, _formatoCantidad(i.cantidad)]],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _colorMarca),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {2: pw.Alignment.center},
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      oddRowDecoration: const pw.BoxDecoration(color: _colorGrisClaro),
      border: null,
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
