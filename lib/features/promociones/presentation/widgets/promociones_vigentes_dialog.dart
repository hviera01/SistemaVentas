import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/promocion_model.dart';
import '../../providers/promociones_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Consulta rápida de todas las promociones vigentes ahora mismo, para que
/// el cajero no tenga que ir producto por producto en el buscador para
/// enterarse qué está en oferta. Se abre desde Registrar Venta.
class PromocionesVigentesDialog extends ConsumerWidget {
  const PromocionesVigentesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promocionesAsync = ref.watch(promocionesStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 640 ? tamano.width - 24 : 520.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 40 : 560.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer_outlined, color: Color(0xFFC62828)),
                const SizedBox(width: 8),
                Expanded(child: Text('Promociones Vigentes', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Todas las promociones activas y dentro de fecha, ahora mismo.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 14),
            Expanded(
              child: promocionesAsync.when(
                data: (todas) {
                  final vigentes = promocionesVigentes(todas);
                  if (vigentes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text('No hay promociones vigentes ahora mismo', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: vigentes.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _tarjeta(vigentes[i]),
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

  Widget _tarjeta(PromocionModel p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(p.etiquetaCorta, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_descripcion(p), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
          if (p.alcancePago != 'Todos') ...[
            const SizedBox(height: 4),
            Text('Solo aplica a ventas al ${p.alcancePago}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  String _descripcion(PromocionModel p) {
    switch (p.tipo) {
      case TipoPromocion.porcentaje:
        return 'Aplica a: ${p.nombresProductos.join(', ')}';
      case TipoPromocion.precioFijo:
        return '${formatearMoneda(p.valor)} c/u en: ${p.nombresProductos.join(', ')}';
      case TipoPromocion.comboCantidad:
        return 'Llevando ${p.cantidadRequerida} de "${p.nombreProductoBase}", se pagan ${formatearMoneda(p.precioCombo)} en total.';
      case TipoPromocion.regalo:
        return 'Llevando ${p.cantidadRequerida} de "${p.nombreProductoBase}", se regalan ${p.cantidadRegalo} de "${p.nombreProductoRegalo}".';
    }
  }
}
