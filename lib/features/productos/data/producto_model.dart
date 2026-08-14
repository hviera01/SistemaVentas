/// Un componente de la receta de un producto tipo combo/kit: apunta a un
/// producto individual real (con su propio stock/lotes) y cuántas unidades
/// de ese producto lleva cada unidad del combo.
class ComponenteProductoModel {
  final String idProducto;
  final double cantidad;

  ComponenteProductoModel({required this.idProducto, required this.cantidad});

  Map<String, dynamic> toMap() => {'idProducto': idProducto, 'cantidad': cantidad};

  factory ComponenteProductoModel.fromMap(Map<String, dynamic> data) {
    return ComponenteProductoModel(
      idProducto: data['idProducto'] ?? '',
      cantidad: (data['cantidad'] ?? 0).toDouble(),
    );
  }
}

class ProductoModel {
  final String id;
  final String codigo;
  final String codigoBarras;
  final String nombre;
  final String descripcion;
  final String idCategoria;
  final double stock;
  final double precioCompra;
  final double precioVenta;
  final double precioVenta2;
  final double precioVenta3;
  final bool estado;
  final String imagenUrl;
  final bool esCombo;
  final List<ComponenteProductoModel> componentes;

  ProductoModel({
    required this.id,
    required this.codigo,
    required this.codigoBarras,
    required this.nombre,
    required this.descripcion,
    required this.idCategoria,
    required this.stock,
    required this.precioCompra,
    required this.precioVenta,
    required this.precioVenta2,
    required this.precioVenta3,
    required this.estado,
    this.imagenUrl = '',
    this.esCombo = false,
    this.componentes = const [],
  });

  factory ProductoModel.fromMap(String id, Map<String, dynamic> data) {
    return ProductoModel(
      id: id,
      codigo: data['codigo'] ?? '',
      codigoBarras: data['codigoBarras'] ?? '',
      nombre: data['nombre'] ?? '',
      descripcion: data['descripcion'] ?? '',
      idCategoria: data['idCategoria'] ?? '',
      stock: (data['stock'] ?? 0).toDouble(),
      precioCompra: (data['precioCompra'] ?? 0).toDouble(),
      precioVenta: (data['precioVenta'] ?? 0).toDouble(),
      precioVenta2: (data['precioVenta2'] ?? 0).toDouble(),
      precioVenta3: (data['precioVenta3'] ?? 0).toDouble(),
      estado: data['estado'] ?? true,
      imagenUrl: data['imagenUrl'] ?? '',
      esCombo: data['esCombo'] ?? false,
      componentes: (data['componentes'] as List<dynamic>? ?? [])
          .map((c) => ComponenteProductoModel.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }

  String get textoBusqueda => '$codigo $codigoBarras $nombre $descripcion';

  /// Existencia estimada del combo según lo que hay disponible de cada
  /// componente (mínimo entre todos, dividido por la cantidad que lleva cada
  /// uno). Es solo informativo: nunca bloquea una venta si da 0 o negativo.
  double stockDisponibleCombo(Map<String, ProductoModel> mapaProductos) {
    if (componentes.isEmpty) return 0;
    double? minimo;
    for (final c in componentes) {
      if (c.cantidad <= 0) continue;
      final stockComponente = mapaProductos[c.idProducto]?.stock ?? 0;
      final disponible = (stockComponente / c.cantidad).floorToDouble();
      if (minimo == null || disponible < minimo) minimo = disponible;
    }
    return minimo ?? 0;
  }
}