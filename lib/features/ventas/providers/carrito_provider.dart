import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/item_venta_model.dart';
import '../data/venta_en_espera_model.dart';
import '../../productos/data/producto_model.dart';
import '../../../core/utils/formato_moneda.dart';

double _subtotalLinea(double precioVenta, double cantidad, double descuentoPorcentaje) {
  return redondearMoneda(precioVenta * cantidad * (1 - descuentoPorcentaje / 100));
}

class CarritoVentaState {
  final String? idEnEspera;
  final List<ItemVentaModel> items;
  final String tipoDocumento;
  final String condicion;
  final String metodoPago;
  final String documentoCliente;
  final String nombreCliente;
  final DateTime fecha;
  final DateTime? fechaVencimiento;
  final String oc;
  final String regExonerado;
  final String regSag;
  final double pagoCon;
  final double cambio;
  final double descuentoGlobalPorcentaje;

  CarritoVentaState({
    this.idEnEspera,
    this.items = const [],
    this.tipoDocumento = 'Factura',
    this.condicion = 'Contado',
    this.metodoPago = 'Efectivo',
    this.documentoCliente = '',
    this.nombreCliente = '',
    DateTime? fecha,
    this.fechaVencimiento,
    this.oc = '',
    this.regExonerado = '',
    this.regSag = '',
    this.pagoCon = 0,
    this.cambio = 0,
    this.descuentoGlobalPorcentaje = 0,
  }) : fecha = fecha ?? DateTime.now();

  bool get esCotizacion => tipoDocumento == 'Cotizacion';
  bool get esVentaSinFacturar => tipoDocumento == 'VentaSinFacturar';
  bool get esCredito => condicion == 'Credito';

  double get _subtotalLineasSinDescuentoGlobal => items.fold<double>(0, (s, i) => s + i.subtotal);

  double get subtotal => redondearMoneda(_subtotalLineasSinDescuentoGlobal * (1 - descuentoGlobalPorcentaje / 100));

  double get _totalConImpuestoBase {
    var total = 0.0;
    for (final i in items) {
      final precioConIsv = redondearMoneda(i.precioVenta * 1.15);
      total += _subtotalLinea(precioConIsv, i.cantidad, i.descuentoPorcentaje);
    }
    total *= (1 - descuentoGlobalPorcentaje / 100);
    return redondearMoneda(total);
  }

  // redondearMoneda acá también: aunque _totalConImpuestoBase y subtotal ya
  // vienen cada uno redondeado a centavos, restar dos doubles "limpios" en
  // punto flotante binario puede dar un resultado como 79.99999999999997 en
  // vez de 80.00 exacto, y eso terminaba imprimiéndose como 79.99 o 80.01.
  double get impuesto => redondearMoneda(_totalConImpuestoBase - subtotal);

  /// Redondeo a lempira entero: si el residuo es >= .90 sube, si no baja.
  double get totalAPagar {
    final t = _totalConImpuestoBase;
    final base = t.floorToDouble();
    final resto = t - base;
    return resto >= 0.90 ? base + 1 : base;
  }

  double get cantidadTotalProductos => items.fold<double>(0, (s, i) => s + i.cantidad);

  CarritoVentaState copyWith({
    Object? idEnEspera = _sinCambio,
    List<ItemVentaModel>? items,
    String? tipoDocumento,
    String? condicion,
    String? metodoPago,
    String? documentoCliente,
    String? nombreCliente,
    DateTime? fecha,
    Object? fechaVencimiento = _sinCambio,
    String? oc,
    String? regExonerado,
    String? regSag,
    double? pagoCon,
    double? cambio,
    double? descuentoGlobalPorcentaje,
  }) {
    return CarritoVentaState(
      idEnEspera: idEnEspera == _sinCambio ? this.idEnEspera : idEnEspera as String?,
      items: items ?? this.items,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      condicion: condicion ?? this.condicion,
      metodoPago: metodoPago ?? this.metodoPago,
      documentoCliente: documentoCliente ?? this.documentoCliente,
      nombreCliente: nombreCliente ?? this.nombreCliente,
      fecha: fecha ?? this.fecha,
      fechaVencimiento: fechaVencimiento == _sinCambio ? this.fechaVencimiento : fechaVencimiento as DateTime?,
      oc: oc ?? this.oc,
      regExonerado: regExonerado ?? this.regExonerado,
      regSag: regSag ?? this.regSag,
      pagoCon: pagoCon ?? this.pagoCon,
      cambio: cambio ?? this.cambio,
      descuentoGlobalPorcentaje: descuentoGlobalPorcentaje ?? this.descuentoGlobalPorcentaje,
    );
  }
}

const _sinCambio = Object();

class CarritoVentaNotifier extends Notifier<CarritoVentaState> {
  @override
  CarritoVentaState build() => CarritoVentaState();

  void agregarItem(ItemVentaModel item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Agrega un producto directamente a la tabla (seleccionado desde el modal
  /// de búsqueda), con cantidad 1 y sin descuento por defecto. Si el cajero
  /// eligió un nivel de precio distinto al principal, [precioSeleccionado]
  /// trae ese precio (con ISV, tal como se muestra en el buscador).
  void agregarProductoDirecto(ProductoModel producto, {double? precioSeleccionado, double precioCompraUsado = 0, bool reembasado = false}) {
    final precioConIsv = precioSeleccionado ?? producto.precioVenta;
    final precioSinIsv = redondearMoneda(precioConIsv / 1.15);
    final item = ItemVentaModel(
      idProducto: producto.id,
      idCategoria: producto.idCategoria,
      nombreProducto: producto.nombre,
      precioVenta: precioSinIsv,
      cantidad: 1,
      subtotal: _subtotalLinea(precioSinIsv, 1, 0),
      precioCompraUsado: precioCompraUsado > 0 ? precioCompraUsado : producto.precioCompra,
      reembasado: reembasado,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  void quitarItem(int index) {
    final nuevos = [...state.items]..removeAt(index);
    state = state.copyWith(items: nuevos);
  }

  void actualizarItem(int index, ItemVentaModel nuevo) {
    final nuevos = [...state.items];
    nuevos[index] = nuevo;
    state = state.copyWith(items: nuevos);
  }

  /// Actualiza cantidad, precio (con ISV, tal como lo ve el cajero) y/o
  /// descuento de línea directamente desde la tabla, recalculando el subtotal.
  void actualizarLinea(int index, {double? cantidad, double? precioConIsv, double? descuentoPorcentaje, bool? reembasado}) {
    final actual = state.items[index];
    final nuevaCantidad = cantidad ?? actual.cantidad;
    final nuevoPrecio = precioConIsv != null ? redondearMoneda(precioConIsv / 1.15) : actual.precioVenta;
    final nuevoDescuento = descuentoPorcentaje ?? actual.descuentoPorcentaje;
    final nuevos = [...state.items];
    nuevos[index] = ItemVentaModel(
      idProducto: actual.idProducto,
      idCategoria: actual.idCategoria,
      nombreProducto: actual.nombreProducto,
      precioVenta: nuevoPrecio,
      cantidad: nuevaCantidad,
      subtotal: _subtotalLinea(nuevoPrecio, nuevaCantidad, nuevoDescuento),
      precioCompraUsado: actual.precioCompraUsado,
      reembasado: reembasado ?? actual.reembasado,
      descuentoPorcentaje: nuevoDescuento,
    );
    state = state.copyWith(items: nuevos);
  }

  /// Cambia la descripción mostrada/impresa de una línea del carrito (no
  /// afecta el producto real).
  void actualizarDescripcion(int index, String nuevaDescripcion) {
    final texto = nuevaDescripcion.trim();
    if (texto.isEmpty) return;
    final nuevos = [...state.items];
    nuevos[index] = nuevos[index].copyWith(nombreProducto: texto);
    state = state.copyWith(items: nuevos);
  }

  void establecerDescuentoGlobal(double v) => state = state.copyWith(descuentoGlobalPorcentaje: v);

  void establecerTipoDocumento(String v) => state = state.copyWith(tipoDocumento: v);

  void establecerCondicion(String v) {
    state = state.copyWith(
      condicion: v,
      metodoPago: v == 'Credito' ? '' : 'Efectivo',
      fechaVencimiento: v == 'Credito' ? (state.fechaVencimiento ?? DateTime.now().add(const Duration(days: 30))) : null,
    );
  }

  void establecerMetodoPago(String v) => state = state.copyWith(metodoPago: v);
  void establecerCliente({required String documento, required String nombre}) {
    state = state.copyWith(documentoCliente: documento, nombreCliente: nombre);
  }
  void establecerDocumentoCliente(String v) => state = state.copyWith(documentoCliente: v);
  void establecerFecha(DateTime v) => state = state.copyWith(fecha: v);
  void establecerFechaVencimiento(DateTime v) => state = state.copyWith(fechaVencimiento: v);
  void establecerOc(String v) => state = state.copyWith(oc: v);
  void establecerRegExonerado(String v) => state = state.copyWith(regExonerado: v);
  void establecerRegSag(String v) => state = state.copyWith(regSag: v);
  void establecerPago({required double pagoCon, required double cambio}) {
    state = state.copyWith(pagoCon: pagoCon, cambio: cambio);
  }
  void cargarSesion(VentaEnEsperaModel sesion) {
    state = CarritoVentaState(
      idEnEspera: sesion.id,
      items: sesion.items,
      tipoDocumento: sesion.tipoDocumento,
      condicion: sesion.condicion,
      metodoPago: sesion.metodoPago,
      documentoCliente: sesion.documentoCliente,
      nombreCliente: sesion.nombreCliente,
      fechaVencimiento: sesion.fechaVencimiento,
      oc: sesion.oc,
      regExonerado: sesion.regExonerado,
      regSag: sesion.regSag,
      descuentoGlobalPorcentaje: sesion.descuentoGlobal,
    );
  }

  void limpiar() {
    state = CarritoVentaState();
  }
}

final carritoVentaProvider = NotifierProvider<CarritoVentaNotifier, CarritoVentaState>(CarritoVentaNotifier.new);
