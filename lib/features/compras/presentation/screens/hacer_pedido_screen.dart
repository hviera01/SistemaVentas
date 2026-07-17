import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/item_pedido_model.dart';
import '../../data/pedido_export_service.dart';
import '../../../productos/data/producto_model.dart';
import '../../../proveedores/data/proveedor_model.dart';
import '../../../proveedores/providers/proveedores_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/buscar_producto_compra_dialog.dart';

/// Pedido de compra: agregás productos y la cantidad que necesitás, y se
/// genera un PDF listo para enviarle al proveedor. No se guarda nada en
/// Firestore — es una herramienta de una sola vez, no un historial.
class HacerPedidoScreen extends ConsumerStatefulWidget {
  const HacerPedidoScreen({super.key});

  @override
  ConsumerState<HacerPedidoScreen> createState() => _HacerPedidoScreenState();
}

class _HacerPedidoScreenState extends ConsumerState<HacerPedidoScreen> {
  final _servicioExport = PedidoExportService();
  final _observacionesController = TextEditingController();
  ProveedorModel? _proveedor;
  List<ItemPedidoModel> _items = [];
  bool _generando = false;

  final Map<int, TextEditingController> _ctrlCantidad = {};
  int _conteoItemsControladores = -1;

  @override
  void dispose() {
    _observacionesController.dispose();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _agregarProducto() async {
    final producto = await Navigator.of(context).push<ProductoModel>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoCompraDialog()),
    );
    if (producto == null || !mounted) return;
    if (_items.any((i) => i.idProducto == producto.id)) {
      _mostrarMensaje('Ese producto ya está en el pedido');
      return;
    }
    setState(() {
      _items = [
        ..._items,
        ItemPedidoModel(idProducto: producto.id, codigo: producto.codigo, nombreProducto: producto.nombre, stockActual: producto.stock, cantidad: 1),
      ];
    });
  }

  void _quitarItem(int index) {
    setState(() => _items = [..._items]..removeAt(index));
  }

  void _actualizarCantidad(int index, double cantidad) {
    if (cantidad <= 0) {
      _mostrarMensaje('La cantidad debe ser mayor a 0');
      return;
    }
    setState(() {
      final nuevos = [..._items];
      nuevos[index] = nuevos[index].copyWith(cantidad: cantidad);
      _items = nuevos;
    });
  }

  void _limpiar() {
    setState(() {
      _items = [];
      _proveedor = null;
    });
    _observacionesController.clear();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    _ctrlCantidad.clear();
    _conteoItemsControladores = 0;
  }

  Future<void> _generarPdf() async {
    if (_items.isEmpty) {
      _mostrarMensaje('Agregá al menos un producto al pedido');
      return;
    }
    setState(() => _generando = true);
    try {
      final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Vista previa · Pedido de Compra',
          nombreArchivo: 'pedido_compra.pdf',
          generarPdf: () => _servicioExport.generarPdf(
            negocio: negocio,
            proveedor: _proveedor,
            observaciones: _observacionesController.text,
            items: _items,
            fecha: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      _mostrarMensaje('No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          return SingleChildScrollView(
            padding: EdgeInsets.all(esMovil ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 14),
                _tarjetaDatosPedido(esMovil),
                const SizedBox(height: 14),
                _tarjetaProductos(esMovil),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _generando ? null : _generarPdf,
                    icon: _generando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    label: Text('Generar PDF del Pedido', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text('Hacer Pedido', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        OutlinedButton.icon(
          onPressed: _limpiar,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ],
    );
  }

  Widget _tarjetaDatosPedido(bool esMovil) {
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);
    return _tarjeta(
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: esMovil ? double.infinity : 280,
            child: proveedoresAsync.when(
              data: (proveedores) {
                return DropdownButtonFormField<ProveedorModel?>(
                  initialValue: _proveedor,
                  isExpanded: true,
                  decoration: _decoracion('Proveedor (opcional)'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: [
                    DropdownMenuItem<ProveedorModel?>(value: null, child: Text('Sin especificar', style: GoogleFonts.poppins(fontSize: 13))),
                    ...proveedores.map((p) => DropdownMenuItem<ProveedorModel?>(value: p, child: Text(p.razonSocial, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _proveedor = v),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, st) => Text('Error cargando proveedores', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
            ),
          ),
          SizedBox(
            width: esMovil ? double.infinity : 360,
            child: TextField(
              controller: _observacionesController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: _decoracion('Observaciones (opcional)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProductos(bool esMovil) {
    if (_items.length != _conteoItemsControladores) {
      for (final c in _ctrlCantidad.values) {
        c.dispose();
      }
      _ctrlCantidad.clear();
      _conteoItemsControladores = _items.length;
    }

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Productos del pedido', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _agregarProducto,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'Todavía no agregaste productos.\nUsá "Agregar Producto" para buscar del inventario.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ),
            )
          else ...[
            if (!esMovil) ...[_encabezadoTabla(), Divider(height: 18, color: Colors.grey.shade300)],
            for (var i = 0; i < _items.length; i++) ...[
              esMovil ? _filaMovil(i, _items[i]) : _filaTabla(i, _items[i]),
              if (i != _items.length - 1) Divider(height: 1, color: Colors.grey.shade200),
            ],
          ],
        ],
      ),
    );
  }

  Widget _encabezadoTabla() {
    final estilo = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 5, child: Text('Producto', style: estilo)),
        Expanded(flex: 2, child: Text('Stock actual', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Cantidad a pedir', textAlign: TextAlign.center, style: estilo)),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _campoCantidad(int index, ItemPedidoModel item) {
    final ctrl = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad)));
    void confirmar() {
      final valor = double.tryParse(ctrl.text.replaceAll(',', '').trim());
      if (valor != null) _actualizarCantidad(index, valor);
    }

    return TextField(
      controller: ctrl,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFE8EAF0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onSubmitted: (_) => confirmar(),
      onTapOutside: (_) => confirmar(),
    );
  }

  Widget _filaTabla(int index, ItemPedidoModel item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: Text(item.codigo.isEmpty ? '-' : item.codigo, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(flex: 5, child: Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(_formatoCantidad(item.stockActual), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoCantidad(index, item))),
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
          ),
        ],
      ),
    );
  }

  Widget _filaMovil(int index, ItemPedidoModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('${item.codigo.isEmpty ? '-' : item.codigo} · Stock: ${_formatoCantidad(item.stockActual)}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(width: 140, child: _campoCantidad(index, item)),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
