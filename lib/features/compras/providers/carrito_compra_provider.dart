import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/compra_en_espera_model.dart';
import '../data/item_compra_model.dart';
import '../../productos/data/producto_model.dart';
import '../../../core/utils/formato_moneda.dart';

double _subtotalLinea(double precioCompra, double cantidad, double descuentoPorcentaje) {
  return redondearMoneda(precioCompra * cantidad * (1 - descuentoPorcentaje / 100));
}

class CarritoCompraState {
  // Id del documento en 'comprasEnEspera' que respalda esta compra en curso
  // (ver RegistrarCompraScreen: se autoguarda con debounce apenas hay
  // productos). Null hasta el primer autoguardado o mientras no venga de
  // "Ver en Espera".
  final String? idEnEspera;
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
    this.idEnEspera,
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

  /// Suma de los descuentos propios de cada línea (precio × cantidad, antes
  /// de ese descuento, menos el subtotal ya rebajado de la línea) — para
  /// mostrarlo como un renglón aparte en los totales ("Descuentos y
  /// Rebajas", igual que lo muestran las facturas de los proveedores) en
  /// vez de que cada descuento de línea solo se note escondido dentro del
  /// importe de su propia fila. No es lo mismo que [descuentoTotalMonto]:
  /// ese es solo el descuento GLOBAL (el campo aparte "Descuento global %"
  /// de esta pantalla); acá se sabe cuánto se descontó línea por línea.
  double get descuentoLineasMonto {
    final bruto = items.fold<double>(0, (s, i) => s + redondearMoneda(i.precioCompra * i.cantidad));
    final neto = items.fold<double>(0, (s, i) => s + i.subtotal);
    return redondearMoneda(bruto - neto);
  }

  double get impuesto => redondearMoneda(subtotal * isvPorcentaje / 100);

  double get totalAPagar => redondearMoneda(subtotal + impuesto + ajusteManual);

  double get cantidadTotalProductos => items.fold<double>(0, (s, i) => s + i.cantidad);

  CarritoCompraState copyWith({
    Object? idEnEspera = _sinCambio,
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
      idEnEspera: idEnEspera == _sinCambio ? this.idEnEspera : idEnEspera as String?,
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
  ///
  /// El "Precio Compra" guardado en el catálogo incluye el ISV (así llega el
  /// costo en la factura del proveedor). Como el ISV de la compra se aplica
  /// una sola vez sobre el total (ver [CarritoCompraState.impuesto]), si acá
  /// se cargara ese mismo precio y la compra usa ISV el impuesto quedaría
  /// contado dos veces. Por eso, si la compra tiene ISV (>0), se le quita ese
  /// porcentaje antes de cargarlo a la línea; si la compra está en ISV 0
  /// (proveedor exento, por ejemplo), se carga el precio del catálogo tal
  /// cual.
  void agregarProductoDirecto(ProductoModel producto) {
    final precioCompra = state.isvPorcentaje > 0
        ? redondearMoneda(producto.precioCompra / (1 + state.isvPorcentaje / 100))
        : producto.precioCompra;
    final item = ItemCompraModel(
      idProducto: producto.id,
      idCategoria: producto.idCategoria,
      nombreProducto: producto.nombre,
      precioCompra: precioCompra,
      cantidad: 1,
      subtotal: _subtotalLinea(precioCompra, 1, 0),
      precioVentaNuevo: producto.precioVenta,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Agrega un producto ya emparejado desde el escaneo de factura (ver
  /// EscanearFacturaDialog), con la cantidad/precio/descuento que se leyó
  /// (y el cajero confirmó) en vez de los valores por defecto de
  /// [agregarProductoDirecto]. [precioCompra] es el precio unitario tal
  /// como viene en la factura del proveedor -sin ISV, como ya lo maneja
  /// esta pantalla en cualquier otra fila-.
  void agregarItemEscaneado({
    required ProductoModel producto,
    required double cantidad,
    required double precioCompra,
    required double descuentoPorcentaje,
  }) {
    final item = ItemCompraModel(
      idProducto: producto.id,
      idCategoria: producto.idCategoria,
      nombreProducto: producto.nombre,
      precioCompra: precioCompra,
      cantidad: cantidad,
      subtotal: _subtotalLinea(precioCompra, cantidad, descuentoPorcentaje),
      descuentoPorcentaje: descuentoPorcentaje,
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
      fechaVencimiento: v == 'Credito' ? (state.fechaVencimiento ?? state.fecha.add(const Duration(days: 30))) : null,
    );
  }

  void establecerMetodoPago(String v) => state = state.copyWith(metodoPago: v);

  /// Al cambiar la fecha de registro, la fecha de vencimiento del crédito se
  /// recalcula sola a 30 días de esa fecha (no de "hoy"), para que quede
  /// consistente con lo que el usuario acaba de elegir.
  void establecerFecha(DateTime v) => state = state.copyWith(fecha: v, fechaVencimiento: v.add(const Duration(days: 30)));
  void establecerFechaVencimiento(DateTime v) => state = state.copyWith(fechaVencimiento: v);
  void establecerDescuentoGlobal(double v) => state = state.copyWith(descuentoGlobalPorcentaje: v);
  void establecerIsv(double v) => state = state.copyWith(isvPorcentaje: v);
  void establecerAjusteManual(double v) => state = state.copyWith(ajusteManual: v);

  /// Registra el id del documento de 'comprasEnEspera' que quedó respaldando
  /// esta compra tras el primer autoguardado (ver RegistrarCompraScreen).
  void establecerIdEnEspera(String id) => state = state.copyWith(idEnEspera: id);

  void cargarSesion(CompraEnEsperaModel sesion) {
    state = CarritoCompraState(
      idEnEspera: sesion.id,
      items: sesion.items,
      idProveedor: sesion.idProveedor,
      documentoProveedor: sesion.documentoProveedor,
      razonSocial: sesion.razonSocial,
      noFactura: sesion.noFactura,
      condicion: sesion.condicion,
      metodoPago: sesion.metodoPago,
      fecha: sesion.fechaRegistro ?? DateTime.now(),
      fechaVencimiento: sesion.fechaVencimiento,
      descuentoGlobalPorcentaje: sesion.descuentoGlobalPorcentaje,
      isvPorcentaje: sesion.isvPorcentaje,
      ajusteManual: sesion.ajusteManual,
    );
  }

  void limpiar() {
    state = CarritoCompraState();
  }
}

final carritoCompraProvider = NotifierProvider<CarritoCompraNotifier, CarritoCompraState>(CarritoCompraNotifier.new);
