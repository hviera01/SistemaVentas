import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/venta_repository.dart';
import '../data/venta_en_espera_model.dart';
import '../data/venta_model.dart';
import '../data/presencia_impresion_repository.dart';

final ventaRepositoryProvider = Provider((ref) => VentaRepository());

final presenciaImpresionRepositoryProvider = Provider((ref) => PresenciaImpresionRepository());

final ventasEnEsperaStreamProvider = StreamProvider<List<VentaEnEsperaModel>>((ref) {
  return ref.watch(ventaRepositoryProvider).obtenerVentasEnEspera();
});

final ventasPendientesImpresionStreamProvider = StreamProvider<List<VentaModel>>((ref) {
  return ref.watch(ventaRepositoryProvider).obtenerVentasPendientesImpresion();
});

final ventasConSolicitudImpresionEnVivoStreamProvider = StreamProvider<List<VentaModel>>((ref) {
  return ref.watch(ventaRepositoryProvider).obtenerVentasConSolicitudImpresionEnVivo();
});
