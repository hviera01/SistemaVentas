import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/item_compra_model.dart';
import '../../productos/data/producto_model.dart';
import '../../../core/utils/formato_moneda.dart';

double _subtotalLinea(double precioCompra, double cantidad, double descuentoPorcentaje) {
  return redondearMoneda(precioCompra * cantidad * (1 - descuentoPorcentaje / 100));
}

class CarritoCompraState {
  final List<ItemCompraModel> items;
  final String idProveedor;
  final String documentoProveedor;
  final String razonSocial;
  final String noFactura;
  final String condicion;
  final String metodoPago;
  final DateTime fecha;
  final DateTime? fechaVencimiento;
  final double descuentoGlobalPorcentaje;
  final double isvPorcentaje;
  final double ajusteManual;

  CarritoCompraState({
    this.items = const [],
    this.idProveedor = '',
    this.documentoProveedor = '',
    this.razonSocial = '',
    this.noFactura = '',
    this.condicion = 'Contado',
    this.metodoPago = 'Efectivo',
    DateTime? fecha,
    this.fechaVencimiento,
    this.descuentoGlobalPorcentaje = 0,
    this.isvPorcentaje = 15,
    this.ajusteManual = 0,
  }) : fecha = fecha ?? DateTime.now();

  bool get esCredito => condicion == 'Credito';

  double get _subtotalLineasSinDescuentoGlobal => items.fold<double>(0, (s, i) => s + i.subtotal);

  double get subtotal => redondearMoneda(_subtotalLineasSinDescuentoGlobal * (1 - descuentoGlobalPorcentaje / 100));

  double get descuentoTotalMonto => redondearMoneda(_subtotalLineasSinDescuentoGlobal - subtotal);

  double get impuesto => redondearMoneda(subtotal * isvPorcentaje / 100);

  double get totalAPagar => redondearMoneda(subtotal + impuesto + ajusteManual);

  double get cantidadTotalProductos => items.fold<double>(0, (s, i) => s + i.cantidad);

  CarritoCompraState copyWith({
    List<ItemCompraModel>? items,
    String? idProveedor,
    String? documentoProveedor,
    String? razonSocial,
    String? noFactura,
    String? condicion,
    String? metodoPago,
    DateTime? fecha,
    Object? fechaVencimiento = _sinCambio,
    double? descuentoGlobalPorcentaje,
    double? isvPorcentaje,
    double? ajusteManual,
  }) {
    return CarritoCompraState(
      items: items ?? this.items,
      idProveedor: idProveedor ?? this.idProveedor,
      documentoProveedor: documentoProveedor ?? this.documentoProveedor,
      razonSocial: razonSocial ?? this.razonSocial,
      noFactura: noFactura ?? this.noFactura,
      condicion: condicion ?? this.condicion,
      metodoPago: metodoPago ?? this.metodoPago,
      fecha: fecha ?? this.fecha,
      fechaVencimiento: fechaVencimiento == _sinCambio ? this.fechaVencimiento : fechaVencimiento as DateTime?,
      descuentoGlobalPorcentaje: descuentoGlobalPorcentaje ?? this.descuentoGlobalPorcentaje,
      isvPorcentaje: isvPorcentaje ?? this.isvPorcentaje,
      ajusteManual: ajusteManual ?? this.ajusteManual,
    );
  }
}

const _sinCambio = Object();

class CarritoCompraNotifier extends Notifier<CarritoCompraState> {
  @override
  CarritoCompraState build() => CarritoCompraState();

  /// Agrega un producto directamente a la tabla, con cantidad 1 y el costo
  /// unitario que ya tiene registrado el producto (editable en la fila).
  void agregarProductoDirecto(ProductoModel producto) {
    final item = ItemCompraModel(
      idProducto: producto.id,
      idCategoria: producto.idCategoria,
      nombreProducto: producto.nombre,
      precioCompra: producto.precioCompra,
      cantidad: 1,
      subtotal: _subtotalLinea(producto.precioCompra, 1, 0),
      precioVentaNuevo: producto.precioVenta,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  void quitarItem(int index) {
    final nuevos = [...state.items]..removeAt(index);
    state = state.copyWith(items: nuevos);
  }

  /// Actualiza cantidad, precio de costo, descuento y/o el nuevo precio de
  /// venta de línea directamente desde la tabla, recalculando el subtotal.
  void actualizarLinea(int index, {double? cantidad, double? precioCompra, double? descuentoPorcentaje, double? precioVentaNuevo}) {
    final actual = state.items[index];
    final nuevaCantidad = cantidad ?? actual.cantidad;
    final nuevoPrecio = precioCompra ?? actual.precioCompra;
    final nuevoDescuento = descuentoPorcentaje ?? actual.descuentoPorcentaje;
    final nuevos = [...state.items];
    nuevos[index] = ItemCompraModel(
      idProducto: actual.idProducto,
      idCategoria: actual.idCategoria,
      nombreProducto: actual.nombreProducto,
      precioCompra: nuevoPrecio,
      cantidad: nuevaCantidad,
      subtotal: _subtotalLinea(nuevoPrecio, nuevaCantidad, nuevoDescuento),
      descuentoPorcentaje: nuevoDescuento,
      precioVentaNuevo: precioVentaNuevo ?? actual.precioVentaNuevo,
    );
    state = state.copyWith(items: nuevos);
  }

  void establecerProveedor({required String idProveedor, required String documentoProveedor, required String razonSocial}) {
    state = state.copyWith(idProveedor: idProveedor, documentoProveedor: documentoProveedor, razonSocial: razonSocial);
  }

  void establecerNoFactura(String v) => state = state.copyWith(noFactura: v);

  void establecerCondicion(String v) {
    state = state.copyWith(
      condicion: v,
      metodoPago: v == 'Credito' ? '' : 'Efectivo',
      fechaVencimiento: v == 'Credito' ? (state.fechaVencimiento ?? DateTime.now().add(const Duration(days: 30))) : null,
    );
  }

  void establecerMetodoPago(String v) => state = state.copyWith(metodoPago: v);
  void establecerFecha(DateTime v) => state = state.copyWith(fecha: v);
  void establecerFechaVencimiento(DateTime v) => state = state.copyWith(fechaVencimiento: v);
  void establecerDescuentoGlobal(double v) => state = state.copyWith(descuentoGlobalPorcentaje: v);
  void establecerIsv(double v) => state = state.copyWith(isvPorcentaje: v);
  void establecerAjusteManual(double v) => state = state.copyWith(ajusteManual: v);

  void limpiar() {
    state = CarritoCompraState();
  }
}

final carritoCompraProvider = NotifierProvider<CarritoCompraNotifier, CarritoCompraState>(CarritoCompraNotifier.new);
