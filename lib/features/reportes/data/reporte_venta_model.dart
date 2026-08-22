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
  // Vínculo real al registro de 'clientes' (ver CRM de clientes, Fase 1).
  // null en ventas de antes de ese vínculo, o hechas sin cliente elegido -ver
  // ReporteFinancieroRepository._agruparClientesTop, que lo usa para agrupar
  // con más precisión que solo el texto de nombreCliente-.
  final String? idCliente;
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
  // 'firestore' (sistema actual) o 'historico' (sistema anterior, vía D1/Worker
  // — ver HistoricoVentaService). Nunca se mezclan por numeroDocumento porque
  // los rangos de numeración de ambos sistemas se traslapan.
  final String origen;

  bool get esHistorica => origen == 'historico';

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
    this.idCliente,
    required this.impuesto,
    required this.condicion,
    required this.fechaVencimiento,
    required this.estado,
    this.pendienteImpresion = false,
    this.creadoEn,
    this.pagosMixtos = const [],
    this.origen = 'firestore',
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
      idCliente: data['idCliente'] as String?,
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      condicion: data['condicion'] ?? '',
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      estado: data['estado'] ?? 'Activa',
      pendienteImpresion: data['pendienteImpresion'] ?? false,
      creadoEn: (data['creadoEn'] as Timestamp?)?.toDate(),
      pagosMixtos: PagoDetalle.listaFromMaps(data['pagosMixtos'] as List<dynamic>?),
    );
  }

  /// Fila del histórico (sistema anterior, servida por el Worker en
  /// `/historico/ventas`). El `id` se prefija con `historico:` para que
  /// nunca choque con un id autogenerado de Firestore ni con el
  /// numeroDocumento (que sí se traslapa entre ambos sistemas).
  factory ReporteVentaModel.fromHistorico(Map<String, dynamic> data) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return ReporteVentaModel(
      id: 'historico:${data['id_venta']}',
      fechaRegistro: fecha(data['fecha_registro'] as String?),
      tipoDocumento: (data['tipo_documento'] as String?) ?? 'Factura',
      numeroDocumento: (data['numero_documento'] as String?) ?? '',
      totalAPagar: ((data['monto_total'] as num?) ?? 0).toDouble(),
      cantidadProductos: ((data['cantidad_productos'] as num?) ?? 0).toInt(),
      metodoPago: (data['metodo_pago'] as String?) ?? '',
      usuarioRegistro: '',
      documentoCliente: (data['documento_cliente'] as String?) ?? '',
      nombreCliente: (data['nombre_cliente'] as String?) ?? '',
      impuesto: ((data['impuesto'] as num?) ?? 0).toDouble(),
      condicion: (data['condicion'] as String?) ?? '',
      fechaVencimiento: fecha(data['fecha_vencimiento'] as String?),
      estado: (data['estado'] as String?) ?? 'Activa',
      origen: 'historico',
    );
  }

  String get textoBusqueda => '$numeroDocumento $nombreCliente $documentoCliente $metodoPago $tipoDocumento $condicion $usuarioRegistro';
}
