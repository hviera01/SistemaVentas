import 'package:cloud_firestore/cloud_firestore.dart';

class ClienteModel {
  final String id;
  final String dni;
  final String nombreCompleto;
  final String direccion;
  final String telefono;
  final bool estado;
  // Denormalizado: se actualiza solo (merge) cada vez que este cliente
  // registra una venta real (ver VentaRepository.registrarVenta), para poder
  // detectar clientes inactivos sin tener que recorrer todas sus ventas cada
  // vez (Fase 3 del CRM).
  final DateTime? fechaUltimaCompra;
  // Quién trajo a este cliente (pintor/contratista referidor). Sin UI
  // todavía -se agrega el campo ahora para no tener que tocar este modelo
  // dos veces- ver módulo 'referidores' (Fase 2).
  final String? idReferidor;

  ClienteModel({
    required this.id,
    required this.dni,
    required this.nombreCompleto,
    required this.direccion,
    required this.telefono,
    required this.estado,
    this.fechaUltimaCompra,
    this.idReferidor,
  });

  factory ClienteModel.fromMap(String id, Map<String, dynamic> data) {
    return ClienteModel(
      id: id,
      dni: data['dni'] ?? '',
      nombreCompleto: data['nombreCompleto'] ?? '',
      direccion: data['direccion'] ?? '',
      telefono: data['telefono'] ?? '',
      estado: data['estado'] ?? true,
      fechaUltimaCompra: (data['fechaUltimaCompra'] as Timestamp?)?.toDate(),
      idReferidor: data['idReferidor'] as String?,
    );
  }

  /// Serialización completa del modelo. OJO: `ClienteRepository.actualizar`
  /// (el editar desde el formulario de Clientes) NO usa esto tal cual para
  /// no pisar `fechaUltimaCompra`/`idReferidor` con null cada vez que alguien
  /// solo corrige el teléfono -esos dos campos los escriben otros flujos
  /// (registrar venta, futuro selector de referidor)-. Sí se usa completo en
  /// `crear`, donde no hay nada previo que perder.
  Map<String, dynamic> toMap() {
    return {
      'dni': dni,
      'nombreCompleto': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
      'fechaUltimaCompra': fechaUltimaCompra != null ? Timestamp.fromDate(fechaUltimaCompra!) : null,
      'idReferidor': idReferidor,
    };
  }

  String get textoBusqueda => '$dni $nombreCompleto $direccion $telefono';
}
