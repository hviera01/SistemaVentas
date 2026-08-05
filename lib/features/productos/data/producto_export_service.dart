import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart' as bc;
import 'producto_model.dart';
import '../../../core/utils/formato_moneda.dart';

class ProductoExportService {
  Uint8List generarExcel(List<ProductoModel> lista, Map<String, String> mapaCategorias) {
    final libro = xls.Excel.createExcel();
    final hoja = libro['Inventario'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Código'),
      xls.TextCellValue('Nombre'),
      xls.TextCellValue('Descripción'),
      xls.TextCellValue('Categoría'),
      xls.TextCellValue('Existencia'),
      xls.TextCellValue('Precio Venta'),
      xls.TextCellValue('Precio Compra'),
      xls.TextCellValue('Estado'),
    ]);

    for (final p in lista) {
      hoja.appendRow([
        xls.TextCellValue(p.codigo),
        xls.TextCellValue(p.nombre),
        xls.TextCellValue(p.descripcion),
        xls.TextCellValue(mapaCategorias[p.idCategoria] ?? '-'),
        xls.TextCellValue(p.stock.toString()),
        xls.TextCellValue(formatearMoneda(p.precioVenta)),
        xls.TextCellValue(formatearMoneda(p.precioCompra)),
        xls.TextCellValue(p.estado ? 'Activo' : 'Inactivo'),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> generarPdfInventario(List<ProductoModel> lista, Map<String, String> mapaCategorias) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Inventario · SUPERCOLOR', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFC62828))),
            pw.SizedBox(height: 4),
            pw.Text('Total de productos: ${lista.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Código', 'Nombre', 'Descripción', 'Categoría', 'Existencia', 'P. Venta', 'P. Compra', 'Estado'],
            data: lista.map((p) {
              return [
                p.codigo,
                p.nombre,
                p.descripcion.isEmpty ? '-' : p.descripcion,
                mapaCategorias[p.idCategoria] ?? '-',
                p.stock.toString(),
                formatearMoneda(p.precioVenta),
                formatearMoneda(p.precioCompra),
                p.estado ? 'Activo' : 'Inactivo',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFC62828)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EAF0)),
            border: null,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(2.4),
              2: const pw.FlexColumnWidth(2.4),
              3: const pw.FlexColumnWidth(1.6),
              4: const pw.FlexColumnWidth(1.1),
              5: const pw.FlexColumnWidth(1.3),
              6: const pw.FlexColumnWidth(1.3),
              7: const pw.FlexColumnWidth(1.1),
            },
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generarPdfTicket(
    List<ProductoModel> lista,
    Map<String, String> mapaCategorias,
    Set<String> campos,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text('SUPERCOLOR', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text('Listado de Inventario', style: const pw.TextStyle(fontSize: 9))),
              pw.SizedBox(height: 8),
              pw.Divider(),
              ...lista.map((p) {
                final lineas = <pw.Widget>[];
                if (campos.contains('codigo')) lineas.add(pw.Text('Código: ${p.codigo}', style: const pw.TextStyle(fontSize: 8)));
                lineas.add(pw.Text(p.nombre, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
                if (campos.contains('descripcion') && p.descripcion.isNotEmpty) {
                  lineas.add(pw.Text(p.descripcion, style: const pw.TextStyle(fontSize: 7.5)));
                }
                if (campos.contains('categoria')) {
                  lineas.add(pw.Text('Categoría: ${mapaCategorias[p.idCategoria] ?? '-'}', style: const pw.TextStyle(fontSize: 7.5)));
                }
                if (campos.contains('existencia')) {
                  lineas.add(pw.Text('Existencia: ${p.stock}', style: const pw.TextStyle(fontSize: 7.5)));
                }
                if (campos.contains('precioVenta')) {
                  lineas.add(pw.Text('P. Venta: ${formatearMoneda(p.precioVenta)}', style: const pw.TextStyle(fontSize: 7.5)));
                }
                if (campos.contains('precioCompra')) {
                  lineas.add(pw.Text('P. Compra: ${formatearMoneda(p.precioCompra)}', style: const pw.TextStyle(fontSize: 7.5)));
                }
                lineas.add(pw.SizedBox(height: 6));
                lineas.add(pw.Divider());
                return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: lineas);
              }),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  // Hoja de etiquetas de código de barras chicas (~2x1 pulgada, tamaño
  // estándar de etiqueta) para imprimir en la impresora térmica de 80mm que
  // ya se usa para tickets (mientras no haya una "tiquetera" de etiquetas
  // dedicada): a ese ancho de etiqueta solo entra 1 por fila, pero salen
  // varias apiladas en la misma tira de papel para cortarlas y pegarlas en
  // el producto. Se usa tanto para la impresión masiva ("Etiquetas" en
  // Inventario, una por producto distinto) como para la de un solo producto
  // con varias copias (menú "Código de barras" de cada fila, repitiendo el
  // mismo ProductoModel N veces en la lista).
  Future<Uint8List> generarPdfEtiquetasGrid(List<ProductoModel> productos) async {
    const columnas = 1;
    const anchoEtiquetaMm = 50.8; // 2 pulgadas
    const altoEtiquetaMm = 25.4; // 1 pulgada
    const margenMm = 3.0;
    final doc = pw.Document();

    final filas = <List<ProductoModel?>>[];
    for (var i = 0; i < productos.length; i += columnas) {
      filas.add(List.generate(columnas, (j) => i + j < productos.length ? productos[i + j] : null));
    }

    pw.Widget etiqueta(ProductoModel? p) {
      if (p == null) return pw.SizedBox(width: anchoEtiquetaMm * PdfPageFormat.mm, height: altoEtiquetaMm * PdfPageFormat.mm);
      final codigo = p.codigoBarras.isNotEmpty ? p.codigoBarras : p.codigo;
      return pw.Container(
        width: anchoEtiquetaMm * PdfPageFormat.mm,
        height: altoEtiquetaMm * PdfPageFormat.mm,
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(p.nombre, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 1, overflow: pw.TextOverflow.clip),
            pw.SizedBox(height: 3),
            pw.BarcodeWidget(barcode: bc.Barcode.code128(), data: codigo, width: (anchoEtiquetaMm - 10) * PdfPageFormat.mm, height: 30),
            pw.SizedBox(height: 2),
            pw.Text(codigo, style: const pw.TextStyle(fontSize: 7)),
            pw.Text(formatearMoneda(p.precioVenta), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
    }

    // pw.Page (no pw.MultiPage) con una altura calculada de antemano: con
    // MultiPage + altura infinita esta hoja salía completamente en blanco en
    // la vista previa (MultiPage necesita saber dónde cortar la página, y
    // con alto infinito nunca "cierra" el layout). El ticket normal
    // (generarPdfFactura) tiene el mismo problema documentado y por eso ya
    // usa alto calculado en vez de infinito.
    final altoPaginaMm = margenMm * 2 + filas.length * altoEtiquetaMm;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, altoPaginaMm * PdfPageFormat.mm, marginAll: margenMm * PdfPageFormat.mm),
        build: (context) {
          return pw.Column(
            children: filas
                .map((fila) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                      children: fila.map(etiqueta).toList(),
                    ))
                .toList(),
          );
        },
      ),
    );
    return doc.save();
  }
}