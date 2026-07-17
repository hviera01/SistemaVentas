import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/venta_credito_model.dart';
import '../../data/abono_model.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../auth/providers/auth_provider.dart';

class RegistrarAbonoDialog extends ConsumerStatefulWidget {
  final VentaCreditoModel credito;

  const RegistrarAbonoDialog({super.key, required this.credito});

  @override
  ConsumerState<RegistrarAbonoDialog> createState() => _RegistrarAbonoDialogState();
}

class _RegistrarAbonoDialogState extends ConsumerState<RegistrarAbonoDialog> {
  final _montoAbonadoController = TextEditingController();
  final _interesController = TextEditingController(text: '0');
  final _numeroReciboController = TextEditingController();
  String _metodoPago = 'Efectivo';
  bool _guardando = false;
  String? _error;

  static const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];

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
  double get _saldoPendienteNuevo {
    final saldo = widget.credito.saldoPendiente - _montoAbonado + _interes;
    return saldo < 0 ? 0 : saldo;
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
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      final saldoAnterior = widget.credito.saldoPendiente;
      final saldoPendiente = _saldoPendienteNuevo;
      await ref.read(ventaCreditoRepositoryProvider).registrarAbono(
            idCredito: widget.credito.id,
            saldoAnterior: saldoAnterior,
            montoAbonado: _montoAbonado,
            interes: _interes,
            metodoPago: _metodoPago,
            numeroRecibo: _numeroReciboController.text.trim(),
            usuario: usuario,
          );
      if (!mounted) return;
      Navigator.pop(
        context,
        AbonoModel(
          id: '',
          fecha: DateTime.now(),
          montoAbonado: _montoAbonado,
          saldoAnterior: saldoAnterior,
          interes: _interes,
          saldoPendiente: saldoPendiente,
          metodoPago: _metodoPago,
          numeroRecibo: _numeroReciboController.text.trim(),
          usuario: usuario,
        ),
      );
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

  Widget _filaSoloLectura(String etiqueta, String valor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          const Spacer(),
          Text(valor, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 500;
    final anchoDialog = esMovil ? tamano.width - 48 : 440.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 660),
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
                    decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.payments_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Registrar Abono · ${widget.credito.numeroDocumento}',
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
                    TextField(
                      controller: _montoAbonadoController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Monto abonado'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _filaSoloLectura('Saldo anterior', formatearMoneda(widget.credito.saldoPendiente)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _interesController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Interés (opcional)'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _filaSoloLectura('Saldo pendiente', formatearMoneda(_saldoPendienteNuevo)),
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
                      TextField(
                        controller: _numeroReciboController,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: _decoracion('No. de recibo (opcional)'),
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
                        : Text('Registrar Abono', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
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
