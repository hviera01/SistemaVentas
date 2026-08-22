import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_venta_model.dart';

class VentaEnEsperaModel {
  final String id;
  final DateTime? fecha;
  final String tipoDocumento;
  final String condicion;
  final String metodoPago;
  final String documentoCliente;
  final String nombreCliente;
  // Vínculo real al registro de 'clientes' (ver CRM de clientes, Fase 1):
  // se guarda para que "guardar en espera" y recuperarla después no pierda
  // el cliente elegido/auto-registrado, sin tener que re-resolverlo por
  // nombre al confirmar -ver VentaRepository._resolverIdCliente, que solo
  // entra a jugar cuando esto viene null-.
  final String? idCliente;
  final DateTime? fechaVencimiento;
  final String oc;
  final String regExonerado;
  final String regSag;
  final String observaciones;
  final double descuentoGlobal;
  final List<ItemVentaModel> items;

  VentaEnEsperaModel({
    required this.id,
    required this.fecha,
    required this.tipoDocumento,
    required this.condicion,
    required this.metodoPago,
    required this.documentoCliente,
    required this.nombreCliente,
    this.idCliente,
    required this.fechaVencimiento,
    required this.oc,
    required this.regExonerado,
    required this.regSag,
    this.observaciones = '',
    this.descuentoGlobal = 0,
    required this.items,
  });

  double get total => items.fold<double>(0, (s, i) => s + i.subtotal);

  factory VentaEnEsperaModel.fromMap(String id, Map<String, dynamic> data) {
    final itemsRaw = (data['items'] as List<dynamic>? ?? []);
    return VentaEnEsperaModel(
      id: id,
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      tipoDocumento: data['tipoDocumento'] ?? 'Factura',
      condicion: data['condicion'] ?? 'Contado',
      metodoPago: data['metodoPago'] ?? 'Efectivo',
      documentoCliente: data['documentoCliente'] ?? '',
      nombreCliente: data['nombreCliente'] ?? '',
      idCliente: data['idCliente'] as String?,
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      oc: data['oc'] ?? '',
      regExonerado: data['regExonerado'] ?? '',
      regSag: data['regSag'] ?? '',
      observaciones: data['observaciones'] ?? '',
      descuentoGlobal: (data['descuentoGlobal'] ?? 0).toDouble(),
      items: itemsRaw.map((e) => ItemVentaModel.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fecha': FieldValue.serverTimestamp(),
      'tipoDocumento': tipoDocumento,
      'condicion': condicion,
      'metodoPago': metodoPago,
      'documentoCliente': documentoCliente,
      'nombreCliente': nombreCliente,
      'idCliente': idCliente,
      'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento!) : null,
      'oc': oc,
      'regExonerado': regExonerado,
      'regSag': regSag,
      'observaciones': observaciones,
      'descuentoGlobal': descuentoGlobal,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
