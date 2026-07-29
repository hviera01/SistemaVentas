import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reportes/providers/reportes_provider.dart';

class ResumenVentasHome {
  final double totalDia;
  final double totalMes;
  final int cantidadVentasDia;

  const ResumenVentasHome({
    required this.totalDia,
    required this.totalMes,
    required this.cantidadVentasDia,
  });
}

/// Resumen en vivo de venta del día y del mes para la tarjeta de Inicio.
/// Se recalcula solo cuando se registra o anula una venta (stream de
/// Firestore), sin necesidad de refrescar la pantalla manualmente.
final resumenVentasHomeProvider = StreamProvider.autoDispose<ResumenVentasHome>((ref) {
  final ahora = DateTime.now();
  final inicioMes = DateTime(ahora.year, ahora.month, 1);
  final inicioHoy = DateTime(ahora.year, ahora.month, ahora.day);
  final finHoy = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);

  return ref.watch(reporteRepositoryProvider).observarReporteVentas(inicioMes, finHoy).map((lista) {
    final ventasValidas = lista.where((v) => v.esActiva && !v.esCotizacion);
    final totalMes = ventasValidas.fold<double>(0, (s, v) => s + v.totalAPagar);
    final ventasHoy = ventasValidas.where((v) {
      final f = v.fechaRegistro;
      return f != null && !f.isBefore(inicioHoy) && !f.isAfter(finHoy);
    }).toList();
    final totalDia = ventasHoy.fold<double>(0, (s, v) => s + v.totalAPagar);
    return ResumenVentasHome(totalDia: totalDia, totalMes: totalMes, cantidadVentasDia: ventasHoy.length);
  });
});
