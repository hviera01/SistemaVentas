import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/cliente_repository.dart';
import '../data/cliente_model.dart';
import '../data/cliente_historial_repository.dart';

final clienteRepositoryProvider = Provider((ref) => ClienteRepository());

final clienteHistorialRepositoryProvider = Provider((ref) => ClienteHistorialRepository());

final clientesStreamProvider = StreamProvider<List<ClienteModel>>((ref) {
  return ref.watch(clienteRepositoryProvider).obtenerClientes();
});

class ClientesBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final clientesBusquedaProvider = NotifierProvider<ClientesBusquedaNotifier, String>(ClientesBusquedaNotifier.new);

class ClientesVistaNotifier extends Notifier<String> {
  @override
  String build() => 'filtrados';
  void actualizar(String valor) => state = valor;
}

final clientesVistaProvider = NotifierProvider<ClientesVistaNotifier, String>(ClientesVistaNotifier.new);
