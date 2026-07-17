import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/venta_credito_model.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

class UnirFacturasDialog extends ConsumerStatefulWidget {
  final List<VentaCreditoModel> facturas;

  const UnirFacturasDialog({super.key, required this.facturas});

  @override
  ConsumerState<UnirFacturasDialog> createState() => _UnirFacturasDialogState();
}

class _UnirFacturasDialogState extends ConsumerState<UnirFacturasDialog> {
  final _documentoController = TextEditingController();
  final _nombreController = TextEditingController();
  late DateTime _fechaVencimiento;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final primera = widget.facturas.first;
    _documentoController.text = primera.documentoCliente == 'N/A' ? '' : primera.documentoCliente;
    _nombreController.text = primera.nombreCliente;
    _fechaVencimiento = DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _documentoController.dispose();
    _nombreController.dispose();
    super.dispose();
  }

  double get _totalUnificado => widget.facturas.fold<double>(0, (s, f) => s + f.saldoPendiente);

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaVencimiento,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() => _fechaVencimiento = fecha);
  }

  Future<void> _unir() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre del cliente es obligatorio');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(ventaCreditoRepositoryProvider).unirFacturas(
            facturas: widget.facturas,
            documentoCliente: _documentoController.text.trim(),
            nombreCliente: nombre,
            fechaVencimiento: _fechaVencimiento,
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
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 580;
    final anchoDialog = esMovil ? tamano.width - 48 : 520.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 700),
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
                    child: const Icon(Icons.call_merge_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Unir Facturas de Crédito', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                            child: Row(
                              children: [
                                Expanded(flex: 2, child: Text('FACTURA', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                                Expanded(flex: 3, child: Text('CLIENTE', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                                Expanded(flex: 2, child: Text('SALDO', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              ],
                            ),
                          ),
                          ...widget.facturas.map((f) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text(f.numeroDocumento, style: GoogleFonts.poppins(fontSize: 12.5))),
                                    Expanded(flex: 3, child: Text(f.nombreCliente, style: GoogleFonts.poppins(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text(formatearMoneda(f.saldoPendiente), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _documentoController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Documento cliente (opcional)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nombreController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Nombre cliente'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Fecha de vencimiento', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _seleccionarFecha,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                                      const SizedBox(width: 10),
                                      Text(formatoFecha.format(_fechaVencimiento), style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total unificado', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                                child: Text(formatearMoneda(_totalUnificado), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                    onPressed: _guardando ? null : _unir,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Unir Facturas', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
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
