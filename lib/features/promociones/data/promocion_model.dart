import 'package:cloud_firestore/cloud_firestore.dart';

/// Los 5 tipos de promoción que puede armar el usuario:
/// - [porcentaje]: % de descuento sobre uno o varios productos.
/// - [precioFijo]: precio especial (fijo) sobre uno o varios productos.
/// - [comboCantidad]: "llevando [cantidadRequerida] unidades de
///   [idProductoBase], se pagan [precioCombo]" (precio de bulto, MISMO
///   producto en cantidad).
/// - [comboMultiproducto]: "llevando 1 unidad de CADA UNO de los productos
///   en [idsProductosCombo] (2 o más productos DISTINTOS), el paquete
///   completo se paga [precioCombo]". No depende de cantidad por producto,
///   solo de que estén todos presentes en el carrito.
/// - [regalo]: "si lleva [cantidadRequerida] de [idProductoBase], se regalan
///   [cantidadRegalo] unidades de CADA producto en [idsProductosRegalo]".
enum TipoPromocion { porcentaje, precioFijo, comboCantidad, comboMultiproducto, regalo }

TipoPromocion tipoPromocionDesdeTexto(String? texto) {
  return TipoPromocion.values.firstWhere((t) => t.name == texto, orElse: () => TipoPromocion.porcentaje);
}

class PromocionModel {
  final String id;
  final String nombre;
  final TipoPromocion tipo;

  /// porcentaje / precioFijo: se aplica individualmente a cada producto de
  /// esta lista (mismo % o mismo precio especial en cada uno).
  final List<String> idsProductos;
  final List<String> nombresProductos;

  /// porcentaje: 0-100. precioFijo: el precio especial en Lempiras (con ISV,
  /// igual que el precio de venta que ve el cajero).
  final double valor;

  /// comboCantidad / regalo: producto sobre el que se cuenta la cantidad
  /// llevada.
  final String idProductoBase;
  final String nombreProductoBase;
  final int cantidadRequerida;

  /// comboCantidad: precio total (con ISV) a pagar por las
  /// [cantidadRequerida] unidades del producto base.
  /// comboMultiproducto: precio total (con ISV) del paquete completo (1
  /// unidad de cada producto en [idsProductosCombo]).
  final double precioCombo;

  /// comboMultiproducto: 2 o más productos DISTINTOS que arman el paquete,
  /// 1 unidad de cada uno.
  final List<String> idsProductosCombo;
  final List<String> nombresProductosCombo;

  /// regalo: productos que se regalan al completar [cantidadRequerida] del
  /// producto base. [cantidadRegalo] es la cantidad regalada de CADA
  /// producto de la lista (ej. cantidadRegalo=1 con 2 productos regalo =
  /// se regala 1 unidad de cada uno de los 2).
  final List<String> idsProductosRegalo;
  final List<String> nombresProductosRegalo;
  final int cantidadRegalo;

  final DateTime fechaInicio;
  final DateTime? fechaFin;

  /// 'Todos' | 'Contado' | 'Credito' — coincide con el campo `condicion` que
  /// ya usa el resto del sistema (ver CarritoVentaState.condicion). El
  /// nombre "alcancePago" es histórico y en realidad filtra por CONDICIÓN,
  /// no por método de pago (ver [metodoPagoAlcance] para eso) — no se
  /// renombra para no romper promociones ya creadas en producción.
  final String alcancePago;

  /// 'Todos' | 'Efectivo' | 'Tarjeta' | 'Transferencia' — filtro
  /// independiente de [alcancePago], coincide con
  /// CarritoVentaState.metodoPago ('Mixto' incluido ahí, pero nunca
  /// matchea un alcance específico acá, solo 'Todos').
  final String metodoPagoAlcance;

  final bool activo;
  final DateTime? creadoEn;
  final String creadoPor;

  PromocionModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.idsProductos = const [],
    this.nombresProductos = const [],
    this.valor = 0,
    this.idProductoBase = '',
    this.nombreProductoBase = '',
    this.cantidadRequerida = 1,
    this.precioCombo = 0,
    this.idsProductosCombo = const [],
    this.nombresProductosCombo = const [],
    this.idsProductosRegalo = const [],
    this.nombresProductosRegalo = const [],
    this.cantidadRegalo = 1,
    required this.fechaInicio,
    this.fechaFin,
    this.alcancePago = 'Todos',
    this.metodoPagoAlcance = 'Todos',
    this.activo = true,
    this.creadoEn,
    this.creadoPor = '',
  });

  bool get esIndefinida => fechaFin == null;
  bool get esPorcentajeOFijo => tipo == TipoPromocion.porcentaje || tipo == TipoPromocion.precioFijo;
  bool get esComboORegalo => tipo == TipoPromocion.comboCantidad || tipo == TipoPromocion.regalo;

  /// Si esta promoción está dentro de su vigencia (fecha y activa) en el
  /// momento [ahora]. No mira método de pago ni condición, ver
  /// [aplicaCondicion] y [aplicaMetodoPago].
  bool vigente(DateTime ahora) {
    if (!activo) return false;
    final inicio = DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day);
    if (ahora.isBefore(inicio)) return false;
    final fin = fechaFin;
    if (fin != null) {
      final finInclusive = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
      if (ahora.isAfter(finInclusive)) return false;
    }
    return true;
  }

  bool aplicaCondicion(String condicion) {
    if (alcancePago == 'Todos') return true;
    return alcancePago == condicion;
  }

  /// [metodoPago]: 'Efectivo' | 'Tarjeta' | 'Transferencia' | 'Mixto' (ver
  /// CarritoVentaState.metodoPago). 'Mixto' nunca matchea un alcance
  /// específico, solo 'Todos' — no tendría sentido restringir un combo a
  /// "Tarjeta" y que aplicara en un pago mixto que ni siquiera se sabe
  /// cuánto fue con tarjeta.
  bool aplicaMetodoPago(String metodoPago) {
    if (metodoPagoAlcance == 'Todos') return true;
    return metodoPagoAlcance == metodoPago;
  }

  bool aplicaAlProducto(String idProducto) {
    if (tipo == TipoPromocion.comboMultiproducto) return idsProductosCombo.contains(idProducto);
    if (esComboORegalo) return idProductoBase == idProducto;
    return idsProductos.contains(idProducto);
  }

  /// Texto corto para el badge/chip del buscador de productos.
  String get etiquetaCorta {
    switch (tipo) {
      case TipoPromocion.porcentaje:
        return '-${valor.toStringAsFixed(valor == valor.roundToDouble() ? 0 : 1)}%';
      case TipoPromocion.precioFijo:
        return 'Precio especial';
      case TipoPromocion.comboCantidad:
        return 'Combo x$cantidadRequerida';
      case TipoPromocion.comboMultiproducto:
        return 'Combo x${idsProductosCombo.length}';
      case TipoPromocion.regalo:
        return 'Lleva $cantidadRequerida y te regalamos $cantidadRegalo';
    }
  }

  factory PromocionModel.fromMap(String id, Map<String, dynamic> data) {
    // Migración de documentos viejos de "regalo" (creados antes de permitir
    // varios productos regalo): si no hay idsProductosRegalo/
    // nombresProductosRegalo todavía, pero sí el campo único idProductoRegalo/
    // nombreProductoRegalo de antes, se envuelve en una lista de 1 elemento
    // para no romper esas promociones ya creadas en producción.
    final idsRegaloNuevo = data['idsProductosRegalo'];
    final idRegaloViejo = data['idProductoRegalo'] as String?;
    final idsProductosRegalo = idsRegaloNuevo is List
        ? List<String>.from(idsRegaloNuevo)
        : (idRegaloViejo != null && idRegaloViejo.isNotEmpty ? [idRegaloViejo] : const <String>[]);

    final nombresRegaloNuevo = data['nombresProductosRegalo'];
    final nombreRegaloViejo = data['nombreProductoRegalo'] as String?;
    final nombresProductosRegalo = nombresRegaloNuevo is List
        ? List<String>.from(nombresRegaloNuevo)
        : (nombreRegaloViejo != null && nombreRegaloViejo.isNotEmpty ? [nombreRegaloViejo] : const <String>[]);

    return PromocionModel(
      id: id,
      nombre: data['nombre'] ?? '',
      tipo: tipoPromocionDesdeTexto(data['tipo'] as String?),
      idsProductos: List<String>.from(data['idsProductos'] ?? const []),
      nombresProductos: List<String>.from(data['nombresProductos'] ?? const []),
      valor: (data['valor'] ?? 0).toDouble(),
      idProductoBase: data['idProductoBase'] ?? '',
      nombreProductoBase: data['nombreProductoBase'] ?? '',
      cantidadRequerida: (data['cantidadRequerida'] ?? 1).toInt(),
      precioCombo: (data['precioCombo'] ?? 0).toDouble(),
      idsProductosCombo: List<String>.from(data['idsProductosCombo'] ?? const []),
      nombresProductosCombo: List<String>.from(data['nombresProductosCombo'] ?? const []),
      idsProductosRegalo: idsProductosRegalo,
      nombresProductosRegalo: nombresProductosRegalo,
      cantidadRegalo: (data['cantidadRegalo'] ?? 1).toInt(),
      fechaInicio: (data['fechaInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechaFin: (data['fechaFin'] as Timestamp?)?.toDate(),
      alcancePago: data['alcancePago'] ?? 'Todos',
      metodoPagoAlcance: data['metodoPagoAlcance'] ?? 'Todos',
      activo: data['activo'] ?? true,
      creadoEn: (data['creadoEn'] as Timestamp?)?.toDate(),
      creadoPor: data['creadoPor'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'tipo': tipo.name,
      'idsProductos': idsProductos,
      'nombresProductos': nombresProductos,
      'valor': valor,
      'idProductoBase': idProductoBase,
      'nombreProductoBase': nombreProductoBase,
      'cantidadRequerida': cantidadRequerida,
      'precioCombo': precioCombo,
      'idsProductosCombo': idsProductosCombo,
      'nombresProductosCombo': nombresProductosCombo,
      'idsProductosRegalo': idsProductosRegalo,
      'nombresProductosRegalo': nombresProductosRegalo,
      'cantidadRegalo': cantidadRegalo,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': fechaFin == null ? null : Timestamp.fromDate(fechaFin!),
      'alcancePago': alcancePago,
      'metodoPagoAlcance': metodoPagoAlcance,
      'activo': activo,
      'creadoEn': creadoEn == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(creadoEn!),
      'creadoPor': creadoPor,
    };
  }

  String get textoBusqueda =>
      '$nombre ${nombresProductos.join(' ')} $nombreProductoBase ${nombresProductosCombo.join(' ')} ${nombresProductosRegalo.join(' ')}';
}
