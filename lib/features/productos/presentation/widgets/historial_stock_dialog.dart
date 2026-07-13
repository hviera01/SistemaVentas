import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/producto_model.dart';
import '../../data/historial_stock_model.dart';
import '../../providers/productos_provider.dart';

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
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
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

  @override
  Widget build(BuildContext context) {
    final historialStream = ref.watch(productoRepositoryProvider).obtenerHistorialStock(widget.producto.id);
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final formatoDia = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 760 ? tamano.width - 32 : 720.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 60 : 560.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Historial de Existencia · ${widget.producto.nombre}',
                    style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _botonFecha('Desde', _fechaInicio, formatoDia, () => _seleccionarFecha(true)),
                _botonFecha('Hasta', _fechaFin, formatoDia, () => _seleccionarFecha(false)),
                if (_fechaInicio != null || _fechaFin != null)
                  TextButton.icon(
                    onPressed: _limpiarFechas,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text('Limpiar fechas', style: GoogleFonts.poppins(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: StreamBuilder(
                stream: historialStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)));
                  final registros = _filtrar(snapshot.data!);
                  if (registros.isEmpty) {
                    return Center(child: Text('Sin movimientos en el rango seleccionado', style: GoogleFonts.poppins(color: Colors.grey.shade500)));
                  }
                  return Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCDFE6)), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text('FECHA', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 2, child: Text('ANTERIOR', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 2, child: Text('NUEVO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 4, child: Text('MOTIVO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              Expanded(flex: 3, child: Text('USUARIO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
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
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text(r.fecha != null ? formatoFecha.format(r.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 12))),
                                    Expanded(flex: 2, child: Text(r.stockAnterior.toString(), style: GoogleFonts.poppins(fontSize: 12))),
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Icon(subio ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
                                          const SizedBox(width: 4),
                                          Text(r.stockNuevo.toString(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        r.motivo.isEmpty ? '-' : r.motivo,
                                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                    Expanded(flex: 3, child: Text(r.usuario, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                  ],
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

  Widget _botonFecha(String label, DateTime? fecha, DateFormat formato, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDCDFE6))),
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