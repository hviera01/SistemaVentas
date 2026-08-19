const _sinCambio = Object();

class ItemCompraModel {
  final String idProducto;
  final String idCategoria;
  final String nombreProducto;
  final double precioCompra;
  final double cantidad;
  final double subtotal;
  final double descuentoPorcentaje;
  // Nuevo precio de venta (con ISV) a aplicar al producto al registrar la
  // compra. Null significa "no cambiar el precio de venta actual".
  final double? precioVentaNuevo;
  // Vínculo manual a una venta anticipada (ver PendienteReposicionModel):
  // para cuando lo que se compra acá es un producto de catálogo DISTINTO al
  // que se facturó -por ejemplo, se vendió "Pintura Preparada" sin saber
  // todavía qué marca real se iba a comprar, y acá se compra "Corona Quinto"
  // para reponerla-. El emparejamiento automático por idProducto (ver
  // CompraRepository.registrarCompra) no puede detectar esto solo porque son
  // productos distintos, así que el cajero lo elige a mano. Si no se vincula
  // nada, sigue aplicando el emparejamiento automático como antes.
  final String? idPendienteReposicionVinculado;
  final String? numeroDocumentoVentaVinculada;
  final String? nombreProductoVentaVinculada;

  ItemCompraModel({
    required this.idProducto,
    required this.idCategoria,
    required this.nombreProducto,
    required this.precioCompra,
    required this.cantidad,
    required this.subtotal,
    this.descuentoPorcentaje = 0,
    this.precioVentaNuevo,
    this.idPendienteReposicionVinculado,
    this.numeroDocumentoVentaVinculada,
    this.nombreProductoVentaVinculada,
  });

  factory ItemCompraModel.fromMap(Map<String, dynamic> data) {
    return ItemCompraModel(
      idProducto: data['idProducto'] ?? '',
      idCategoria: data['idCategoria'] ?? '',
      nombreProducto: data['nombreProducto'] ?? '',
      precioCompra: (data['precioCompra'] ?? 0).toDouble(),
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      descuentoPorcentaje: (data['descuentoPorcentaje'] ?? 0).toDouble(),
      precioVentaNuevo: (data['precioVentaNuevo'] as num?)?.toDouble(),
      idPendienteReposicionVinculado: data['idPendienteReposicionVinculado'] as String?,
      numeroDocumentoVentaVinculada: data['numeroDocumentoVentaVinculada'] as String?,
      nombreProductoVentaVinculada: data['nombreProductoVentaVinculada'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idProducto': idProducto,
      'idCategoria': idCategoria,
      'nombreProducto': nombreProducto,
      'precioCompra': precioCompra,
      'cantidad': cantidad,
      'subtotal': subtotal,
      'descuentoPorcentaje': descuentoPorcentaje,
      'precioVentaNuevo': precioVentaNuevo,
      'idPendienteReposicionVinculado': idPendienteReposicionVinculado,
      'numeroDocumentoVentaVinculada': numeroDocumentoVentaVinculada,
      'nombreProductoVentaVinculada': nombreProductoVentaVinculada,
    };
  }

  ItemCompraModel copyWith({
    double? precioCompra,
    double? cantidad,
    double? subtotal,
    double? descuentoPorcentaje,
    double? precioVentaNuevo,
    Object? idPendienteReposicionVinculado = _sinCambio,
    Object? numeroDocumentoVentaVinculada = _sinCambio,
    Object? nombreProductoVentaVinculada = _sinCambio,
  }) {
    return ItemCompraModel(
      idProducto: idProducto,
      idCategoria: idCategoria,
      nombreProducto: nombreProducto,
      precioCompra: precioCompra ?? this.precioCompra,
      cantidad: cantidad ?? this.cantidad,
      subtotal: subtotal ?? this.subtotal,
      descuentoPorcentaje: descuentoPorcentaje ?? this.descuentoPorcentaje,
      precioVentaNuevo: precioVentaNuevo ?? this.precioVentaNuevo,
      idPendienteReposicionVinculado: idPendienteReposicionVinculado == _sinCambio ? this.idPendienteReposicionVinculado : idPendienteReposicionVinculado as String?,
      numeroDocumentoVentaVinculada: numeroDocumentoVentaVinculada == _sinCambio ? this.numeroDocumentoVentaVinculada : numeroDocumentoVentaVinculada as String?,
      nombreProductoVentaVinculada: nombreProductoVentaVinculada == _sinCambio ? this.nombreProductoVentaVinculada : nombreProductoVentaVinculada as String?,
    );
  }
}
