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
  });

  bool get esCombo => componentes.isNotEmpty;

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
    );
  }
}
