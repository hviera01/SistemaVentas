import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../proveedores/providers/proveedores_provider.dart';
import '../../../proveedores/data/proveedor_model.dart';

class RegistrarCreditoCompraDialog extends ConsumerStatefulWidget {
  const RegistrarCreditoCompraDialog({super.key});

  @override
  ConsumerState<RegistrarCreditoCompraDialog> createState() => _RegistrarCreditoCompraDialogState();
}

class _RegistrarCreditoCompraDialogState extends ConsumerState<RegistrarCreditoCompraDialog> {
  final _numeroDocumentoController = TextEditingController();
  final _noFacturaController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _saldoPendienteController = TextEditingController();
  ProveedorModel? _proveedor;
  DateTime _fechaVencimiento = DateTime.now().add(const Duration(days: 30));
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _noFacturaController.dispose();
    _montoTotalController.dispose();
    _saldoPendienteController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

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

  Future<void> _guardar() async {
    final proveedor = _proveedor;
    if (proveedor == null) {
      setState(() => _error = 'Seleccioná un proveedor');
      return;
    }
    final montoTotal = _parseDouble(_montoTotalController.text);
    if (montoTotal <= 0) {
      setState(() => _error = 'Ingresá un monto total válido');
      return;
    }
    final saldoTexto = _saldoPendienteController.text.trim();
    final saldoPendiente = saldoTexto.isEmpty ? montoTotal : _parseDouble(saldoTexto);

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(compraCreditoRepositoryProvider).crearCreditoManual(
            idProveedor: proveedor.id,
            documentoProveedor: proveedor.rtn,
            nombreProveedor: proveedor.razonSocial,
            numeroDocumento: _numeroDocumentoController.text.trim(),
            noFactura: _noFacturaController.text.trim(),
            montoTotal: montoTotal,
            saldoPendiente: saldoPendiente,
            fechaVencimiento: _fechaVencimiento,
          );
      if (mounted) Navigator.pop(context);
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
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 520;
    final anchoDialog = esMovil ? tamano.width - 48 : 460.0;

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
                    child: const Icon(Icons.credit_score_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Registrar Crédito de Compra', style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
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
                    Text(
                      'Usá esto para créditos de compra que no vienen de una compra registrada en el sistema (créditos anteriores, migraciones, etc.).',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    proveedoresAsync.when(
                      data: (proveedores) {
                        return DropdownButtonFormField<ProveedorModel>(
                          initialValue: _proveedor,
                          decoration: _decoracion('Proveedor'),
                          isExpanded: true,
                          style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                          items: proveedores.map((p) => DropdownMenuItem(value: p, child: Text(p.razonSocial, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _proveedor = v),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, st) => Text('Error cargando proveedores', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _numeroDocumentoController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('No. Documento (opcional)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _noFacturaController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('No. Factura'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _montoTotalController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Monto total'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _saldoPendienteController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Saldo pendiente'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Fecha de vencimiento', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Flexible(child: Text(formatoFecha.format(_fechaVencimiento), overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)))),
                          ],
                        ),
                      ),
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
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Registrar Crédito', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
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
