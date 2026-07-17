import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../auth/providers/auth_provider.dart';

class AjusteStockDialog extends ConsumerStatefulWidget {
  final ProductoModel producto;

  const AjusteStockDialog({super.key, required this.producto});

  @override
  ConsumerState<AjusteStockDialog> createState() => _AjusteStockDialogState();
}

class _AjusteStockDialogState extends ConsumerState<AjusteStockDialog> {
  late TextEditingController _stockController;
  final _motivoController = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stockController = TextEditingController(text: widget.producto.stock.toString());
  }

  @override
  void dispose() {
    _stockController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nuevoStock = double.tryParse(_stockController.text.replaceAll(',', '').trim());
    if (nuevoStock == null) {
      setState(() => _error = 'Ingresá un número válido');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final usuario = ref.read(authProvider).usuario;
      await ref.read(productoRepositoryProvider).ajustarStock(
        id: widget.producto.id,
        stockActual: widget.producto.stock,
        stockNuevo: nuevoStock,
        usuario: usuario?.nombreCompleto ?? 'Sistema',
        motivo: _motivoController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
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
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajustar Existencia', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            Text('Existencia actual: ${widget.producto.stock}', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            TextField(
              controller: _stockController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Nueva existencia',
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _motivoController,
              maxLines: 2,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Motivo (opcional)',
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                const Spacer(),
                TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                      : Text('Guardar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}