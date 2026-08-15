import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/compra_en_espera_model.dart';
import '../data/compra_repository.dart';

final compraRepositoryProvider = Provider((ref) => CompraRepository());

final comprasEnEsperaStreamProvider = StreamProvider<List<CompraEnEsperaModel>>((ref) {
  return ref.watch(compraRepositoryProvider).obtenerComprasEnEspera();
});
