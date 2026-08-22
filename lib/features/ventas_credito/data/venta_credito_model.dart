import 'package:cloud_firestore/cloud_firestore.dart';

class FacturaOrigenModel {
  final String id;
  final String numeroDocumento;
  final double saldoPendiente;

  FacturaOrigenModel({required this.id, required this.numeroDocumento, required this.saldoPendiente});

  factory FacturaOrigenModel.fromMap(Map<String, dynamic> data) {
    return FacturaOrigenModel(
      id: data['id'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      saldoPendiente: (data['saldoPendiente'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'numeroDocumento': numeroDocumento, 'saldoPendiente': saldoPendiente};
}

class VentaCreditoModel {
  final String id;
  final String documentoCliente;
  final String nombreCliente;
  // Vínculo real al registro de 'clientes' (ver CRM de clientes, Fase 1).
  // null en créditos manuales sin cliente elegido y en créditos viejos.
  final String? idCliente;
  final String numeroDocumento;
  final double montoTotal;
  final double saldoPendiente;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final bool fusionada;

  /// true cuando este crédito no tiene un documento de venta real asociado
  /// (se creó a mano, se importó desde Excel, o nació de unir facturas) —
  /// en esos casos no existe un `ventas/{id}` que mostrar en "Ver detalle
  /// de venta". Los créditos generados desde una venta real de POS nunca
  /// escriben este campo, así que por defecto (false) sí tienen detalle.
  final bool sinVentaOrigen;

  /// Facturas que se combinaron para formar este crédito (solo aplica a
  /// créditos creados desde "Unir Facturas").
  final List<FacturaOrigenModel> facturasOrigen;

  VentaCreditoModel({
    required this.id,
    required this.documentoCliente,
    required this.nombreCliente,
    this.idCliente,
    required this.numeroDocumento,
    required this.montoTotal,
    required this.saldoPendiente,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.fusionada = false,
    this.sinVentaOrigen = false,
    this.facturasOrigen = const [],
  });

  bool get liquidada => saldoPendiente <= 0;

  bool get vencida => !liquidada && fechaVencimiento != null && DateTime.now().isAfter(fechaVencimiento!);

  bool get esFusion => facturasOrigen.isNotEmpty;

  factory VentaCreditoModel.fromMap(String id, Map<String, dynamic> data) {
    return VentaCreditoModel(
      id: id,
      documentoCliente: data['documentoCliente'] ?? '',
      nombreCliente: data['nombreCliente'] ?? '',
      idCliente: data['idCliente'] as String?,
      numeroDocumento: data['numeroDocumento'] ?? '',
      montoTotal: (data['montoTotal'] ?? 0).toDouble(),
      saldoPendiente: (data['saldoPendiente'] ?? 0).toDouble(),
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      fusionada: data['fusionada'] ?? false,
      sinVentaOrigen: data['sinVentaOrigen'] ?? false,
      facturasOrigen: ((data['facturasOrigen'] as List<dynamic>?) ?? [])
          .map((f) => FacturaOrigenModel.fromMap(Map<String, dynamic>.from(f as Map)))
          .toList(),
    );
  }

  String get textoBusqueda => '$numeroDocumento $nombreCliente $documentoCliente';
}
