import 'package:cloud_firestore/cloud_firestore.dart';
import 'compra_en_espera_model.dart';
import 'compra_model.dart';
import 'item_compra_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../productos/data/lote_costo_repository.dart';

/// Ver comentario equivalente en VentaRepository: los ítems de una compra
/// también se guardan en una subcolección 'detalle' con id autogenerado, y
/// esta función los reordena según el campo 'orden' guardado al registrar.
List<QueryDocumentSnapshot<Map<String, dynamic>>> _ordenarDetalle(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final conIndice = docs.asMap().entries.toList();
  conIndice.sort((a, b) {
    final ordenA = a.value.data()['orden'] as int?;
    final ordenB = b.value.data()['orden'] as int?;
    if (ordenA == null && ordenB == null) return a.key.compareTo(b.key);
    if (ordenA == null) return 1;
    if (ordenB == null) return -1;
    return ordenA.compareTo(ordenB);
  });
  return conIndice.map((e) => e.value).toList();
}

String _formatoCantidad(double cantidad) {
  if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
  return cantidad.toStringAsFixed(2);
}

class CompraRepository {
  final _db = FirebaseFirestore.instance;
  final _colCompras = FirebaseFirestore.instance.collection('compras');
  final _colContadores = FirebaseFirestore.instance.collection('contadores');
  final _colComprasCredito = FirebaseFirestore.instance.collection('comprasCredito');
  final _colEspera = FirebaseFirestore.instance.collection('comprasEnEspera');
  final _colPendientesReposicion = FirebaseFirestore.instance.collection('pendientesReposicion');
  final _lotes = LoteCostoRepository();

  // ---------- Compras en espera (borrador autoguardado) ----------
  //
  // Mismo patrón que VentaRepository.*VentaEnEspera, pero acá el guardado lo
  // dispara solo RegistrarCompraScreen (autoguardado con debounce) en vez de
  // un botón manual: así una compra en curso nunca queda solo en la memoria
  // de la pestaña -si el navegador la recarga sola (p.ej. "ahorro de
  // memoria" descartando la pestaña en segundo plano), sin internet, o se
  // cierra la app, el borrador ya está en Firestore y se recupera desde "Ver
  // en Espera".

  Stream<List<CompraEnEsperaModel>> obtenerComprasEnEspera() {
    return _colEspera.orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => CompraEnEsperaModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<String> guardarCompraEnEspera(CompraEnEsperaModel sesion) async {
    final ref = await _colEspera.add(sesion.toMap());
    return ref.id;
  }

  Future<void> actualizarCompraEnEspera(String id, CompraEnEsperaModel sesion) async {
    await _colEspera.doc(id).update(sesion.toMap());
  }

  Future<void> eliminarCompraEnEspera(String id) async {
    await _colEspera.doc(id).delete();
  }

  String _formatearCorrelativo(int numero) => numero.toString().padLeft(8, '0');

  Future<CompraModel> registrarCompra({
    required String noFactura,
    required String idProveedor,
    required String documentoProveedor,
    required String razonSocial,
    required String condicion,
    required String metodoPago,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    double descuentoGlobalPorcentaje = 0,
    double descuentoTotalMonto = 0,
    double isvPorcentaje = 15,
    double ajusteManual = 0,
    required List<ItemCompraModel> items,
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
  }) async {
    final contadorRef = _colContadores.doc('compra');
    final compraRef = _colCompras.doc();

    late String numeroDocumento;

    // "Venta anticipada": por cada producto distinto de esta compra (de las
    // líneas que no se vincularon a mano a una venta específica, ver más
    // abajo) se busca si hay ventas ya registradas del MISMO producto que se
    // vendieron sin saber todavía cuál compra las iba a reponer (ver
    // VentaRepository.registrarVenta y PendienteReposicionRepository).
    // Firestore no permite consultas con .where() dentro de una transacción
    // del cliente, así que esto se trae ANTES de abrir la transacción -mismo
    // trade-off ya aceptado para los lotes de costo en VentaRepository: el
    // riesgo de que dos compras concurrentes del mismo producto repartan la
    // misma venta pendiente es mínimo para el volumen de este negocio-.
    final idsProductoUnicos = items.where((i) => i.idPendienteReposicionVinculado == null).map((i) => i.idProducto).toSet().toList();
    final pendientesPorProducto = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    await Future.wait(idsProductoUnicos.map((id) async {
      final snap = await _colPendientesReposicion
          .where('idProducto', isEqualTo: id)
          .where('estado', isEqualTo: 'Pendiente')
          .orderBy('fechaRegistro')
          .get();
      pendientesPorProducto[id] = snap.docs;
    }));

    // Líneas vinculadas a mano (ver VincularPendienteDialog): cuando el
    // producto comprado es distinto al que se facturó, el cajero elige a
    // cuál venta pendiente corresponde en vez de depender del emparejamiento
    // automático por idProducto de arriba. Como ya se conoce el id exacto,
    // esto sí se puede leer DENTRO de la transacción (transaction.get por
    // referencia directa, no una query).
    final idsVinculadosUnicos = items.map((i) => i.idPendienteReposicionVinculado).whereType<String>().toSet().toList();

    // Timeout corto (el default del SDK es 30s): en cajas con internet
    // lento/intermitente es mejor que se vea rápido que falló y se pueda
    // reintentar, a que la pantalla quede "cargando" media hora.
    await _db.runTransaction((transaction) async {
      final contadorSnap = await transaction.get(contadorRef);
      final actual = ((contadorSnap.data()?['ultimo'] ?? 0) as num).toInt();
      final nuevo = actual + 1;
      numeroDocumento = _formatearCorrelativo(nuevo);

      // Lecturas en paralelo (Future.wait) en vez de una por una: con varios
      // productos en la compra, esperar cada round-trip en serie hacía que
      // registrar una compra se sintiera colgado con internet lento.
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        items.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < items.length; i++) {
        stocksActuales[items[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      final snapsVinculados = await Future.wait(
        idsVinculadosUnicos.map((id) => transaction.get(_colPendientesReposicion.doc(id))),
      );

      transaction.set(contadorRef, {'ultimo': nuevo}, SetOptions(merge: true));

      transaction.set(compraRef, {
        'tipoDocumento': 'Factura',
        'numeroDocumento': numeroDocumento,
        'noFactura': noFactura,
        'idProveedor': idProveedor,
        'documentoProveedor': documentoProveedor,
        'razonSocial': razonSocial,
        'condicion': condicion,
        'metodoPago': metodoPago,
        'subtotal': subtotal,
        'descuentoGlobalPorcentaje': descuentoGlobalPorcentaje,
        'descuentoTotalMonto': descuentoTotalMonto,
        'isvPorcentaje': isvPorcentaje,
        'impuesto': impuesto,
        'ajusteManual': ajusteManual,
        'totalAPagar': totalAPagar,
        'fechaRegistro': Timestamp.fromDate(fechaRegistro),
        'fechaVencimiento': fechaVencimiento != null ? Timestamp.fromDate(fechaVencimiento) : null,
        'estado': 'Activa',
        'usuarioRegistro': usuario,
        'cantidadProductos': items.fold<double>(0, (s, i) => s + i.cantidad),
      });

      for (final entry in items.asMap().entries) {
        final item = entry.value;
        final itemRef = compraRef.collection('detalle').doc();
        // 'fecha' permite consultar el detalle de todas las compras de un
        // rango con una sola query (collectionGroup) en vez de tener que
        // leer la subcolección de cada compra una por una. 'orden' es la
        // posición de la línea en el carrito, para que la reimpresión
        // respete el mismo orden con el que se registró (ver _ordenarDetalle).
        transaction.set(itemRef, {...item.toMap(), 'fecha': Timestamp.fromDate(fechaRegistro), 'orden': entry.key});
      }

      if (condicion == 'Credito') {
        transaction.set(_colComprasCredito.doc(compraRef.id), {
          'idProveedor': idProveedor,
          'documentoProveedor': documentoProveedor.isEmpty ? 'N/A' : documentoProveedor,
          'nombreProveedor': razonSocial,
          'numeroDocumento': numeroDocumento,
          'noFactura': noFactura,
          'montoTotal': totalAPagar,
          'saldoPendiente': totalAPagar,
          'fechaRegistro': Timestamp.fromDate(fechaRegistro),
          'fechaVencimiento': Timestamp.fromDate(fechaVencimiento ?? fechaRegistro),
          'manual': false,
        });
      }

      // Estado mutable de cada venta pendiente que esta compra vaya tocando:
      // hace falta compartido (no solo leer doc.data() cada vez) porque la
      // misma compra puede traer más de una línea del mismo producto -por
      // ejemplo, la misma referencia con dos descuentos distintos-, y la
      // segunda línea tiene que ver lo que la primera ya le aplicó, no los
      // datos "viejos" de antes de que empezara esta compra.
      final estadoPendientes = <String, ({double cantidadPendiente, double cantidadOriginal, double costoRegistrado, String idVenta, String idItemDetalle, String numeroDocumentoVenta})>{};
      final refsPendientes = <String, DocumentReference<Map<String, dynamic>>>{};
      final pendientesTocados = <String>{};
      for (final lista in pendientesPorProducto.values) {
        for (final doc in lista) {
          final data = doc.data();
          estadoPendientes[doc.id] = (
            cantidadPendiente: ((data['cantidadPendiente'] ?? 0) as num).toDouble(),
            cantidadOriginal: ((data['cantidadOriginal'] ?? 0) as num).toDouble(),
            costoRegistrado: ((data['costoRegistrado'] ?? 0) as num).toDouble(),
            idVenta: data['idVenta'] as String? ?? '',
            idItemDetalle: data['idItemDetalle'] as String? ?? '',
            numeroDocumentoVenta: data['numeroDocumentoVenta'] as String? ?? '',
          );
          refsPendientes[doc.id] = doc.reference;
        }
      }
      // Se suman también las vinculadas a mano (mismo mapa: si por alguna
      // razón coincidieran con una ya cargada arriba, no pasa nada, es el
      // mismo doc con los mismos datos). Si la venta vinculada ya se
      // completó o se canceló mientras tanto, no se agrega -la línea de
      // compra simplemente no encuentra nada que repartir y su cantidad
      // queda como stock disponible normal, sin romper el registro-.
      for (final snap in snapsVinculados) {
        if (!snap.exists) continue;
        final data = snap.data()!;
        if (data['estado'] != 'Pendiente') continue;
        estadoPendientes[snap.id] = (
          cantidadPendiente: ((data['cantidadPendiente'] ?? 0) as num).toDouble(),
          cantidadOriginal: ((data['cantidadOriginal'] ?? 0) as num).toDouble(),
          costoRegistrado: ((data['costoRegistrado'] ?? 0) as num).toDouble(),
          idVenta: data['idVenta'] as String? ?? '',
          idItemDetalle: data['idItemDetalle'] as String? ?? '',
          numeroDocumentoVenta: data['numeroDocumentoVenta'] as String? ?? '',
        );
        refsPendientes[snap.id] = snap.reference;
      }
      // Mismo motivo: el stock "de partida" de cada línea tiene que ser el
      // que dejó la línea anterior de ese mismo producto en esta compra, no
      // siempre el mismo valor leído al principio.
      final stockAcumulado = Map<String, double>.from(stocksActuales);

      for (final item in items) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stockAcumulado[item.idProducto] ?? 0;

        // Costo vigente del producto: precio unitario menos el descuento de
        // línea (importe gravado), más el ISV de esta compra.
        final precioFinalConIsv = redondearMoneda(item.precioCompra * (1 - item.descuentoPorcentaje / 100) * (1 + isvPorcentaje / 100));

        // Reparte esta compra contra ventas anticipadas ANTES de dejar el
        // resto como existencia disponible: esa cantidad ya estaba vendida
        // de antemano -no debe quedar sumada al stock como si estuviera
        // libre para vender de nuevo-, y de paso corrige el costo de esas
        // ventas (que se había guardado provisional) al costo real de esta
        // compra. Si el cajero vinculó esta línea a mano a una venta
        // específica (producto distinto al facturado, ver
        // VincularPendienteDialog) se reparte solo contra esa; si no, se
        // reparte automático contra las más viejas del mismo producto.
        var disponibleParaPendientes = item.cantidad;
        final numerosVentaCubiertas = <String>{};

        void aplicarContra(String idPendiente) {
          if (disponibleParaPendientes <= 0) return;
          final estado = estadoPendientes[idPendiente];
          if (estado == null || estado.cantidadPendiente <= 0) return;
          final aplicado = disponibleParaPendientes >= estado.cantidadPendiente ? estado.cantidadPendiente : disponibleParaPendientes;
          final nuevaCantidadPendiente = redondearMoneda(estado.cantidadPendiente - aplicado);

          // Costo ponderado: si esta venta pendiente ya se había completado
          // parcialmente antes (otra compra anterior, o otra línea de esta
          // misma, cubrió parte de la cantidad), el costo final es el
          // promedio ponderado entre lo ya cubierto y lo que cubre esto
          // -igual que el costeo FIFO normal de una venta (ver
          // LoteCostoRepository.consumir)-.
          final cantidadYaCubierta = estado.cantidadOriginal - estado.cantidadPendiente;
          final baseCosteo = cantidadYaCubierta + aplicado;
          final costoPonderado = baseCosteo <= 0 ? precioFinalConIsv : ((estado.costoRegistrado * cantidadYaCubierta) + (precioFinalConIsv * aplicado)) / baseCosteo;

          estadoPendientes[idPendiente] = (
            cantidadPendiente: nuevaCantidadPendiente,
            cantidadOriginal: estado.cantidadOriginal,
            costoRegistrado: costoPonderado,
            idVenta: estado.idVenta,
            idItemDetalle: estado.idItemDetalle,
            numeroDocumentoVenta: estado.numeroDocumentoVenta,
          );

          if (estado.idVenta.isNotEmpty && estado.idItemDetalle.isNotEmpty) {
            transaction.update(
              _db.collection('ventas').doc(estado.idVenta).collection('detalle').doc(estado.idItemDetalle),
              {'precioCompraUsado': costoPonderado},
            );
          }
          if (estado.numeroDocumentoVenta.isNotEmpty) numerosVentaCubiertas.add(estado.numeroDocumentoVenta);
          pendientesTocados.add(idPendiente);

          disponibleParaPendientes -= aplicado;
        }

        final idVinculado = item.idPendienteReposicionVinculado;
        if (idVinculado != null) {
          aplicarContra(idVinculado);
        } else {
          for (final doc in pendientesPorProducto[item.idProducto] ?? const []) {
            if (disponibleParaPendientes <= 0) break;
            aplicarContra(doc.id);
          }
        }

        final cantidadAplicadaAPendientes = redondearMoneda(item.cantidad - disponibleParaPendientes);
        final stockNuevo = stockActual + item.cantidad - cantidadAplicadaAPendientes;
        stockAcumulado[item.idProducto] = stockNuevo;

        final Map<String, dynamic> actualizacion = {'stock': stockNuevo, 'precioCompra': precioFinalConIsv};
        if (item.precioVentaNuevo != null) {
          actualizacion['precioVenta'] = item.precioVentaNuevo!;
        }
        transaction.update(ref, actualizacion);

        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': cantidadAplicadaAPendientes > 0
              ? 'Compra $numeroDocumento (${_formatoCantidad(cantidadAplicadaAPendientes)} ya vendida por adelantado en factura(s) ${numerosVentaCubiertas.join(', ')})'
              : 'Compra $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });

        final historialPrecioRef = ref.collection('historialPreciosCompra').doc();
        transaction.set(historialPrecioRef, {
          'idCompra': compraRef.id,
          'precioCompra': precioFinalConIsv,
          'precioUnitario': item.precioCompra,
          'descuentoPorcentaje': item.descuentoPorcentaje,
          'isvPorcentaje': isvPorcentaje,
          'cantidad': item.cantidad,
          'numeroDocumento': numeroDocumento,
          'noFactura': noFactura,
          'proveedor': razonSocial,
          'usuario': usuario,
          'fecha': FieldValue.serverTimestamp(),
        });

        // Lote de costo propio para esta compra: es lo que permite que,
        // si el mismo producto se compró antes a otro precio, cada venta
        // futura consuma el costo real del lote que le toca (FIFO) en vez
        // de un costo único por producto. cantidadRestante ya sale rebajada
        // por lo que se acaba de repartir contra ventas pendientes -esas
        // unidades ya están vendidas, no están libres para una venta futura-.
        _lotes.crearLote(
          transaction,
          item.idProducto,
          cantidad: item.cantidad,
          cantidadRestante: item.cantidad - cantidadAplicadaAPendientes,
          costoUnitario: precioFinalConIsv,
          fecha: fechaRegistro,
          origen: 'compra',
          idCompra: compraRef.id,
        );
      }

      // Escribe el estado final de cada pendiente que esta compra tocó, una
      // sola vez cada una (aunque más de una línea de esta misma compra la
      // haya tocado, ver estadoPendientes arriba).
      for (final id in pendientesTocados) {
        final estado = estadoPendientes[id]!;
        transaction.update(refsPendientes[id]!, {
          'cantidadPendiente': estado.cantidadPendiente,
          'costoRegistrado': estado.costoRegistrado,
          if (estado.cantidadPendiente <= 0) 'estado': 'Completado',
          if (estado.cantidadPendiente <= 0) 'fechaCompletado': FieldValue.serverTimestamp(),
        });
      }
    }, timeout: const Duration(seconds: 12));

    return CompraModel(
      id: compraRef.id,
      tipoDocumento: 'Factura',
      numeroDocumento: numeroDocumento,
      noFactura: noFactura,
      idProveedor: idProveedor,
      documentoProveedor: documentoProveedor,
      razonSocial: razonSocial,
      condicion: condicion,
      metodoPago: metodoPago,
      subtotal: subtotal,
      descuentoGlobalPorcentaje: descuentoGlobalPorcentaje,
      descuentoTotalMonto: descuentoTotalMonto,
      isvPorcentaje: isvPorcentaje,
      impuesto: impuesto,
      ajusteManual: ajusteManual,
      totalAPagar: totalAPagar,
      fechaRegistro: fechaRegistro,
      fechaVencimiento: fechaVencimiento,
      estado: 'Activa',
      usuarioRegistro: usuario,
      cantidadProductos: items.fold<double>(0, (s, i) => s + i.cantidad),
      detalle: items,
    );
  }

  Future<CompraModel?> obtenerCompraPorId(String id) async {
    final snap = await _colCompras.doc(id).get();
    if (!snap.exists) return null;
    final detalleSnap = await _colCompras.doc(id).collection('detalle').get();
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemCompraModel.fromMap(d.data())).toList();
    return CompraModel.fromMap(id, snap.data()!, items);
  }

  /// Busca por número de documento (correlativo interno, ej. "00000123") o
  /// por número de factura (el que trae la factura física del proveedor).
  /// El número de documento se normaliza quitando ceros a la izquierda antes
  /// de comparar, así "123" encuentra "00000123" sin que el usuario tenga que
  /// escribir el correlativo completo con ceros.
  Future<CompraModel?> obtenerCompraPorNumeroDocumento(String numeroDocumento) async {
    final texto = numeroDocumento.trim();
    if (texto.isEmpty) return null;

    final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;

    if (soloDigitos.isNotEmpty) {
      final sinCeros = soloDigitos.replaceFirst(RegExp(r'^0+'), '');
      final correlativo = _formatearCorrelativo(int.parse(sinCeros.isEmpty ? '0' : sinCeros));
      final porDocumento = await _colCompras.where('numeroDocumento', isEqualTo: correlativo).limit(1).get();
      if (porDocumento.docs.isNotEmpty) doc = porDocumento.docs.first;
    }

    if (doc == null) {
      final porFactura = await _colCompras.where('noFactura', isEqualTo: texto).limit(1).get();
      if (porFactura.docs.isNotEmpty) doc = porFactura.docs.first;
    }

    if (doc == null) return null;
    final detalleSnap = await doc.reference.collection('detalle').get();
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemCompraModel.fromMap(d.data())).toList();
    return CompraModel.fromMap(doc.id, doc.data(), items);
  }

  /// Anula una compra: la marca como 'Anulada', descuenta del inventario el
  /// stock que había sumado, y si era una compra a crédito sin abonos,
  /// elimina su registro en `comprasCredito`.
  Future<void> anularCompra({
    required String id,
    required String usuario,
    String motivo = '',
  }) async {
    final compraSnap = await _colCompras.doc(id).get();
    if (!compraSnap.exists) {
      throw Exception('No se encontró la compra');
    }
    final data = compraSnap.data()!;
    if (data['estado'] == 'Anulada') {
      throw Exception('Esta compra ya está anulada');
    }
    final condicion = data['condicion'] as String? ?? '';
    final numeroDocumento = data['numeroDocumento'] as String? ?? '';

    final detalleSnap = await _colCompras.doc(id).collection('detalle').get();
    final items = _ordenarDetalle(detalleSnap.docs).map((d) => ItemCompraModel.fromMap(d.data())).toList();

    var creditoExiste = false;
    if (condicion == 'Credito') {
      final creditoSnap = await _colComprasCredito.doc(id).get();
      if (creditoSnap.exists) {
        creditoExiste = true;
        final montoTotal = ((creditoSnap.data()?['montoTotal'] ?? 0) as num).toDouble();
        final saldoPendiente = ((creditoSnap.data()?['saldoPendiente'] ?? 0) as num).toDouble();
        if (saldoPendiente < montoTotal) {
          throw Exception('No se puede anular: esta compra a crédito ya tiene abonos registrados');
        }
      }
    }

    // Ubicar (fuera de la transacción, ya que es una query y no una lectura
    // por referencia) el lote que generó esta compra en cada producto, para
    // poder descontarle lo que corresponda al anularla.
    final loteRefPorProducto = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final item in items) {
      final query = await _lotes.colLotes(item.idProducto).where('idCompra', isEqualTo: id).limit(1).get();
      if (query.docs.isNotEmpty) loteRefPorProducto[item.idProducto] = query.docs.first.reference;
    }

    await _db.runTransaction((transaction) async {
      final stocksActuales = <String, double>{};
      final snapsStock = await Future.wait(
        items.map((item) => transaction.get(_db.collection('productos').doc(item.idProducto))),
      );
      for (var i = 0; i < items.length; i++) {
        stocksActuales[items[i].idProducto] = ((snapsStock[i].data()?['stock'] ?? 0) as num).toDouble();
      }

      // Misma regla de "todas las lecturas antes que cualquier escritura":
      // se leen ahora (transaccionalmente) los lotes ya ubicados arriba.
      final loteSnapsPorProducto = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in loteRefPorProducto.entries) {
        loteSnapsPorProducto[entry.key] = await transaction.get(entry.value);
      }

      transaction.update(_colCompras.doc(id), {
        'estado': 'Anulada',
        'usuarioAnulacion': usuario,
        'motivoAnulacion': motivo,
        'fechaAnulacion': FieldValue.serverTimestamp(),
      });

      if (creditoExiste) {
        transaction.delete(_colComprasCredito.doc(id));
      }

      for (final item in items) {
        final ref = _db.collection('productos').doc(item.idProducto);
        final stockActual = stocksActuales[item.idProducto] ?? 0;
        final stockNuevo = stockActual - item.cantidad;
        transaction.update(ref, {'stock': stockNuevo});

        // Caso borde documentado: si ya se vendió parte de este lote antes
        // de anular la compra, no se puede "des-vender" retroactivamente —
        // se descuenta como máximo lo que le queda al lote.
        final loteSnap = loteSnapsPorProducto[item.idProducto];
        if (loteSnap != null && loteSnap.exists) {
          final restanteActual = ((loteSnap.data()?['cantidadRestante'] ?? 0) as num).toDouble();
          final nuevoRestante = restanteActual - item.cantidad;
          transaction.update(loteSnap.reference, {'cantidadRestante': nuevoRestante < 0 ? 0.0 : nuevoRestante});
        }

        final historialRef = ref.collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': 'Anulación de compra $numeroDocumento',
          'fecha': FieldValue.serverTimestamp(),
        });
      }
    }, timeout: const Duration(seconds: 12));
  }
}
