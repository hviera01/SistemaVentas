import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'venta_model.dart';
import 'numero_a_letras.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_escpos.dart';
import '../../../core/utils/texto_utils.dart';
import '../../negocio/data/negocio_model.dart';

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
      // confunda dónde termina la descripción-.
      bytes += generador.row([
        _columna(item.nombreProducto, width: 8),
        _columna('', width: 4),
      ]);
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
