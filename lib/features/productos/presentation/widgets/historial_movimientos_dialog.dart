import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/producto_model.dart';

class HistorialMovimientosDialog extends StatefulWidget {
  final ProductoModel producto;
  final String tipo;

  const HistorialMovimientosDialog({super.key, required this.producto, required this.tipo});

  @override
  State<HistorialMovimientosDialog> createState() => _HistorialMovimientosDialogState();
}

class _HistorialMovimientosDialogState extends State<HistorialMovimientosDialog> {
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

  @override
  Widget build(BuildContext context) {
    final esVentas = widget.tipo == 'ventas';
    final titulo = esVentas ? 'Historial de Ventas' : 'Historial de Compras';
    final icono = esVentas ? Icons.point_of_sale_outlined : Icons.shopping_cart_outlined;
    final formatoDia = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 760 ? tamano.width - 32 : 680.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: anchoDialog,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$titulo · ${widget.producto.nombre}',
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
            const SizedBox(height: 30),
            Icon(icono, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('Todavía no hay movimientos', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Text(
              'Este historial se completa automáticamente cuando el módulo de ${esVentas ? 'Ventas' : 'Compras'} esté conectado',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
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