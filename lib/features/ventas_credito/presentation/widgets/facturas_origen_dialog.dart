import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import '../../data/venta_credito_model.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../ventas/data/item_venta_model.dart';
import '../../../ventas/data/venta_model.dart';
import '../../../ventas/data/venta_export_service.dart';
import '../../../ventas/providers/ventas_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../auth/providers/auth_provider.dart';

/// Item consolidado para el detalle único de una factura fusionada: junta
/// las líneas de producto de todas las facturas que se unieron, marcando de
/// cuál venía cada una para no perder trazabilidad.
class _ItemConsolidado {
  final String numeroFacturaOrigen;
  final ItemVentaModel item;

  _ItemConsolidado(this.numeroFacturaOrigen, this.item);
}

class FacturasOrigenDialog extends ConsumerStatefulWidget {
  final VentaCreditoModel credito;

  const FacturasOrigenDialog({super.key, required this.credito});

  @override
  ConsumerState<FacturasOrigenDialog> createState() => _FacturasOrigenDialogState();
}

class _FacturasOrigenDialogState extends ConsumerState<FacturasOrigenDialog> {
  bool _cargando = true;
  bool _vistaAgrupada = false;
  List<VentaModel> _ventasOrigen = [];
  List<_ItemConsolidado> _items = [];
  List<String> _facturasSinDetalle = [];
  List<String> _numerosFacturasUnidas = [];

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  // Misma conversión que usa DetalleVentaScreen: precioVenta/subtotal se
  // guardan sin ISV, así que hay que aplicar el 15% para mostrarlos como en
  // la factura real.
  double _precioConIsv(ItemVentaModel item) => redondearMoneda(item.precioVenta * 1.15);

  double _importeConIsv(ItemVentaModel item) => redondearMoneda(_precioConIsv(item) * item.cantidad * (1 - item.descuentoPorcentaje / 100));

  // Una factura "origen" puede a su vez ser el resultado de otra unión
  // anterior (unir una factura ya fusionada con una nueva) — en ese caso no
  // tiene una venta real propia, pero sí su propia lista de facturasOrigen.
  // Se baja recursivamente hasta encontrar las ventas reales del fondo, para
  // que el detalle consolidado siempre muestre todos los productos sin
  // importar cuántos niveles de fusión haya.
  Future<void> _resolverFactura(
    FacturaOrigenModel factura,
    List<VentaModel> ventas,
    List<String> sinDetalle,
    List<String> numeros,
    Set<String> visitados,
  ) async {
    if (factura.id.isEmpty || !visitados.add(factura.id)) {
      if (factura.id.isEmpty) {
        sinDetalle.add(factura.numeroDocumento);
        numeros.add(factura.numeroDocumento);
      }
      return;
    }
    try {
      final venta = await ref.read(ventaRepositoryProvider).obtenerVentaPorId(factura.id);
      if (venta != null && venta.detalle.isNotEmpty) {
        ventas.add(venta);
        numeros.add(venta.numeroDocumento);
        return;
      }
      final creditoOrigen = await ref.read(ventaCreditoRepositoryProvider).obtenerPorId(factura.id);
      if (creditoOrigen != null && creditoOrigen.facturasOrigen.isNotEmpty) {
        for (final sub in creditoOrigen.facturasOrigen) {
          await _resolverFactura(sub, ventas, sinDetalle, numeros, visitados);
        }
      } else {
        sinDetalle.add(factura.numeroDocumento);
        numeros.add(factura.numeroDocumento);
      }
    } catch (_) {
      sinDetalle.add(factura.numeroDocumento);
      numeros.add(factura.numeroDocumento);
    }
  }

  Future<void> _cargarDetalle() async {
    final ventas = <VentaModel>[];
    final sinDetalle = <String>[];
    final numeros = <String>[];
    final visitados = <String>{};
    for (final factura in widget.credito.facturasOrigen) {
      await _resolverFactura(factura, ventas, sinDetalle, numeros, visitados);
    }
    if (!mounted) return;
    setState(() {
      _ventasOrigen = ventas;
      _items = [for (final v in ventas) for (final item in v.detalle) _ItemConsolidado(v.numeroDocumento, item)];
      _facturasSinDetalle = sinDetalle;
      _numerosFacturasUnidas = numeros;
      _cargando = false;
    });
  }

  Future<void> _imprimirPorSeparado() async {
    if (_ventasOrigen.isEmpty) return;
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Facturas por separado',
        nombreArchivo: 'facturas_${widget.credito.numeroDocumento}.pdf',
        generarPdf: () => VentaExportService().generarPdfFacturasPorSeparado(_ventasOrigen, negocio),
        generarPdfConFormato: (formato) => VentaExportService().generarPdfFacturasPorSeparado(_ventasOrigen, negocio, formatoImpresora: formato),
        impresora: impresora,
      ),
    );
  }

  // Junta las líneas que son exactamente el mismo producto (mismo precio y
  // descuento) sumando cantidad e importe en una sola fila, en vez de
  // repetir el producto una vez por cada factura de la que vino.
  List<ItemVentaModel> _consolidarItems() {
    final porClave = <String, ItemVentaModel>{};
    for (final c in _items) {
      final item = c.item;
      final clave = '${item.idProducto}|${item.precioVenta}|${item.descuentoPorcentaje}';
      final existente = porClave[clave];
      porClave[clave] = existente == null
          ? item
          : existente.copyWith(cantidad: existente.cantidad + item.cantidad, subtotal: existente.subtotal + item.subtotal);
    }
    return porClave.values.toList();
  }

  // Se arma (y se reserva su número real) una sola vez por apertura de este
  // diálogo, sin importar cuántas veces se pida imprimir o descargar el PDF
  // desde acá: así "Imprimir todo en un solo papel" y "Descargar PDF" hablan
  // siempre del mismo documento con el mismo número, en vez de gastar un
  // número de la secuencia oficial por cada clic.
  VentaModel? _ventaSinteticaCache;

  Future<VentaModel> _obtenerVentaSintetica() async {
    final cache = _ventaSinteticaCache;
    if (cache != null) return cache;
    // Número real de la secuencia oficial (el que le tocaría a la próxima
    // factura), aunque no se registre una venta nueva: es solo para que
    // este documento tenga un número válido y no se repita con el de una
    // venta futura.
    final numeroDocumento = await ref.read(ventaRepositoryProvider).reservarProximoNumeroFactura();
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
    final itemsConsolidados = _consolidarItems();
    // El total sale directo del crédito (ya es el monto exacto y correcto,
    // suma de los saldos reales de las facturas unidas) en vez de volver a
    // sumar los ítems y sacarle el 15% aparte: hacerlo por separado puede
    // arrastrar una diferencia de un centavo (.01/.99) por el redondeo doble
    // (cada línea redondeada + el total redondeado). Acá el ISV sale de
    // restarle el subtotal al total ya conocido, así siempre cuadra exacto.
    final totalAPagar = widget.credito.montoTotal;
    final subtotal = redondearMoneda(totalAPagar / 1.15);
    final impuesto = redondearMoneda(totalAPagar - subtotal);
    final venta = VentaModel(
      id: '',
      tipoDocumento: 'Factura',
      numeroDocumento: numeroDocumento,
      documentoCliente: widget.credito.documentoCliente,
      nombreCliente: widget.credito.nombreCliente,
      metodoPago: 'N/A',
      montoPago: 0,
      montoCambio: 0,
      subtotal: subtotal,
      impuesto: impuesto,
      totalAPagar: totalAPagar,
      condicion: 'Credito',
      fechaVencimiento: widget.credito.fechaVencimiento,
      fechaRegistro: DateTime.now(),
      estado: 'Activa',
      usuarioRegistro: usuario,
      cantidadProductos: itemsConsolidados.fold<double>(0, (s, i) => s + i.cantidad),
      oc: '',
      regExonerado: '',
      regSag: '',
      detalle: itemsConsolidados,
    );
    _ventaSinteticaCache = venta;
    return venta;
  }

  Future<void> _imprimirUnificado() async {
    if (_ventasOrigen.isEmpty) return;
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    final ventaSintetica = await _obtenerVentaSintetica();
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · ${ventaSintetica.numeroDocumento}',
        nombreArchivo: 'venta_${ventaSintetica.numeroDocumento}.pdf',
        generarPdf: () => VentaExportService().generarPdfFactura(ventaSintetica, negocio),
        generarPdfConFormato: (formato) => VentaExportService().generarPdfFactura(ventaSintetica, negocio, formatoImpresora: formato),
        impresora: impresora,
      ),
    );
  }

  // Mismo documento formal en tamaño carta que ofrece "Ver detalle de
  // venta" (VentaExportService.generarPdfDetalleVenta), para poder
  // descargar/compartir el PDF sin pasar por la vista de ticket térmico.
  Future<void> _descargarPdf() async {
    if (_ventasOrigen.isEmpty) return;
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    final ventaSintetica = await _obtenerVentaSintetica();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Documento formal · ${ventaSintetica.numeroDocumento}',
        nombreArchivo: '${ventaSintetica.tipoDocumento}_${ventaSintetica.numeroDocumento}.pdf',
        generarPdf: () => VentaExportService().generarPdfDetalleVenta(ventaSintetica, negocio),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credito = widget.credito;
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 640;
    final anchoDialog = esMovil ? tamano.width - 24 : 640.0;
    final altoDialog = tamano.height < 700 ? tamano.height - 40 : 640.0;
    final totalItems = _items.fold<double>(0, (s, i) => s + _importeConIsv(i.item));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 16 : 22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.call_merge_outlined, color: Color(0xFFC62828), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detalle de Facturas Unidas', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text('${credito.numeroDocumento} · ${credito.nombreCliente}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Facturas unidas: ${(_numerosFacturasUnidas.isEmpty ? credito.facturasOrigen.map((f) => f.numeroDocumento) : _numerosFacturasUnidas).join(', ')}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (!_cargando && _items.isNotEmpty) ...[
              const SizedBox(height: 10),
              _selectorVista(),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))
                  : _items.isEmpty
                      ? Center(child: Text('No se encontró el detalle de productos de estas facturas', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)))
                      : _tabla(),
            ),
            if (_facturasSinDetalle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Sin detalle disponible: ${_facturasSinDetalle.join(', ')}',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _items.isEmpty ? '' : 'Suma de productos (c/ISV): ${formatearMoneda(totalItems)}',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                Text('Total unificado: ${formatearMoneda(credito.montoTotal)}', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
            if (!_cargando && _ventasOrigen.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _imprimirPorSeparado,
                    icon: const Icon(Icons.receipt_long_outlined, size: 17),
                    label: Text('Imprimir factura por factura', style: GoogleFonts.poppins(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  OutlinedButton.icon(
                    onPressed: _descargarPdf,
                    icon: const Icon(Icons.download_outlined, size: 17),
                    label: Text('Descargar PDF', style: GoogleFonts.poppins(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  FilledButton.icon(
                    onPressed: _imprimirUnificado,
                    icon: const Icon(Icons.description_outlined, size: 17),
                    label: Text('Imprimir todo en un solo papel', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectorVista() {
    Widget opcion(String texto, bool valor) {
      final activo = _vistaAgrupada == valor;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _vistaAgrupada = valor),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: activo ? const Color(0xFFC62828) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Text(
              texto,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF4B4F58)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFECEEF3), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [opcion('Por factura', false), opcion('Agrupado por producto', true)]),
    );
  }

  Widget _tabla() {
    final items = _vistaAgrupada ? _consolidarItems() : _items.map((c) => c.item).toList();
    final etiquetasFactura = _vistaAgrupada ? List<String?>.filled(items.length, null) : _items.map((c) => c.numeroFacturaOrigen).toList();
    final filas = [for (var i = 0; i < items.length; i++) _celdaProducto(items[i].nombreProducto, etiquetasFactura[i])];

    return SingleChildScrollView(
      child: Table(
        columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.6), 3: FlexColumnWidth(1.6)},
        children: [
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFB6BCC7)))),
            children: [
              _celdaEncabezado('PRODUCTO'),
              _celdaEncabezado('CANT.', alinear: TextAlign.right),
              _celdaEncabezado('PRECIO (c/ISV)', alinear: TextAlign.right),
              _celdaEncabezado('IMPORTE (c/ISV)', alinear: TextAlign.right),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEEF3)))),
              children: [
                filas[i],
                _celda(items[i].cantidad.toStringAsFixed(items[i].cantidad % 1 == 0 ? 0 : 2), alinear: TextAlign.right),
                _celda(formatearMoneda(_precioConIsv(items[i])), alinear: TextAlign.right),
                _celda(formatearMoneda(_importeConIsv(items[i])), alinear: TextAlign.right),
              ],
            ),
        ],
      ),
    );
  }

  Widget _celdaEncabezado(String texto, {TextAlign alinear = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(texto, textAlign: alinear, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
    );
  }

  Widget _celda(String texto, {TextAlign alinear = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(texto, textAlign: alinear, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _celdaProducto(String nombreProducto, String? numeroFacturaOrigen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5)),
          if (numeroFacturaOrigen != null) Text('Factura $numeroFacturaOrigen', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
