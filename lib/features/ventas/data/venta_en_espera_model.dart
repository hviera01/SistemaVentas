import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_venta_model.dart';
import '../../../core/utils/formato_moneda.dart';

/// 'manual': el cajero apretó "Guardar en Espera" a propósito -pedido
/// explícito del dueño: mientras esté así, el stock queda reservado (ver
/// VentaRepository.guardarVentaEnEsperaManual/eliminarVentaEnEspera), hasta
/// que se complete la venta o se elimine desde acá-.
/// 'automatico': autoguardado silencioso de un carrito en curso (ver
/// RegistrarVentaScreen._guardarEnEsperaAutomatico, dispara solo, cada vez
/// que el carrito cambia) -pensado como respaldo por si el cajero cierra la
/// pestaña/se cae la app a mitad de una venta, NO como un "en espera" real:
/// nunca reserva stock, y se ve aparte en "Ver Perdidas", no en "Ver en
/// Espera"-.
class OrigenVentaEnEspera {
  static const manual = 'manual';
  static const automatico = 'automatico';
}

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
  // Ver OrigenVentaEnEspera. Entradas viejas (de antes de este campo) caen
  // en 'automatico' por default -tratarlas como "perdida", no reservaban
  // stock cuando se crearon, así que es lo correcto para esas también-.
  final String origen;
  // true si el stock de [items] está descontado/reservado ahora mismo por
  // esta espera -solo puede pasar con origen manual, ver
  // VentaRepository.guardarVentaEnEsperaManual-. Hace falta guardarlo (no
  // inferirlo solo de origen=='manual') porque una espera manual podría en
  // teoría quedar sin reserva activa si algo falla a mitad de la
  // transacción de guardado -el flag solo se pone en true después de que la
  // reserva de verdad se escribió-.
  final bool stockReservado;
  // Foto INMUTABLE (idProducto -> cantidad) de lo que de verdad se reservó
  // la última vez que guardarVentaEnEsperaManual corrió -NO se recalcula de
  // [items] al leer, y guardarVentaEnEsperaAutomatica nunca la toca-. Hace
  // falta guardarla aparte de [items] porque [items] SÍ puede seguir
  // cambiando mientras la espera sigue abierta (el cajero la recupera y le
  // sigue editando, autoguardado de fondo va actualizando items sin tocar
  // stock): si al soltar la reserva se recalculara desde el [items] de ESE
  // momento en vez de desde esta foto, se devolvería la cantidad EDITADA,
  // no la que en verdad se había descontado -bug real detectado en revisión
  // antes de shippear esto: reservás 3, editás a 5 sin volver a guardar en
  // espera, confirmás la venta (descuenta 5 de verdad), se libera la
  // espera y devuelve 5 en vez de 3, dejando el stock 2 de más-.
  final Map<String, double> cantidadesReservadas;

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
    this.origen = OrigenVentaEnEspera.automatico,
    this.stockReservado = false,
    this.cantidadesReservadas = const {},
  });

  /// Suma de líneas SIN ISV ni descuento global -ver [totalFinal] para el
  /// precio final que de verdad paga el cliente.
  double get total => items.fold<double>(0, (s, i) => s + i.subtotal);

  /// Precio final (con ISV y descuento global aplicados) -mismo cálculo
  /// EXACTO que CarritoVentaState.totalAPagar (ver carrito_provider.dart):
  /// cada línea se calcula con su precio CON ISV (precioVenta*1.15) y su
  /// propio descuento, se suman, se aplica el descuento global, y se
  /// redondea al lempira más cercano (resto >= .90 sube, si no baja).
  /// Pedido explícito del dueño: "los montos en Ver Perdidas o Ver en
  /// Espera tienen que salir con el precio final, estaban saliendo sin
  /// impuesto" -antes se mostraba [total], que es el subtotal sin ISV-.
  double get totalFinal {
    var totalConIsv = 0.0;
    for (final i in items) {
      final precioConIsv = redondearMoneda(i.precioVenta * 1.15);
      totalConIsv += redondearMoneda(precioConIsv * i.cantidad * (1 - i.descuentoPorcentaje / 100));
    }
    totalConIsv *= (1 - descuentoGlobal / 100);
    final base = totalConIsv.floorToDouble();
    final resto = totalConIsv - base;
    return resto >= 0.90 ? base + 1 : base;
  }

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
      origen: data['origen'] ?? OrigenVentaEnEspera.automatico,
      stockReservado: data['stockReservado'] ?? false,
      cantidadesReservadas: (data['cantidadesReservadas'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, (v as num).toDouble())),
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
      'origen': origen,
      'stockReservado': stockReservado,
      'cantidadesReservadas': cantidadesReservadas,
    };
  }
}
