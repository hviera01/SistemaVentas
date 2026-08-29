import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/venta_credito_model.dart';
import '../../data/abono_model.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Corrige un abono ya registrado (monto, interés, fecha, método, recibo) —
/// ver comentario en EditarAbonoCompraDialog (mismo patrón, lado ventas).
class EditarAbonoDialog extends ConsumerStatefulWidget {
  final VentaCreditoModel credito;
  final AbonoModel abono;

  const EditarAbonoDialog({super.key, required this.credito, required this.abono});

  @override
  ConsumerState<EditarAbonoDialog> createState() => _EditarAbonoDialogState();
}

class _EditarAbonoDialogState extends ConsumerState<EditarAbonoDialog> {
  late final TextEditingController _montoAbonadoController;
  late final TextEditingController _interesController;
  late final TextEditingController _numeroReciboController;
  late String _metodoPago;
  late DateTime _fecha;
  bool _guardando = false;
  String? _error;

  static const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];

  @override
  void initState() {
    super.initState();
    _montoAbonadoController = TextEditingController(text: widget.abono.montoAbonado.toStringAsFixed(2));
    _interesController = TextEditingController(text: widget.abono.interes.toStringAsFixed(2));
    _numeroReciboController = TextEditingController(text: widget.abono.numeroRecibo);
    _metodoPago = _metodosPago.contains(widget.abono.metodoPago) ? widget.abono.metodoPago : 'Efectivo';
    _fecha = widget.abono.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _montoAbonadoController.dispose();
    _interesController.dispose();
    _numeroReciboController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  double get _montoAbonado => _parseDouble(_montoAbonadoController.text);
  double get _interes => _parseDouble(_interesController.text);

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (fecha == null) return;
    setState(() => _fecha = DateTime(fecha.year, fecha.month, fecha.day, _fecha.hour, _fecha.minute, _fecha.second));
  }

  Future<void> _guardar() async {
    if (_montoAbonado <= 0) {
      setState(() => _error = 'Ingresá un monto de abono válido');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(ventaCreditoRepositoryProvider).editarAbono(
            idCredito: widget.credito.id,
            idAbono: widget.abono.id,
            montoTotal: widget.credito.montoTotal,
            montoAbonado: _montoAbonado,
            interes: _interes,
            fecha: _fecha,
            metodoPago: _metodoPago,
            numeroRecibo: _numeroReciboController.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 500;
    final anchoDialog = esMovil ? tamano.width - 32 : 480.0;
    final altoMaximo = (tamano.height - 40).clamp(0, 780).toDouble();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: altoMaximo),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFC62828).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.edit_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Editar Abono · ${widget.credito.numeroDocumento}',
                      style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.credito.nombreCliente, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CampoTecladoCompacto(
                      controller: _montoAbonadoController,
                      numerico: true,
                      child: TextField(
                        inputFormatters: [mayusculasInputFormatter],
                        autocorrect: false,
                        enableSuggestions: false,
                        controller: _montoAbonadoController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: _decoracion('Monto abonado'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    CampoTecladoCompacto(
                      controller: _interesController,
                      numerico: true,
                      child: TextField(
                        inputFormatters: [mayusculasInputFormatter],
                        autocorrect: false,
                        enableSuggestions: false,
                        controller: _interesController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: _decoracion('Interés (opcional)'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 10),
                            Text('Fecha del abono', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                            const Spacer(),
                            Text(DateFormat('dd/MM/yyyy').format(_fecha), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _metodoPago,
                      decoration: _decoracion('Método de pago'),
                      style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                      items: _metodosPago.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _metodoPago = v);
                      },
                    ),
                    if (_metodoPago == 'Transferencia') ...[
                      const SizedBox(height: 14),
                      CampoTecladoCompacto(
                        controller: _numeroReciboController,
                        numerico: false,
                        child: TextField(
                          inputFormatters: [mayusculasInputFormatter],
                          autocorrect: false,
                          enableSuggestions: false,
                          controller: _numeroReciboController,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: _decoracion('No. de recibo (opcional)'),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Guardar Cambios', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
