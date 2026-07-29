import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dispositivo_model.dart';
import '../data/dispositivo_repository.dart';

final dispositivoRepositoryProvider = Provider((ref) => DispositivoRepository());

final dispositivosStreamProvider = StreamProvider<List<DispositivoModel>>((ref) {
  return ref.watch(dispositivoRepositoryProvider).obtenerDispositivos();
});
