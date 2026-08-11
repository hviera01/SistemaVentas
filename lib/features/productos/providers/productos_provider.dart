import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/producto_repository.dart';
import '../data/producto_model.dart';
import '../data/historial_stock_model.dart';
import '../data/historial_precio_compra_model.dart';
import '../data/historial_venta_producto_model.dart';
import '../data/lote_costo_model.dart';
import '../data/lote_costo_repository.dart';

final productoRepositoryProvider = Provider((ref) => ProductoRepository());

final loteCostoRepositoryProvider = Provider((ref) => LoteCostoRepository());

final lotesProductoProvider = StreamProvider.family<List<LoteCostoModel>, String>((ref, idProducto) {
  return ref.watch(loteCostoRepositoryProvider).obtenerLotes(idProducto);
});

final productosStreamProvider = StreamProvider<List<ProductoModel>>((ref) {
  return ref.watch(productoRepositoryProvider).obtenerProductos();
});

// FutureProvider.autoDispose (no StreamProvider): son historiales de solo
// lectura que no necesitan reactividad en vivo, así que se piden una sola
// vez en vez de dejar un listener de Firestore abierto mientras el diálogo
// está en pantalla. `autoDispose` es clave acá: sin él, un FutureProvider
// .family sin listeners igual mantiene cacheado para siempre el resultado
// de cada idProducto que se haya consultado alguna vez en la sesión, y al
// reabrir el historial de ese mismo producto se vería una foto vieja en vez
// de pedir de nuevo. Con autoDispose, al cerrar el diálogo (0 listeners) se
// descarta el caché y la próxima vez se vuelve a pedir fresco. Los diálogos
// que los consumen (`historial_stock_dialog.dart`,
// `historial_movimientos_dialog.dart`) siguen funcionando igual porque
// `AsyncValue.when` es compatible entre Stream y FutureProvider.
final historialStockProvider = FutureProvider.autoDispose.family<List<HistorialStockModel>, String>((ref, idProducto) {
  return ref.watch(productoRepositoryProvider).obtenerHistorialStock(idProducto);
});

final historialPreciosCompraProvider = FutureProvider.autoDispose.family<List<HistorialPrecioCompraModel>, String>((ref, idProducto) {
  return ref.watch(productoRepositoryProvider).obtenerHistorialPreciosCompra(idProducto);
});

final historialVentasProductoProvider = FutureProvider.autoDispose.family<List<HistorialVentaProductoModel>, String>((ref, idProducto) {
  return ref.watch(productoRepositoryProvider).obtenerHistorialVentas(idProducto);
});

class InventarioBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final inventarioBusquedaProvider = NotifierProvider<InventarioBusquedaNotifier, String>(InventarioBusquedaNotifier.new);

class InventarioVistaNotifier extends Notifier<String> {
  @override
  String build() => 'filtrados';
  void actualizar(String valor) => state = valor;
}

final inventarioVistaProvider = NotifierProvider<InventarioVistaNotifier, String>(InventarioVistaNotifier.new);