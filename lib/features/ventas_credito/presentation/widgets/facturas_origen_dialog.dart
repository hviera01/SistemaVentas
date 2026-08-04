import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/venta_credito_model.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../ventas/data/item_venta_model.dart';
import '../../../ventas/providers/ventas_provider.dart';

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
  List<_ItemConsolidado> _items = [];
  List<String> _facturasSinDetalle = [];

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

  Future<void> _cargarDetalle() async {
    final repo = ref.read(ventaRepositoryProvider);
    final items = <_ItemConsolidado>[];
    final sinDetalle = <String>[];
    for (final factura in widget.credito.facturasOrigen) {
      if (factura.id.isEmpty) {
        sinDetalle.add(factura.numeroDocumento);
        continue;
      }
      try {
        final detalle = await repo.obtenerDetalleVenta(factura.id);
        if (detalle.isEmpty) {
          sinDetalle.add(factura.numeroDocumento);
        } else {
          items.addAll(detalle.map((i) => _ItemConsolidado(factura.numeroDocumento, i)));
        }
      } catch (_) {
        sinDetalle.add(factura.numeroDocumento);
      }
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _facturasSinDetalle = sinDetalle;
      _cargando = false;
    });
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
              'Facturas unidas: ${credito.facturasOrigen.map((f) => f.numeroDocumento).join(', ')}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
            ),
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
          ],
        ),
      ),
    );
  }

  Widget _tabla() {
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
          ..._items.map((c) => TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEEF3)))),
                children: [
                  _celdaProducto(c.item.nombreProducto, c.numeroFacturaOrigen),
                  _celda(c.item.cantidad.toStringAsFixed(c.item.cantidad % 1 == 0 ? 0 : 2), alinear: TextAlign.right),
                  _celda(formatearMoneda(_precioConIsv(c.item)), alinear: TextAlign.right),
                  _celda(formatearMoneda(_importeConIsv(c.item)), alinear: TextAlign.right),
                ],
              )),
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

  Widget _celdaProducto(String nombreProducto, String numeroFacturaOrigen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5)),
          Text('Factura $numeroFacturaOrigen', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
