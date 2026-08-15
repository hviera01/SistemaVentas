import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_compra_model.dart';

class CompraEnEsperaModel {
  final String id;
  final DateTime? fecha;
  final String idProveedor;
  final String documentoProveedor;
  final String razonSocial;
  final String noFactura;
  final String condicion;
  final String metodoPago;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final double descuentoGlobalPorcentaje;
  final double isvPorcentaje;
  final double ajusteManual;
  final List<ItemCompraModel> items;

  CompraEnEsperaModel({
    required this.id,
    required this.fecha,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.razonSocial,
    required this.noFactura,
    required this.condicion,
    required this.metodoPago,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.descuentoGlobalPorcentaje = 0,
    this.isvPorcentaje = 15,
    this.ajusteManual = 0,
    required this.items,
  });

  double get total => items.fold<double>(0, (s, i) => s + i.subtotal);

  factory CompraEnEsperaModel.fromMap(String id, Map<String, dynamic> data) {
    final itemsRaw = (data['items'] as List<dynamic>? ?? []);
    return CompraEnEsperaModel(
      id: id,
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      idProveedor: data['idProveedor'] ?? '',
      documentoProveedor: data['documentoProveedor'] ?? '',
      razonSocial: data['razonSocial'] ?? '',
      noFactura: data['noFactura'] ?? '',
      condicion: data['condicion'] ?? 'Contado',
      metodoPago: data['metodoPago'] ?? 'Efectivo',
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      descuentoGlobalPorcentaje: (data['descuentoGlobalPorcentaje'] ?? 0).toDouble(),
      isvPorcentaje: (data['isvPorcentaje'] ?? 15).toDouble(),
      ajusteManual: (data['ajusteManual'] ?? 0).toDouble(),
      items: itemsRaw.map((e) => ItemCompraModel.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fecha': FieldValue.serverTimestamp(),
      'idProveedor': idProveedor,
      'documentoProveedor': documentoProveedor,
      'razonSocial': razonSocial,
      'noFactura': noFactura,
      'condicion': condicion,
      'metodoPago': metodoPago,
      'fechaRegistro': fechaRegistro != null ? Timestamp.fromDate(fechaRegistro!) : null,
      'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento!) : null,
      'descuentoGlobalPorcentaje': descuentoGlobalPorcentaje,
      'isvPorcentaje': isvPorcentaje,
      'ajusteManual': ajusteManual,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
