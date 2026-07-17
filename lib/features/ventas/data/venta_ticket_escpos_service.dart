import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'venta_model.dart';
import 'numero_a_letras.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../negocio/data/negocio_model.dart';

/// Genera el mismo contenido del ticket térmico de `generarPdfFactura` (ver
/// VentaExportService) pero como comandos ESC/POS crudos, para mandarlos
/// directo a una impresora de red (ImpresoraRedService) en vez de un PDF —
/// es la vía de impresión que funciona desde el celular.
class VentaTicketEscPosService {
  Future<List<int>> generarTicket(VentaModel venta, NegocioModel negocio) async {
    final perfil = await CapabilityProfile.load();
    final generador = Generator(PaperSize.mm80, perfil);
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final formatoDia = DateFormat('dd/MM/yyyy');

    double precioMostrado(dynamic item) => negocio.facturaPreciosConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;
    double importeMostrado(dynamic item) {
      if (!negocio.facturaPreciosConIsv) return item.subtotal as double;
      final precio = precioMostrado(item);
      return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
    }

    List<int> bytes = [];
    bytes += generador.reset();

    if (negocio.nombre.isNotEmpty) {
      bytes += generador.text(negocio.nombre.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    if (negocio.eslogan.isNotEmpty) bytes += generador.text(negocio.eslogan, styles: const PosStyles(align: PosAlign.center));
    if (negocio.direccion.isNotEmpty) bytes += generador.text('Dirección: ${negocio.direccion}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.rtn.isNotEmpty) bytes += generador.text('RTN: ${negocio.rtn}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.telefono.isNotEmpty) bytes += generador.text('Tel: ${negocio.telefono}', styles: const PosStyles(align: PosAlign.center));
    if (negocio.cai.isNotEmpty) bytes += generador.text('CAI: ${negocio.cai}', styles: const PosStyles(align: PosAlign.center));
    bytes += generador.hr();

    bytes += generador.text('${venta.tipoDocumento.toUpperCase()} ${negocio.rangoPrefijo}${venta.numeroDocumento}', styles: const PosStyles(bold: true));
    bytes += generador.text('Fecha: ${venta.fechaRegistro != null ? formatoFecha.format(venta.fechaRegistro!) : '-'}');
    bytes += generador.text('Atendido por: ${venta.usuarioRegistro}');
    bytes += generador.text('Condición: ${venta.condicion}');
    if (venta.condicion == 'Credito' && venta.fechaVencimiento != null) {
      bytes += generador.text('Fecha de vencimiento: ${formatoDia.format(venta.fechaVencimiento!)}');
    }
    bytes += generador.hr();

    bytes += generador.text('Cliente: ${venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente}');
    bytes += generador.text('ID/RTN Cliente: ${venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente}');
    if (venta.oc.isNotEmpty) bytes += generador.text('No. O/C exenta: ${venta.oc}');
    if (venta.regExonerado.isNotEmpty) bytes += generador.text('No. Reg de exonerado: ${venta.regExonerado}');
    if (venta.regSag.isNotEmpty) bytes += generador.text('No. De reg de la SAG: ${venta.regSag}');
    bytes += generador.hr();

    for (final item in venta.detalle) {
      bytes += generador.text(item.nombreProducto);
      bytes += generador.row([
        PosColumn(text: '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(precioMostrado(item))}${item.descuentoPorcentaje > 0 ? ' (-${_formatoCantidad(item.descuentoPorcentaje)}%)' : ''}', width: 8),
        PosColumn(text: formatearMoneda(importeMostrado(item)), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generador.hr();

    bytes += _filaTotal(generador, 'SUBTOTAL:', venta.subtotal);
    if (venta.descuentoGlobal > 0) bytes += generador.text('Descuento global: ${_formatoCantidad(venta.descuentoGlobal)}%');
    bytes += _filaTotal(generador, 'Gravado 15%:', venta.subtotal);
    bytes += _filaTotal(generador, 'ISV 15%:', venta.impuesto);
    bytes += _filaTotal(generador, 'TOTAL A PAGAR:', venta.totalAPagar, negrita: true);
    bytes += generador.hr();

    bytes += generador.text('Son: ${convertirNumeroALetras(venta.totalAPagar)}');
    if (venta.condicion != 'Credito') {
      if (venta.metodoPago == 'Efectivo') {
        bytes += generador.text('Efectivo: ${formatearMoneda(venta.montoPago)}');
        bytes += generador.text('Cambio: ${formatearMoneda(venta.montoCambio)}');
      } else if (venta.metodoPago == 'Tarjeta') {
        bytes += generador.text('Pago con tarjeta: ${formatearMoneda(venta.totalAPagar)}');
      } else if (venta.metodoPago == 'Transferencia') {
        bytes += generador.text('Transferencia');
      }
    }
    bytes += generador.hr();

    if (negocio.rangoPrefijo.isNotEmpty || negocio.rangoDesde.isNotEmpty) {
      bytes += generador.text('Rango Aut.: ${negocio.rangoPrefijo}${negocio.rangoDesde} al ${negocio.rangoPrefijo}${negocio.rangoHasta}');
    }
    if (negocio.fechaLimiteEmision != null) {
      bytes += generador.text('Fecha Límite: ${formatoDia.format(negocio.fechaLimiteEmision!)}');
    }
    bytes += generador.text('ORIGINAL: CLIENTE');
    bytes += generador.text('COPIA: OBLIGADO TRIBUTARIO EMISOR');
    bytes += generador.text('LA FACTURA ES BENEFICIO DE TODOS, ¡EXÍJALA!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generador.text('¡GRACIAS POR SU COMPRA!', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generador.cut();

    return bytes;
  }

  List<int> _filaTotal(Generator generador, String etiqueta, double valor, {bool negrita = false}) {
    return generador.row([
      PosColumn(text: etiqueta, width: 8, styles: PosStyles(bold: negrita)),
      PosColumn(text: formatearMoneda(valor), width: 4, styles: PosStyles(align: PosAlign.right, bold: negrita)),
    ]);
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
