import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../data/pago_detalle_model.dart';

/// Diálogo para repartir el total de una venta entre varios métodos de pago
/// (por ejemplo, parte en Efectivo y el resto en Transferencia). Devuelve la
/// lista de renglones {método, monto} cuando la suma cuadra exacto con el
/// total, o null si el cajero cancela.
class PagoMixtoDialog extends StatefulWidget {
  final double total;
  final List<String> metodosDisponibles;

  const PagoMixtoDialog({super.key, required this.total, this.metodosDisponibles = const ['Efectivo', 'Tarjeta', 'Transferencia']});

  @override
  State<PagoMixtoDialog> createState() => _PagoMixtoDialogState();
}

class _Renglon {
  String metodo;
  final TextEditingController controller;
  _Renglon({required this.metodo}) : controller = TextEditingController();
}

class _PagoMixtoDialogState extends State<PagoMixtoDialog> {
  late List<_Renglon> _renglones;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renglones = [
      _Renglon(metodo: widget.metodosDisponibles.first),
      _Renglon(metodo: widget.metodosDisponibles.length > 1 ? widget.metodosDisponibles[1] : widget.metodosDisponibles.first),
    ];
  }

  @override
  void dispose() {
    for (final r in _renglones) {
      r.controller.dispose();
    }
    super.dispose();
  }

  double _montoDe(_Renglon r) => double.tryParse(r.controller.text.replaceAll(',', '').trim()) ?? 0;

  double get _asignado => _renglones.fold<double>(0, (s, r) => s + _montoDe(r));

  double get _falta => widget.total - _asignado;

  void _agregarRenglon() {
    setState(() => _renglones.add(_Renglon(metodo: widget.metodosDisponibles.first)));
  }

  void _quitarRenglon(int index) {
    if (_renglones.length <= 1) return;
    setState(() {
      _renglones[index].controller.dispose();
      _renglones.removeAt(index);
    });
  }

  void _confirmar() {
    final conMonto = _renglones.where((r) => _montoDe(r) > 0).toList();
    if (conMonto.isEmpty) {
      setState(() => _error = 'Ingresá al menos un monto');
      return;
    }
    if (_falta.abs() > 0.01) {
      setState(() => _error = _falta > 0 ? 'Falta ${formatearMoneda(_falta)} por asignar' : 'Te pasaste por ${formatearMoneda(-_falta)}');
      return;
    }
    final resultado = conMonto.map((r) => PagoDetalle(metodoPago: r.metodo, monto: _montoDe(r))).toList();
    Navigator.pop(context, resultado);
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 440;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: tamano.height * 0.85),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pago mixto', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(color: const Color(0xFFFBEAEA), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL A PAGAR', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFC62828), letterSpacing: 0.5)),
                    Text(formatearMoneda(widget.total), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFFC62828))),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < _renglones.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          initialValue: _renglones[i].metodo,
                          isExpanded: true,
                          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFE8EAF0),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          items: widget.metodosDisponibles.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _renglones[i].metodo = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _renglones[i].controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Monto',
                            labelStyle: GoogleFonts.poppins(fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFFE8EAF0),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _renglones.length > 1 ? () => _quitarRenglon(i) : null,
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ),
              ],
              TextButton.icon(
                onPressed: _agregarRenglon,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Agregar método', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFC62828)),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Text(_falta.abs() <= 0.01 ? 'Completo' : (_falta > 0 ? 'Falta' : 'Sobra'), style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF3B82F6))),
                    const Spacer(),
                    Text(formatearMoneda(_falta.abs()), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF3B82F6))),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _confirmar,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Confirmar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
