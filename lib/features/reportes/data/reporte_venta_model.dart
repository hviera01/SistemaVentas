import 'package:cloud_firestore/cloud_firestore.dart';
import '../../ventas/data/pago_detalle_model.dart';

class ReporteVentaModel {
  final String id;
  final DateTime? fechaRegistro;
  final String tipoDocumento;
  final String numeroDocumento;
  final double totalAPagar;
  final int cantidadProductos;
  final String metodoPago;
  final String usuarioRegistro;
  final String documentoCliente;
  final String nombreCliente;
  final double impuesto;
  final String condicion;
  final DateTime? fechaVencimiento;
  final String estado;
  final bool pendienteImpresion;
  // Momento real en que se creó el registro (puesto por el servidor),
  // distinto de fechaRegistro (la fecha de negocio, que el cajero puede
  // elegir a mano). null en ventas viejas de antes de que este campo
  // existiera. Ver ReporteRepository.obtenerReporteVentas.
  final DateTime? creadoEn;
  // Desglose cuando metodoPago == 'Mixto': ver VentaModel.pagosMixtos. Se usa
  // para repartir el ingreso entre efectivo/tarjeta/transferencia en el
  // libro financiero (EgresoRepository.obtenerLibroFinanciero).
  final List<PagoDetalle> pagosMixtos;

  ReporteVentaModel({
    required this.id,
    required this.fechaRegistro,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.totalAPagar,
    required this.cantidadProductos,
    required this.metodoPago,
    required this.usuarioRegistro,
    required this.documentoCliente,
    required this.nombreCliente,
    required this.impuesto,
    required this.condicion,
    required this.fechaVencimiento,
    required this.estado,
    this.pendienteImpresion = false,
    this.creadoEn,
    this.pagosMixtos = const [],
  });

  bool get esActiva => estado == 'Activa';
  bool get esCotizacion => tipoDocumento == 'Cotizacion';

  factory ReporteVentaModel.fromMap(String id, Map<String, dynamic> data) {
    return ReporteVentaModel(
      id: id,
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      tipoDocumento: data['tipoDocumento'] ?? 'Factura',
      numeroDocumento: data['numeroDocumento'] ?? '',
      totalAPagar: (data['totalAPagar'] ?? 0).toDouble(),
      cantidadProductos: (data['cantidadProductos'] ?? 0).toInt(),
      metodoPago: data['metodoPago'] ?? '',
      usuarioRegistro: data['usuarioRegistro'] ?? '',
      documentoCliente: data['documentoCliente'] ?? '',
      nombreCliente: data['nombreCliente'] ?? '',
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      condicion: data['condicion'] ?? '',
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      estado: data['estado'] ?? 'Activa',
      pendienteImpresion: data['pendienteImpresion'] ?? false,
      creadoEn: (data['creadoEn'] as Timestamp?)?.toDate(),
      pagosMixtos: PagoDetalle.listaFromMaps(data['pagosMixtos'] as List<dynamic>?),
    );
  }

  String get textoBusqueda => '$numeroDocumento $nombreCliente $documentoCliente $metodoPago $tipoDocumento $condicion $usuarioRegistro';
}
