import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/compra_credito_model.dart';
import '../../data/abono_compra_model.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

class HistorialAbonosCompraDialog extends ConsumerWidget {
  final CompraCreditoModel compra;

  const HistorialAbonosCompraDialog({super.key, required this.compra});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abonosAsync = ref.watch(abonosCompraStreamProvider(compra.id));
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;
    final anchoDialog = esMovil ? tamano.width - 24 : (tamano.width - 48).clamp(0, 1100).toDouble();
    final altoDialog = tamano.height < 700 ? tamano.height - 40 : 640.0;

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
                Expanded(
                  child: Text('Historial de Abonos · ${compra.noFactura}', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text(compra.nombreProveedor, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            Expanded(
              child: abonosAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                data: (abonos) {
                  if (abonos.isEmpty) {
                    return Center(child: Text('Todavía no hay abonos registrados', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)));
                  }
                  return esMovil ? _tarjetas(abonos) : _tabla(abonos);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabla(List<AbonoCompraModel> abonos) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(
              children: [
                _celdaHeader('FECHA', 3),
                _celdaHeader('MONTO ABONADO', 2),
                _celdaHeader('SALDO ANTERIOR', 2),
                _celdaHeader('INTERÉS', 2),
                _celdaHeader('SALDO PENDIENTE', 2),
                _celdaHeader('MÉTODO DE PAGO', 2),
                _celdaHeader('RECIBO', 2),
                _celdaHeader('USUARIO', 2),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: abonos.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final a = abonos[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      _celda(3, a.fecha != null ? formatoFecha.format(a.fecha!) : '-'),
                      _celda(2, formatearMoneda(a.montoAbonado), peso: FontWeight.w700, color: const Color(0xFF16A34A)),
                      _celda(2, formatearMoneda(a.saldoAnterior)),
                      _celda(2, a.interes > 0 ? formatearMoneda(a.interes) : '-'),
                      _celda(2, formatearMoneda(a.saldoPendiente), peso: FontWeight.w700),
                      _celda(2, a.metodoPago),
                      _celda(2, a.numeroRecibo.isEmpty ? '-' : a.numeroRecibo),
                      _celda(2, a.usuario.isEmpty ? '-' : a.usuario),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
    );
  }

  Widget _celda(int flex, String texto, {FontWeight peso = FontWeight.w400, Color? color}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(texto, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 12, fontWeight: peso, color: color ?? const Color(0xFF1A1A1A))),
      ),
    );
  }

  Widget _tarjetas(List<AbonoCompraModel> abonos) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return ListView.separated(
      itemCount: abonos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final a = abonos[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(formatearMoneda(a.montoAbonado), style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A))),
                  const Spacer(),
                  Text(a.fecha != null ? formatoFecha.format(a.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Saldo anterior: ${formatearMoneda(a.saldoAnterior)} → Saldo pendiente: ${formatearMoneda(a.saldoPendiente)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
              if (a.interes > 0) ...[
                const SizedBox(height: 4),
                Text('Interés aplicado: ${formatearMoneda(a.interes)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(a.metodoPago, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  if (a.numeroRecibo.isNotEmpty) Text(' · Recibo: ${a.numeroRecibo}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  if (a.usuario.isNotEmpty) Text(' · ${a.usuario}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
