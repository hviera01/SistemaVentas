import 'package:cloud_firestore/cloud_firestore.dart';

class HistorialStockModel {
  final String id;
  final double stockAnterior;
  final double stockNuevo;
  final DateTime? fecha;
  final String usuario;
  final String motivo;

  HistorialStockModel({
    required this.id,
    required this.stockAnterior,
    required this.stockNuevo,
    required this.fecha,
    required this.usuario,
    required this.motivo,
  });

  factory HistorialStockModel.fromMap(String id, Map<String, dynamic> data) {
    return HistorialStockModel(
      id: id,
      stockAnterior: (data['stockAnterior'] ?? 0).toDouble(),
      stockNuevo: (data['stockNuevo'] ?? 0).toDouble(),
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      usuario: data['usuario'] ?? '',
      motivo: data['motivo'] ?? '',
    );
  }

  /// Cuánto cambió el stock en este movimiento (con signo).
  double get delta => stockNuevo - stockAnterior;

  /// Tipo de movimiento -pedido explícito del dueño: "poder ver el detalle
  /// de si es venta, si es compra, etc"-. No se guarda como campo propio en
  /// Firestore: no hacía falta tocar cada punto del código que escribe un
  /// historial (venta, compra, ajuste manual, anulaciones, reembasado) para
  /// lograrlo, y así también funciona retroactivo para movimientos ya
  /// guardados. Se INFIERE del texto de [motivo] (cada escritor ya usa un
  /// prefijo fijo y reconocible, ver ProductoRepository/VentaRepository/
  /// CompraRepository) y, si no matchea ninguno -motivo personalizado en un
  /// ajuste manual-, del signo de [delta] (que siempre es correcto,
  /// independiente del texto).
  TipoMovimientoStock get tipo {
    if (motivo.startsWith('Anulación de venta')) return TipoMovimientoStock.anulacionVenta;
    if (motivo.startsWith('Venta ')) return TipoMovimientoStock.venta;
    if (motivo.startsWith('Anulación de compra')) return TipoMovimientoStock.anulacionCompra;
    if (motivo.startsWith('Compra ')) return TipoMovimientoStock.compra;
    if (motivo.startsWith('Reembasado')) return TipoMovimientoStock.reembasado;
    return delta >= 0 ? TipoMovimientoStock.ajusteEntrada : TipoMovimientoStock.ajusteSalida;
  }
}

enum TipoMovimientoStock { venta, anulacionVenta, compra, anulacionCompra, reembasado, ajusteEntrada, ajusteSalida }

const etiquetasTipoMovimientoStock = {
  TipoMovimientoStock.venta: 'Venta',
  TipoMovimientoStock.anulacionVenta: 'Anulación de venta',
  TipoMovimientoStock.compra: 'Compra',
  TipoMovimientoStock.anulacionCompra: 'Anulación de compra',
  TipoMovimientoStock.reembasado: 'Reembasado',
  TipoMovimientoStock.ajusteEntrada: 'Ajuste (entrada)',
  TipoMovimientoStock.ajusteSalida: 'Ajuste (salida)',
};