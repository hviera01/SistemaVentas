import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_venta_model.dart';
import 'pago_detalle_model.dart';

class VentaModel {
  final String id;
  final String tipoDocumento;
  final String numeroDocumento;
  final String documentoCliente;
  final String nombreCliente;
  // Vínculo real al registro de 'clientes' (a diferencia de
  // documentoCliente/nombreCliente, que son solo texto suelto histórico).
  // null en ventas viejas (de antes de este campo) o cuando el cajero dejó
  // el nombre vacío (Consumidor Final) — ver VentaRepository.registrarVenta.
  final String? idCliente;
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
  final String observaciones;
  final List<ItemVentaModel> detalle;
  // Desglose cuando metodoPago == 'Mixto' (una venta pagada con más de un
  // método a la vez, ej. mitad Efectivo/mitad Tarjeta). Vacío en cualquier
  // otro caso: ahí montoPago/montoCambio/metodoPago ya alcanzan solos.
  final List<PagoDetalle> pagosMixtos;
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
  // Datos de envío -pedido explícito del dueño: poder marcar una venta como
  // envío, con nombre/dirección/teléfono propios (prellenados del cliente
  // pero editables, para envíos a otra persona/dirección), e imprimir una
  // guía aparte del recibo (ver VentaTicketEscPosService.generarGuiaEnvio).
  // Vacíos/false en cualquier venta que no sea envío.
  final bool esEnvio;
  final String envioNombre;
  final String envioDireccion;
  final String envioTelefono;
  // Mismo mecanismo/criterio que solicitudImpresionEnVivo, pero para la
  // guía -pedido explícito del dueño: "que también funcione la impresión y
  // reimpresión de estas guías en remoto, así como toda impresión"-: si
  // este dispositivo no tiene la impresora a mano, le pide a la PC
  // principal que imprima la guía sola apenas la detecte (ver AppShell).
  final bool solicitudImpresionGuiaEnvio;
  final bool solicitudImpresionGuiaGrande;

  bool get estaAnulada => estado == 'Anulada';

  // Usado para completar con el detalle (items) una VentaModel que ya se
  // tenía con todo lo demás (por ejemplo, la que llega de un stream sin
  // detalle, ver VentaRepository.obtenerVentasConSolicitudImpresionEnVivo)
  // sin tener que releer el documento completo de nuevo — para que la
  // impresión remota en vivo tarde lo menos posible, ver AppShell.
  VentaModel copyWith({
    List<ItemVentaModel>? detalle,
    bool? esEnvio,
    String? envioNombre,
    String? envioDireccion,
    String? envioTelefono,
    bool? solicitudImpresionGuiaEnvio,
    bool? solicitudImpresionGuiaGrande,
  }) {
    return VentaModel(
      id: id,
      tipoDocumento: tipoDocumento,
      numeroDocumento: numeroDocumento,
      documentoCliente: documentoCliente,
      nombreCliente: nombreCliente,
      idCliente: idCliente,
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
      observaciones: observaciones,
      detalle: detalle ?? this.detalle,
      pagosMixtos: pagosMixtos,
      usuarioAnulacion: usuarioAnulacion,
      motivoAnulacion: motivoAnulacion,
      fechaAnulacion: fechaAnulacion,
      pendienteImpresion: pendienteImpresion,
      solicitudImpresionEnVivo: solicitudImpresionEnVivo,
      solicitudImpresionEsCopia: solicitudImpresionEsCopia,
      esEnvio: esEnvio ?? this.esEnvio,
      envioNombre: envioNombre ?? this.envioNombre,
      envioDireccion: envioDireccion ?? this.envioDireccion,
      envioTelefono: envioTelefono ?? this.envioTelefono,
      solicitudImpresionGuiaEnvio: solicitudImpresionGuiaEnvio ?? this.solicitudImpresionGuiaEnvio,
      solicitudImpresionGuiaGrande: solicitudImpresionGuiaGrande ?? this.solicitudImpresionGuiaGrande,
    );
  }

  VentaModel({
    required this.id,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.documentoCliente,
    required this.nombreCliente,
    this.idCliente,
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
    this.observaciones = '',
    required this.detalle,
    this.pagosMixtos = const [],
    this.usuarioAnulacion = '',
    this.motivoAnulacion = '',
    this.fechaAnulacion,
    this.pendienteImpresion = false,
    this.solicitudImpresionEnVivo = false,
    this.solicitudImpresionEsCopia,
    this.esEnvio = false,
    this.envioNombre = '',
    this.envioDireccion = '',
    this.envioTelefono = '',
    this.solicitudImpresionGuiaEnvio = false,
    this.solicitudImpresionGuiaGrande = false,
  });

  factory VentaModel.fromMap(String id, Map<String, dynamic> data, List<ItemVentaModel> detalle) {
    return VentaModel(
      id: id,
      tipoDocumento: data['tipoDocumento'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      documentoCliente: data['documentoCliente'] ?? '',
      nombreCliente: data['nombreCliente'] ?? '',
      idCliente: data['idCliente'] as String?,
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
      observaciones: data['observaciones'] ?? '',
      detalle: detalle,
      pagosMixtos: PagoDetalle.listaFromMaps(data['pagosMixtos'] as List<dynamic>?),
      usuarioAnulacion: data['usuarioAnulacion'] ?? '',
      motivoAnulacion: data['motivoAnulacion'] ?? '',
      fechaAnulacion: (data['fechaAnulacion'] as Timestamp?)?.toDate(),
      pendienteImpresion: data['pendienteImpresion'] ?? false,
      solicitudImpresionEnVivo: data['solicitudImpresionEnVivo'] ?? false,
      solicitudImpresionEsCopia: data['solicitudImpresionEsCopia'] as bool?,
      esEnvio: data['esEnvio'] ?? false,
      envioNombre: data['envioNombre'] ?? '',
      envioDireccion: data['envioDireccion'] ?? '',
      envioTelefono: data['envioTelefono'] ?? '',
      solicitudImpresionGuiaEnvio: data['solicitudImpresionGuiaEnvio'] ?? false,
      solicitudImpresionGuiaGrande: data['solicitudImpresionGuiaGrande'] ?? false,
    );
  }
}
