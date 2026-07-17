import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../ventas/presentation/screens/detalle_venta_screen.dart';
import '../../../compras/presentation/screens/detalle_compra_screen.dart';

/// Fila normalizada para mostrar en la tabla, sea de venta o de compra.
class _FilaHistorial {
  final DateTime? fecha;
  final String documento;
  final String contraparte;
  final double cantidad;
  final double precio;
  final String idDetalle;

  _FilaHistorial({
    required this.fecha,
    required this.documento,
    required this.contraparte,
    required this.cantidad,
    required this.precio,
    required this.idDetalle,
  });
}

class HistorialMovimientosDialog extends ConsumerStatefulWidget {
  final ProductoModel producto;
  final String tipo;

  const HistorialMovimientosDialog({super.key, required this.producto, required this.tipo});

  @override
  ConsumerState<HistorialMovimientosDialog> createState() => _HistorialMovimientosDialogState();
}

class _HistorialMovimientosDialogState extends ConsumerState<HistorialMovimientosDialog> {
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  bool get _esVentas => widget.tipo == 'ventas';

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
      } else {
        _fechaFin = fecha;
      }
    });
  }

  void _limpiarFechas() {
    setState(() {
      _fechaInicio = null;
      _fechaFin = null;
    });
  }

  List<_FilaHistorial> _filtrar(List<_FilaHistorial> registros) {
    return registros.where((r) {
      if (r.fecha == null) return true;
      if (_fechaInicio != null && r.fecha!.isBefore(DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day))) return false;
      if (_fechaFin != null && r.fecha!.isAfter(DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59))) return false;
      return true;
    }).toList();
  }

  void _verDetalle(_FilaHistorial fila) {
    if (fila.idDetalle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este registro no tiene un detalle disponible')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _esVentas ? DetalleVentaScreen(ventaIdInicial: fila.idDetalle) : DetalleCompraScreen(compraIdInicial: fila.idDetalle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _esVentas ? 'Historial de Ventas' : 'Historial de Compras';
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final formatoDia = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 640;
    final anchoDialog = esMovil ? tamano.width - 24 : 760.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 40 : 580.0;

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
                Expanded(
                  child: Text('$titulo · ${widget.producto.nombre}', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _botonFecha('Desde', _fechaInicio, formatoDia, () => _seleccionarFecha(true)),
                _botonFecha('Hasta', _fechaFin, formatoDia, () => _seleccionarFecha(false)),
                if (_fechaInicio != null || _fechaFin != null)
                  TextButton.icon(onPressed: _limpiarFechas, icon: const Icon(Icons.close, size: 16), label: Text('Limpiar fechas', style: GoogleFonts.poppins(fontSize: 12))),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _esVentas ? _contenidoVentas(formatoFecha) : _contenidoCompras(formatoFecha)),
          ],
        ),
      ),
    );
  }

  Widget _contenidoVentas(DateFormat formatoFecha) {
    final async = ref.watch(historialVentasProductoProvider(widget.producto.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
      data: (data) {
        final filas = _filtrar(data
            .map((r) => _FilaHistorial(
                  fecha: r.fecha,
                  documento: '${r.tipoDocumento} ${r.numeroDocumento}',
                  contraparte: r.cliente.isEmpty ? 'CONSUMIDOR FINAL' : r.cliente,
                  cantidad: r.cantidad,
                  precio: r.precioVenta,
                  idDetalle: r.idVenta,
                ))
            .toList());
        return _tabla(filas, formatoFecha, etiquetaContraparte: 'CLIENTE', etiquetaDocumento: 'DOCUMENTO', etiquetaPrecio: 'PRECIO', vacio: 'Sin ventas registradas en el rango seleccionado');
      },
    );
  }

  Widget _contenidoCompras(DateFormat formatoFecha) {
    final async = ref.watch(historialPreciosCompraProvider(widget.producto.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
      data: (data) {
        final filas = _filtrar(data
            .map((r) => _FilaHistorial(
                  fecha: r.fecha,
                  documento: r.noFactura.isEmpty ? '-' : r.noFactura,
                  contraparte: r.proveedor.isEmpty ? 'N/A' : r.proveedor,
                  cantidad: r.cantidad,
                  precio: r.precioCompra,
                  idDetalle: r.idCompra,
                ))
            .toList());
        return _tabla(filas, formatoFecha, etiquetaContraparte: 'PROVEEDOR', etiquetaDocumento: 'FACTURA', etiquetaPrecio: 'COSTO', vacio: 'Sin compras registradas en el rango seleccionado');
      },
    );
  }

  Widget _tabla(
    List<_FilaHistorial> filas,
    DateFormat formatoFecha, {
    required String etiquetaContraparte,
    required String etiquetaDocumento,
    required String etiquetaPrecio,
    required String vacio,
  }) {
    if (filas.isEmpty) {
      return Center(child: Text(vacio, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)));
    }
    final estiloHeader = GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    const anchoTabla = 640.0;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: anchoTabla,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(
                  children: [
                    SizedBox(width: 140, child: Text('FECHA', style: estiloHeader)),
                    SizedBox(width: 130, child: Text(etiquetaDocumento, style: estiloHeader)),
                    Expanded(child: Text(etiquetaContraparte, style: estiloHeader)),
                    SizedBox(width: 70, child: Text('CANT.', textAlign: TextAlign.right, style: estiloHeader)),
                    SizedBox(width: 100, child: Text(etiquetaPrecio, textAlign: TextAlign.right, style: estiloHeader)),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filas.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final r = filas[index];
                    return InkWell(
                      onTap: () => _verDetalle(r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(width: 140, child: Text(r.fecha != null ? formatoFecha.format(r.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 12))),
                            SizedBox(width: 130, child: Text(r.documento, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Expanded(child: Text(r.contraparte, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                            SizedBox(width: 70, child: Text(_formatoCantidad(r.cantidad), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12))),
                            SizedBox(width: 100, child: Text(formatearMoneda(r.precio), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                            SizedBox(
                              width: 48,
                              child: IconButton(
                                tooltip: 'Ver detalle',
                                icon: const Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFFC62828)),
                                onPressed: () => _verDetalle(r),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  Widget _botonFecha(String label, DateTime? fecha, DateFormat formato, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFB6BCC7))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(fecha != null ? '$label: ${formato.format(fecha)}' : label, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A))),
          ],
        ),
      ),
    );
  }
}
