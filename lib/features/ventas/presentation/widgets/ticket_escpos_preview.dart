import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../../data/venta_model.dart';
import '../../data/numero_a_letras.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/logo_escpos.dart';
import '../../../../core/utils/texto_utils.dart';

/// Reproduce en pantalla, con widgets normales de Flutter (no un PDF), el
/// mismo contenido y el mismo orden que imprime de verdad
/// VentaTicketEscPosService en la impresora térmica -la vía que se usa en
/// Windows para el ticket de venta, ver PdfPreviewDialog-. No es
/// pixel-perfecto (una impresora térmica real usa su propia tipografía de
/// matriz de puntos), pero muestra las mismas secciones, los mismos datos y
/// en el mismo orden, a diferencia de la vista previa en PDF -que en ese
/// camino ya no es lo que de verdad se manda a imprimir-.
class TicketEscPosPreview extends StatelessWidget {
  final VentaModel venta;
  final NegocioModel negocio;
  final bool esCopia;

  const TicketEscPosPreview({super.key, required this.venta, required this.negocio, required this.esCopia});

  @override
  Widget build(BuildContext context) {
    const estiloBase = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black, height: 1.35);
    final formatoFecha = DateFormat('dd/MM/yyyy hh:mm a');
    final formatoDia = DateFormat('dd/MM/yyyy');

    double precioMostrado(item) => negocio.facturaPreciosConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;
    double importeMostrado(item) {
      if (!negocio.facturaPreciosConIsv) return item.subtotal as double;
      final precio = precioMostrado(item);
      return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
    }

    final totalSinDescuento = venta.detalle.fold<double>(0, (s, item) => s + item.precioVenta * item.cantidad);
    final descuentosYRebajas = redondearMoneda(totalSinDescuento - venta.subtotal);

    // quitarTildes acá también: esta vista previa tiene que mostrar
    // exactamente lo que va a salir impreso (ver el comentario de la
    // clase), y el ticket real no lleva tildes -muchas impresoras térmicas
    // no tienen bien configurada la página de códigos y las imprimen mal-.
    Widget linea(String texto, {bool centrado = false, bool negrita = false, double tamano = 12}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(
          quitarTildes(texto),
          textAlign: centrado ? TextAlign.center : TextAlign.left,
          style: estiloBase.copyWith(fontWeight: negrita ? FontWeight.bold : FontWeight.normal, fontSize: tamano),
        ),
      );
    }

    Widget fila(String izquierda, String derecha, {bool negrita = false}) {
      final estilo = estiloBase.copyWith(fontWeight: negrita ? FontWeight.bold : FontWeight.normal);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(child: Text(quitarTildes(izquierda), style: estilo)),
            Text(quitarTildes(derecha), style: estilo),
          ],
        ),
      );
    }

    Widget separador() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(height: 1, color: Colors.black26),
        );

    // Mismo decode que el ticket real (recortado sin margen en blanco/
    // transparente, ver logo_escpos.dart), re-encodeado a PNG para
    // Image.memory: así la vista previa queda igual de "pegada" al nombre
    // que la impresión de verdad, en vez de mostrar el logo tal cual lo
    // subió el negocio (que puede traer margen de sobra).
    final logoDecodificado = decodificarLogoEscPos(negocio.logoBnBase64);
    final Uint8List? logoBytes = logoDecodificado == null ? null : Uint8List.fromList(img.encodePng(logoDecodificado));

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logoBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Center(child: Image.memory(logoBytes, width: 170)),
            ),
          if (negocio.nombre.isNotEmpty) linea(negocio.nombre.toUpperCase(), centrado: true, negrita: true, tamano: 15),
          if (negocio.eslogan.isNotEmpty) linea(negocio.eslogan, centrado: true),
          if (negocio.direccion.isNotEmpty) linea('Dirección: ${negocio.direccion}', centrado: true),
          if (negocio.rtn.isNotEmpty) linea('RTN: ${negocio.rtn}', centrado: true),
          if (negocio.telefono.isNotEmpty) linea('Tel: ${negocio.telefono}', centrado: true),
          if (negocio.correo.isNotEmpty) linea('Email: ${negocio.correo}', centrado: true),
          if (negocio.cai.isNotEmpty) linea('CAI: ${negocio.cai}', centrado: true),
          const SizedBox(height: 6),
          separador(),
          linea('${venta.tipoDocumento.toUpperCase()} ${negocio.rangoPrefijo}${venta.numeroDocumento}', negrita: true),
          linea('Fecha: ${venta.fechaRegistro != null ? formatoFecha.format(venta.fechaRegistro!) : '-'}'),
          linea('Atendido por: ${venta.usuarioRegistro}'),
          linea('Condición: ${venta.condicion}'),
          if (venta.condicion == 'Credito' && venta.fechaVencimiento != null) linea('Fecha de vencimiento: ${formatoDia.format(venta.fechaVencimiento!)}'),
          separador(),
          linea('Cliente: ${venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente}'),
          linea('ID/RTN Cliente: ${venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente}'),
          if (venta.oc.isNotEmpty) linea('No. O/C exenta: ${venta.oc}'),
          if (venta.regExonerado.isNotEmpty) linea('No. Reg de exonerado: ${venta.regExonerado}'),
          if (venta.regSag.isNotEmpty) linea('No. De reg de la SAG: ${venta.regSag}'),
          separador(),
          fila('CANT DESCRIPCIÓN', 'IMPORTE', negrita: true),
          separador(),
          for (final item in venta.detalle) ...[
            linea(item.nombreProducto),
            fila(
              '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(precioMostrado(item))}${item.descuentoPorcentaje > 0 ? ' (-${_formatoCantidad(item.descuentoPorcentaje)}%)' : ''}',
              formatearMoneda(importeMostrado(item)),
            ),
            const SizedBox(height: 2),
          ],
          separador(),
          fila('SUBTOTAL:', formatearMoneda(venta.subtotal)),
          if (venta.descuentoGlobal > 0) linea('Descuento global: ${_formatoCantidad(venta.descuentoGlobal)}%'),
          fila('Descuentos y rebajas:', formatearMoneda(descuentosYRebajas)),
          fila('Importe Exento:', formatearMoneda(0)),
          fila('Importe Exonerado:', formatearMoneda(0)),
          fila('Gravado 15%:', formatearMoneda(venta.subtotal)),
          fila('Gravado 18%:', formatearMoneda(0)),
          fila('ISV 15%:', formatearMoneda(venta.impuesto)),
          fila('TOTAL A PAGAR:', formatearMoneda(venta.totalAPagar), negrita: true),
          const SizedBox(height: 6),
          separador(),
          linea('Son: ${convertirNumeroALetras(venta.totalAPagar)}'),
          if (venta.condicion != 'Credito') ...[
            if (venta.metodoPago == 'Efectivo') ...[
              linea('Efectivo: ${formatearMoneda(venta.montoPago)}'),
              linea('Cambio: ${formatearMoneda(venta.montoCambio)}'),
            ] else if (venta.metodoPago == 'Tarjeta')
              linea('Pago con tarjeta: ${formatearMoneda(venta.totalAPagar)}')
            else if (venta.metodoPago == 'Transferencia')
              linea('Transferencia')
            else if (venta.metodoPago == 'Mixto')
              for (final pago in venta.pagosMixtos) linea('${pago.metodoPago}: ${formatearMoneda(pago.monto)}'),
          ],
          separador(),
          if (negocio.rangoPrefijo.isNotEmpty || negocio.rangoDesde.isNotEmpty)
            linea('Rango Aut.: ${negocio.rangoPrefijo}${negocio.rangoDesde} al ${negocio.rangoPrefijo}${negocio.rangoHasta}'),
          if (negocio.fechaLimiteEmision != null) linea('Fecha Límite: ${formatoDia.format(negocio.fechaLimiteEmision!)}'),
          const SizedBox(height: 6),
          linea('ORIGINAL: CLIENTE'),
          linea('COPIA: OBLIGADO TRIBUTARIO EMISOR'),
          const SizedBox(height: 8),
          linea('LA FACTURA ES BENEFICIO DE TODOS, ¡EXÍJALA!', centrado: true, negrita: true),
          const SizedBox(height: 6),
          linea('¡GRACIAS POR SU COMPRA!', centrado: true, negrita: true),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: linea(esCopia ? 'COPIA' : 'ORIGINAL', negrita: true)),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
