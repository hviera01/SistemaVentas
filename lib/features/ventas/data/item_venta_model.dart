/// Receta congelada de un componente de combo al momento de vender: guarda
/// una copia de los datos del producto individual usados para descontar
/// stock, para que anular la venta después siga sabiendo qué reponer aunque
/// el combo se haya editado (o borrado) mientras tanto.
class ComponenteComboSnapshot {
  final String idProducto;
  final String idCategoria;
  final String nombreProducto;
  final double cantidad;
  final double precioCompraUsado;

  ComponenteComboSnapshot({
    required this.idProducto,
    required this.idCategoria,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioCompraUsado,
  });

  Map<String, dynamic> toMap() => {
    'idProducto': idProducto,
    'idCategoria': idCategoria,
    'nombreProducto': nombreProducto,
    'cantidad': cantidad,
    'precioCompraUsado': precioCompraUsado,
  };

  factory ComponenteComboSnapshot.fromMap(Map<String, dynamic> data) {
    return ComponenteComboSnapshot(
      idProducto: data['idProducto'] ?? '',
      idCategoria: data['idCategoria'] ?? '',
      nombreProducto: data['nombreProducto'] ?? '',
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      precioCompraUsado: (data['precioCompraUsado'] ?? 0).toDouble(),
    );
  }
}

/// Un tinte real consumido en una línea de venta -ya sea porque el cajero
/// eligió un código de fórmula conectado a un formula real (Escenario A) o
/// lo cargó a mano (Escenario B), ver CodigosColorDialog-. Snapshot igual
/// que ComponenteComboSnapshot: congela el producto/costo al momento de
/// vender, para que anular la venta después siga sabiendo qué reponer aunque
/// el producto de tinte cambie de nombre/costo mientras tanto.
/// costoUnitario/costoTotal empiezan como un ESTIMADO (calculado por
/// CostoTinteService, con el costo FIFO vigente en ese momento, antes de
/// confirmar la venta) y se sobrescriben con el costo FIFO real dentro de la
/// transacción de VentaRepository.registrarVenta -mismo criterio que ya usa
/// hoy ItemVentaModel.precioCompraUsado con productos normales-.
/// idProductoTinte vacío significa que el colorante no tiene un producto de
/// inventario que le corresponda (ver tinte_lookup.dart): no se pudo costear
/// ni se descuenta stock para esa parte, pero queda igual el registro de que
/// se usó, para que el histórico no pierda el dato.
class TinteConsumidoSnapshot {
  final String colorante;
  final String idProductoTinte;
  final String nombreProductoTinte;
  final double cuartosConsumidos;
  final double costoUnitario;
  final double costoTotal;
  // Qué código de color (ver ItemVentaModel.codigosColor) generó este tinte
  // -null si vino de "Tinte manual" (Escenario B, sin código)-. Se guarda de
  // verdad (no solo en memoria mientras el diálogo está abierto) para que
  // "x" en un código siga borrando su tinte correctamente aunque el cajero
  // haya cerrado y vuelto a abrir CodigosColorDialog sobre la misma línea
  // -antes se perdía el vínculo al reabrir, bug reportado por el dueño-.
  final String? codigoOrigen;

  TinteConsumidoSnapshot({
    required this.colorante,
    required this.idProductoTinte,
    required this.nombreProductoTinte,
    required this.cuartosConsumidos,
    required this.costoUnitario,
    required this.costoTotal,
    this.codigoOrigen,
  });

  Map<String, dynamic> toMap() => {
    'colorante': colorante,
    'idProductoTinte': idProductoTinte,
    'nombreProductoTinte': nombreProductoTinte,
    'cuartosConsumidos': cuartosConsumidos,
    'costoUnitario': costoUnitario,
    'costoTotal': costoTotal,
    'codigoOrigen': codigoOrigen,
  };

  factory TinteConsumidoSnapshot.fromMap(Map<String, dynamic> data) {
    return TinteConsumidoSnapshot(
      colorante: data['colorante'] ?? '',
      idProductoTinte: data['idProductoTinte'] ?? '',
      nombreProductoTinte: data['nombreProductoTinte'] ?? '',
      cuartosConsumidos: (data['cuartosConsumidos'] ?? 0).toDouble(),
      costoUnitario: (data['costoUnitario'] ?? 0).toDouble(),
      costoTotal: (data['costoTotal'] ?? 0).toDouble(),
      codigoOrigen: data['codigoOrigen'] as String?,
    );
  }
}

class ItemVentaModel {
  final String idProducto;
  final String idCategoria;
  final String nombreProducto;
  final double precioVenta;
  final double cantidad;
  final double subtotal;
  final double precioCompraUsado;
  final bool reembasado;
  final double descuentoPorcentaje;
  final List<ComponenteComboSnapshot> componentes;
  // "Venta anticipada": el cajero vendió esto sin saber todavía qué producto
  // exacto va a reponer (por ejemplo, pintura preparada antes de comprar el
  // insumo real). El costo que queda acá es solo un provisional (el vigente
  // del producto al momento de vender); cuando entre la compra real que lo
  // repone, VentaRepository/CompraRepository lo emparejan por FIFO (la venta
  // pendiente más vieja primero, ver PendienteReposicionRepository) y
  // corrigen este campo al costo real de esa compra.
  final bool pendienteCompra;
  // Código(s) de color de pintura usado(s) en esta línea (una línea puede
  // llevar más de uno, ej. una mezcla con dos tintes -ver CodigosColorDialog,
  // que es la única forma de editar esto desde la venta-). Lista vacía por
  // defecto (no todas las líneas son pintura teñida).
  final List<String> codigosColor;
  // Tintes reales consumidos para preparar esta línea (Escenario A/B, ver
  // TinteConsumidoSnapshot). Vacío por defecto -no toda línea de pintura usa
  // tinte adicional-. Independiente de codigosColor: un código de color es
  // solo una anotación de texto, esto es lo que de verdad descuenta stock y
  // suma costo real.
  final List<TinteConsumidoSnapshot> tintesConsumidos;

  ItemVentaModel({
    required this.idProducto,
    required this.idCategoria,
    required this.nombreProducto,
    required this.precioVenta,
    required this.cantidad,
    required this.subtotal,
    required this.precioCompraUsado,
    this.reembasado = false,
    this.descuentoPorcentaje = 0,
    this.componentes = const [],
    this.pendienteCompra = false,
    this.codigosColor = const [],
    this.tintesConsumidos = const [],
  });

  bool get esCombo => componentes.isNotEmpty;

  /// Costo total de tinte de esta línea (suma de todos los colorantes
  /// consumidos) -se muestra y se suma a los reportes SEPARADO del costo del
  /// producto base (precioCompraUsado), pedido explícito del dueño: nunca
  /// mezclados en un solo número.
  double get costoTinteTotal => tintesConsumidos.fold<double>(0, (s, t) => s + t.costoTotal);

  factory ItemVentaModel.fromMap(Map<String, dynamic> data) {
    return ItemVentaModel(
      idProducto: data['idProducto'] ?? '',
      idCategoria: data['idCategoria'] ?? '',
      nombreProducto: data['nombreProducto'] ?? '',
      precioVenta: (data['precioVenta'] ?? 0).toDouble(),
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      precioCompraUsado: (data['precioCompraUsado'] ?? 0).toDouble(),
      reembasado: data['reembasado'] ?? false,
      descuentoPorcentaje: (data['descuentoPorcentaje'] ?? 0).toDouble(),
      componentes: (data['componentes'] as List<dynamic>? ?? [])
          .map((c) => ComponenteComboSnapshot.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      pendienteCompra: data['pendienteCompra'] ?? false,
      codigosColor: (data['codigosColor'] as List<dynamic>? ?? []).map((c) => c.toString()).toList(),
      tintesConsumidos: (data['tintesConsumidos'] as List<dynamic>? ?? [])
          .map((t) => TinteConsumidoSnapshot.fromMap(Map<String, dynamic>.from(t)))
          .toList(),
    );
  }

  /// Fila de `detalle_venta` del histórico (Worker `/historico/detalle` o
  /// `/historico/detalle-rango`). No trae idCategoria ni combos — el sistema
  /// anterior no guardaba esos datos por línea.
  factory ItemVentaModel.fromHistoricoMap(Map<String, dynamic> data) {
    return ItemVentaModel(
      idProducto: '${data['id_producto']}',
      idCategoria: '',
      nombreProducto: (data['nombre_producto'] as String?) ?? '',
      precioVenta: ((data['precio_venta'] as num?) ?? 0).toDouble(),
      cantidad: ((data['cantidad'] as num?) ?? 0).toDouble(),
      subtotal: ((data['subtotal'] as num?) ?? 0).toDouble(),
      precioCompraUsado: ((data['precio_compra_usado'] as num?) ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idProducto': idProducto,
      'idCategoria': idCategoria,
      'nombreProducto': nombreProducto,
      'precioVenta': precioVenta,
      'cantidad': cantidad,
      'subtotal': subtotal,
      'precioCompraUsado': precioCompraUsado,
      'reembasado': reembasado,
      'descuentoPorcentaje': descuentoPorcentaje,
      'componentes': componentes.map((c) => c.toMap()).toList(),
      'pendienteCompra': pendienteCompra,
      'codigosColor': codigosColor,
      'tintesConsumidos': tintesConsumidos.map((t) => t.toMap()).toList(),
    };
  }

  ItemVentaModel copyWith({
    String? nombreProducto,
    double? precioVenta,
    double? cantidad,
    double? subtotal,
    double? descuentoPorcentaje,
    double? precioCompraUsado,
    List<ComponenteComboSnapshot>? componentes,
    bool? pendienteCompra,
    List<String>? codigosColor,
    List<TinteConsumidoSnapshot>? tintesConsumidos,
  }) {
    return ItemVentaModel(
      idProducto: idProducto,
      idCategoria: idCategoria,
      nombreProducto: nombreProducto ?? this.nombreProducto,
      precioVenta: precioVenta ?? this.precioVenta,
      cantidad: cantidad ?? this.cantidad,
      subtotal: subtotal ?? this.subtotal,
      precioCompraUsado: precioCompraUsado ?? this.precioCompraUsado,
      reembasado: reembasado,
      descuentoPorcentaje: descuentoPorcentaje ?? this.descuentoPorcentaje,
      componentes: componentes ?? this.componentes,
      pendienteCompra: pendienteCompra ?? this.pendienteCompra,
      codigosColor: codigosColor ?? this.codigosColor,
      tintesConsumidos: tintesConsumidos ?? this.tintesConsumidos,
    );
  }
}
