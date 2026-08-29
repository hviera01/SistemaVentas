import 'package:cloud_firestore/cloud_firestore.dart';
import 'venta_credito_model.dart';
import 'abono_model.dart';
import 'venta_credito_import_service.dart';
import '../../../core/utils/formato_moneda.dart';

class VentaCreditoRepository {
  final _db = FirebaseFirestore.instance;
  final _col = FirebaseFirestore.instance.collection('ventasCredito');

  String _generarNumeroDocumento() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return ahora.substring(ahora.length - 8);
  }

  Stream<List<VentaCreditoModel>> obtenerCreditos() {
    return _col.orderBy('fechaRegistro', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => VentaCreditoModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// El documento de `ventasCredito` de una venta a crédito se crea con el
  /// mismo id que la venta (ver `VentaRepository.registrarVenta`), así que se
  /// puede ir directo a buscarlo por id en vez de filtrar toda la colección.
  Future<VentaCreditoModel?> obtenerPorId(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return VentaCreditoModel.fromMap(snap.id, snap.data()!);
  }

  Stream<List<AbonoModel>> obtenerAbonos(String idCredito) {
    return _col.doc(idCredito).collection('abonos').orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => AbonoModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// Igual que [obtenerAbonos] pero de una sola vez (no stream): para
  /// agregaciones puntuales como la puntualidad histórica de pago en
  /// Detalle de Cliente, que no necesitan quedar escuchando cambios en vivo.
  Future<List<AbonoModel>> obtenerAbonosUnaVez(String idCredito) async {
    final snap = await _col.doc(idCredito).collection('abonos').get();
    return snap.docs.map((d) => AbonoModel.fromMap(d.id, d.data())).toList();
  }

  /// Créditos de un cliente vinculado, para el aviso de "crédito vencido" al
  /// fiar de nuevo (ver RegistrarVentaScreen/RegistrarCreditoDialog) y para
  /// Detalle de Cliente. Prioriza [idCliente] (vínculo real); si no hay,
  /// cae a [documentoCliente] (RTN/DNI, el único dato confiable que ya
  /// existía antes del vínculo real).
  Future<List<VentaCreditoModel>> obtenerCreditosDeCliente({String? idCliente, String? documentoCliente}) async {
    Query<Map<String, dynamic>> query;
    if (idCliente != null && idCliente.isNotEmpty) {
      query = _col.where('idCliente', isEqualTo: idCliente);
    } else if (documentoCliente != null && documentoCliente.trim().isNotEmpty && documentoCliente.trim() != 'N/A') {
      query = _col.where('documentoCliente', isEqualTo: documentoCliente.trim());
    } else {
      return [];
    }
    final snap = await query.get();
    return snap.docs.map((d) => VentaCreditoModel.fromMap(d.id, d.data())).toList();
  }

  Future<void> crearCreditoManual({
    required String documentoCliente,
    required String nombreCliente,
    String? idCliente,
    required String numeroDocumento,
    required double montoTotal,
    required double saldoPendiente,
    required DateTime fechaVencimiento,
    String telefono = '',
  }) async {
    await _col.add({
      'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
      'nombreCliente': nombreCliente,
      'idCliente': idCliente,
      'numeroDocumento': numeroDocumento.isEmpty ? _generarNumeroDocumento() : numeroDocumento,
      'montoTotal': redondearMoneda(montoTotal),
      'saldoPendiente': redondearMoneda(saldoPendiente),
      'fechaRegistro': FieldValue.serverTimestamp(),
      'fechaVencimiento': Timestamp.fromDate(fechaVencimiento),
      'sinVentaOrigen': true,
      'telefono': telefono.trim(),
    });
  }

  /// Cambia (o agrega) el teléfono de contacto de ESTE crédito puntual, sin
  /// tocar el registro de 'clientes' aunque esté vinculado -pedido explícito
  /// del dueño-. Pensado para la acción "Editar teléfono" de
  /// VentasCreditoScreen, sobre todo en créditos viejos/manuales/importados
  /// que nunca tuvieron cliente vinculado y por eso no reciben el aviso
  /// automático de crédito vencido (ver tool/aviso_creditos_whatsapp).
  Future<void> actualizarTelefono(String id, String telefono) async {
    await _col.doc(id).update({'telefono': telefono.trim()});
  }

  /// Pide que se mande YA el aviso de WhatsApp de crédito vencido para
  /// [idCredito] -botón "Enviar aviso ahora" en VentasCreditoScreen-, sin
  /// esperar a la tarea diaria (ver tool/aviso_creditos_whatsapp/README.md).
  /// El envío real lo hace ese script Node aparte (tiene la sesión de
  /// WhatsApp, la app Flutter no) — acá solo se deja marcado el pedido en el
  /// propio documento del crédito, mismo patrón ya probado que
  /// `solicitudImpresionGuiaEnvio` (ver VentaRepository) para pedirle algo a
  /// la PC principal desde cualquier dispositivo sin necesitar una colección
  /// ni reglas nuevas. `escuchar.js`, corriendo en la PC, lo detecta en unos
  /// segundos, arma el estado de cuenta y lo manda.
  Future<void> solicitarAvisoWhatsApp(String idCredito) async {
    // Limpia el error del intento anterior (si lo hubo): así, si este nuevo
    // intento también falla, `errorAvisoWhatsApp` que muestra la pantalla
    // siempre es del pedido actual, no uno viejo que ya se resolvió.
    await _col.doc(idCredito).update({'solicitudAvisoWhatsApp': true, 'errorAvisoWhatsApp': FieldValue.delete()});
  }

  Future<void> registrarAbono({
    required String idCredito,
    required double saldoAnterior,
    required double montoAbonado,
    required double interes,
    required String metodoPago,
    required String numeroRecibo,
    required String usuario,
    required DateTime fecha,
  }) async {
    if (montoAbonado > saldoAnterior + interes + 0.01) {
      throw Exception('El abono (${formatearMoneda(montoAbonado)}) supera el saldo disponible en este crédito (${formatearMoneda(saldoAnterior + interes)})');
    }
    final nuevoSaldo = redondearMoneda((saldoAnterior - montoAbonado + interes).clamp(0, double.infinity).toDouble());
    final batch = _db.batch();
    batch.update(_col.doc(idCredito), {'saldoPendiente': nuevoSaldo});
    final abonoRef = _col.doc(idCredito).collection('abonos').doc();
    batch.set(abonoRef, {
      'fecha': Timestamp.fromDate(fecha),
      'montoAbonado': redondearMoneda(montoAbonado),
      'saldoAnterior': redondearMoneda(saldoAnterior),
      'interes': redondearMoneda(interes),
      'saldoPendiente': nuevoSaldo,
      'metodoPago': metodoPago,
      'numeroRecibo': numeroRecibo,
      'usuario': usuario,
    });
    await batch.commit();
  }

  /// Ver comentario de `_recalcularCadenaAbonos` en CompraCreditoRepository:
  /// mismo problema (cadena de abonos que depende cada uno del anterior) y
  /// misma solución.
  Future<void> _recalcularCadenaAbonos(String idCredito, double montoTotal) async {
    final abonosSnap = await _col.doc(idCredito).collection('abonos').orderBy('fecha').get();
    final batch = _db.batch();
    var saldo = redondearMoneda(montoTotal);
    for (final doc in abonosSnap.docs) {
      final data = doc.data();
      final montoAbonado = (data['montoAbonado'] ?? 0).toDouble();
      final interes = (data['interes'] ?? 0).toDouble();
      final saldoAnterior = saldo;
      final crudo = saldoAnterior - montoAbonado + interes;
      if (crudo < -0.01) {
        throw Exception('El abono de ${formatearMoneda(montoAbonado)} superaría el saldo disponible en ese momento (${formatearMoneda(saldoAnterior + interes)})');
      }
      saldo = redondearMoneda(crudo.clamp(0, double.infinity).toDouble());
      batch.update(doc.reference, {'saldoAnterior': redondearMoneda(saldoAnterior), 'saldoPendiente': saldo});
    }
    batch.update(_col.doc(idCredito), {'saldoPendiente': saldo});
    await batch.commit();
  }

  Future<void> eliminarAbono({required String idCredito, required String idAbono, required double montoTotal}) async {
    await _col.doc(idCredito).collection('abonos').doc(idAbono).delete();
    await _recalcularCadenaAbonos(idCredito, montoTotal);
  }

  Future<void> editarAbono({
    required String idCredito,
    required String idAbono,
    required double montoTotal,
    required double montoAbonado,
    required double interes,
    required DateTime fecha,
    required String metodoPago,
    required String numeroRecibo,
  }) async {
    await _col.doc(idCredito).collection('abonos').doc(idAbono).update({
      'montoAbonado': redondearMoneda(montoAbonado),
      'interes': redondearMoneda(interes),
      'fecha': Timestamp.fromDate(fecha),
      'metodoPago': metodoPago,
      'numeroRecibo': numeroRecibo,
    });
    await _recalcularCadenaAbonos(idCredito, montoTotal);
  }

  Future<void> unirFacturas({
    required List<VentaCreditoModel> facturas,
    required String documentoCliente,
    required String nombreCliente,
    required DateTime fechaVencimiento,
  }) async {
    final total = redondearMoneda(facturas.fold<double>(0, (s, f) => s + f.saldoPendiente));
    final batch = _db.batch();
    for (final factura in facturas) {
      batch.update(_col.doc(factura.id), {'saldoPendiente': 0, 'fusionada': true});
    }
    // Si una de las facturas que se está uniendo ya era, a su vez, el
    // resultado de una unión anterior, se guardan sus facturas de origen
    // reales en vez de su propio id (que no tiene venta real ni detalle
    // propio) — así el nuevo crédito siempre apunta directo a las ventas
    // reales del fondo, sin importar cuántas uniones se encadenen.
    final facturasOrigenPlanas = <FacturaOrigenModel>[
      for (final factura in facturas)
        if (factura.esFusion)
          ...factura.facturasOrigen
        else
          FacturaOrigenModel(id: factura.id, numeroDocumento: factura.numeroDocumento, saldoPendiente: factura.saldoPendiente),
    ];
    final nuevaRef = _col.doc();
    batch.set(nuevaRef, {
      'documentoCliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
      'nombreCliente': nombreCliente,
      'numeroDocumento': _generarNumeroDocumento(),
      'montoTotal': total,
      'saldoPendiente': total,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'fechaVencimiento': Timestamp.fromDate(fechaVencimiento),
      'sinVentaOrigen': true,
      'facturasOrigen': facturasOrigenPlanas.map((f) => f.toMap()).toList(),
    });
    await batch.commit();
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  /// Crea en lote los créditos de venta de una importación desde Excel.
  /// Cada fila se agrega como un crédito manual nuevo (no empareja con
  /// créditos existentes).
  Future<int> importarCreditos(List<FilaImportacionVentaCredito> filas) async {
    var creados = 0;
    var batch = _db.batch();
    var operacionesEnBatch = 0;

    Future<void> descargarBatch() async {
      if (operacionesEnBatch == 0) return;
      await batch.commit();
      batch = _db.batch();
      operacionesEnBatch = 0;
    }

    for (final fila in filas.where((f) => f.valido)) {
      final ref = _col.doc();
      batch.set(ref, {
        'documentoCliente': fila.documentoCliente.isEmpty ? 'N/A' : fila.documentoCliente,
        'nombreCliente': fila.nombreCliente,
        'numeroDocumento': fila.numeroDocumento.isEmpty ? fila.numeroFila.toString() : fila.numeroDocumento,
        'montoTotal': fila.montoTotal,
        'saldoPendiente': fila.saldoPendiente,
        'fechaRegistro': fila.fechaRegistro != null ? Timestamp.fromDate(fila.fechaRegistro!) : FieldValue.serverTimestamp(),
        'fechaVencimiento': Timestamp.fromDate(fila.fechaVencimiento),
        'sinVentaOrigen': true,
      });
      creados++;
      operacionesEnBatch++;
      if (operacionesEnBatch >= 400) await descargarBatch();
    }
    await descargarBatch();
    return creados;
  }

  Future<List<AbonoModel>> obtenerAbonosPorRango(DateTime inicio, DateTime finInclusive) async {
    final snap = await _db
        .collectionGroup('abonos')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .get();
    return snap.docs.map((d) => AbonoModel.fromMap(d.id, d.data())).toList();
  }
}
