import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_venta_model.dart';

class VentaModel {
  final String id;
  final String tipoDocumento;
  final String numeroDocumento;
  final String documentoCliente;
  final String nombreCliente;
  final String metodoPago;
  final double montoPago;
  final double montoCambio;
  final double subtotal;
  final double impuesto;
  final double totalAPagar;
  final String condicion;
  final DateTime? fechaVencimiento;
  final DateTime? fechaRegistro;
  final String estado;
  final String usuarioRegistro;
  final double cantidadProductos;
  final String oc;
  final String regExonerado;
  final String regSag;
  final double descuentoGlobal;
  final List<ItemVentaModel> detalle;
  final String usuarioAnulacion;
  final String motivoAnulacion;
  final DateTime? fechaAnulacion;
  // true cuando la venta se guardó pero no se pudo imprimir (sin impresora
  // configurada en ese dispositivo, o falló el intento) — típicamente una
  // venta hecha en el celular sin la impresora de red a mano. Se resuelve
  // reimprimiendo desde cualquier dispositivo (ver DetalleVentaScreen).
  final bool pendienteImpresion;
  // true cuando esta venta (hecha desde el celular) le está pidiendo a la
  // PC principal que la imprima automáticamente apenas la detecte, en vez
  // de esperar a que alguien la resuelva a mano desde Pendientes de
  // Impresión. Ver PresenciaImpresionRepository y el listener en AppShell.
  final bool solicitudImpresionEnVivo;
  // Si la solicitud de impresión en vivo es para reimprimir como "copia"
  // (true) u "original" (false): ver DetalleVentaScreen._reimprimir y
  // ImpresionEnVivoService. null (default) significa que no es un
  // reimprimir con elección explícita, sino una venta recién confirmada:
  // ahí se imprime ORIGINAL y, además, COPIA si el negocio tiene esa
  // opción activada (ver VentaExportService.generarPdfFactura) — muy
  // distinto de "false", que fuerza una sola hoja ORIGINAL sin importar esa
  // configuración.
  final bool? solicitudImpresionEsCopia;

  bool get estaAnulada => estado == 'Anulada';

  // Usado para completar con el detalle (items) una VentaModel que ya se
  // tenía con todo lo demás (por ejemplo, la que llega de un stream sin
  // detalle, ver VentaRepository.obtenerVentasConSolicitudImpresionEnVivo)
  // sin tener que releer el documento completo de nuevo — para que la
  // impresión remota en vivo tarde lo menos posible, ver AppShell.
  VentaModel copyWith({List<ItemVentaModel>? detalle}) {
    return VentaModel(
      id: id,
      tipoDocumento: tipoDocumento,
      numeroDocumento: numeroDocumento,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      metodoPago: metodoPago,
      montoPago: montoPago,
      montoCambio: montoCambio,
      subtotal: subtotal,
      impuesto: impuesto,
      totalAPagar: totalAPagar,
      condicion: condicion,
      fechaVencimiento: fechaVencimiento,
      fechaRegistro: fechaRegistro,
      estado: estado,
      usuarioRegistro: usuarioRegistro,
      cantidadProductos: cantidadProductos,
      oc: oc,
      regExonerado: regExonerado,
      regSag: regSag,
      descuentoGlobal: descuentoGlobal,
      detalle: detalle ?? this.detalle,
      usuarioAnulacion: usuarioAnulacion,
      motivoAnulacion: motivoAnulacion,
      fechaAnulacion: fechaAnulacion,
      pendienteImpresion: pendienteImpresion,
      solicitudImpresionEnVivo: solicitudImpresionEnVivo,
      solicitudImpresionEsCopia: solicitudImpresionEsCopia,
    );
  }

  VentaModel({
    required this.id,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.documentoCliente,
    required this.nombreCliente,
    required this.metodoPago,
    required this.montoPago,
    required this.montoCambio,
    required this.subtotal,
    required this.impuesto,
    required this.totalAPagar,
    required this.condicion,
    required this.fechaVencimiento,
    required this.fechaRegistro,
    required this.estado,
    required this.usuarioRegistro,
    required this.cantidadProductos,
    required this.oc,
    required this.regExonerado,
    required this.regSag,
    this.descuentoGlobal = 0,
    required this.detalle,
    this.usuarioAnulacion = '',
    this.motivoAnulacion = '',
    this.fechaAnulacion,
    this.pendienteImpresion = false,
    this.solicitudImpresionEnVivo = false,
    this.solicitudImpresionEsCopia,
  });

  factory VentaModel.fromMap(String id, Map<String, dynamic> data, List<ItemVentaModel> detalle) {
    return VentaModel(
      id: id,
      tipoDocumento: data['tipoDocumento'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      documentoCliente: data['documentoCliente'] ?? '',
      nombreCliente: data['nombreCliente'] ?? '',
      metodoPago: data['metodoPago'] ?? '',
      montoPago: (data['montoPago'] ?? 0).toDouble(),
      montoCambio: (data['montoCambio'] ?? 0).toDouble(),
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      totalAPagar: (data['totalAPagar'] ?? 0).toDouble(),
      condicion: data['condicion'] ?? '',
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      estado: data['estado'] ?? 'Activa',
      usuarioRegistro: data['usuarioRegistro'] ?? '',
      cantidadProductos: (data['cantidadProductos'] ?? 0).toDouble(),
      oc: data['oc'] ?? '',
      regExonerado: data['regExonerado'] ?? '',
      regSag: data['regSag'] ?? '',
      descuentoGlobal: (data['descuentoGlobal'] ?? 0).toDouble(),
      detalle: detalle,
      usuarioAnulacion: data['usuarioAnulacion'] ?? '',
      motivoAnulacion: data['motivoAnulacion'] ?? '',
      fechaAnulacion: (data['fechaAnulacion'] as Timestamp?)?.toDate(),
      pendienteImpresion: data['pendienteImpresion'] ?? false,
      solicitudImpresionEnVivo: data['solicitudImpresionEnVivo'] ?? false,
      solicitudImpresionEsCopia: data['solicitudImpresionEsCopia'] as bool?,
    );
  }
}
