import 'dart:ui' as ui;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'venta_model.dart';
import 'numero_a_letras.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_escpos.dart';
import '../../../core/utils/texto_utils.dart';
import '../../negocio/data/negocio_model.dart';

/// Una franja de la guía "grande" (ver
/// VentaTicketEscPosService._renderizarGuiaRotada): etiqueta chica arriba,
/// valor grande abajo. [medir] arma los TextPainter y calcula [ancho]
/// -llamarlo antes de [pintar]-; el valor se envuelve solo si hace falta
/// (TextPainter con maxWidth), no a mano como en el ticket normal.
class _SeccionGuiaGrande {
  _SeccionGuiaGrande(this.etiqueta, this.valor, {required this.fontEtiqueta, required this.fontValor, required this.maxAnchoValor});

  final String etiqueta;
  final String valor;
  final double fontEtiqueta;
  final double fontValor;
  final double maxAnchoValor;

  late TextPainter _painterEtiqueta;
  late TextPainter _painterValor;
  double ancho = 0;

  void medir() {
    _painterEtiqueta = TextPainter(
      text: TextSpan(text: etiqueta, style: TextStyle(color: const Color(0xFF000000), fontSize: fontEtiqueta, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    _painterValor = TextPainter(
      text: TextSpan(text: valor, style: TextStyle(color: const Color(0xFF000000), fontSize: fontValor, fontWeight: FontWeight.bold)),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxAnchoValor);
    ancho = [_painterEtiqueta.width, _painterValor.width].reduce((a, b) => a > b ? a : b);
  }

  void pintar(Canvas canvas, double x, double altoLienzo) {
    // La etiqueta va arriba y el valor centrado en el espacio que sobra
    // -así una etiqueta+valor cortos no quedan pegados al borde de arriba
    // ni desalineados entre secciones de distinto tamaño de fuente-.
    const espacioEtiquetaValor = 14.0;
    final altoBloque = _painterEtiqueta.height + espacioEtiquetaValor + _painterValor.height;
    final yInicial = ((altoLienzo - altoBloque) / 2).clamp(0.0, altoLienzo);
    _painterEtiqueta.paint(canvas, Offset(x, yInicial));
    _painterValor.paint(canvas, Offset(x, yInicial + _painterEtiqueta.height + espacioEtiquetaValor));
  }
}

/// Genera el mismo contenido del ticket térmico de `generarPdfFactura` (ver
/// VentaExportService) pero como comandos ESC/POS crudos: la vía que ya
/// usaba la impresión por red/celular, y que en Windows ahora también se usa
/// en vez de un PDF -algunos drivers de impresora térmica tienen un tamaño
/// de página máximo fijo y recortan o reescalan cualquier factura más larga
/// que eso, sin importar qué le pidamos al PDF (ver el comentario grande en
/// venta_export_service.dart)-.
class VentaTicketEscPosService {
  /// [forzarCopia] mismo significado que en
  /// `VentaExportService.generarPdfFactura`: null (venta recién confirmada)
  /// imprime ORIGINAL y, si el negocio tiene activado `facturaImprimirCopia`,
  /// agrega una COPIA a continuación (mismo trabajo de impresión, separado
  /// por su propio corte de papel). true/false fuerza una sola copia sin
  /// importar esa configuración -para reimprimir una en particular desde el
  /// detalle de venta-.
  Future<List<int>> generarTicket(VentaModel venta, NegocioModel negocio, {bool? forzarCopia}) async {
    final perfil = await CapabilityProfile.load();
    final generador = Generator(PaperSize.mm80, perfil);
    // Un poco más grande/ancho que el default (300) para que se note más
    // pegado al nombre del negocio, sin pasarse de los ~576 puntos de ancho
    // que tiene una impresora de 80mm.
    final logo = decodificarLogoEscPos(negocio.logoBnBase64, maxDimension: 420);

    List<int> bytes = [];
    bytes += generador.reset();
    bytes += _construirTicket(generador, venta, negocio, logo, esCopia: forzarCopia ?? false);
    if (forzarCopia == null && negocio.facturaImprimirCopia) {
      bytes += _construirTicket(generador, venta, negocio, logo, esCopia: true);
    }
    return bytes;
  }

  /// Guía de envío -pedido explícito del dueño: "imprimir en la térmica así
  /// como a lo ancho para poder hacer la letra un poco grande y clara y
  /// poder pegar eso a una caja"-. [grande]==false: ticket normal, angosto,
  /// con PosTextSize.size2 en nombre/teléfono (texto ESC/POS de verdad, más
  /// rápido/liviano). [grande]==true: "volteado" -pedido explícito del
  /// dueño, aclarado después de que la primera versión (solo letra doble
  /// ancho/alto, sin rotar) no era lo que pedía-: se arma como una IMAGEN
  /// (no hay comando ESC/POS que rote texto de verdad) con cada dato en una
  /// franja bien grande, y esa imagen se rota 90° antes de mandarla a
  /// imprimir. El resultado es una tira más larga que hay que girar de lado
  /// para leer, pero con letra mucho más grande que cualquier texto ESC/POS
  /// normal -el ancho del papel (fijo, ~8cm) pasa a ser la ALTURA de la
  /// letra en vez de cuántos caracteres entran por línea-.
  Future<List<int>> generarGuiaEnvio(VentaModel venta, NegocioModel negocio, {bool grande = false}) async {
    final perfil = await CapabilityProfile.load();
    final generador = Generator(PaperSize.mm80, perfil);

    List<int> bytes = [];
    bytes += generador.reset();

    if (grande) {
      final imagen = await _renderizarGuiaRotada(venta, negocio);
      bytes += generador.image(imagen);
      bytes += generador.emptyLines(2);
      bytes += generador.cut();
      return bytes;
    }

    final formatoFecha = DateFormat('dd/MM/yyyy hh:mm a');
    if (negocio.nombre.isNotEmpty) {
      bytes += _texto(generador, negocio.nombre.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += _texto(generador, 'GUIA DE ENVIO', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generador.hr();
    bytes += generador.emptyLines(1);

    bytes += _texto(generador, 'PARA:', styles: const PosStyles(bold: true));
    // _anchoDoble (24, la mitad de las 48 columnas normales de una línea
    // completa en papel de 80mm): a doble ancho cada carácter ocupa el
    // doble de espacio, así que entra la mitad por línea.
    for (final linea in _envolverDescripcion(venta.envioNombre, _anchoDoble)) {
      bytes += _texto(generador, linea, styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    bytes += generador.emptyLines(1);

    if (venta.envioDireccion.isNotEmpty) {
      bytes += _texto(generador, 'DIRECCION:', styles: const PosStyles(bold: true));
      for (final linea in _envolverDescripcion(venta.envioDireccion, _anchoCompleto)) {
        bytes += _texto(generador, linea, styles: const PosStyles(bold: true, height: PosTextSize.size2));
      }
      bytes += generador.emptyLines(1);
    }

    if (venta.envioTelefono.isNotEmpty) {
      bytes += _texto(generador, 'TELEFONO:', styles: const PosStyles(bold: true));
      bytes += _texto(generador, venta.envioTelefono, styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generador.emptyLines(1);
    }

    bytes += generador.hr();
    bytes += _texto(generador, '${venta.tipoDocumento} ${negocio.rangoPrefijo}${venta.numeroDocumento}');
    bytes += _texto(generador, 'Fecha: ${venta.fechaRegistro != null ? formatoFecha.format(venta.fechaRegistro!) : '-'}');
    if (venta.nombreCliente.isNotEmpty && venta.nombreCliente != venta.envioNombre) {
      bytes += _texto(generador, 'Comprador: ${venta.nombreCliente}');
    }
    bytes += generador.emptyLines(2);
    bytes += generador.cut();

    return bytes;
  }

  // Alto del lienzo ANTES de rotar = ancho real de impresión de una
  // térmica de 80mm en puntos (mismo dato citado en todo este archivo).
  // Después de rotar 90°, este alto se convierte en el ANCHO de la imagen
  // ya impresa -tiene que quedar exacto o menor a esto, es un límite físico
  // del cabezal-.
  static const _altoLienzoGuiaGrande = 576;
  static const _margenGuiaGrande = 24.0;
  static const _separacionSeccionGuiaGrande = 48.0;

  /// Arma la guía "grande" como imagen y la rota 90° -ver el doc grande de
  /// [generarGuiaEnvio]-. Cada dato (nombre, dirección, teléfono) es una
  /// franja: etiqueta chica arriba, valor en letra grande abajo, una franja
  /// al lado de la otra a lo ANCHO del lienzo (que es lo que se vuelve el
  /// LARGO de la tira ya impresa, sin límite real). [maxAnchoValor] de cada
  /// sección se deja angosto A PROPÓSITO -pedido explícito del dueño,
  /// después de ver la primera versión: "no lo quiero tan grande, que
  /// agarre varias líneas siempre, no tan largo el papel"-: fuerza que el
  /// texto envuelva en 2-4 líneas en vez de salir como una sola línea
  /// gigante, dejando la tira bastante más corta con la misma letra clara.
  /// No se prueba en una impresora física desde acá -si sale al revés (hay
  /// que girar la tira para el otro lado) o la letra sale cortada por los
  /// bordes, avisar: es un ajuste de una línea (ángulo en copyRotate, o los
  /// tamaños de acá abajo).
  Future<img.Image> _renderizarGuiaRotada(VentaModel venta, NegocioModel negocio) async {
    final secciones = <_SeccionGuiaGrande>[
      _SeccionGuiaGrande('PARA', venta.envioNombre, fontEtiqueta: 26, fontValor: 65, maxAnchoValor: 550),
      if (venta.envioDireccion.isNotEmpty) _SeccionGuiaGrande('DIRECCION', venta.envioDireccion, fontEtiqueta: 26, fontValor: 50, maxAnchoValor: 550),
      if (venta.envioTelefono.isNotEmpty) _SeccionGuiaGrande('TELEFONO', venta.envioTelefono, fontEtiqueta: 26, fontValor: 65, maxAnchoValor: 400),
      _SeccionGuiaGrande(
        negocio.nombre.isEmpty ? '' : negocio.nombre.toUpperCase(),
        '${venta.tipoDocumento} ${negocio.rangoPrefijo}${venta.numeroDocumento}',
        fontEtiqueta: 22,
        fontValor: 28,
        maxAnchoValor: 500,
      ),
    ];

    for (final s in secciones) {
      s.medir();
    }
    final anchoTotal = secciones.fold<double>(_margenGuiaGrande, (s, seccion) => s + seccion.ancho + _separacionSeccionGuiaGrande);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, anchoTotal, _altoLienzoGuiaGrande.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, anchoTotal, _altoLienzoGuiaGrande.toDouble()), Paint()..color = const Color(0xFFFFFFFF));

    var x = _margenGuiaGrande;
    for (final seccion in secciones) {
      seccion.pintar(canvas, x, _altoLienzoGuiaGrande.toDouble());
      x += seccion.ancho + _separacionSeccionGuiaGrande;
    }

    final picture = recorder.endRecording();
    final imagenUi = await picture.toImage(anchoTotal.ceil(), _altoLienzoGuiaGrande);
    final bytesRgba = await imagenUi.toByteData(format: ui.ImageByteFormat.rawRgba);
    final lienzo = img.Image.fromBytes(
      width: imagenUi.width,
      height: imagenUi.height,
      bytes: bytesRgba!.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.copyRotate(lienzo, angle: 90).convert(numChannels: 3);
  }

  // Muchas impresoras térmicas no tienen bien configurada la página de
  // códigos para tildes/eñes y las imprimen mal (un carácter random, o
  // cortan la línea ahí) — por eso todo el texto que se manda a imprimir
  // pasa por quitarTildes antes. Estos dos wrappers evitan tener que
  // acordarse de hacerlo a mano en cada línea.
  List<int> _texto(Generator g, String texto, {PosStyles styles = const PosStyles()}) {
    return g.text(quitarTildes(texto), styles: styles);
  }

  PosColumn _columna(String texto, {required int width, PosStyles styles = const PosStyles()}) {
    return PosColumn(text: quitarTildes(texto), width: width, styles: styles);
  }

  // Ancho real (en caracteres) de la columna de 8/12 donde va la
  // descripción del producto, para papel de 80mm y fuente por defecto: ver
  // Generator.row en esc_pos_utils_plus (paperWidth=576, 48 caracteres por
  // línea completa, spaceBetweenRows=5 -> floor((576*8/12 - 1 - 5) / 12) = 31.
  // Si algún día cambia el ancho de columna acá (8) o el tamaño de papel,
  // este número hay que recalcularlo con la misma fórmula.
  static const _anchoDescripcion = 31;

  // Usados por generarGuiaEnvio: 48 caracteres por línea completa a ancho
  // normal (mismo dato citado arriba, ver Generator en esc_pos_utils_plus
  // para papel de 80mm); a doble ancho (PosTextSize.size2 en width) cada
  // carácter ocupa el doble de espacio, así que entran la mitad por línea.
  static const _anchoCompleto = 48;
  static const _anchoDoble = 24;

  // La librería (Generator.row con multiLine) parte el texto que no entra
  // en una línea cortando a la cantidad de caracteres exacta, sin importar
  // si eso cae a mitad de una palabra ni dejando ningún indicio del corte
  // -por eso una descripción larga podía salir partida en cualquier punto,
  // a veces dejando una sola letra suelta en el renglón de abajo-. Acá se
  // arma el wrap a mano, por palabra completa, ANTES de pasarle el texto a
  // la librería (una línea por row, ya corta de entrada): si una palabra
  // sola no entra en el ancho disponible, se parte con un guion al final,
  // pero nunca dejando menos de 2 letras a cualquier lado del corte (por
  // ejemplo "electrodo-" / "mestico" en vez de "electrodomestic-" / "o").
  List<String> _envolverDescripcion(String texto, int maxAncho) {
    final palabras = texto.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return [''];

    final lineas = <String>[];
    var actual = '';

    void cerrarLinea() {
      if (actual.isNotEmpty) {
        lineas.add(actual);
        actual = '';
      }
    }

    for (var palabra in palabras) {
      if (actual.isEmpty && palabra.length <= maxAncho) {
        actual = palabra;
        continue;
      }
      if (palabra.length <= maxAncho) {
        if (actual.length + 1 + palabra.length <= maxAncho) {
          actual = '$actual $palabra';
        } else {
          cerrarLinea();
          actual = palabra;
        }
        continue;
      }

      // La palabra sola no entra en una línea completa: se reparte en
      // fragmentos con guion, siempre empezando en una línea nueva.
      cerrarLinea();
      var restante = palabra;
      while (restante.length > maxAncho) {
        var corte = maxAncho - 1; // -1 para dejar espacio al guion
        // Nunca un fragmento de 1 sola letra a ningún lado del corte.
        if (restante.length - corte < 2) corte -= (2 - (restante.length - corte));
        corte = corte.clamp(2, maxAncho - 1);
        lineas.add('${restante.substring(0, corte)}-');
        restante = restante.substring(corte);
      }
      actual = restante;
    }
    cerrarLinea();
    return lineas;
  }

  List<int> _construirTicket(Generator generador, VentaModel venta, NegocioModel negocio, img.Image? logo, {required bool esCopia}) {
    final formatoFecha = DateFormat('dd/MM/yyyy hh:mm a');
    final formatoDia = DateFormat('dd/MM/yyyy');

    // Mismo cálculo que en el PDF (ver VentaExportService): el total y el
    // desglose de ISV siempre reflejan el monto real de la venta, esto solo
    // cambia cómo se ve el precio unitario/importe de cada línea.
    double precioMostrado(dynamic item) => negocio.facturaPreciosConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;
    double importeMostrado(dynamic item) {
      if (!negocio.facturaPreciosConIsv) return item.subtotal as double;
      final precio = precioMostrado(item);
      return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
    }
    final totalSinDescuento = venta.detalle.fold<double>(0, (s, item) => s + item.precioVenta * item.cantidad);
    final descuentosYRebajas = redondearMoneda(totalSinDescuento - venta.subtotal);

    List<int> bytes = [];

    if (logo != null) bytes += generador.image(logo);
    if (negocio.nombre.isNotEmpty) {
      bytes += _texto(generador, negocio.nombre.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    if (negocio.eslogan.isNotEmpty) bytes += _texto(generador, negocio.eslogan, styles: const PosStyles(align: PosAlign.center));
    if (negocio.direccion.isNotEmpty) bytes += _texto(generador, 'Direccion: ${negocio.direccion}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.rtn.isNotEmpty) bytes += _texto(generador, 'RTN: ${negocio.rtn}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.telefono.isNotEmpty) bytes += _texto(generador, 'Tel: ${negocio.telefono}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.correo.isNotEmpty) bytes += _texto(generador, 'Email: ${negocio.correo}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.cai.isNotEmpty) bytes += _texto(generador, 'CAI: ${negocio.cai}', styles: const PosStyles(align: PosAlign.center));
    bytes += generador.emptyLines(1);
    bytes += generador.hr();

    bytes += _texto(generador, '${venta.tipoDocumento.toUpperCase()} ${negocio.rangoPrefijo}${venta.numeroDocumento}', styles: const PosStyles(bold: true));
    bytes += _texto(generador, 'Fecha: ${venta.fechaRegistro != null ? formatoFecha.format(venta.fechaRegistro!) : '-'}');
    bytes += _texto(generador, 'Atendido por: ${venta.usuarioRegistro}');
    bytes += _texto(generador, 'Condicion: ${venta.condicion}');
    if (venta.condicion == 'Credito' && venta.fechaVencimiento != null) {
      bytes += _texto(generador, 'Fecha de vencimiento: ${formatoDia.format(venta.fechaVencimiento!)}');
    }
    bytes += generador.hr();

    bytes += _texto(generador, 'Cliente: ${venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente}');
    bytes += _texto(generador, 'ID/RTN Cliente: ${venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente}');
    if (venta.oc.isNotEmpty) bytes += _texto(generador, 'No. O/C exenta: ${venta.oc}');
    if (venta.regExonerado.isNotEmpty) bytes += _texto(generador, 'No. Reg de exonerado: ${venta.regExonerado}');
    if (venta.regSag.isNotEmpty) bytes += _texto(generador, 'No. De reg de la SAG: ${venta.regSag}');
    if (venta.observaciones.isNotEmpty) {
      bytes += generador.hr();
      bytes += _texto(generador, 'Observaciones: ${venta.observaciones}');
    }
    bytes += generador.hr();

    bytes += generador.row([
      _columna('CANT DESCRIPCION', width: 8, styles: const PosStyles(bold: true)),
      _columna('IMPORTE', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generador.hr();

    for (final item in venta.detalle) {
      // El nombre va en una columna de ancho 8 (con la columna 4 de la
      // derecha vacía, la misma proporción que la fila de cantidad/importe
      // de abajo) en vez de a todo el ancho: así, si el nombre es largo y se
      // parte en más de una línea, esa segunda línea nunca llega hasta donde
      // va el importe -queda esa columna siempre limpia, sin que el cliente
      // confunda dónde termina la descripción-. El wrap en sí lo hace
      // _envolverDescripcion (por palabra completa, con guion si hace falta
      // partir una palabra), una línea por row: así la librería nunca corta
      // por su cuenta a mitad de palabra.
      for (final linea in _envolverDescripcion(item.nombreProducto, _anchoDescripcion)) {
        bytes += generador.row([
          _columna(linea, width: 8),
          _columna('', width: 4),
        ]);
      }
      bytes += generador.row([
        _columna('${_formatoCantidad(item.cantidad)} x ${formatearMoneda(precioMostrado(item))}${item.descuentoPorcentaje > 0 ? ' (-${_formatoCantidad(item.descuentoPorcentaje)}%)' : ''}', width: 8),
        _columna(formatearMoneda(importeMostrado(item)), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
      // Más espacio antes del siguiente producto: antes quedaban todos los
      // renglones pegados uno con otro.
      bytes += generador.emptyLines(1);
    }
    bytes += generador.hr();

    bytes += _filaTotal(generador, 'SUBTOTAL:', venta.subtotal);
    if (venta.descuentoGlobal > 0) bytes += _texto(generador, 'Descuento global: ${_formatoCantidad(venta.descuentoGlobal)}%');
    bytes += _filaTotal(generador, 'Descuentos y rebajas:', descuentosYRebajas);
    bytes += _filaTotal(generador, 'Importe Exento:', 0);
    bytes += _filaTotal(generador, 'Importe Exonerado:', 0);
    bytes += _filaTotal(generador, 'Gravado 15%:', venta.subtotal);
    bytes += _filaTotal(generador, 'Gravado 18%:', 0);
    bytes += _filaTotal(generador, 'ISV 15%:', venta.impuesto);
    bytes += _filaTotal(generador, 'TOTAL A PAGAR:', venta.totalAPagar, negrita: true);
    bytes += generador.emptyLines(1);
    bytes += generador.hr();

    bytes += _texto(generador, 'Son: ${convertirNumeroALetras(venta.totalAPagar)}');
    if (venta.condicion != 'Credito') {
      if (venta.metodoPago == 'Efectivo') {
        bytes += _texto(generador, 'Efectivo: ${formatearMoneda(venta.montoPago)}');
        bytes += _texto(generador, 'Cambio: ${formatearMoneda(venta.montoCambio)}');
      } else if (venta.metodoPago == 'Tarjeta') {
        bytes += _texto(generador, 'Pago con tarjeta: ${formatearMoneda(venta.totalAPagar)}');
      } else if (venta.metodoPago == 'Transferencia') {
        bytes += _texto(generador, 'Transferencia');
      } else if (venta.metodoPago == 'Mixto') {
        for (final pago in venta.pagosMixtos) {
          bytes += _texto(generador, '${pago.metodoPago}: ${formatearMoneda(pago.monto)}');
        }
      }
    }
    bytes += generador.hr();

    if (negocio.rangoPrefijo.isNotEmpty || negocio.rangoDesde.isNotEmpty) {
      bytes += _texto(generador, 'Rango Aut.: ${negocio.rangoPrefijo}${negocio.rangoDesde} al ${negocio.rangoPrefijo}${negocio.rangoHasta}');
    }
    if (negocio.fechaLimiteEmision != null) {
      bytes += _texto(generador, 'Fecha Limite: ${formatoDia.format(negocio.fechaLimiteEmision!)}');
    }
    bytes += generador.emptyLines(1);
    bytes += _texto(generador, 'ORIGINAL: CLIENTE');
    bytes += _texto(generador, 'COPIA: OBLIGADO TRIBUTARIO EMISOR');
    bytes += generador.emptyLines(1);
    bytes += _texto(generador, 'LA FACTURA ES BENEFICIO DE TODOS, EXIJALA!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generador.emptyLines(1);
    bytes += _texto(generador, 'GRACIAS POR SU COMPRA!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generador.emptyLines(1);
    bytes += _texto(generador, esCopia ? 'COPIA' : 'ORIGINAL', styles: const PosStyles(align: PosAlign.right, bold: true));
    bytes += generador.cut();

    return bytes;
  }

  List<int> _filaTotal(Generator generador, String etiqueta, double valor, {bool negrita = false}) {
    return generador.row([
      _columna(etiqueta, width: 8, styles: PosStyles(bold: negrita)),
      _columna(formatearMoneda(valor), width: 4, styles: PosStyles(align: PosAlign.right, bold: negrita)),
    ]);
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
