import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

class TicketOpcionesDialog extends StatefulWidget {
  const TicketOpcionesDialog({super.key});

  @override
  State<TicketOpcionesDialog> createState() => _TicketOpcionesDialogState();
}

class _TicketOpcionesDialogState extends State<TicketOpcionesDialog> {
  final Set<String> _seleccionados = {'codigo', 'existencia', 'precioVenta'};

  final _opciones = const [
    {'key': 'codigo', 'label': 'Código'},
    {'key': 'descripcion', 'label': 'Descripción'},
    {'key': 'categoria', 'label': 'Categoría'},
    {'key': 'existencia', 'label': 'Existencia'},
    {'key': 'precioVenta', 'label': 'Precio de Venta'},
    {'key': 'precioCompra', 'label': 'Precio de Compra'},
  ];

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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.superficie, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Imprimir Ticket', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Elegí qué información incluir', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.gris600)),
            const SizedBox(height: 12),
            ..._opciones.map((op) {
              final key = op['key']!;
              return CheckboxListTile(
                value: _seleccionados.contains(key),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFFC62828),
                title: Text(op['label']!, style: GoogleFonts.poppins(fontSize: 13)),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _seleccionados.add(key);
                    } else {
                      _seleccionados.remove(key);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: AppColors.gris700))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _seleccionados),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Continuar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}