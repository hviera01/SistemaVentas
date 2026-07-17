import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import 'buscar_producto_dialog.dart';

class ReembaseResultado {
  final ProductoModel productoBase;
  final String tipo;

  ReembaseResultado({required this.productoBase, required this.tipo});
}

const opcionesReembase = {
  'GalonACuarto': 'Galón a Cuarto (1/4 de galón)',
  'CubetaACuarto': 'Cubeta a Cuarto (1/4 de cubeta)',
  'CubetaAGalon': 'Cubeta a Galón',
  'GalonAMedioCuarto': 'Galón a Medio Cuarto (1/8 de galón)',
};

class ReembaseDialog extends StatefulWidget {
  const ReembaseDialog({super.key});

  @override
  State<ReembaseDialog> createState() => _ReembaseDialogState();
}

class _ReembaseDialogState extends State<ReembaseDialog> {
  ProductoModel? _productoBase;
  String _tipo = 'GalonACuarto';

  Future<void> _seleccionarProductoBase() async {
    final resultado = await Navigator.of(context).push<ProductoConPrecio>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoDialog()),
    );
    if (resultado != null) setState(() => _productoBase = resultado.producto);
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
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
                Expanded(child: Text('Reembasado', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'No hay stock suficiente. Elegí de qué producto se va a descontar y en qué proporción.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _seleccionarProductoBase,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _productoBase?.nombre ?? 'Seleccionar producto base',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 13, color: _productoBase == null ? Colors.grey.shade500 : const Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Tipo de reembasado', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ...opcionesReembase.entries.map((entrada) => RadioListTile<String>(
                  value: entrada.key,
                  groupValue: _tipo,
                  onChanged: (v) => setState(() => _tipo = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFC62828),
                  title: Text(entrada.value, style: GoogleFonts.poppins(fontSize: 12.5)),
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _productoBase == null
                      ? null
                      : () => Navigator.pop(context, ReembaseResultado(productoBase: _productoBase!, tipo: _tipo)),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Confirmar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
