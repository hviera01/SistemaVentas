import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/venta_credito_repository.dart';
import '../data/venta_credito_model.dart';
import '../data/abono_model.dart';
import '../data/presencia_aviso_whatsapp_repository.dart';

final ventaCreditoRepositoryProvider = Provider((ref) => VentaCreditoRepository());

final presenciaAvisoWhatsappRepositoryProvider = Provider((ref) => PresenciaAvisoWhatsappRepository());

final ventasCreditoStreamProvider = StreamProvider<List<VentaCreditoModel>>((ref) {
  return ref.watch(ventaCreditoRepositoryProvider).obtenerCreditos();
});

final abonosStreamProvider = StreamProvider.family<List<AbonoModel>, String>((ref, idCredito) {
  return ref.watch(ventaCreditoRepositoryProvider).obtenerAbonos(idCredito);
});

class VentasCreditoBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final ventasCreditoBusquedaProvider = NotifierProvider<VentasCreditoBusquedaNotifier, String>(VentasCreditoBusquedaNotifier.new);

class VentasCreditoVistaNotifier extends Notifier<String> {
  @override
  String build() => 'debe';
  void actualizar(String valor) => state = valor;
}

final ventasCreditoVistaProvider = NotifierProvider<VentasCreditoVistaNotifier, String>(VentasCreditoVistaNotifier.new);
