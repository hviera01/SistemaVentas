import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/venta_en_espera_model.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Mismo diálogo sirve para las dos pantallas -pedido explícito del dueño:
/// separar "Ver en Espera" (lo que el cajero pone en espera A PROPÓSITO,
/// con el stock reservado mientras tanto) de "Ver Perdidas" (autoguardados
/// silenciosos de un carrito que quedó a medias -se cerró la pestaña/la app
/// antes de confirmar o descartar-, nunca reservan stock). [perdidas]
/// decide de cuál de las dos colecciones filtradas lee (ver
/// VentaRepository.obtenerVentasEnEspera/obtenerVentasPerdidas) y los
/// textos; el resto del comportamiento (tocar una fila la recupera al
/// carrito, el ícono de basura la elimina -soltando la reserva de stock si
/// la tenía-) es idéntico para las dos.
class VentasEnEsperaDialog extends ConsumerWidget {
  final bool perdidas;
  const VentasEnEsperaDialog({super.key, this.perdidas = false});

  Future<void> _eliminar(BuildContext context, WidgetRef ref, VentaEnEsperaModel sesion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(perdidas ? 'Eliminar venta perdida' : 'Eliminar venta en espera', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          sesion.stockReservado
              ? '¿Seguro que querés eliminar esta venta guardada? El stock que tenía reservado se va a devolver al inventario.'
              : '¿Seguro que querés eliminar esta venta guardada?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
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
    if (confirmar != true) return;
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
    await ref.read(ventaRepositoryProvider).eliminarVentaEnEspera(sesion.id, usuario: usuario);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ventasAsync = ref.watch(perdidas ? ventasPerdidasStreamProvider : ventasEnEsperaStreamProvider);
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
                Expanded(child: Text(perdidas ? 'Facturas Perdidas' : 'Ventas en Espera', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            if (perdidas) ...[
              const SizedBox(height: 4),
              Text(
                'Ventas que quedaron a medias (se cerró antes de confirmarlas o descartarlas). No tienen stock reservado.',
                style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: ventasAsync.when(
                data: (ventas) {
                  if (ventas.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(perdidas ? Icons.find_in_page_outlined : Icons.pause_circle_outline, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(perdidas ? 'No hay facturas perdidas' : 'No hay ventas en espera', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: ventas.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final sesion = ventas[i];
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
                                      sesion.nombreCliente.isEmpty ? 'Sin cliente' : sesion.nombreCliente,
                                      style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      // totalFinal (con ISV y descuento global, lo que de verdad
                                      // pagaría el cliente) -pedido explícito del dueño: antes
                                      // salía el subtotal sin impuesto-.
                                      '${sesion.tipoDocumento} · ${sesion.items.length} producto(s) · ${formatearMoneda(sesion.totalFinal)}',
                                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
                                    ),
                                    if (sesion.fecha != null) ...[
                                      const SizedBox(height: 2),
                                      Text(formatoFecha.format(sesion.fecha!), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                                    ],
                                    if (sesion.stockReservado) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.lock_outline, size: 12, color: Color(0xFF1565C0)),
                                          const SizedBox(width: 4),
                                          Text('Stock reservado', style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                                        ],
                                      ),
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
