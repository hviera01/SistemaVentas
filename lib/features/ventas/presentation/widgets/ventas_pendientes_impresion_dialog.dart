import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/impresion_pendiente_service.dart';
import '../../data/venta_model.dart';
import '../../providers/ventas_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../screens/detalle_venta_screen.dart';

/// Lista de ventas guardadas pero sin imprimir (típicamente hechas desde el
/// celular sin la impresora térmica a mano). Tocar una abre su detalle,
/// desde donde se puede reimprimir o marcar como impresa; el botón de
/// impresora permite imprimirla ahí mismo, sin salir de la lista.
class VentasPendientesImpresionDialog extends ConsumerStatefulWidget {
  const VentasPendientesImpresionDialog({super.key});

  @override
  ConsumerState<VentasPendientesImpresionDialog> createState() => _VentasPendientesImpresionDialogState();
}

class _VentasPendientesImpresionDialogState extends ConsumerState<VentasPendientesImpresionDialog> {
  final _servicioImpresion = ImpresionPendienteService();
  final _idsImprimiendo = <String>{};

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _imprimir(VentaModel ventaResumen) async {
    if (_idsImprimiendo.contains(ventaResumen.id)) return;
    setState(() => _idsImprimiendo.add(ventaResumen.id));
    try {
      final ventaRepo = ref.read(ventaRepositoryProvider);
      final venta = await ventaRepo.obtenerVentaPorId(ventaResumen.id);
      if (venta == null) {
        _mostrarMensaje('Esta venta ya no existe');
        return;
      }
      final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
      if (!mounted) return;
      await _servicioImpresion.imprimir(
        context: context,
        venta: venta,
        negocio: negocio,
        ventaRepo: ventaRepo,
        mostrarMensaje: _mostrarMensaje,
      );
    } finally {
      if (mounted) setState(() => _idsImprimiendo.remove(ventaResumen.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ventasAsync = ref.watch(ventasPendientesImpresionStreamProvider);
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
                Expanded(child: Text('Pendientes de Impresión', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ventasAsync.when(
                data: (ventas) {
                  if (ventas.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.print_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text('No hay ventas pendientes de impresión', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: ventas.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final venta = ventas[i];
                      final imprimiendo = _idsImprimiendo.contains(venta.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleVentaScreen(ventaIdInicial: venta.id)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFFFF8EC), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0A63C))),
                          child: Row(
                            children: [
                              Icon(Icons.print_disabled_outlined, size: 20, color: Colors.amber.shade800),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      venta.nombreCliente.isEmpty ? 'Sin cliente' : venta.nombreCliente,
                                      style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${venta.tipoDocumento} · ${venta.numeroDocumento} · ${formatearMoneda(venta.totalAPagar)}',
                                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
                                    ),
                                    if (venta.fechaRegistro != null) ...[
                                      const SizedBox(height: 2),
                                      Text(formatoFecha.format(venta.fechaRegistro!), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                                    ],
                                  ],
                                ),
                              ),
                              imprimiendo
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12),
                                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC62828))),
                                    )
                                  : IconButton(
                                      tooltip: 'Imprimir',
                                      icon: Icon(Icons.print_outlined, color: Colors.amber.shade800),
                                      onPressed: () => _imprimir(venta),
                                    ),
                              Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
