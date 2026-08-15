import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/compra_en_espera_model.dart';
import '../../providers/compras_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

class ComprasEnEsperaDialog extends ConsumerWidget {
  const ComprasEnEsperaDialog({super.key});

  Future<void> _eliminar(BuildContext context, WidgetRef ref, CompraEnEsperaModel sesion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar compra en espera', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar esta compra guardada?', style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await ref.read(compraRepositoryProvider).eliminarCompraEnEspera(sesion.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comprasAsync = ref.watch(comprasEnEsperaStreamProvider);
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 560;
    final anchoDialog = esMovil ? tamano.width - 24 : 520.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 40 : 560.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 16 : 22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Compras en Espera', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Compras guardadas automáticamente mientras estaban en curso (por ejemplo si se cerró la app o se perdió el internet a medio armar).',
              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: comprasAsync.when(
                data: (compras) {
                  if (compras.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_outline, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text('No hay compras en espera', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: compras.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final sesion = compras[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, sesion),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sesion.razonSocial.isEmpty ? 'Sin proveedor' : sesion.razonSocial,
                                      style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sesion.items.length} producto(s) · ${formatearMoneda(sesion.total)}',
                                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
                                    ),
                                    if (sesion.fecha != null) ...[
                                      const SizedBox(height: 2),
                                      Text(formatoFecha.format(sesion.fecha!), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFC62828)),
                                onPressed: () => _eliminar(context, ref, sesion),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
