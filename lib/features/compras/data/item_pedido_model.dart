/// Una línea del pedido de compra: no se guarda en Firestore, solo vive
/// mientras se arma el PDF para enviarle al proveedor.
class ItemPedidoModel {
  final String idProducto;
  final String codigo;
  final String nombreProducto;
  final double stockActual;
  final double cantidad;

  ItemPedidoModel({
    required this.idProducto,
    required this.codigo,
    required this.nombreProducto,
    required this.stockActual,
    required this.cantidad,
  });

  ItemPedidoModel copyWith({double? cantidad}) {
    return ItemPedidoModel(
      idProducto: idProducto,
      codigo: codigo,
      nombreProducto: nombreProducto,
      stockActual: stockActual,
      cantidad: cantidad ?? this.cantidad,
    );
  }
}
