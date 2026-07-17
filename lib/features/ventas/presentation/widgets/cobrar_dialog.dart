import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/formato_moneda.dart';

class CobrarResultado {
  final double pagoCon;
  final double cambio;

  CobrarResultado({required this.pagoCon, required this.cambio});
}

class CobrarDialog extends StatefulWidget {
  final double total;

  const CobrarDialog({super.key, required this.total});

  @override
  State<CobrarDialog> createState() => _CobrarDialogState();
}

class _CobrarDialogState extends State<CobrarDialog> {
  final _pagoController = TextEditingController();
  String? _error;

  double get _pagoCon => double.tryParse(_pagoController.text.replaceAll(',', '').trim()) ?? 0;
  double get _cambio => _pagoCon > widget.total ? _pagoCon - widget.total : 0;

  @override
  void dispose() {
    _pagoController.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (_pagoCon < widget.total) {
      setState(() => _error = 'El pago debe ser al menos igual al total');
      return;
    }
    Navigator.pop(context, CobrarResultado(pagoCon: _pagoCon, cambio: _cambio));
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 440;
    final anchoDialog = esMovil ? tamano.width - 48 : 380.0;

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
            Text('Cobrar Factura', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
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
            TextField(
              controller: _pagoController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirmar(),
              decoration: InputDecoration(
                labelText: 'Paga con',
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Text('Cambio', style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF3B82F6))),
                  const Spacer(),
                  Text(formatearMoneda(_cambio), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF3B82F6))),
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
