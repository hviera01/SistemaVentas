import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/item_venta_model.dart';
import '../data/pago_detalle_model.dart';
import '../data/venta_en_espera_model.dart';
import '../data/venta_model.dart';
import '../data/registrar_venta_vista_storage.dart';
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

  void establecer(VentaModel venta, {bool forzarFactura = false}) =>
      state = DatosVentaParaCargar(venta: venta, forzarFactura: forzarFactura);
  void limpiar() => state = null;
}

final ventaParaCargarProvider =
    NotifierProvider<VentaParaCargarNotifier, DatosVentaParaCargar?>(
      VentaParaCargarNotifier.new,
    );

double _subtotalLinea(
  double precioVenta,
  double cantidad,
  double descuentoPorcentaje,
) {
  return redondearMoneda(
    precioVenta * cantidad * (1 - descuentoPorcentaje / 100),
  );
}

class CarritoVentaState {
  final String? idEnEspera;
  final List<ItemVentaModel> items;
  final String tipoDocumento;
  final String condicion;
  final String metodoPago;
  final String documentoCliente;
  final String nombreCliente;
  // Vínculo real al registro de 'clientes' (ver CRM de clientes). Se limpia
  // a null apenas el cajero edita a mano el nombre o el documento después de
  // haber elegido un cliente por el buscador, para no dejar un vínculo
  // falso -ver establecerDocumentoCliente/establecerNombreClienteManual-.
  final String? idCliente;
  final DateTime fecha;
  final DateTime? fechaVencimiento;
  // Teléfono de contacto propio de este crédito (ver VentaCreditoModel.
  // telefono) — solo relevante cuando condicion == 'Credito'. Se precarga
  // con el del cliente vinculado, pero es independiente y editable.
  final String telefonoCredito;
  final String oc;
  final String regExonerado;
  final String regSag;
  final String observaciones;
  final double pagoCon;
  final double cambio;
  final double descuentoGlobalPorcentaje;
  // Desglose cuando metodoPago == 'Mixto' (ver PagoMixtoDialog). Vacío en
  // cualquier otro método.
  final List<PagoDetalle> pagosMixtos;

  CarritoVentaState({
    this.idEnEspera,
    this.items = const [],
    this.tipoDocumento = 'Factura',
    this.condicion = 'Contado',
    this.metodoPago = 'Efectivo',
    this.documentoCliente = '',
    this.nombreCliente = '',
    this.idCliente,
    DateTime? fecha,
    this.fechaVencimiento,
    this.telefonoCredito = '',
    this.oc = '',
    this.regExonerado = '',
    this.regSag = '',
    this.observaciones = '',
    this.pagoCon = 0,
    this.cambio = 0,
    this.descuentoGlobalPorcentaje = 0,
    this.pagosMixtos = const [],
  }) : fecha = fecha ?? DateTime.now();

  bool get esCotizacion => tipoDocumento == 'Cotizacion';
  bool get esVentaSinFacturar => tipoDocumento == 'VentaSinFacturar';
  bool get esCredito => condicion == 'Credito';
  bool get esPagoMixto => metodoPago == 'Mixto';

  double get _subtotalLineasSinDescuentoGlobal =>
      items.fold<double>(0, (s, i) => s + i.subtotal);

  double get subtotal => redondearMoneda(
    _subtotalLineasSinDescuentoGlobal * (1 - descuentoGlobalPorcentaje / 100),
  );

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

  double get cantidadTotalProductos =>
      items.fold<double>(0, (s, i) => s + i.cantidad);

  CarritoVentaState copyWith({
    Object? idEnEspera = _sinCambio,
    List<ItemVentaModel>? items,
    String? tipoDocumento,
    String? condicion,
    String? metodoPago,
    String? documentoCliente,
    String? nombreCliente,
    Object? idCliente = _sinCambio,
    DateTime? fecha,
    Object? fechaVencimiento = _sinCambio,
    String? telefonoCredito,
    String? oc,
    String? regExonerado,
    String? regSag,
    String? observaciones,
    double? pagoCon,
    double? cambio,
    double? descuentoGlobalPorcentaje,
    List<PagoDetalle>? pagosMixtos,
  }) {
    return CarritoVentaState(
      idEnEspera: idEnEspera == _sinCambio
          ? this.idEnEspera
          : idEnEspera as String?,
      items: items ?? this.items,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      condicion: condicion ?? this.condicion,
      metodoPago: metodoPago ?? this.metodoPago,
      documentoCliente: documentoCliente ?? this.documentoCliente,
      nombreCliente: nombreCliente ?? this.nombreCliente,
      idCliente: idCliente == _sinCambio
          ? this.idCliente
          : idCliente as String?,
      fecha: fecha ?? this.fecha,
      fechaVencimiento: fechaVencimiento == _sinCambio
          ? this.fechaVencimiento
          : fechaVencimiento as DateTime?,
      telefonoCredito: telefonoCredito ?? this.telefonoCredito,
      oc: oc ?? this.oc,
      regExonerado: regExonerado ?? this.regExonerado,
      regSag: regSag ?? this.regSag,
      observaciones: observaciones ?? this.observaciones,
      pagoCon: pagoCon ?? this.pagoCon,
      cambio: cambio ?? this.cambio,
      descuentoGlobalPorcentaje:
          descuentoGlobalPorcentaje ?? this.descuentoGlobalPorcentaje,
      pagosMixtos: pagosMixtos ?? this.pagosMixtos,
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
  void agregarProductoDirecto(
    ProductoModel producto, {
    double? precioSeleccionado,
    double precioCompraUsado = 0,
    bool reembasado = false,
  }) {
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
      precioCompraUsado: precioCompraUsado > 0
          ? precioCompraUsado
          : producto.precioCompra,
      reembasado: reembasado,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Igual que agregarProductoDirecto, pero cuando [fusionarSiYaExiste] es
  /// true y el producto ya está en el carrito como línea normal (no combo),
  /// en vez de crear una línea nueva le suma 1 a la cantidad de esa línea
  /// existente -devuelve el índice de la línea afectada (la existente si se
  /// fusionó, o la recién creada si no), para que quien llama (por ejemplo,
  /// para aplicar una promoción) sepa sobre cuál línea actuar-.
  ///
  /// Quién decide [fusionarSiYaExiste] es RegistrarVentaScreen: al escanear
  /// un código de barras SIEMPRE se fusiona (sin importar la categoría del
  /// producto) -pedido explícito del dueño-; al agregar a mano desde el
  /// buscador (BuscarProductoDialog) se fusiona solo si la categoría NO es
  /// de pintura -ver _esCategoriaPintura-, porque una línea de pintura puede
  /// llevar su propio código/tinte de color (ver CodigosColorDialog) y el
  /// dueño quiere poder vender, por ejemplo, "2 galones de la misma pintura
  /// base" como dos líneas separadas, cada una teñida a un color distinto,
  /// en vez de una sola línea de cantidad 2 que solo podría llevar un color.
  int agregarOFusionarProductoDirecto(
    ProductoModel producto, {
    double? precioSeleccionado,
    double precioCompraUsado = 0,
    bool reembasado = false,
    bool fusionarSiYaExiste = false,
  }) {
    if (fusionarSiYaExiste) {
      final idx = state.items.indexWhere(
        (i) => i.idProducto == producto.id && !i.esCombo,
      );
      if (idx != -1) {
        actualizarLinea(idx, cantidad: state.items[idx].cantidad + 1);
        return idx;
      }
    }
    agregarProductoDirecto(
      producto,
      precioSeleccionado: precioSeleccionado,
      precioCompraUsado: precioCompraUsado,
      reembasado: reembasado,
    );
    return state.items.length - 1;
  }

  /// Agrega un producto tipo combo/kit directamente a la tabla, en una sola
  /// línea. La receta de componentes se congela (snapshot) en el momento de
  /// agregarlo -no se resuelve de nuevo después- para que anular la venta
  /// más adelante siga sabiendo qué reponer aunque el combo se edite.
  void agregarComboDirecto(
    ProductoModel combo, {
    required Map<String, ProductoModel> mapaProductos,
    double? precioSeleccionado,
  }) {
    final precioConIsv = precioSeleccionado ?? combo.precioVenta;
    final precioSinIsv = precioConIsv / 1.15;
    final componentesSnapshot = combo.componentes.map((c) {
      final productoComponente = mapaProductos[c.idProducto];
      return ComponenteComboSnapshot(
        idProducto: c.idProducto,
        idCategoria: productoComponente?.idCategoria ?? '',
        nombreProducto: productoComponente?.nombre ?? '',
        cantidad: c.cantidad,
        precioCompraUsado: productoComponente?.precioCompra ?? 0,
      );
    }).toList();
    final item = ItemVentaModel(
      idProducto: combo.id,
      idCategoria: combo.idCategoria,
      nombreProducto: combo.nombre,
      precioVenta: precioSinIsv,
      cantidad: 1,
      subtotal: _subtotalLinea(precioSinIsv, 1, 0),
      precioCompraUsado: combo.precioCompra,
      componentes: componentesSnapshot,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  void quitarItem(int index) {
    final nuevos = [...state.items]..removeAt(index);
    state = state.copyWith(items: nuevos);
  }

  /// Cambia la posición de una línea en la tabla (subir/bajar o arrastrar).
  /// Ese orden es el que se guarda al registrar la venta y el que después
  /// se respeta en el detalle y en la reimpresión.
  void moverItem(int oldIndex, int newIndex) {
    final nuevos = [...state.items];
    final item = nuevos.removeAt(oldIndex);
    nuevos.insert(newIndex, item);
    state = state.copyWith(items: nuevos);
  }

  void actualizarItem(int index, ItemVentaModel nuevo) {
    final nuevos = [...state.items];
    nuevos[index] = nuevo;
    state = state.copyWith(items: nuevos);
  }

  /// Actualiza cantidad, precio (con ISV, tal como lo ve el cajero) y/o
  /// descuento de línea directamente desde la tabla, recalculando el subtotal.
  void actualizarLinea(
    int index, {
    double? cantidad,
    double? precioConIsv,
    double? descuentoPorcentaje,
    bool? reembasado,
  }) {
    final actual = state.items[index];
    final nuevaCantidad = cantidad ?? actual.cantidad;
    // Ver el comentario en agregarProductoDirecto: no se redondea acá para
    // no perder precisión antes de multiplicar de nuevo por 1.15.
    final nuevoPrecio = precioConIsv != null
        ? precioConIsv / 1.15
        : actual.precioVenta;
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
      componentes: actual.componentes,
      pendienteCompra: actual.pendienteCompra,
      codigosColor: actual.codigosColor,
      // OJO: si la línea ya tenía tinte cargado (ver CodigosColorDialog) y
      // acá se le cambia la cantidad, el tinte NO se re-escala solo -sigue
      // siendo la cantidad de tinte que se calculó para la cantidad vieja-.
      // Reabrir "Código Color" y volver a cargar el tinte es lo que
      // recalcula para la cantidad nueva.
      tintesConsumidos: actual.tintesConsumidos,
    );
    state = state.copyWith(items: nuevos);
  }

  /// Marca/desmarca una línea como "venta anticipada" (se vende sin saber
  /// todavía qué producto exacto la va a reponer). No cambia nada del
  /// descuento de stock ni del costo de la línea en este momento -eso ya
  /// pasa igual que siempre-; solo queda la bandera que, al confirmar la
  /// venta, hace que VentaRepository deje un registro en 'pendientesReposicion'
  /// para que la próxima compra de ese producto la empareje automáticamente
  /// (ver PendienteReposicionRepository y CompraRepository.registrarCompra).
  void marcarPendienteCompra(int index, bool valor) {
    final nuevos = [...state.items];
    nuevos[index] = nuevos[index].copyWith(pendienteCompra: valor);
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

  /// Reemplaza la lista completa de códigos de color de una línea del
  /// carrito (viene de CodigosColorDialog, que maneja su propia lista local
  /// y entrega el resultado final al cerrar). Sí se puede dejar vacía
  /// -quitar todos los códigos ya cargados es una edición válida-.
  void actualizarCodigosColor(int index, List<String> nuevosCodigos) {
    final nuevos = [...state.items];
    nuevos[index] = nuevos[index].copyWith(codigosColor: nuevosCodigos);
    state = state.copyWith(items: nuevos);
  }

  /// Igual que actualizarCodigosColor pero para el tinte real consumido en
  /// la línea (ver TinteConsumidoSnapshot, CodigosColorDialog) -costo
  /// estimado en este punto, VentaRepository.registrarVenta lo recalcula
  /// con el costo FIFO real al confirmar la venta.
  void actualizarTintesConsumidos(
    int index,
    List<TinteConsumidoSnapshot> nuevosTintes,
  ) {
    final nuevos = [...state.items];
    nuevos[index] = nuevos[index].copyWith(tintesConsumidos: nuevosTintes);
    state = state.copyWith(items: nuevos);
  }

  void establecerDescuentoGlobal(double v) =>
      state = state.copyWith(descuentoGlobalPorcentaje: v);

  void establecerTipoDocumento(String v) =>
      state = state.copyWith(tipoDocumento: v);

  void establecerCondicion(String v) {
    state = state.copyWith(
      condicion: v,
      metodoPago: v == 'Credito' ? '' : 'Efectivo',
      fechaVencimiento: v == 'Credito'
          ? (state.fechaVencimiento ??
                DateTime.now().add(const Duration(days: 30)))
          : null,
      pagosMixtos: const [],
    );
  }

  void establecerMetodoPago(String v) => state = state.copyWith(
    metodoPago: v,
    pagosMixtos: v == 'Mixto' ? state.pagosMixtos : const [],
  );

  /// Guarda el desglose confirmado en PagoMixtoDialog. No cambia metodoPago:
  /// eso ya se hizo al elegir "Mixto" en el dropdown.
  void establecerPagosMixtos(List<PagoDetalle> pagos) =>
      state = state.copyWith(pagosMixtos: pagos);

  /// [idCliente] es el vínculo real al registro de 'clientes' (viene de
  /// BuscarClienteDialog). Al no pasarlo (o pasar null explícito) se limpia
  /// -es lo correcto para un nombre/documento tipeado a mano sin cliente
  /// elegido-.
  void establecerCliente({
    required String documento,
    required String nombre,
    String? idCliente,
  }) {
    state = state.copyWith(
      documentoCliente: documento,
      nombreCliente: nombre,
      idCliente: idCliente,
    );
  }

  /// El cajero tipeó el documento a mano: si antes había un cliente elegido
  /// por el buscador, ese vínculo ya no es confiable (pudo cambiar el RTN a
  /// mano sin que sea el mismo cliente), así que se limpia.
  void establecerDocumentoCliente(String v) =>
      state = state.copyWith(documentoCliente: v, idCliente: null);

  /// Igual que establecerDocumentoCliente pero para el campo de nombre
  /// (RegistrarVentaScreen lo conecta al onChanged del campo "Cliente").
  void establecerNombreClienteManual(String v) =>
      state = state.copyWith(nombreCliente: v, idCliente: null);
  void establecerFecha(DateTime v) => state = state.copyWith(fecha: v);
  void establecerFechaVencimiento(DateTime v) =>
      state = state.copyWith(fechaVencimiento: v);
  void establecerTelefonoCredito(String v) =>
      state = state.copyWith(telefonoCredito: v);
  void establecerOc(String v) => state = state.copyWith(oc: v);
  void establecerRegExonerado(String v) =>
      state = state.copyWith(regExonerado: v);
  void establecerRegSag(String v) => state = state.copyWith(regSag: v);
  void establecerObservaciones(String v) =>
      state = state.copyWith(observaciones: v);
  void establecerPago({required double pagoCon, required double cambio}) {
    state = state.copyWith(pagoCon: pagoCon, cambio: cambio);
  }

  /// Registra el id del documento de 'ventasEnEspera' que quedó respaldando
  /// esta venta en curso tras el primer autoguardado (ver
  /// RegistrarVentaScreen). Distinto de _guardarEnEspera (botón manual, que
  /// además limpia el carrito): esto solo deja la referencia para que el
  /// próximo autoguardado actualice el mismo documento en vez de crear otro.
  void establecerIdEnEspera(String id) =>
      state = state.copyWith(idEnEspera: id);

  void cargarSesion(VentaEnEsperaModel sesion) {
    state = CarritoVentaState(
      idEnEspera: sesion.id,
      items: sesion.items,
      tipoDocumento: sesion.tipoDocumento,
      condicion: sesion.condicion,
      metodoPago: sesion.metodoPago,
      documentoCliente: sesion.documentoCliente,
      nombreCliente: sesion.nombreCliente,
      // Restaura el vínculo real tal cual estaba al poner la venta en
      // espera -sin esto, resumirla la dejaba dependiendo de la
      // re-resolución por nombre en VentaRepository al confirmar, con
      // riesgo de emparejar mal o duplicar el cliente-.
      idCliente: sesion.idCliente,
      fechaVencimiento: sesion.fechaVencimiento,
      oc: sesion.oc,
      regExonerado: sesion.regExonerado,
      regSag: sesion.regSag,
      observaciones: sesion.observaciones,
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
          .map(
            (item) => ItemVentaModel(
              idProducto: item.idProducto,
              idCategoria: item.idCategoria,
              nombreProducto: item.nombreProducto,
              precioVenta: item.precioVenta,
              cantidad: item.cantidad,
              subtotal: item.subtotal,
              precioCompraUsado: item.precioCompraUsado,
              descuentoPorcentaje: item.descuentoPorcentaje,
              componentes: item.componentes,
              codigosColor: item.codigosColor,
              tintesConsumidos: item.tintesConsumidos,
            ),
          )
          .toList(),
      tipoDocumento: (forzarFactura && venta.tipoDocumento == 'Cotizacion')
          ? 'Factura'
          : venta.tipoDocumento,
      condicion: venta.condicion,
      metodoPago: venta.condicion == 'Credito'
          ? ''
          : (venta.metodoPago.isEmpty ? 'Efectivo' : venta.metodoPago),
      documentoCliente: venta.documentoCliente,
      nombreCliente: venta.nombreCliente,
      // La venta original ya tiene un vínculo real a 'clientes' (o no lo
      // tiene, si es de antes de este campo): se copia tal cual, no hay
      // ambigüedad -es el mismo cliente, solo se está duplicando la venta-.
      idCliente: venta.idCliente,
      fechaVencimiento: venta.condicion == 'Credito'
          ? DateTime.now().add(const Duration(days: 30))
          : null,
      oc: venta.oc,
      regExonerado: venta.regExonerado,
      regSag: venta.regSag,
      observaciones: venta.observaciones,
      descuentoGlobalPorcentaje: venta.descuentoGlobal,
    );
  }

  void limpiar() {
    state = CarritoVentaState();
  }
}

final carritoVentaProvider =
    NotifierProvider<CarritoVentaNotifier, CarritoVentaState>(
      CarritoVentaNotifier.new,
    );

/// Qué diseño de Registrar Venta eligió el usuario -pedido explícito del
/// dueño: 'clasica' (la de siempre), 'dividida' (buscador con fotos +
/// carrito lado a lado) o 'dynamics' (tabla del carrito ocupando casi toda
/// la pantalla)-. `build()` arranca en 'clasica' (SharedPreferences no es
/// síncrono la primera vez, mismo motivo que _cargarCredencialFaceId en
/// LoginScreen) y se actualiza sola apenas resuelve la lectura guardada.
class RegistrarVentaVistaNotifier extends Notifier<String> {
  @override
  String build() {
    obtenerVistaGuardada().then((valor) {
      if (ref.mounted && valor != state) state = valor;
    });
    return registrarVentaVistaClasica;
  }

  void elegir(String valor) {
    state = valor;
    guardarVista(valor);
  }
}

final registrarVentaVistaProvider =
    NotifierProvider<RegistrarVentaVistaNotifier, String>(
      RegistrarVentaVistaNotifier.new,
    );
