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
/// método de pago — para la pantalla de "consultar promociones vigentes".
List<PromocionModel> promocionesVigentes(List<PromocionModel> todas) {
  final ahora = DateTime.now();
  return todas.where((p) => p.vigente(ahora)).toList();
}

/// De entre las promociones de porcentaje/precio fijo vigentes, aplicables
/// al método de pago elegido y que incluyan [idProducto], devuelve la que le
/// da mayor beneficio al cliente (menor precio final por unidad). null si
/// ninguna aplica.
PromocionModel? mejorPromoPrecio({
  required List<PromocionModel> promociones,
  required String idProducto,
  required double precioActual,
  required String condicion,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final aplicables = promociones.where((p) =>
      p.esPorcentajeOFijo && p.vigente(momento) && p.aplicaCondicion(condicion) && p.aplicaAlProducto(idProducto));
  if (aplicables.isEmpty) return null;

  double precioFinal(PromocionModel p) {
    if (p.tipo == TipoPromocion.porcentaje) return precioActual * (1 - p.valor / 100);
    return p.valor;
  }

  return aplicables.reduce((mejor, actual) => precioFinal(actual) < precioFinal(mejor) ? actual : mejor);
}

/// De entre las promociones de combo/regalo vigentes, aplicables al método
/// de pago elegido y cuyo producto base sea [idProducto], la que se cumple
/// con [cantidadEnCarrito] unidades (la de mayor cantidadRequerida que sí se
/// alcanza, para no ofrecer un combo de 3 cuando ya se juntan 6 y hay uno
/// mejor). null si ninguna aplica.
PromocionModel? promoComboORegaloAplicable({
  required List<PromocionModel> promociones,
  required String idProducto,
  required double cantidadEnCarrito,
  required String condicion,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final aplicables = promociones
      .where((p) =>
          p.esComboORegalo &&
          p.vigente(momento) &&
          p.aplicaCondicion(condicion) &&
          p.aplicaAlProducto(idProducto) &&
          cantidadEnCarrito >= p.cantidadRequerida)
      .toList();
  if (aplicables.isEmpty) return null;
  aplicables.sort((a, b) => b.cantidadRequerida.compareTo(a.cantidadRequerida));
  return aplicables.first;
}

/// Para el badge/chip del buscador de productos: la promoción vigente y
/// aplicable al método de pago que toque a [idProducto], sin importar si ya
/// se alcanzó la cantidad requerida (acá solo se quiere avisar que existe,
/// no aplicarla todavía). Si hay varias, se prioriza porcentaje/precio fijo
/// (beneficio inmediato en cualquier cantidad) sobre combo/regalo.
PromocionModel? promoParaBadge({
  required List<PromocionModel> promociones,
  required String idProducto,
  required String condicion,
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final vigentesAplicables = promociones.where((p) => p.vigente(momento) && p.aplicaCondicion(condicion) && p.aplicaAlProducto(idProducto)).toList();
  if (vigentesAplicables.isEmpty) return null;
  vigentesAplicables.sort((a, b) => (a.esPorcentajeOFijo ? 0 : 1).compareTo(b.esPorcentajeOFijo ? 0 : 1));
  return vigentesAplicables.first;
}
