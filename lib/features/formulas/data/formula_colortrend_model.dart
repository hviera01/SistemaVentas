/// Un colorante y su cantidad dentro de una fórmula, en las 3 presentaciones
/// del libro (Quart/Gallon/5-Gallon). Las cantidades ya vienen convertidas a
/// onzas decimales (el libro las imprime en onzas y 48avos -ver
/// FormulasColortrendService- así que 1 unidad impresa sin "Y" es 1/48 oz).
class ColoranteFormula {
  final String colorante;
  final double? cuartoOz;
  final double? galonOz;
  final double? cubeta5galOz;

  const ColoranteFormula({required this.colorante, this.cuartoOz, this.galonOz, this.cubeta5galOz});

  factory ColoranteFormula.fromMap(Map<String, dynamic> data) {
    return ColoranteFormula(
      colorante: data['colorante'] ?? '',
      cuartoOz: (data['cuartoOz'] as num?)?.toDouble(),
      galonOz: (data['galonOz'] as num?)?.toDouble(),
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
