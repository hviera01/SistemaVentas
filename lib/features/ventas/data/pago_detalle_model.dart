/// Un renglón de un pago mixto: parte del total pagada con un método
/// específico (por ejemplo, la porción en Efectivo de una venta pagada
/// mitad Efectivo/mitad Tarjeta). Ver CarritoVentaState.pagosMixtos.
class PagoDetalle {
  final String metodoPago;
  final double monto;

  const PagoDetalle({required this.metodoPago, required this.monto});

  Map<String, dynamic> toMap() => {'metodoPago': metodoPago, 'monto': monto};

  factory PagoDetalle.fromMap(Map<String, dynamic> data) {
    return PagoDetalle(
      metodoPago: data['metodoPago'] ?? '',
      monto: (data['monto'] ?? 0).toDouble(),
    );
  }

  static List<PagoDetalle> listaFromMaps(List<dynamic>? data) {
    if (data == null) return const [];
    return data.map((d) => PagoDetalle.fromMap(Map<String, dynamic>.from(d as Map))).toList();
  }

  static List<Map<String, dynamic>> listaToMaps(List<PagoDetalle> pagos) => pagos.map((p) => p.toMap()).toList();
}
