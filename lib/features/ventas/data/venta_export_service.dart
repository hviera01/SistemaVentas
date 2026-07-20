import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'venta_model.dart';
import 'numero_a_letras.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_pdf.dart';
import '../../negocio/data/negocio_model.dart';

class VentaExportService {
  static const _colorMarca = PdfColor.fromInt(0xFFC62828);
  static const _colorGrisTexto = PdfColor.fromInt(0xFF4B4F58);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF2F3F7);
  static const _colorBorde = PdfColor.fromInt(0xFFE0E2E8);

  /// PDF formal en tamaño carta, pensado para descargar/compartir/archivar
  /// (distinto al ticket térmico de 80mm que se usa para imprimir en punto
  /// de venta). [preciosConIsv] es la elección del usuario en pantalla (ver
  /// el selector en Detalle de Venta); si no se manda, cae al valor por
  /// defecto del negocio, igual que hacía antes.
  Future<Uint8List> generarPdfDetalleVenta(VentaModel venta, NegocioModel negocio, {bool? preciosConIsv}) async {
    final conIsv = preciosConIsv ?? negocio.facturaPreciosConIsv;
    final doc = pw.Document();
    final logo = decodificarLogoPdf(negocio.logoColorBase64);
    final formatoDia = DateFormat('dd/MM/yyyy');
    final esCotizacion = venta.tipoDocumento == 'Cotizacion';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _encabezadoFormal(venta, negocio, logo),
              pw.SizedBox(height: 18),
              if (venta.estaAnulada) ...[
                _bannerAnulado(venta),
                pw.SizedBox(height: 14),
              ],
              _infoFormal(venta, formatoDia),
              pw.SizedBox(height: 16),
              _tablaItemsFormal(venta, conIsv),
              pw.SizedBox(height: 14),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: _bloqueLetrasYPago(venta)),
                  pw.SizedBox(width: 16),
                  _bloqueTotales(venta),
                ],
              ),
              pw.Spacer(),
              _piePagina(venta, negocio, formatoDia, esCotizacion),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _encabezadoFormal(VentaModel venta, NegocioModel negocio, pw.MemoryImage? logo) {
    final esCotizacion = venta.tipoDocumento == 'Cotizacion';
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
              if (negocio.eslogan.isNotEmpty) pw.Text(negocio.eslogan, style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: _colorGrisTexto)),
              pw.SizedBox(height: 4),
              if (negocio.direccion.isNotEmpty) pw.Text(negocio.direccion, style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto)),
              pw.Text(
                [
                  if (negocio.rtn.isNotEmpty) 'RTN: ${negocio.rtn}',
                  if (negocio.telefono.isNotEmpty) 'Tel: ${negocio.telefono}',
                  if (negocio.correo.isNotEmpty) negocio.correo,
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
              pw.Text(esCotizacion ? 'COTIZACIÓN' : venta.tipoDocumento.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text('No. ${venta.numeroDocumento}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _bannerAnulado(VentaModel venta) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFCE4E4), borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: _colorMarca, width: 1)),
      child: pw.Text(
        'DOCUMENTO ANULADO${venta.motivoAnulacion.isNotEmpty ? ' — ${venta.motivoAnulacion}' : ''}',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _colorMarca),
      ),
    );
  }

  pw.Widget _celdaInfo(String etiqueta, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$etiqueta: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _colorGrisTexto)),
            pw.TextSpan(text: valor, style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
          ],
        ),
      ),
    );
  }

  pw.Widget _infoFormal(VentaModel venta, DateFormat formatoDia) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: _colorGrisClaro, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _celdaInfo('Cliente', venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente),
                _celdaInfo('Documento', venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente),
                if (venta.oc.isNotEmpty) _celdaInfo('No. O/C exenta', venta.oc),
                if (venta.regExonerado.isNotEmpty) _celdaInfo('Reg. exonerado', venta.regExonerado),
                if (venta.regSag.isNotEmpty) _celdaInfo('Reg. SAG', venta.regSag),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _celdaInfo('Fecha', venta.fechaRegistro != null ? formatoDia.format(venta.fechaRegistro!) : '-'),
                _celdaInfo('Atendido por', venta.usuarioRegistro),
                _celdaInfo('Condición', venta.condicion == 'Credito' ? 'Crédito' : 'Contado'),
                if (venta.condicion == 'Credito' && venta.fechaVencimiento != null) _celdaInfo('Vence', formatoDia.format(venta.fechaVencimiento!)),
                if (venta.condicion != 'Credito' && venta.metodoPago.isNotEmpty && venta.metodoPago != 'N/A') _celdaInfo('Método de pago', venta.metodoPago),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tablaItemsFormal(VentaModel venta, bool conIsv) {
    final estiloEncabezado = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final estiloCelda = const pw.TextStyle(fontSize: 9);
    double precioMostrado(dynamic item) => conIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;
    double importeMostrado(dynamic item) {
      if (!conIsv) return item.subtotal as double;
      final precio = precioMostrado(item);
      return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
    }

    return pw.TableHelper.fromTextArray(
      headers: ['Cant.', 'Descripción', conIsv ? 'P. Unitario (c/ISV)' : 'P. Unitario (s/ISV)', 'Desc. %', 'Importe'],
      data: venta.detalle.map((item) {
        return [
          _formatoCantidad(item.cantidad),
          item.nombreProducto,
          formatearMoneda(precioMostrado(item)),
          item.descuentoPorcentaje > 0 ? '${_formatoCantidad(item.descuentoPorcentaje)}%' : '-',
          formatearMoneda(importeMostrado(item)),
        ];
      }).toList(),
      headerStyle: estiloEncabezado,
      headerDecoration: const pw.BoxDecoration(color: _colorMarca),
      cellStyle: estiloCelda,
      cellHeight: 22,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(1.6),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.6),
      },
      border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _colorBorde, width: 0.6)),
      oddRowDecoration: const pw.BoxDecoration(color: _colorGrisClaro),
    );
  }

  pw.Widget _bloqueLetrasYPago(VentaModel venta) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Son: ${convertirNumeroALetras(venta.totalAPagar)}', style: const pw.TextStyle(fontSize: 8.5, color: _colorGrisTexto)),
        if (venta.condicion != 'Credito' && venta.tipoDocumento != 'Cotizacion') ...[
          pw.SizedBox(height: 8),
          if (venta.metodoPago == 'Efectivo') ...[
            pw.Text('Efectivo recibido: ${formatearMoneda(venta.montoPago)}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Cambio: ${formatearMoneda(venta.montoCambio)}', style: const pw.TextStyle(fontSize: 9)),
          ] else
            pw.Text('Pago: ${venta.metodoPago}', style: const pw.TextStyle(fontSize: 9)),
        ],
      ],
    );
  }

  pw.Widget _filaTotalFormal(String etiqueta, String valor, {bool destacado = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiqueta, style: pw.TextStyle(fontSize: destacado ? 11 : 9, fontWeight: destacado ? pw.FontWeight.bold : pw.FontWeight.normal, color: destacado ? _colorMarca : _colorGrisTexto)),
          pw.SizedBox(width: 20),
          pw.Text(valor, style: pw.TextStyle(fontSize: destacado ? 11 : 9, fontWeight: destacado ? pw.FontWeight.bold : pw.FontWeight.normal, color: destacado ? _colorMarca : PdfColors.black)),
        ],
      ),
    );
  }

  pw.Widget _bloqueTotales(VentaModel venta) {
    // Misma base sin ISV que ya usan Subtotal y Gravado 15%: precio de lista
    // (sin descuento) de cada línea menos lo que realmente quedó en
    // subtotal, así que cuadra con el resto del desglose.
    final totalSinDescuento = venta.detalle.fold<double>(0, (s, item) => s + item.precioVenta * item.cantidad);
    final descuentosYRebajas = redondearMoneda(totalSinDescuento - venta.subtotal);

    return pw.Container(
      width: 210,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: _colorGrisClaro, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _filaTotalFormal('Subtotal', formatearMoneda(venta.subtotal)),
          if (venta.descuentoGlobal > 0) _filaTotalFormal('Descuento global', '${_formatoCantidad(venta.descuentoGlobal)}%'),
          _filaTotalFormal('Descuentos y rebajas', formatearMoneda(descuentosYRebajas)),
          _filaTotalFormal('Importe exento', formatearMoneda(0)),
          _filaTotalFormal('Importe exonerado', formatearMoneda(0)),
          _filaTotalFormal('Gravado 15%', formatearMoneda(venta.subtotal)),
          _filaTotalFormal('Gravado 18%', formatearMoneda(0)),
          _filaTotalFormal('ISV (15%)', formatearMoneda(venta.impuesto)),
          pw.Divider(color: _colorBorde, height: 10),
          _filaTotalFormal('TOTAL', formatearMoneda(venta.totalAPagar), destacado: true),
        ],
      ),
    );
  }

  pw.Widget _piePagina(VentaModel venta, NegocioModel negocio, DateFormat formatoDia, bool esCotizacion) {
    final estiloFiscal = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _colorGrisTexto);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: _colorBorde),
        if (!esCotizacion) ...[
          // Datos fiscales de la factura: siempre se incluyen en documentos
          // fiscales (Factura/Boleta/Venta Sin Facturar), nunca en cotizaciones.
          pw.Text('CAI: ${negocio.cai.isEmpty ? 'N/D' : negocio.cai}', style: estiloFiscal),
          pw.Text('Rango autorizado: ${negocio.rangoPrefijo}${negocio.rangoDesde} al ${negocio.rangoPrefijo}${negocio.rangoHasta}', style: estiloFiscal),
          pw.Text('Fecha límite de emisión: ${negocio.fechaLimiteEmision != null ? formatoDia.format(negocio.fechaLimiteEmision!) : 'N/D'}', style: estiloFiscal),
          pw.SizedBox(height: 6),
          pw.Text('ORIGINAL: CLIENTE', style: estiloFiscal),
          pw.Text('COPIA: OBLIGADO TRIBUTARIO EMISOR', style: estiloFiscal),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('LA FACTURA ES BENEFICIO DE TODOS, ¡EXÍJALA!', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
          ),
          pw.SizedBox(height: 6),
        ],
        pw.Center(
          child: pw.Text(
            esCotizacion ? 'Documento no fiscal — solo de referencia' : '¡Gracias por su compra!',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _colorGrisTexto),
          ),
        ),
      ],
    );
  }

  // [forzarCopia] es para cuando se reimprime desde Detalle de Venta y el
  // usuario elige explícitamente si quiere una hoja que diga "ORIGINAL" o
  // "COPIA": si se manda, se imprime solo esa (una sola página), sin importar
  // negocio.facturaImprimirCopia. Si se deja en null, es el comportamiento de
  // siempre (al momento de la venta): ORIGINAL, y además COPIA si el negocio
  // tiene esa opción activada.
  //
  // [formatoImpresora] es el `format` que el propio paquete `printing` le
  // pasa a `onLayout` con el tamaño de página real que espera la impresora
  // seleccionada en Windows (según su configuración en el sistema). En web
  // sale centrado sin este dato porque el navegador reescala/ubica solo,
  // pero en el .exe de Windows, si armamos el PDF con un ancho fijo de 80mm
  // que no coincide exactamente con lo que el driver de la impresora tiene
  // configurado, el resultado queda con el contenido pegado a un lado en vez
  // de centrado. Si viene un formato que parece de rollo térmico (entre 40 y
  // 120mm de ancho) se usa ese ancho real en vez del fijo; si no, se sigue
  // usando 80mm como hasta ahora.
  Future<Uint8List> generarPdfFactura(VentaModel venta, NegocioModel negocio, {bool? forzarCopia, PdfPageFormat? formatoImpresora}) async {
    final doc = pw.Document();
    // maxDimension más alto que el default acá: el logo del ticket ahora se
    // imprime más grande (ver _construirPaginaTicket), y con la resolución
    // chica que alcanza para un logo de cabecera normal se vería borroso.
    final logo = decodificarLogoPdf(negocio.logoBnBase64, maxDimension: 400);
    final anchoMm = _anchoValidoDesdeFormato(formatoImpresora);

    if (forzarCopia != null) {
      doc.addPage(_construirPaginaTicket(venta, negocio, logo, esCopia: forzarCopia, anchoMm: anchoMm));
      return doc.save();
    }

    doc.addPage(_construirPaginaTicket(venta, negocio, logo, esCopia: false, anchoMm: anchoMm));
    if (negocio.facturaImprimirCopia) {
      doc.addPage(_construirPaginaTicket(venta, negocio, logo, esCopia: true, anchoMm: anchoMm));
    }
    return doc.save();
  }

  double? _anchoValidoDesdeFormato(PdfPageFormat? formato) {
    if (formato == null) return null;
    final anchoMm = formato.width / PdfPageFormat.mm;
    if (anchoMm < 40 || anchoMm > 120) return null;
    return anchoMm;
  }

  // pw.MultiPage en vez de pw.Page: antes esto usaba una altura "infinita"
  // (double.infinity) para que el ticket se ajuste a lo que ocupe el
  // contenido, pensado para el rollo continuo de la térmica. Funciona bien
  // en la vista previa (el paquete mide el contenido real antes de
  // mostrarlo), pero al imprimir directo sin pasar por esa vista previa,
  // algunos drivers de impresora en Windows no manejan bien una altura
  // infinita y terminaban cortando el ticket a la mitad (palabras y cifras
  // cortadas). Con MultiPage el contenido que no entra en una página sigue
  // en la próxima automáticamente, así que nunca se recorta información sin
  // importar por qué camino se mande a imprimir. El alto se calcula según lo
  // que realmente va a imprimirse (ver _estimarAlturaTicketMm) en vez de un
  // valor fijo enorme: con una altura fija muy por encima de lo real, la
  // vista previa quedaba con un espacio en blanco gigante al final.
  pw.Page _construirPaginaTicket(VentaModel venta, NegocioModel negocio, pw.MemoryImage? logo, {required bool esCopia, double? anchoMm}) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final formatoDia = DateFormat('dd/MM/yyyy');
    const fSmall = 7.5;
    const fNormal = 8.0;
    final alturaMm = _estimarAlturaTicketMm(venta, negocio, tieneLogo: logo != null);

    // El total y el desglose de ISV siempre reflejan el monto real de la
    // venta; esto solo cambia cómo se ve el precio unitario y el importe de
    // cada línea (con o sin ISV incluido), según la configuración del
    // negocio.
    double precioMostrado(dynamic item) => negocio.facturaPreciosConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;
    double importeMostrado(dynamic item) {
      if (!negocio.facturaPreciosConIsv) return item.subtotal as double;
      final precio = precioMostrado(item);
      return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
    }

    // Suma de descuentos por línea (precio de lista de cada producto, sin
    // descuento, menos lo que realmente quedó en subtotal) más el descuento
    // global: es la misma base sin ISV que ya usan SUBTOTAL y Gravado 15%
    // más abajo, así que cuadra con el resto de la lista.
    final totalSinDescuento = venta.detalle.fold<double>(0, (s, item) => s + item.precioVenta * item.cantidad);
    final descuentosYRebajas = redondearMoneda(totalSinDescuento - venta.subtotal);

    // En la web (imprime a través del diálogo del navegador) y en Android
    // (ESC/POS por red, ni siquiera pasa por acá) 5mm de margen imprime
    // perfecto. Pero en el .exe de Windows, imprimiendo nativo (con o sin
    // vista previa), sigue saliendo recortado a lo ancho aun con esos 5mm:
    // el controlador de la impresora en Windows debe estar interpretando un
    // área imprimible más angosta que los 80mm declarados, y a diferencia
    // del navegador, no reescala el contenido para que quepa — lo recorta
    // tal cual. La solución robusta sin poder probar en la impresora real es
    // darle más margen de sobra SOLO en Windows nativo, dejando la web y el
    // APK exactamente como están (que ya imprimen bien).
    final margenMm = (!kIsWeb && Platform.isWindows) ? 9.0 : 5.0;
    // Ancho real de la impresora (ver _anchoValidoDesdeFormato) si vino uno
    // que parece de rollo térmico; si no, el fijo de siempre.
    final anchoPaginaMm = anchoMm ?? 80.0;

    return pw.MultiPage(
      pageFormat: PdfPageFormat(anchoPaginaMm * PdfPageFormat.mm, alturaMm * PdfPageFormat.mm, marginAll: margenMm * PdfPageFormat.mm),
      build: (context) {
        return [
            // Ancho fijo (en vez de alto) para que se vea grande y nítido sin
            // desbordar el ticket de 80mm, sea cual sea la proporción del
            // logo que suba el negocio: antes salía muy chico porque solo se
            // limitaba el alto a 50pt.
            if (logo != null) pw.Center(child: pw.Image(logo, width: 140)),
            if (negocio.nombre.isNotEmpty)
              pw.Center(child: pw.Text(negocio.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            if (negocio.eslogan.isNotEmpty)
              pw.Center(child: pw.Text(negocio.eslogan, style: const pw.TextStyle(fontSize: 9))),
            if (negocio.direccion.isNotEmpty)
              pw.Center(child: pw.Text('Dirección: ${negocio.direccion}', style: const pw.TextStyle(fontSize: fSmall), textAlign: pw.TextAlign.center)),
            if (negocio.rtn.isNotEmpty) pw.Center(child: pw.Text('RTN: ${negocio.rtn}', style: const pw.TextStyle(fontSize: fSmall))),
            if (negocio.telefono.isNotEmpty) pw.Center(child: pw.Text('Tel: ${negocio.telefono}', style: const pw.TextStyle(fontSize: fSmall))),
            if (negocio.correo.isNotEmpty) pw.Center(child: pw.Text('Email: ${negocio.correo}', style: const pw.TextStyle(fontSize: fSmall))),
            if (negocio.cai.isNotEmpty) pw.Center(child: pw.Text('CAI: ${negocio.cai}', style: const pw.TextStyle(fontSize: fSmall))),
            pw.SizedBox(height: 6),
            _separador(),
            pw.Text('${venta.tipoDocumento.toUpperCase()} ${negocio.rangoPrefijo}${venta.numeroDocumento}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('Fecha: ${venta.fechaRegistro != null ? formatoFecha.format(venta.fechaRegistro!) : '-'}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('Atendido por: ${venta.usuarioRegistro}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('Condición: ${venta.condicion}', style: const pw.TextStyle(fontSize: fNormal)),
            if (venta.condicion == 'Credito' && venta.fechaVencimiento != null)
              pw.Text('Fecha de vencimiento: ${formatoDia.format(venta.fechaVencimiento!)}', style: const pw.TextStyle(fontSize: fNormal)),
            _separador(),
            pw.Text('Cliente: ${venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('ID/RTN Cliente: ${venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente}', style: const pw.TextStyle(fontSize: fNormal)),
            if (venta.oc.isNotEmpty) pw.Text('No. O/C exenta: ${venta.oc}', style: const pw.TextStyle(fontSize: fNormal)),
            if (venta.regExonerado.isNotEmpty) pw.Text('No. Reg de exonerado: ${venta.regExonerado}', style: const pw.TextStyle(fontSize: fNormal)),
            if (venta.regSag.isNotEmpty) pw.Text('No. De reg de la SAG: ${venta.regSag}', style: const pw.TextStyle(fontSize: fNormal)),
            _separador(),
            // Fila con spaceBetween (no texto con espacios a mano) para que
            // "IMPORTE" quede alineado de verdad arriba del monto de cada
            // línea, que también se dibuja pegado a la derecha.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('CANT  DESCRIPCIÓN', style: const pw.TextStyle(fontSize: fSmall)),
                pw.Text('IMPORTE', style: const pw.TextStyle(fontSize: fSmall)),
              ],
            ),
            _separador(),
            ...venta.detalle.map((item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Sin negrita: en la impresora térmica el texto en
                      // negrita se ve más "manchado" y termina siendo menos
                      // claro que el peso normal, sobre todo en letra chica.
                      pw.Text(item.nombreProducto, style: const pw.TextStyle(fontSize: fSmall)),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(precioMostrado(item))}${item.descuentoPorcentaje > 0 ? ' (-${_formatoCantidad(item.descuentoPorcentaje)}%)' : ''}',
                            style: const pw.TextStyle(fontSize: fSmall),
                          ),
                          pw.Text(formatearMoneda(importeMostrado(item)), style: const pw.TextStyle(fontSize: fSmall)),
                        ],
                      ),
                    ],
                  ),
                )),
            _separador(),
            _filaTotal('SUBTOTAL:', venta.subtotal),
            if (venta.descuentoGlobal > 0) pw.Text('Descuento global: ${_formatoCantidad(venta.descuentoGlobal)}%', style: const pw.TextStyle(fontSize: fSmall)),
            _filaTotal('Descuentos y rebajas:', descuentosYRebajas),
            _filaTotal('Importe Exento:', 0),
            _filaTotal('Importe Exonerado:', 0),
            _filaTotal('Gravado 15%:', venta.subtotal),
            _filaTotal('Gravado 18%:', 0),
            _filaTotal('ISV 15%:', venta.impuesto),
            _filaTotal('TOTAL A PAGAR:', venta.totalAPagar, negrita: true),
            pw.SizedBox(height: 6),
            _separador(),
            pw.Text('Son: ${convertirNumeroALetras(venta.totalAPagar)}', style: const pw.TextStyle(fontSize: fNormal)),
            if (venta.condicion != 'Credito') ...[
              if (venta.metodoPago == 'Efectivo') ...[
                pw.Text('Efectivo: ${formatearMoneda(venta.montoPago)}', style: const pw.TextStyle(fontSize: fNormal)),
                pw.Text('Cambio: ${formatearMoneda(venta.montoCambio)}', style: const pw.TextStyle(fontSize: fNormal)),
              ] else if (venta.metodoPago == 'Tarjeta')
                pw.Text('Pago con tarjeta: ${formatearMoneda(venta.totalAPagar)}', style: const pw.TextStyle(fontSize: fNormal))
              else if (venta.metodoPago == 'Transferencia')
                pw.Text('Transferencia', style: const pw.TextStyle(fontSize: fNormal)),
            ],
            _separador(),
            if (negocio.rangoPrefijo.isNotEmpty || negocio.rangoDesde.isNotEmpty)
              pw.Text('Rango Aut.: ${negocio.rangoPrefijo}${negocio.rangoDesde} al ${negocio.rangoPrefijo}${negocio.rangoHasta}', style: const pw.TextStyle(fontSize: fSmall)),
            if (negocio.fechaLimiteEmision != null)
              pw.Text('Fecha Límite: ${formatoDia.format(negocio.fechaLimiteEmision!)}', style: const pw.TextStyle(fontSize: fSmall)),
            pw.SizedBox(height: 4),
            pw.Text('ORIGINAL: CLIENTE', style: const pw.TextStyle(fontSize: fSmall)),
            pw.Text('COPIA: OBLIGADO TRIBUTARIO EMISOR', style: const pw.TextStyle(fontSize: fSmall)),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'LA FACTURA ES BENEFICIO DE TODOS, ¡EXÍJALA!',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: fSmall),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('¡GRACIAS POR SU COMPRA!', style: const pw.TextStyle(fontSize: fNormal)),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(esCopia ? 'COPIA' : 'ORIGINAL', style: const pw.TextStyle(fontSize: fNormal)),
            ),
          ];
      },
    );
  }

  // Estima cuánto va a ocupar el ticket según lo que realmente se va a
  // imprimir (mismas condiciones que el `build` de arriba), para que el
  // rollo térmico no quede con un espacio en blanco larguísimo al final ni,
  // al revés, tan corto que MultiPage tenga que partir el ticket en más de
  // una página (en un rollo continuo eso es peor que un poco de papel de
  // más: por larga que sea, la factura tiene que salir en una sola página).
  // Por eso el número base ya incluye un margen de sobra generoso: es mejor
  // que sobre un poco de papel en blanco al final a que se corte en dos.
  double _estimarAlturaTicketMm(VentaModel venta, NegocioModel negocio, {required bool tieneLogo}) {
    // Bloque fijo que siempre se imprime: tipo/fecha/atendido/condición,
    // cliente + id, encabezado de tabla, los 7 separadores entre secciones,
    // los 8 renglones de totales (incluye "Descuentos y rebajas"), "son:",
    // forma de pago, avisos legales de original/copia, agradecimiento y el
    // "ORIGINAL"/"COPIA" final — más margen de la página y colchón de
    // seguridad.
    double alto = 200.0;

    if (tieneLogo) alto += 20.0;
    if (negocio.nombre.isNotEmpty) alto += 6.0;
    if (negocio.eslogan.isNotEmpty) alto += 6.0;
    if (negocio.direccion.isNotEmpty) alto += 10.0;
    if (negocio.rtn.isNotEmpty) alto += 6.0;
    if (negocio.telefono.isNotEmpty) alto += 6.0;
    if (negocio.correo.isNotEmpty) alto += 6.0;
    if (negocio.cai.isNotEmpty) alto += 6.0;

    if (venta.condicion == 'Credito' && venta.fechaVencimiento != null) alto += 6.0;
    if (venta.oc.isNotEmpty) alto += 6.0;
    if (venta.regExonerado.isNotEmpty) alto += 6.0;
    if (venta.regSag.isNotEmpty) alto += 6.0;
    if (venta.descuentoGlobal > 0) alto += 6.0;
    // "Rango Aut.: 000-0001-01-00005401 al 000-0001-01-00006000" es largo y
    // casi siempre se parte en dos líneas dentro de los 80mm.
    if (negocio.rangoPrefijo.isNotEmpty || negocio.rangoDesde.isNotEmpty) alto += 10.0;
    if (negocio.fechaLimiteEmision != null) alto += 6.0;

    // Cada producto: nombre + renglón de cantidad/importe, con margen extra
    // por si el nombre es largo y se parte en dos líneas.
    alto += venta.detalle.length * 16.0;

    return alto;
  }

  pw.Widget _separador() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(thickness: 0.7),
    );
  }

  pw.Widget _filaTotal(String etiqueta, double valor, {bool negrita = false}) {
    final estilo = pw.TextStyle(fontSize: 8, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiqueta, style: estilo),
          pw.Text(formatearMoneda(valor), style: estilo),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  Uint8List generarExcel(List<VentaModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['Ventas'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Tipo Documento'),
      xls.TextCellValue('No. Documento'),
      xls.TextCellValue('Cliente'),
      xls.TextCellValue('Total'),
      xls.TextCellValue('Método de Pago'),
      xls.TextCellValue('Condición'),
      xls.TextCellValue('Usuario'),
    ]);

    for (final v in lista) {
      hoja.appendRow([
        xls.TextCellValue(v.fechaRegistro != null ? formato.format(v.fechaRegistro!) : '-'),
        xls.TextCellValue(v.tipoDocumento),
        xls.TextCellValue(v.numeroDocumento),
        xls.TextCellValue(v.nombreCliente),
        xls.TextCellValue(formatearMoneda(v.totalAPagar)),
        xls.TextCellValue(v.metodoPago),
        xls.TextCellValue(v.condicion),
        xls.TextCellValue(v.usuarioRegistro),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }
}
