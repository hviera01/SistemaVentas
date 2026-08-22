import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/referidor_repository.dart';
import '../data/referidor_model.dart';

final referidorRepositoryProvider = Provider((ref) => ReferidorRepository());

final referidoresStreamProvider = StreamProvider<List<ReferidorModel>>((ref) {
  return ref.watch(referidorRepositoryProvider).obtenerReferidores();
});

class ReferidoresBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final referidoresBusquedaProvider = NotifierProvider<ReferidoresBusquedaNotifier, String>(ReferidoresBusquedaNotifier.new);

class ReferidoresVistaNotifier extends Notifier<String> {
  @override
  String build() => 'filtrados';
  void actualizar(String valor) => state = valor;
}

final referidoresVistaProvider = NotifierProvider<ReferidoresVistaNotifier, String>(ReferidoresVistaNotifier.new);
