import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/item_venta_model.dart';
import '../data/venta_en_espera_model.dart';
import '../data/venta_model.dart';
import '../../productos/data/producto_model.dart';
import '../../../core/utils/formato_moneda.dart';

/// [forzarFactura] distingue "Duplicar venta" (la cotización sigue siendo
/// cotización) de "Convertir a venta" (la cotización pasa a Factura).
class DatosVentaParaCargar {
  final VentaModel venta;
  final bool forzarFactura;

  DatosVentaParaCargar({required this.venta, this.forzarFactura = false});
}

/// Guarda una venta "de paso" para que la próxima pestaña de Registrar Venta
/// que se abra la cargue en su carrito (ver duplicar/convertir en
/// DetalleVentaScreen). Es un provider global (no por pestaña, a diferencia
/// de carritoVentaProvider) a propósito: se llena justo antes de abrir la
/// pestaña nueva y esa pestaña lo consume (lo deja en null) apenas arranca,
/// así que no hay riesgo de que se cuele en una pestaña futura sin querer.
class VentaParaCargarNotifier extends Notifier<DatosVentaParaCargar?> {
  @override
  DatosVentaParaCargar? build() => null;

  void establecer(VentaModel venta, {bool forzarFactura = false}) => state = DatosVentaParaCargar(venta: venta, forzarFactura: forzarFactura);
  void limpiar() => state = null;
}

final ventaParaCargarProvider = NotifierProvider<VentaParaCargarNotifier, DatosVentaParaCargar?>(VentaParaCargarNotifier.new);

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
    // Sin redondear a centavos acá: precioVenta (sin ISV) no siempre es un
    // número "limpio" de 2 decimales -por ejemplo 100/1.15- y redondearlo
    // de una vez, antes de multiplicarlo de nuevo por 1.15 para mostrar o
    // sumar el total, es lo que causaba precios como 100.01 en vez de
    // 100.00 (dos redondeos en cadena). Se redondea una sola vez, recién al
    // mostrar o calcular un total (ver _totalConImpuestoBase más abajo).
    final precioSinIsv = precioConIsv / 1.15;
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
    // Ver el comentario en agregarProductoDirecto: no se redondea acá para
    // no perder precisión antes de multiplicar de nuevo por 1.15.
    final nuevoPrecio = precioConIsv != null ? precioConIsv / 1.15 : actual.precioVenta;
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

  /// Carga en el carrito los productos y datos de una venta ya registrada
  /// (para "Duplicar venta" o, si era una cotización, "Convertir a venta"
  /// desde DetalleVentaScreen): arma una venta nueva desde cero con los
  /// mismos productos, no continúa ni modifica la original. [forzarFactura]
  /// solo aplica cuando la original es una cotización: "Duplicar" la deja
  /// como cotización otra vez, "Convertir a venta" la pasa a Factura.
  void cargarDesdeVenta(VentaModel venta, {bool forzarFactura = false}) {
    state = CarritoVentaState(
      // Sin reembasado: si algún item lo tenía marcado en la venta
      // original, el descuento de stock del producto base ya se hizo en su
      // momento. Esta es una venta nueva, así que si vuelve a faltar
      // existencia, se pregunta por reembasado de nuevo en vez de asumir
      // que ya está resuelto.
      items: venta.detalle
          .map((item) => ItemVentaModel(
                idProducto: item.idProducto,
                idCategoria: item.idCategoria,
                nombreProducto: item.nombreProducto,
                precioVenta: item.precioVenta,
                cantidad: item.cantidad,
                subtotal: item.subtotal,
                precioCompraUsado: item.precioCompraUsado,
                descuentoPorcentaje: item.descuentoPorcentaje,
              ))
          .toList(),
      tipoDocumento: (forzarFactura && venta.tipoDocumento == 'Cotizacion') ? 'Factura' : venta.tipoDocumento,
      condicion: venta.condicion,
      metodoPago: venta.condicion == 'Credito' ? '' : (venta.metodoPago.isEmpty ? 'Efectivo' : venta.metodoPago),
      documentoCliente: venta.documentoCliente,
      nombreCliente: venta.nombreCliente,
      fechaVencimiento: venta.condicion == 'Credito' ? DateTime.now().add(const Duration(days: 30)) : null,
      oc: venta.oc,
      regExonerado: venta.regExonerado,
      regSag: venta.regSag,
      descuentoGlobalPorcentaje: venta.descuentoGlobal,
    );
  }

  void limpiar() {
    state = CarritoVentaState();
  }
}

final carritoVentaProvider = NotifierProvider<CarritoVentaNotifier, CarritoVentaState>(CarritoVentaNotifier.new);
