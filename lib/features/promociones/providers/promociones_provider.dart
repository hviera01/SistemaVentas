import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/promocion_model.dart';
import '../data/promocion_repository.dart';

final promocionRepositoryProvider = Provider((ref) => PromocionRepository());

final promocionesStreamProvider = StreamProvider<List<PromocionModel>>((ref) {
  return ref.watch(promocionRepositoryProvider).obtenerPromociones();
});

class PromocionesBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final promocionesBusquedaProvider = NotifierProvider<PromocionesBusquedaNotifier, String>(PromocionesBusquedaNotifier.new);

/// Todas las promociones vigentes ahora mismo (fecha + activa), sin mirar
/// método de pago ni condición — para la pantalla de "consultar promociones
/// vigentes".
List<PromocionModel> promocionesVigentes(List<PromocionModel> todas) {
  final ahora = DateTime.now();
  return todas.where((p) => p.vigente(ahora)).toList();
}

/// De entre las promociones de porcentaje/precio fijo vigentes, aplicables a
/// la condición y método de pago elegidos y que incluyan [idProducto],
/// devuelve la que le da mayor beneficio al cliente (menor precio final por
/// unidad). null si ninguna aplica.
PromocionModel? mejorPromoPrecio({
  required List<PromocionModel> promociones,
  required String idProducto,
  required double precioActual,
  required String condicion,
  required String metodoPago,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final aplicables = promociones.where((p) =>
      p.esPorcentajeOFijo &&
      p.vigente(momento) &&
      p.aplicaCondicion(condicion) &&
      p.aplicaMetodoPago(metodoPago) &&
      p.aplicaAlProducto(idProducto));
  if (aplicables.isEmpty) return null;

  double precioFinal(PromocionModel p) {
    if (p.tipo == TipoPromocion.porcentaje) return precioActual * (1 - p.valor / 100);
    return p.valor;
  }

  return aplicables.reduce((mejor, actual) => precioFinal(actual) < precioFinal(mejor) ? actual : mejor);
}

/// De entre las promociones de combo por cantidad/regalo vigentes,
/// aplicables a la condición y método de pago elegidos y cuyo producto base
/// sea [idProducto], la que se cumple con [cantidadEnCarrito] unidades (la
/// de mayor cantidadRequerida que sí se alcanza, para no ofrecer un combo de
/// 3 cuando ya se juntan 6 y hay uno mejor). null si ninguna aplica.
PromocionModel? promoComboORegaloAplicable({
  required List<PromocionModel> promociones,
  required String idProducto,
  required double cantidadEnCarrito,
  required String condicion,
  required String metodoPago,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final aplicables = promociones
      .where((p) =>
          p.esComboORegalo &&
          p.vigente(momento) &&
          p.aplicaCondicion(condicion) &&
          p.aplicaMetodoPago(metodoPago) &&
          p.aplicaAlProducto(idProducto) &&
          cantidadEnCarrito >= p.cantidadRequerida)
      .toList();
  if (aplicables.isEmpty) return null;
  aplicables.sort((a, b) => b.cantidadRequerida.compareTo(a.cantidadRequerida));
  return aplicables.first;
}

/// De entre las promociones de combo multiproducto vigentes y aplicables a
/// la condición y método de pago elegidos, que incluyan a [idProducto] entre
/// sus productos del combo, la primera para la cual YA está en el carrito al
/// menos 1 unidad de CADA uno de sus productos (ver [cantidadesEnCarrito]:
/// idProducto -> cantidad total en el carrito). null si ninguna está
/// completa todavía (falta agregar algún producto del combo).
PromocionModel? promoComboMultiproductoAplicable({
  required List<PromocionModel> promociones,
  required String idProducto,
  required Map<String, double> cantidadesEnCarrito,
  required String condicion,
  required String metodoPago,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final aplicables = promociones.where((p) =>
      p.tipo == TipoPromocion.comboMultiproducto &&
      p.vigente(momento) &&
      p.aplicaCondicion(condicion) &&
      p.aplicaMetodoPago(metodoPago) &&
      p.idsProductosCombo.contains(idProducto));
  for (final p in aplicables) {
    final completo = p.idsProductosCombo.every((id) => (cantidadesEnCarrito[id] ?? 0) >= 1);
    if (completo) return p;
  }
  return null;
}

/// Para el badge/chip del buscador de productos: la promoción vigente y
/// aplicable a la condición y método de pago que toque a [idProducto], sin
/// importar si ya se alcanzó la cantidad requerida o si ya están todos los
/// productos del combo en el carrito (acá solo se quiere avisar que existe,
/// no aplicarla todavía). Si hay varias, se prioriza porcentaje/precio fijo
/// (beneficio inmediato en cualquier cantidad) sobre combo/regalo/combo
/// multiproducto.
PromocionModel? promoParaBadge({
  required List<PromocionModel> promociones,
  required String idProducto,
  required String condicion,
  required String metodoPago,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final vigentesAplicables = promociones
      .where((p) => p.vigente(momento) && p.aplicaCondicion(condicion) && p.aplicaMetodoPago(metodoPago) && p.aplicaAlProducto(idProducto))
      .toList();
  if (vigentesAplicables.isEmpty) return null;
  vigentesAplicables.sort((a, b) => (a.esPorcentajeOFijo ? 0 : 1).compareTo(b.esPorcentajeOFijo ? 0 : 1));
  return vigentesAplicables.first;
}
