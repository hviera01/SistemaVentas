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
  // Quién trajo a este cliente (pintor/contratista referidor) -apunta al id
  // de OTRO ClienteModel con esReferidor == true, ver comentario en ese
  // campo más abajo-.
  final String? idReferidor;
  // true cuando este registro de cliente es, además (o en vez de), un
  // referidor: alguien (típicamente un pintor/contratista) que trae otros
  // clientes. A propósito NO es un módulo/colección aparte -el dueño pidió
  // explícitamente que un referidor sea simplemente un cliente marcado así,
  // manejado desde la misma pantalla de Clientes, y no una sección
  // separada (ver antiguo módulo 'referidores', eliminado)-.
  final bool esReferidor;

  ClienteModel({
    required this.id,
    required this.dni,
    required this.nombreCompleto,
    required this.direccion,
    required this.telefono,
    required this.estado,
    this.fechaUltimaCompra,
    this.idReferidor,
    this.esReferidor = false,
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
      esReferidor: data['esReferidor'] ?? false,
    );
  }

  /// Serialización completa del modelo. OJO: `ClienteRepository.actualizar`
  /// (el editar desde el formulario de Clientes) NO usa esto tal cual para
  /// no pisar `fechaUltimaCompra` con null cada vez que alguien solo corrige
  /// el teléfono -ese campo lo escribe otro flujo (registrar venta)-. Sí se
  /// usa completo en `crear`, donde no hay nada previo que perder.
  Map<String, dynamic> toMap() {
    return {
      'dni': dni,
      'nombreCompleto': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
      'fechaUltimaCompra': fechaUltimaCompra != null ? Timestamp.fromDate(fechaUltimaCompra!) : null,
      'idReferidor': idReferidor,
      'esReferidor': esReferidor,
    };
  }

  String get textoBusqueda => '$dni $nombreCompleto $direccion $telefono';
}
