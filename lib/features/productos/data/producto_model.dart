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
    );
  }

  String get textoBusqueda => '$codigo $codigoBarras $nombre $descripcion';
}