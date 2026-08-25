/// Calculadora de cuánta pintura hace falta según el área a pintar -misma
/// lógica que `supercolor_web/src/lib/rendimiento.ts` (el sitio web público
/// tiene la misma calculadora, pedido explícito del dueño: "pongamos esa
/// calculadora en Registrar Venta también"). No hay forma de compartir
/// código entre un sitio Astro/TS y esta app Flutter/Dart, así que está
/// escrita dos veces a propósito -mantenerlas en sync a mano si se ajustan
/// los números de rendimiento.
///
/// El rendimiento (m² por galón) es un ESTIMADO por tipo de producto -pedido
/// explícito del dueño: sin cargar nada a mano por producto exacto ("hazlo
/// todo vos")-. Donde encontré una ficha técnica real de LANCO se usa ese
/// dato (látex general ~40 m²/galón; impermeabilizante Dry Coat: ~37
/// m²/galón como pintura o ~9.5 m²/galón como sellador, mucho más grueso);
/// donde no encontré ficha exacta (aceite, piscina, sellador/base) se usa
/// una cifra típica de la industria para ese tipo de producto.
enum TipoProductoPintura {
  latex,
  aceite,
  impermeabilizantePintura,
  impermeabilizanteSellador,
  piscina,
  selladorBase,
}

const _etiquetasTipoProducto = {
  TipoProductoPintura.latex: 'Látex (interior/exterior)',
  TipoProductoPintura.aceite: 'Esmalte / Aceite',
  TipoProductoPintura.impermeabilizantePintura: 'Impermeabilizante, usado como pintura',
  TipoProductoPintura.impermeabilizanteSellador: 'Impermeabilizante, usado como sellador (capa gruesa)',
  TipoProductoPintura.piscina: 'Pintura de piscina',
  TipoProductoPintura.selladorBase: 'Sellador / Base',
};

String etiquetaTipoProductoPintura(TipoProductoPintura t) => _etiquetasTipoProducto[t]!;

const _rendimientoM2PorGalon = {
  TipoProductoPintura.latex: 40.0,
  TipoProductoPintura.aceite: 32.0,
  TipoProductoPintura.impermeabilizantePintura: 37.0,
  TipoProductoPintura.impermeabilizanteSellador: 9.5,
  TipoProductoPintura.piscina: 22.0,
  TipoProductoPintura.selladorBase: 35.0,
};

class CompraSugeridaPintura {
  final int cubetas;
  final int galones;
  final int cuartos;
  const CompraSugeridaPintura({required this.cubetas, required this.galones, required this.cuartos});
}

class ResultadoRendimientoPintura {
  final double areaM2;
  final double galonesNecesarios;
  final CompraSugeridaPintura compra;
  const ResultadoRendimientoPintura({required this.areaM2, required this.galonesNecesarios, required this.compra});
}

double areaDesdeAnchoAlto(double anchoM, double altoM) {
  return (anchoM < 0 ? 0 : anchoM) * (altoM < 0 ? 0 : altoM);
}

double areaDesdeLineal(double metrosLineales, double alturaM) {
  return (metrosLineales < 0 ? 0 : metrosLineales) * (alturaM < 0 ? 0 : alturaM);
}

/// Cuartos (0.25gal), galones y cubetas (5gal) que cubren [galones]
/// necesarios, priorizando los tamaños más grandes -greedy de mayor a
/// menor, redondeando hacia arriba en el último tramo para no quedar corto.
CompraSugeridaPintura _sugerirCompra(double galones) {
  if (galones <= 0) return const CompraSugeridaPintura(cubetas: 0, galones: 0, cuartos: 0);
  var restante = galones;
  final cubetas = (restante / 5).floor();
  restante -= cubetas * 5;
  var galonesSueltos = restante.floor();
  restante = double.parse((restante - galonesSueltos).toStringAsFixed(3));
  var cuartos = (restante / 0.25 - 1e-9).ceil();
  if (cuartos >= 4) {
    cuartos = 0;
    galonesSueltos += 1;
  }
  return CompraSugeridaPintura(cubetas: cubetas, galones: galonesSueltos, cuartos: cuartos);
}

ResultadoRendimientoPintura calcularPintura(double areaM2, TipoProductoPintura tipo, int manos) {
  final rendimiento = _rendimientoM2PorGalon[tipo]!;
  final manosValidas = manos < 1 ? 1 : manos;
  final galonesNecesarios = double.parse(((areaM2 * manosValidas) / rendimiento).toStringAsFixed(3));
  return ResultadoRendimientoPintura(areaM2: areaM2, galonesNecesarios: galonesNecesarios, compra: _sugerirCompra(galonesNecesarios));
}
