import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/compra_credito_model.dart';
import '../../data/compra_credito_repository.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../auth/providers/auth_provider.dart';

class _ProveedorConDeuda {
  final String idProveedor;
  final String nombreProveedor;
  final double deudaTotal;

  _ProveedorConDeuda({required this.idProveedor, required this.nombreProveedor, required this.deudaTotal});
}

class AbonoGeneralDialog extends ConsumerStatefulWidget {
  final List<CompraCreditoModel> comprasConDeuda;

  const AbonoGeneralDialog({super.key, required this.comprasConDeuda});

  @override
  ConsumerState<AbonoGeneralDialog> createState() => _AbonoGeneralDialogState();
}

class _AbonoGeneralDialogState extends ConsumerState<AbonoGeneralDialog> {
  final _montoController = TextEditingController();
  final _numeroReciboController = TextEditingController();
  String? _idProveedorSeleccionado;
  String _metodoPago = 'Efectivo';
  bool _guardando = false;
  String? _error;

  static const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  @override
  void dispose() {
    _montoController.dispose();
    _numeroReciboController.dispose();
    super.dispose();
  }

  List<_ProveedorConDeuda> get _proveedores {
    final mapa = <String, _ProveedorConDeuda>{};
    for (final c in widget.comprasConDeuda) {
      final existente = mapa[c.idProveedor];
      if (existente == null) {
        mapa[c.idProveedor] = _ProveedorConDeuda(idProveedor: c.idProveedor, nombreProveedor: c.nombreProveedor, deudaTotal: c.saldoPendiente);
      } else {
        mapa[c.idProveedor] = _ProveedorConDeuda(idProveedor: c.idProveedor, nombreProveedor: c.nombreProveedor, deudaTotal: existente.deudaTotal + c.saldoPendiente);
      }
    }
    final lista = mapa.values.toList();
    lista.sort((a, b) => a.nombreProveedor.compareTo(b.nombreProveedor));
    return lista;
  }

  List<CompraCreditoModel> get _comprasDelProveedor {
    if (_idProveedorSeleccionado == null) return [];
    return widget.comprasConDeuda.where((c) => c.idProveedor == _idProveedorSeleccionado).toList();
  }

  List<DistribucionAbono> get _distribucion {
    final monto = _parseDouble(_montoController.text);
    if (monto <= 0 || _idProveedorSeleccionado == null) return [];
    return ref.read(compraCreditoRepositoryProvider).calcularDistribucion(_comprasDelProveedor, monto);
  }

  Future<void> _confirmar() async {
    final monto = _parseDouble(_montoController.text);
    if (_idProveedorSeleccionado == null) {
      setState(() => _error = 'Seleccioná un proveedor');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'Ingresá un monto válido');
      return;
    }
    final deudaTotal = _comprasDelProveedor.fold<double>(0, (s, c) => s + c.saldoPendiente);
    if (monto > deudaTotal) {
      setState(() => _error = 'El monto supera la deuda total del proveedor (${formatearMoneda(deudaTotal)})');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      await ref.read(compraCreditoRepositoryProvider).registrarAbonoGeneral(
            distribucion: _distribucion,
            metodoPago: _metodoPago,
            usuario: usuario,
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
    final proveedores = _proveedores;
    final deudaTotal = _comprasDelProveedor.fold<double>(0, (s, c) => s + c.saldoPendiente);
    final distribucion = _distribucion;
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 560;
    final anchoDialog = esMovil ? tamano.width - 48 : 500.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 720),
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
                    child: const Icon(Icons.call_split_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Abono General por Proveedor', style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
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
                      'Ingresá un monto total y se reparte automáticamente entre las facturas pendientes del proveedor, pagando primero las que vencen antes.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _idProveedorSeleccionado,
                      decoration: _decoracion('Proveedor'),
                      isExpanded: true,
                      style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                      items: proveedores
                          .map((p) => DropdownMenuItem(value: p.idProveedor, child: Text('${p.nombreProveedor} · ${formatearMoneda(p.deudaTotal)}', overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _idProveedorSeleccionado = v),
                    ),
                    if (_idProveedorSeleccionado != null) ...[
                      const SizedBox(height: 10),
                      Text('Deuda total del proveedor: ${formatearMoneda(deudaTotal)}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: _montoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Monto a abonar'),
                      onChanged: (_) => setState(() {}),
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
                    if (distribucion.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Así se va a repartir:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                      const SizedBox(height: 8),
                      ...distribucion.map((d) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('Factura ${d.compra.noFactura}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ),
                                  Text('${formatearMoneda(d.montoAplicado)} → ', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                                  Text(
                                    d.saldoResultante <= 0 ? 'Liquidada' : formatearMoneda(d.saldoResultante),
                                    style: GoogleFonts.poppins(fontSize: 12, color: d.saldoResultante <= 0 ? const Color(0xFF16A34A) : Colors.grey.shade600, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          )),
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
                    onPressed: _guardando ? null : _confirmar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Confirmar Abono', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
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
