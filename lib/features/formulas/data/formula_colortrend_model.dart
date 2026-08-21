/// Un colorante y su cantidad dentro de una fórmula, en las 3 presentaciones
/// del libro (Quart/Gallon/5-Gallon). "cuarto"/"galon"/"cubeta5gal" son el
/// texto TAL CUAL lo imprime el libro (ej. "6", "0.5", "1Y42") -pedido
/// explícito: mostrar el dato real sin recalcularlo, para no arriesgar un
/// error de conversión-. Las versiones "*Oz" son ese mismo valor convertido
/// a onzas decimales, usadas solo para el estimado de Cuarto cuando el libro
/// no trae esa presentación (ver FormulaDetalleCard).
class ColoranteFormula {
  final String colorante;
  final String? cuarto;
  final double? cuartoOz;
  final String? galon;
  final double? galonOz;
  final String? cubeta5gal;
  final double? cubeta5galOz;

  const ColoranteFormula({
    required this.colorante,
    this.cuarto,
    this.cuartoOz,
    this.galon,
    this.galonOz,
    this.cubeta5gal,
    this.cubeta5galOz,
  });

  factory ColoranteFormula.fromMap(Map<String, dynamic> data) {
    return ColoranteFormula(
      colorante: data['colorante'] ?? '',
      cuarto: data['cuarto'] as String?,
      cuartoOz: (data['cuartoOz'] as num?)?.toDouble(),
      galon: data['galon'] as String?,
      galonOz: (data['galonOz'] as num?)?.toDouble(),
      cubeta5gal: data['cubeta5gal'] as String?,
      cubeta5galOz: (data['cubeta5galOz'] as num?)?.toDouble(),
    );
  }
}

/// Una fórmula de color del libro físico "Color Codex Formulas" (Chromaflo
/// Technologies, Colortrend). Datos estáticos: se extrajeron una sola vez
/// del PDF y viajan empaquetados en el asset formulas_colortrend.json -no
/// están en Firestore porque es una referencia fija que no cambia sola.
class FormulaColortrendModel {
  final String codigo;
  final String nombre;
  final String base;
  final int pagina;
  // false cuando el libro imprime literalmente "No Quart Formula" para esta
  // fórmula: no existe presentación de Quart, solo Gallon y 5-Gallon.
  final bool cuartoDisponible;
  final List<ColoranteFormula> colorantes;

  const FormulaColortrendModel({
    required this.codigo,
    required this.nombre,
    required this.base,
    required this.pagina,
    required this.cuartoDisponible,
    required this.colorantes,
  });

  factory FormulaColortrendModel.fromMap(Map<String, dynamic> data) {
    return FormulaColortrendModel(
      codigo: data['codigo'] ?? '',
      nombre: data['nombre'] ?? '',
      base: data['base'] ?? '',
      pagina: (data['pagina'] as num?)?.toInt() ?? 0,
      cuartoDisponible: data['cuartoDisponible'] ?? false,
      colorantes: ((data['colorantes'] as List?) ?? [])
          .map((c) => ColoranteFormula.fromMap(c as Map<String, dynamic>))
          .toList(),
    );
  }

  String get textoBusqueda => '$codigo $nombre $base';
}
