import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/producto_model.dart';
import '../../data/historial_stock_model.dart';
import '../../providers/productos_provider.dart';
import '../../../ventas/presentation/screens/detalle_venta_screen.dart';
import '../../../compras/presentation/screens/detalle_compra_screen.dart';

class HistorialStockDialog extends ConsumerStatefulWidget {
  final ProductoModel producto;

  const HistorialStockDialog({super.key, required this.producto});

  @override
  ConsumerState<HistorialStockDialog> createState() => _HistorialStockDialogState();
}

class _HistorialStockDialogState extends ConsumerState<HistorialStockDialog> {
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

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

  List<HistorialStockModel> _filtrar(List<HistorialStockModel> registros) {
    return registros.where((r) {
      if (r.fecha == null) return true;
      if (_fechaInicio != null && r.fecha!.isBefore(DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day))) return false;
      if (_fechaFin != null && r.fecha!.isAfter(DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59))) return false;
      return true;
    }).toList();
  }

  /// Solo venta/compra (y sus anulaciones) están ligadas a un documento
  /// real que se pueda abrir -pedido explícito del dueño: "al tocar la fila
  /// pueda abrirse el detalle de venta o la compra que es". Ajustes
  /// manuales/reembasados no tienen documento propio, no son tocables.
  /// El número sale del propio texto de [HistorialStockModel.motivo] (ver
  /// el getter `tipo`, mismo criterio: no hizo falta guardar un idVenta/
  /// idCompra en cada historial para lograr esto, y así funciona también
  /// retroactivo para movimientos ya guardados).
  String? _numeroDocumentoDesde(HistorialStockModel r) {
    switch (r.tipo) {
      case TipoMovimientoStock.venta:
      case TipoMovimientoStock.anulacionVenta:
      case TipoMovimientoStock.compra:
      case TipoMovimientoStock.anulacionCompra:
        return RegExp(r'\d+').firstMatch(r.motivo)?.group(0);
      case TipoMovimientoStock.reembasado:
      case TipoMovimientoStock.ajusteEntrada:
      case TipoMovimientoStock.ajusteSalida:
        return null;
    }
  }

  void _abrirDetalle(HistorialStockModel r) {
    final numero = _numeroDocumentoDesde(r);
    if (numero == null) return;
    final esVenta = r.tipo == TipoMovimientoStock.venta || r.tipo == TipoMovimientoStock.anulacionVenta;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => esVenta ? DetalleVentaScreen(numeroDocumentoInicial: numero) : DetalleCompraScreen(numeroDocumentoInicial: numero),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historialAsync = ref.watch(historialStockProvider(widget.producto.id));
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final formatoDia = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 640;
    // 1040 en vez de 720 -pedido explícito del dueño: la columna MOTIVO se
    // desbordaba con los movimientos de tintes, cuyo motivo suele ser más
    // largo (describe la fórmula/colorante, no solo "venta"/"compra").
    final anchoDialog = esMovil ? tamano.width - 24 : (tamano.width - 64 < 1040 ? tamano.width - 64 : 1040.0);
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
                  child: Text('Historial de Existencia · ${widget.producto.nombre}', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
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
            Expanded(
              child: historialAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                data: (data) {
                  final registros = _filtrar(data);
                  if (registros.isEmpty) {
                    return Center(child: Text('Sin movimientos en el rango seleccionado', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)));
                  }
                  if (esMovil) {
                    return ListView.separated(
                      itemCount: registros.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final r = registros[index];
                        final subio = r.stockNuevo >= r.stockAnterior;
                        final numeroDocumento = _numeroDocumentoDesde(r);
                        return Material(
                          color: const Color(0xFFF8F9FB),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: numeroDocumento == null ? null : () => _abrirDetalle(r),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _chipTipo(r.tipo),
                                      const Spacer(),
                                      Text(r.fecha != null ? formatoFecha.format(r.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
                                      if (numeroDocumento != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400)],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(subio ? Icons.arrow_upward : Icons.arrow_downward, size: 15, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
                                      const SizedBox(width: 6),
                                      Text('${r.stockAnterior} → ${r.stockNuevo}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 8),
                                      Text('(${subio ? '+' : ''}${r.delta.toStringAsFixed(r.delta == r.delta.roundToDouble() ? 0 : 2)})', style: GoogleFonts.poppins(fontSize: 12, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828))),
                                    ],
                                  ),
                                  if (r.motivo.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(r.motivo, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(r.usuario, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text('FECHA', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 2, child: Text('TIPO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 1, child: Text('ANTERIOR', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 1, child: Text('NUEVO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 1, child: Text('CAMBIO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 5, child: Text('MOTIVO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 2, child: Text('USUARIO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: registros.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, index) {
                              final r = registros[index];
                              final subio = r.stockNuevo >= r.stockAnterior;
                              final numeroDocumento = _numeroDocumentoDesde(r);
                              return InkWell(
                                onTap: numeroDocumento == null ? null : () => _abrirDetalle(r),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            Flexible(child: Text(r.fecha != null ? formatoFecha.format(r.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 12))),
                                            if (numeroDocumento != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right, size: 15, color: Colors.grey.shade400)],
                                          ],
                                        ),
                                      ),
                                      Expanded(flex: 2, child: _chipTipo(r.tipo)),
                                      Expanded(flex: 1, child: Text(r.stockAnterior.toString(), style: GoogleFonts.poppins(fontSize: 12))),
                                      Expanded(
                                        flex: 1,
                                        child: Row(
                                          children: [
                                            Icon(subio ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
                                            const SizedBox(width: 4),
                                            Text(r.stockNuevo.toString(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(
                                          '${subio ? '+' : ''}${r.delta.toStringAsFixed(r.delta == r.delta.roundToDouble() ? 0 : 2)}',
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
                                        ),
                                      ),
                                      Expanded(flex: 5, child: Text(r.motivo.isEmpty ? '-' : r.motivo, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis, maxLines: 3)),
                                      Expanded(flex: 2, child: Text(r.usuario, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipTipo(TipoMovimientoStock tipo) {
    final (color, icono) = switch (tipo) {
      TipoMovimientoStock.venta => (const Color(0xFF16A34A), Icons.point_of_sale),
      TipoMovimientoStock.anulacionVenta => (const Color(0xFFC62828), Icons.undo),
      TipoMovimientoStock.compra => (const Color(0xFF2B6CB0), Icons.local_shipping_outlined),
      TipoMovimientoStock.anulacionCompra => (const Color(0xFFC62828), Icons.undo),
      TipoMovimientoStock.reembasado => (const Color(0xFF9333EA), Icons.opacity),
      TipoMovimientoStock.ajusteEntrada => (const Color(0xFF6B7280), Icons.tune),
      TipoMovimientoStock.ajusteSalida => (const Color(0xFF6B7280), Icons.tune),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(etiquetasTipoMovimientoStock[tipo]!, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
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