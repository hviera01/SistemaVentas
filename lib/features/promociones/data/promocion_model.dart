import 'package:cloud_firestore/cloud_firestore.dart';

/// Los 4 tipos de promoción que puede armar el usuario:
/// - [porcentaje]: % de descuento sobre uno o varios productos.
/// - [precioFijo]: precio especial (fijo) sobre uno o varios productos.
/// - [comboCantidad]: "llevando [cantidadRequerida] unidades de
///   [idProductoBase], se pagan [precioCombo]" (precio de bulto).
/// - [regalo]: "si lleva [cantidadRequerida] de [idProductoBase], se regalan
///   [cantidadRegalo] de [idProductoRegalo]".
enum TipoPromocion { porcentaje, precioFijo, comboCantidad, regalo }

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
  final double precioCombo;

  /// regalo: producto y cantidad que se regalan al completar
  /// [cantidadRequerida] del producto base.
  final String idProductoRegalo;
  final String nombreProductoRegalo;
  final int cantidadRegalo;

  final DateTime fechaInicio;
  final DateTime? fechaFin;

  /// 'Todos' | 'Contado' | 'Credito' — coincide con el campo `condicion` que
  /// ya usa el resto del sistema (ver CarritoVentaState.condicion).
  final String alcancePago;

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
    this.idProductoRegalo = '',
    this.nombreProductoRegalo = '',
    this.cantidadRegalo = 1,
    required this.fechaInicio,
    this.fechaFin,
    this.alcancePago = 'Todos',
    this.activo = true,
    this.creadoEn,
    this.creadoPor = '',
  });

  bool get esIndefinida => fechaFin == null;
  bool get esPorcentajeOFijo => tipo == TipoPromocion.porcentaje || tipo == TipoPromocion.precioFijo;
  bool get esComboORegalo => tipo == TipoPromocion.comboCantidad || tipo == TipoPromocion.regalo;

  /// Si esta promoción está dentro de su vigencia (fecha y activa) en el
  /// momento [ahora]. No mira método de pago, ver [aplicaCondicion].
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

  bool aplicaAlProducto(String idProducto) {
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
      case TipoPromocion.regalo:
        return 'Lleva $cantidadRequerida y te regalamos $cantidadRegalo';
    }
  }

  factory PromocionModel.fromMap(String id, Map<String, dynamic> data) {
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
      idProductoRegalo: data['idProductoRegalo'] ?? '',
      nombreProductoRegalo: data['nombreProductoRegalo'] ?? '',
      cantidadRegalo: (data['cantidadRegalo'] ?? 1).toInt(),
      fechaInicio: (data['fechaInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechaFin: (data['fechaFin'] as Timestamp?)?.toDate(),
      alcancePago: data['alcancePago'] ?? 'Todos',
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
      'idProductoRegalo': idProductoRegalo,
      'nombreProductoRegalo': nombreProductoRegalo,
      'cantidadRegalo': cantidadRegalo,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': fechaFin == null ? null : Timestamp.fromDate(fechaFin!),
      'alcancePago': alcancePago,
      'activo': activo,
      'creadoEn': creadoEn == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(creadoEn!),
      'creadoPor': creadoPor,
    };
  }

  String get textoBusqueda => '$nombre ${nombresProductos.join(' ')} $nombreProductoBase $nombreProductoRegalo';
}
