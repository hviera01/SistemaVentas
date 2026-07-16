import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../providers/carrito_compra_provider.dart';
import '../../providers/compras_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../proveedores/data/proveedor_model.dart';
import '../../../proveedores/providers/proveedores_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../widgets/buscar_producto_compra_dialog.dart';
import 'detalle_compra_screen.dart';

const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];

class RegistrarCompraScreen extends ConsumerStatefulWidget {
  const RegistrarCompraScreen({super.key});

  @override
  ConsumerState<RegistrarCompraScreen> createState() => _RegistrarCompraScreenState();
}

class _RegistrarCompraScreenState extends ConsumerState<RegistrarCompraScreen> {
  final _noFacturaController = TextEditingController();
  final _descuentoGlobalController = TextEditingController();
  final _isvController = TextEditingController(text: '15');
  final _ajusteManualController = TextEditingController();
  bool _datosExpandidos = false;
  bool _guardando = false;

  final Map<int, TextEditingController> _ctrlCantidad = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};
  final Map<int, TextEditingController> _ctrlDescuento = {};
  int _conteoItemsControladores = -1;

  @override
  void dispose() {
    _noFacturaController.dispose();
    _descuentoGlobalController.dispose();
    _isvController.dispose();
    _ajusteManualController.dispose();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<bool> _confirmarDialogo(String titulo, String mensaje) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(mensaje, style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sí', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  // ---------- Producto ----------

  Future<void> _agregarProductoDesdeBusqueda() async {
    final producto = await Navigator.of(context).push<ProductoModel>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoCompraDialog()),
    );
    if (producto == null || !mounted) return;
    ref.read(carritoCompraProvider.notifier).agregarProductoDirecto(producto);
  }

  void _quitarItem(int index) {
    ref.read(carritoCompraProvider.notifier).quitarItem(index);
  }

  void _actualizarCantidad(int index, double nuevaCantidad) {
    if (nuevaCantidad <= 0) {
      _mostrarMensaje('La cantidad debe ser mayor a 0');
      return;
    }
    ref.read(carritoCompraProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
  }

  void _actualizarPrecio(int index, double nuevoPrecio) {
    if (nuevoPrecio < 0) {
      _mostrarMensaje('Precio inválido');
      return;
    }
    ref.read(carritoCompraProvider.notifier).actualizarLinea(index, precioCompra: nuevoPrecio);
  }

  void _actualizarDescuentoLinea(int index, double descuento) {
    if (descuento < 0 || descuento > 100) {
      _mostrarMensaje('El descuento debe estar entre 0 y 100');
      return;
    }
    ref.read(carritoCompraProvider.notifier).actualizarLinea(index, descuentoPorcentaje: descuento);
  }

  double _descuentoLineaMonto(dynamic item) {
    final sinDescuento = (item.precioCompra as double) * (item.cantidad as double);
    return sinDescuento - (item.subtotal as double);
  }

  // ---------- Limpiar ----------

  void _limpiarTodo() {
    ref.read(carritoCompraProvider.notifier).limpiar();
    _noFacturaController.clear();
    _descuentoGlobalController.clear();
    _isvController.text = '15';
    _ajusteManualController.clear();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    _ctrlCantidad.clear();
    _ctrlPrecio.clear();
    _ctrlDescuento.clear();
    _conteoItemsControladores = 0;
  }

  Future<void> _confirmarLimpiar() async {
    final carrito = ref.read(carritoCompraProvider);
    final hayAlgoQuePerder = carrito.items.isNotEmpty || carrito.razonSocial.isNotEmpty;
    if (hayAlgoQuePerder) {
      final continuar = await _confirmarDialogo('Limpiar compra', '¿Seguro que querés borrar todos los productos y datos ingresados en esta compra?');
      if (!continuar) return;
    }
    _limpiarTodo();
  }

  // ---------- Confirmar compra ----------

  Future<void> _confirmarCompra() async {
    final carrito = ref.read(carritoCompraProvider);
    if (carrito.items.isEmpty) {
      _mostrarMensaje('Debe ingresar productos en la compra');
      return;
    }
    if (carrito.idProveedor.isEmpty) {
      _mostrarMensaje('Seleccioná un proveedor');
      return;
    }
    if (carrito.esCredito && carrito.fechaVencimiento == null) {
      _mostrarMensaje('Definí la fecha de vencimiento del crédito');
      return;
    }

    setState(() => _guardando = true);
    try {
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      final compra = await ref.read(compraRepositoryProvider).registrarCompra(
            noFactura: _noFacturaController.text.trim(),
            idProveedor: carrito.idProveedor,
            documentoProveedor: carrito.documentoProveedor,
            razonSocial: carrito.razonSocial,
            condicion: carrito.condicion,
            metodoPago: carrito.esCredito ? 'N/A' : carrito.metodoPago,
            fechaRegistro: carrito.fecha,
            fechaVencimiento: carrito.esCredito ? carrito.fechaVencimiento : null,
            descuentoGlobalPorcentaje: carrito.descuentoGlobalPorcentaje,
            descuentoTotalMonto: carrito.descuentoTotalMonto,
            isvPorcentaje: carrito.isvPorcentaje,
            ajusteManual: carrito.ajusteManual,
            items: carrito.items,
            subtotal: carrito.subtotal,
            impuesto: carrito.impuesto,
            totalAPagar: carrito.totalAPagar,
            usuario: usuario,
          );

      if (!mounted) return;
      _limpiarTodo();
      _mostrarMensaje('Compra registrada: ${compra.numeroDocumento}');
    } catch (e) {
      _mostrarMensaje(e is TimeoutException
          ? 'No se pudo guardar: se agotó el tiempo de espera. Revisá la conexión a internet e intentá de nuevo.'
          : 'Error al registrar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final carrito = ref.watch(carritoCompraProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          final altoTabla = (constraints.maxHeight * 0.58).clamp(360.0, 1000.0);
          return SingleChildScrollView(
            padding: EdgeInsets.all(esMovil ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 14),
                _tarjetaDatosCompra(carrito, esMovil),
                const SizedBox(height: 14),
                SizedBox(height: altoTabla, child: _tarjetaCarritoGrande(carrito, esMovil)),
                const SizedBox(height: 14),
                _tarjetaTotales(carrito, esMovil),
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
        Text('Registrar Compra', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        OutlinedButton.icon(
          onPressed: _confirmarLimpiar,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text('Limpiar Compra', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _verDetalleCompra,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text('Ver Detalle', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
      ],
    );
  }

  void _verDetalleCompra() {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const DetalleCompraScreen()),
    );
  }

  ButtonStyle _estiloBotonSecundario() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF1A1A1A),
      side: const BorderSide(color: Color(0xFFDCDFE6)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EC)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  InputDecoration _decoracion(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      hintStyle: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400),
      filled: true,
      fillColor: const Color(0xFFF5F6FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _tarjetaDatosCompra(CarritoCompraState carrito, bool esMovil) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: esMovil ? double.infinity : 160,
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(context: context, initialDate: carrito.fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (fecha != null) ref.read(carritoCompraProvider.notifier).establecerFecha(fecha);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Flexible(child: Text(formatoFecha.format(carrito.fecha), overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)))),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 260,
                child: proveedoresAsync.when(
                  data: (proveedores) {
                    final actual = proveedores.where((p) => p.id == carrito.idProveedor).toList();
                    return DropdownButtonFormField<ProveedorModel>(
                      initialValue: actual.isNotEmpty ? actual.first : null,
                      isExpanded: true,
                      decoration: _decoracion('Proveedor'),
                      style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                      items: proveedores.map((p) => DropdownMenuItem(value: p, child: Text(p.razonSocial, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        ref.read(carritoCompraProvider.notifier).establecerProveedor(idProveedor: v.id, documentoProveedor: v.rtn, razonSocial: v.razonSocial);
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, st) => Text('Error cargando proveedores', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 180,
                child: TextField(
                  controller: _noFacturaController,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: _decoracion('No. Factura'),
                  onChanged: (v) => ref.read(carritoCompraProvider.notifier).establecerNoFactura(v),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 150,
                child: DropdownButtonFormField<String>(
                  initialValue: carrito.condicion,
                  isExpanded: true,
                  decoration: _decoracion('Condición'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: const [
                    DropdownMenuItem(value: 'Contado', child: Text('Contado')),
                    DropdownMenuItem(value: 'Credito', child: Text('Crédito')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(carritoCompraProvider.notifier).establecerCondicion(v);
                  },
                ),
              ),
              if (carrito.condicion == 'Credito')
                SizedBox(
                  width: esMovil ? double.infinity : 160,
                  child: InkWell(
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate: carrito.fechaVencimiento ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (fecha != null) ref.read(carritoCompraProvider.notifier).establecerFechaVencimiento(fecha);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.event_outlined, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Vence: ${carrito.fechaVencimiento != null ? formatoFecha.format(carrito.fechaVencimiento!) : 'Sin definir'}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: esMovil ? double.infinity : 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _metodosPago.contains(carrito.metodoPago) ? carrito.metodoPago : null,
                    isExpanded: true,
                    decoration: _decoracion('Método de pago'),
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                    items: _metodosPago.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(carritoCompraProvider.notifier).establecerMetodoPago(v);
                    },
                  ),
                ),
              InkWell(
                onTap: () => setState(() => _datosExpandidos = !_datosExpandidos),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _datosExpandidos ? 'Ver menos' : 'Más datos',
                        style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFFC62828)),
                      ),
                      Icon(_datosExpandidos ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFFC62828)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: !_datosExpandidos
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 14),
                        Text('Descuento global, ISV y ajuste manual', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: esMovil ? double.infinity : 220,
                              child: TextField(
                                controller: _descuentoGlobalController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('Descuento global (%)'),
                                onChanged: (v) {
                                  final valor = double.tryParse(v.replaceAll(',', '').trim());
                                  if (valor == null || valor < 0 || valor > 100) return;
                                  ref.read(carritoCompraProvider.notifier).establecerDescuentoGlobal(valor);
                                },
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 160,
                              child: TextField(
                                controller: _isvController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('ISV (%)'),
                                onChanged: (v) {
                                  final valor = double.tryParse(v.replaceAll(',', '').trim());
                                  if (valor == null || valor < 0) return;
                                  ref.read(carritoCompraProvider.notifier).establecerIsv(valor);
                                },
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 260,
                              child: TextField(
                                controller: _ajusteManualController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('Ajuste manual (+/-)', hint: 'Para cuadrar centavos con la factura'),
                                onChanged: (v) {
                                  final valor = double.tryParse(v.replaceAll(',', '').trim());
                                  ref.read(carritoCompraProvider.notifier).establecerAjusteManual(valor ?? 0);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCarritoGrande(CarritoCompraState carrito, bool esMovil) {
    final productos = ref.watch(productosStreamProvider).value ?? [];
    final mapaProductos = {for (final p in productos) p.id: p};

    if (carrito.items.length != _conteoItemsControladores) {
      for (final c in _ctrlCantidad.values) {
        c.dispose();
      }
      for (final c in _ctrlPrecio.values) {
        c.dispose();
      }
      for (final c in _ctrlDescuento.values) {
        c.dispose();
      }
      _ctrlCantidad.clear();
      _ctrlPrecio.clear();
      _ctrlDescuento.clear();
      _conteoItemsControladores = carrito.items.length;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EC)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          esMovil
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Productos en la compra', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _agregarProductoDesdeBusqueda,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text('Productos en la compra', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _agregarProductoDesdeBusqueda,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
          const SizedBox(height: 14),
          if (!esMovil) ...[
            _encabezadoTablaCarrito(),
            Divider(height: 18, color: Colors.grey.shade300),
          ],
          Expanded(
            child: carrito.items.isEmpty
                ? Center(
                    child: Text(
                      'Todavía no agregaste productos.\nUsá "Agregar Producto" para buscar del inventario.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    itemCount: carrito.items.length,
                    separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) => esMovil ? _filaCarritoMovil(i, carrito.items[i], mapaProductos) : _filaCarritoTabla(i, carrito.items[i], mapaProductos),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoTablaCarrito() {
    final estilo = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 4, child: Text('Descripción', style: estilo)),
        Expanded(flex: 2, child: Text('Cantidad', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Costo unitario', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Descuento %', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Descuento (L)', textAlign: TextAlign.right, style: estilo)),
        Expanded(flex: 2, child: Text('Importe', textAlign: TextAlign.right, style: estilo)),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _campoInlineNumero(TextEditingController controlador, void Function(double) alConfirmar, {String? sufijo}) {
    void confirmar() {
      final valor = double.tryParse(controlador.text.replaceAll(',', '').trim());
      if (valor != null) alConfirmar(valor);
    }

    return TextField(
      controller: controlador,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        suffixText: sufijo,
        filled: true,
        fillColor: const Color(0xFFF5F6FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: (_) => confirmar(),
      onSubmitted: (_) => confirmar(),
      onTapOutside: (_) => confirmar(),
    );
  }

  Widget _campoInlineConEtiqueta(String etiqueta, TextEditingController controlador, void Function(double) alConfirmar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        _campoInlineNumero(controlador, alConfirmar),
      ],
    );
  }

  Widget _filaCarritoTabla(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: (item.precioCompra as double).toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(
            flex: 4,
            child: Text(item.nombreProducto as String, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlCantidad, (v) => _actualizarCantidad(index, v)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlPrecio, (v) => _actualizarPrecio(index, v)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero(ctrlDescuento, (v) => _actualizarDescuentoLinea(index, v), sufijo: '%'))),
          Expanded(flex: 2, child: Text(formatearMoneda(_descuentoLineaMonto(item)), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(flex: 2, child: Text(formatearMoneda(item.subtotal as double), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
          ),
        ],
      ),
    );
  }

  Widget _filaCarritoMovil(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: (item.precioCompra as double).toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EC))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombreProducto as String, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campoInlineConEtiqueta('Cantidad', ctrlCantidad, (v) => _actualizarCantidad(index, v))),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('Costo unitario', ctrlPrecio, (v) => _actualizarPrecio(index, v))),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('Desc. %', ctrlDescuento, (v) => _actualizarDescuentoLinea(index, v))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Descuento: ${formatearMoneda(_descuentoLineaMonto(item))}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              Text('Importe: ${formatearMoneda(item.subtotal as double)}', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  Widget _tarjetaTotales(CarritoCompraState carrito, bool esMovil) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _filaTotalTexto('Subtotal', carrito.subtotal),
              if (carrito.descuentoTotalMonto > 0) _filaTotalTexto('Descuento total', carrito.descuentoTotalMonto),
              _filaTotalTexto('ISV (${_formatoCantidad(carrito.isvPorcentaje)}%)', carrito.impuesto),
              if (carrito.ajusteManual != 0) _filaTotalTexto('Ajuste', carrito.ajusteManual),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL A PAGAR', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(formatearMoneda(carrito.totalAPagar), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmarCompra,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                  : Text('Registrar Compra', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTotalTexto(String etiqueta, double valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }
}
