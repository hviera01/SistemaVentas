import 'package:cloud_firestore/cloud_firestore.dart';

class PermisosEspeciales {
  static const inventarioEditarProducto = 'inventario_editar_producto';
  static const inventarioAjustarStock = 'inventario_ajustar_stock';
  static const ventasCreditoEliminar = 'ventas_credito_eliminar';
  static const ventasCambiarPrecio = 'ventas_cambiar_precio';

  static const Map<String, String> etiquetas = {
    inventarioEditarProducto: 'Editar productos en Inventario',
    inventarioAjustarStock: 'Cambiar existencias en Inventario',
    ventasCreditoEliminar: 'Eliminar créditos en Ventas a Crédito',
    ventasCambiarPrecio: 'Cambiar precio de un producto en Ventas',
  };

  static const Map<String, String> descripciones = {
    inventarioEditarProducto: 'Pide la clave especial antes de guardar cambios en un producto existente.',
    inventarioAjustarStock: 'Pide la clave especial antes de confirmar un ajuste de existencia.',
    ventasCreditoEliminar: 'Pide la clave especial antes de eliminar un crédito.',
    ventasCambiarPrecio: 'Pide la clave especial antes de modificar el precio unitario de un producto dentro de una venta.',
  };
}

class NegocioModel {
  final String nombre;
  final String correo;
  final String rtn;
  final String cai;
  final String direccion;
  final String telefono;
  final String eslogan;
  final String rangoPrefijo;
  final String rangoDesde;
  final String rangoHasta;
  final DateTime? fechaLimiteEmision;
  final String logoColorBase64;
  final String logoBnBase64;
  final String claveEspecialHash;
  final Map<String, bool> permisos;
  final String impresoraTermicaUrl;
  final String impresoraTermicaNombre;
  final String impresoraEtiquetasUrl;
  final String impresoraEtiquetasNombre;
  // Si es false, el ticket de venta solo imprime la hoja "ORIGINAL" (se
  // salta la "COPIA"), para no gastar papel de más cuando no hace falta.
  final bool facturaImprimirCopia;
  // Si es true, el precio unitario y el importe de cada línea del ticket se
  // muestran con ISV incluido (igual que el recuadro "Con ISV" del carrito
  // en Registrar Venta). Si es false (default, comportamiento de siempre)
  // se muestran sin ISV, con el ISV desglosado aparte en el total.
  final bool facturaPreciosConIsv;

  const NegocioModel({
    this.nombre = '',
    this.correo = '',
    this.rtn = '',
    this.cai = '',
    this.direccion = '',
    this.telefono = '',
    this.eslogan = '',
    this.rangoPrefijo = '',
    this.rangoDesde = '',
    this.rangoHasta = '',
    this.fechaLimiteEmision,
    this.logoColorBase64 = '',
    this.logoBnBase64 = '',
    this.claveEspecialHash = '',
    this.permisos = const {},
    this.impresoraTermicaUrl = '',
    this.impresoraTermicaNombre = '',
    this.impresoraEtiquetasUrl = '',
    this.impresoraEtiquetasNombre = '',
    this.facturaImprimirCopia = true,
    this.facturaPreciosConIsv = false,
  });

  bool get tieneClaveEspecial => claveEspecialHash.isNotEmpty;

  bool tienePermiso(String key) => permisos[key] == true;

  factory NegocioModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const NegocioModel();
    return NegocioModel(
      nombre: data['nombre'] ?? '',
      correo: data['correo'] ?? '',
      rtn: data['rtn'] ?? '',
      cai: data['cai'] ?? '',
      direccion: data['direccion'] ?? '',
      telefono: data['telefono'] ?? '',
      eslogan: data['eslogan'] ?? '',
      rangoPrefijo: data['rangoPrefijo'] ?? '',
      rangoDesde: data['rangoDesde'] ?? '',
      rangoHasta: data['rangoHasta'] ?? '',
      fechaLimiteEmision: (data['fechaLimiteEmision'] as Timestamp?)?.toDate(),
      logoColorBase64: data['logoColorBase64'] ?? '',
      logoBnBase64: data['logoBnBase64'] ?? '',
      claveEspecialHash: data['claveEspecialHash'] ?? '',
      permisos: Map<String, bool>.from(data['permisos'] ?? {}),
      impresoraTermicaUrl: data['impresoraTermicaUrl'] ?? '',
      impresoraTermicaNombre: data['impresoraTermicaNombre'] ?? '',
      impresoraEtiquetasUrl: data['impresoraEtiquetasUrl'] ?? '',
      impresoraEtiquetasNombre: data['impresoraEtiquetasNombre'] ?? '',
      facturaImprimirCopia: data['facturaImprimirCopia'] ?? true,
      facturaPreciosConIsv: data['facturaPreciosConIsv'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'correo': correo,
      'rtn': rtn,
      'cai': cai,
      'direccion': direccion,
      'telefono': telefono,
      'eslogan': eslogan,
      'rangoPrefijo': rangoPrefijo,
      'rangoDesde': rangoDesde,
      'rangoHasta': rangoHasta,
      'fechaLimiteEmision': fechaLimiteEmision != null ? Timestamp.fromDate(fechaLimiteEmision!) : null,
      'logoColorBase64': logoColorBase64,
      'logoBnBase64': logoBnBase64,
      'claveEspecialHash': claveEspecialHash,
      'permisos': permisos,
      'impresoraTermicaUrl': impresoraTermicaUrl,
      'impresoraTermicaNombre': impresoraTermicaNombre,
      'impresoraEtiquetasUrl': impresoraEtiquetasUrl,
      'impresoraEtiquetasNombre': impresoraEtiquetasNombre,
      'facturaImprimirCopia': facturaImprimirCopia,
      'facturaPreciosConIsv': facturaPreciosConIsv,
    };
  }

  NegocioModel copyWith({
    String? nombre,
    String? correo,
    String? rtn,
    String? cai,
    String? direccion,
    String? telefono,
    String? eslogan,
    String? rangoPrefijo,
    String? rangoDesde,
    String? rangoHasta,
    DateTime? fechaLimiteEmision,
    String? logoColorBase64,
    String? logoBnBase64,
    String? claveEspecialHash,
    Map<String, bool>? permisos,
    bool? facturaImprimirCopia,
    bool? facturaPreciosConIsv,
  }) {
    return NegocioModel(
      nombre: nombre ?? this.nombre,
      correo: correo ?? this.correo,
      rtn: rtn ?? this.rtn,
      cai: cai ?? this.cai,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      eslogan: eslogan ?? this.eslogan,
      rangoPrefijo: rangoPrefijo ?? this.rangoPrefijo,
      rangoDesde: rangoDesde ?? this.rangoDesde,
      rangoHasta: rangoHasta ?? this.rangoHasta,
      fechaLimiteEmision: fechaLimiteEmision ?? this.fechaLimiteEmision,
      logoColorBase64: logoColorBase64 ?? this.logoColorBase64,
      logoBnBase64: logoBnBase64 ?? this.logoBnBase64,
      claveEspecialHash: claveEspecialHash ?? this.claveEspecialHash,
      permisos: permisos ?? this.permisos,
      impresoraTermicaUrl: impresoraTermicaUrl,
      impresoraTermicaNombre: impresoraTermicaNombre,
      impresoraEtiquetasUrl: impresoraEtiquetasUrl,
      impresoraEtiquetasNombre: impresoraEtiquetasNombre,
      facturaImprimirCopia: facturaImprimirCopia ?? this.facturaImprimirCopia,
      facturaPreciosConIsv: facturaPreciosConIsv ?? this.facturaPreciosConIsv,
    );
  }
}
