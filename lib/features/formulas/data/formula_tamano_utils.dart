import 'formula_colortrend_model.dart';

/// Tamaño de presentación de una fórmula del libro Color Codex -ver
/// FormulaColortrendModel- más "quinto", que no existe como columna propia
/// en el libro pero sí es un tamaño real de producto de este negocio (ver
/// [onzasFormulaParaTamano]).
enum TamanoFormula { cuarto, galon, cubeta5gal, quinto }

String etiquetaTamano(TamanoFormula t) {
  switch (t) {
    case TamanoFormula.cuarto:
      return 'Cuarto';
    case TamanoFormula.galon:
      return 'Galón';
    case TamanoFormula.cubeta5gal:
      return 'Cubeta 5 Gal.';
    case TamanoFormula.quinto:
      return 'Quinto';
  }
}

/// Determina el tamaño de fórmula que corresponde a un producto de pintura
/// real, a partir del PREFIJO de tamaño en su nombre -confirmado contra
/// datos reales de producción: los productos de pintura de este negocio
/// arrancan con la palabra de su tamaño, ej. "CUARTO TOTAL LATEX PALMA
/// VERDE", "GALON TOTAL ACEITE BLANCO", "QUINTO TOTAL LATEX MELON", "QUINTO
/// SUPRA SATIN DEEP". Si el nombre no arranca con ninguna de las 4 palabras
/// reconocidas, devuelve null -mejor no calcular el costo de tinte que
/// adivinar mal un tamaño y calcular un costo real equivocado (pedido
/// explícito del dueño)-.
TamanoFormula? tamanoDesdeNombreProducto(String nombreProducto) {
  final nombre = nombreProducto.trim().toUpperCase();
  if (nombre.startsWith('CUARTO')) return TamanoFormula.cuarto;
  if (nombre.startsWith('GALON') || nombre.startsWith('GALÓN')) return TamanoFormula.galon;
  if (nombre.startsWith('QUINTO')) return TamanoFormula.quinto;
  if (nombre.startsWith('CUBETA')) return TamanoFormula.cubeta5gal;
  return null;
}

/// Onzas de UN colorante para un tamaño dado, según la fórmula, más si ese
/// valor es un dato real del libro o un estimado calculado:
/// - CUARTO: valor real del libro si `formula.cuartoDisponible`, si no
///   Galón ÷ 4 -mismo estimado que ya usa FormulaDetalleCard, marcado igual
///   de aproximado-.
/// - GALÓN / CUBETA 5 GAL.: valor real del libro.
/// - QUINTO: no existe en el libro -un quinto es exactamente 1/5 de un
///   galón, así que se deriva como Galón ÷ 5 (más preciso que aproximar vía
///   Cuarto), pero SIEMPRE como estimado: es un valor derivado, no impreso
///   en el libro físico.
/// Devuelve null si no hay forma de resolverlo (ni el dato real ni el
/// insumo -Galón- para estimarlo).
({double onzas, bool esEstimado})? onzasColoranteParaTamano(FormulaColortrendModel formula, ColoranteFormula colorante, TamanoFormula tamano) {
  switch (tamano) {
    case TamanoFormula.cuarto:
      if (formula.cuartoDisponible && colorante.cuartoOz != null) return (onzas: colorante.cuartoOz!, esEstimado: false);
      if (colorante.galonOz != null) return (onzas: colorante.galonOz! / 4, esEstimado: true);
      return null;
    case TamanoFormula.galon:
      if (colorante.galonOz != null) return (onzas: colorante.galonOz!, esEstimado: false);
      return null;
    case TamanoFormula.cubeta5gal:
      if (colorante.cubeta5galOz != null) return (onzas: colorante.cubeta5galOz!, esEstimado: false);
      return null;
    case TamanoFormula.quinto:
      if (colorante.galonOz != null) return (onzas: colorante.galonOz! / 5, esEstimado: true);
      return null;
  }
}

/// Onzas de CADA colorante de la fórmula para un tamaño dado -ver
/// [onzasColoranteParaTamano]-, ya multiplicadas por [cantidadLinea] (cuántas
/// unidades de ese tamaño vende la línea del carrito). Los colorantes sin
/// valor resoluble para ese tamaño se excluyen de la lista en vez de
/// agregarse como "0 onzas" -caso raro de datos incompletos del libro, no
/// hay nada razonable que inventar ahí-.
List<({String colorante, double onzas, bool esEstimado})> onzasFormulaParaTamano(FormulaColortrendModel formula, TamanoFormula tamano, double cantidadLinea) {
  final resultado = <({String colorante, double onzas, bool esEstimado})>[];
  for (final c in formula.colorantes) {
    final valor = onzasColoranteParaTamano(formula, c, tamano);
    if (valor == null) continue;
    resultado.add((colorante: c.colorante, onzas: valor.onzas * cantidadLinea, esEstimado: valor.esEstimado));
  }
  return resultado;
}
