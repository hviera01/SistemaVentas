import 'package:cloud_firestore/cloud_firestore.dart';
import 'lote_costo_model.dart';

/// Estado de trabajo (en memoria) de un lote mientras se calcula cuánto
/// consumir de él. Se separa de LoteCostoModel porque acá cantidadRestante
/// va cambiando a medida que varias líneas del carrito del mismo producto
/// consumen del mismo lote, antes de escribir el valor final a Firestore.
class EstadoLote {
  double restante;
  final double costoUnitario;
  bool tocado = false;
  EstadoLote({required this.restante, required this.costoUnitario});
}

typedef EstadoLotesProducto = Map<DocumentReference<Map<String, dynamic>>, EstadoLote>;

/// Costeo FIFO por lotes (ver LoteCostoModel). Se usa desde dentro de
/// transacciones de Firestore de otros repositorios (compras, ventas,
/// ajustes de stock); los métodos que escriben (crearLote, aplicarEstado)
/// reciben la [Transaction] de quien los llama en vez de manejar la suya
/// propia.
class LoteCostoRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> colLotes(String idProducto) {
    return _db.collection('productos').doc(idProducto).collection('lotes');
  }

  /// Crea un lote nuevo (compra, o ajuste de stock que sube existencia con
  /// un costo propio). Es una escritura pura (documento nuevo): no necesita
  /// lectura previa, así que se puede llamar en cualquier punto de la fase
  /// de escritura de la transacción.
  ///
  /// [cantidadRestante] es opcional y solo hace falta cuando parte de esta
  /// compra ya nace "comprometida" -por ejemplo, cubre una venta anticipada
  /// que se había vendido antes sin saber todavía cuál compra la iba a
  /// reponer (ver CompraRepository.registrarCompra)-: ahí [cantidad] sigue
  /// siendo lo que de verdad se compró (para que el historial del lote no
  /// mienta), pero lo disponible para futuras ventas es menos. Si no se
  /// indica, el lote nace con toda su cantidad disponible, como siempre.
  void crearLote(
    Transaction transaction,
    String idProducto, {
    required double cantidad,
    required double costoUnitario,
    required DateTime fecha,
    required String origen,
    String? idCompra,
    double? cantidadRestante,
  }) {
    if (cantidad <= 0) return;
    final ref = colLotes(idProducto).doc();
    transaction.set(ref, {
      'cantidadOriginal': cantidad,
      'cantidadRestante': cantidadRestante ?? cantidad,
      'costoUnitario': costoUnitario,
      'fecha': Timestamp.fromDate(fecha),
      'origen': origen,
      'idCompra': idCompra,
    });
  }

  /// Lectura simple (no transaccional: Firestore no permite queries dentro
  /// de una transacción del cliente) de los lotes candidatos de un
  /// producto, ordenados del más viejo al más nuevo. A propósito NO vuelve a
  /// leer cada documento de forma transaccional (como se hacía antes): eso
  /// agregaba una ida y vuelta a Firestore extra POR PRODUCTO en cada venta,
  /// y la venta tiene que sentirse instantánea. Para el volumen de este
  /// negocio, el riesgo de que dos ventas concurrentes consuman justo el
  /// mismo lote en el mismo instante es mínimo, y aceptarlo vale la pena a
  /// cambio de no perder velocidad. Como no depende de las demás lecturas de
  /// la transacción (contador/stock), se puede lanzar en paralelo con ellas
  /// en vez de esperarlas primero.
  Future<QuerySnapshot<Map<String, dynamic>>> consultarLotes(String idProducto) {
    return colLotes(idProducto).orderBy('fecha').limit(30).get();
  }

  /// Para mostrar en pantalla: todos los lotes de un producto (agotados o
  /// no), en el orden en que el costeo FIFO los va a ir consumiendo — por
  /// fecha (el más viejo primero), salvo que el usuario haya reordenado a
  /// mano con [reordenarLotes], en cuyo caso manda esa prioridad manual.
  /// Sirve para ver de un vistazo cuántas unidades quedan a cada costo y
  /// cuál va a salir primero.
  Stream<List<LoteCostoModel>> obtenerLotes(String idProducto) {
    return colLotes(idProducto).orderBy('fecha').snapshots().map((snap) {
      final lotes = snap.docs.map((d) => LoteCostoModel.fromMap(d.id, d.data())).toList();
      lotes.sort(_compararLotesPorPrioridad);
      return lotes;
    });
  }

  /// Cambia a mano cuál lote sale primero: se le asigna una prioridad nueva
  /// (0 = primero) a TODOS los lotes con existencia pasados en
  /// [idsEnOrdenDeseado], según el orden de esa lista — así nunca queda un
  /// lote "con prioridad" mezclado de forma ambigua con uno "sin prioridad"
  /// (que seguiría ordenándose por fecha). Se puede volver a llamar cuantas
  /// veces se quiera, aunque el lote elegido ya tenga ventas parciales.
  Future<void> reordenarLotes(String idProducto, List<String> idsEnOrdenDeseado) async {
    final batch = _db.batch();
    for (var i = 0; i < idsEnOrdenDeseado.length; i++) {
      batch.update(colLotes(idProducto).doc(idsEnOrdenDeseado[i]), {'prioridad': i});
    }
    await batch.commit();
    // Reordenar a mano puede cambiar cuál es el lote activo (el que sale
    // primero) sin que se haya vendido/comprado nada -mismo criterio que el
    // resto de operaciones sobre lotes, ver sincronizarPrecioCompraActivo.
    await sincronizarPrecioCompraActivo(idProducto);
  }

  /// Arma el estado de trabajo a partir del resultado de [consultarLotes].
  /// Cuando el carrito tiene más de una línea del mismo producto, las dos
  /// deben consumir del mismo estado en vez de cada una partir de la query
  /// original: si no, contarían dos veces la misma capacidad de un lote.
  /// Los documentos se reordenan acá por prioridad manual (ver
  /// [reordenarLotes]) antes de armar el mapa, para que una venta real
  /// consuma en el mismo orden que se ve en "Costos por lote (FIFO)".
  EstadoLotesProducto inicializarEstado(QuerySnapshot<Map<String, dynamic>> query) {
    final docsOrdenados = query.docs.toList()
      ..sort((a, b) {
        final prioA = (a.data()['prioridad'] as num?)?.toInt();
        final prioB = (b.data()['prioridad'] as num?)?.toInt();
        if (prioA != null && prioB != null) return prioA.compareTo(prioB);
        if (prioA != null) return -1;
        if (prioB != null) return 1;
        return 0; // ya vienen ordenados por fecha desde consultarLotes()
      });
    final estado = <DocumentReference<Map<String, dynamic>>, EstadoLote>{};
    for (final doc in docsOrdenados) {
      estado[doc.reference] = EstadoLote(
        restante: ((doc.data()['cantidadRestante'] ?? 0) as num).toDouble(),
        costoUnitario: ((doc.data()['costoUnitario'] ?? 0) as num).toDouble(),
      );
    }
    return estado;
  }

  /// Consume [cantidad] del estado de trabajo (mutándolo) y devuelve el
  /// costo unitario promedio ponderado de lo consumido. Los lotes se
  /// procesan en el mismo orden en que vinieron los snapshots (ya ordenados
  /// por fecha ascendente desde la query), o sea el más viejo primero. Si
  /// los lotes registrados no alcanzan a cubrir toda la cantidad (stock de
  /// antes de esta funcionalidad, o ajustes hechos sin lote), el resto se
  /// costea con [costoFallback] en vez de fallar.
  double consumir(EstadoLotesProducto estado, double cantidad, {required double costoFallback}) {
    if (cantidad <= 0) return costoFallback;
    var restante = cantidad;
    var costoTotal = 0.0;
    for (final lote in estado.values) {
      if (restante <= 0) break;
      if (lote.restante <= 0) continue;
      final consumido = lote.restante < restante ? lote.restante : restante;
      lote.restante -= consumido;
      lote.tocado = true;
      costoTotal += consumido * lote.costoUnitario;
      restante -= consumido;
    }
    if (restante > 0) costoTotal += restante * costoFallback;
    return costoTotal / cantidad;
  }

  /// Escribe en la transacción los lotes cuyo estado cambió por consumir().
  void aplicarEstado(Transaction transaction, EstadoLotesProducto estado) {
    for (final entry in estado.entries) {
      if (entry.value.tocado) transaction.update(entry.key, {'cantidadRestante': entry.value.restante});
    }
  }

  /// Sincroniza `productos/{id}.precioCompra` con el costo del lote que el
  /// FIFO va a consumir A CONTINUACIÓN (el más viejo con existencia, o el de
  /// prioridad manual más alta) -pedido explícito del dueño: la columna
  /// "P. Compra" de Inventario, el "Valor compra" del inventario, y el costo
  /// de arranque del estimado de Consultar Costo tienen que reflejar lo que
  /// en verdad se está vendiendo ahora mismo, no la última compra
  /// registrada ni el último ajuste manual. Antes `precioCompra` se pisaba
  /// directo en cada compra/edición manual sin mirar los lotes -bug real
  /// reportado por el dueño: con dos lotes (uno viejo con existencia a costo
  /// 10, uno nuevo a costo 12), la columna mostraba 12 aunque la próxima
  /// unidad vendida en verdad costara 10-.
  ///
  /// Se llama DESPUÉS de que la operación que tocó lotes (compra, venta,
  /// ajuste de stock, anulación, reordenar) ya haya CONFIRMADO sus cambios
  /// -por eso es una escritura aparte, no algo más que agregar dentro de esa
  /// misma transacción: una query normal (no transaccional, que es lo único
  /// que Firestore permite para queries del lado del cliente, ver
  /// [consultarLotes]) hecha DENTRO de esa transacción no vería los cambios
  /// de lotes que esa misma transacción todavía no confirmó-. Si ya no
  /// queda ningún lote con existencia, no toca nada (se deja el último
  /// precioCompra conocido, igual que el comportamiento de siempre).
  Future<void> sincronizarPrecioCompraActivo(String idProducto) async {
    final snap = await colLotes(idProducto).orderBy('fecha').get();
    final lotes = snap.docs.map((d) => LoteCostoModel.fromMap(d.id, d.data())).toList();
    final activo = loteActivo(lotes);
    if (activo != null) {
      await _db.collection('productos').doc(idProducto).update({'precioCompra': activo.costoUnitario});
    }
  }
}

/// Lote que el FIFO va a consumir a continuación de una lista YA completa
/// de lotes de un producto (agotados o no): el primero, en el mismo orden
/// que usa el costeo real -prioridad manual si existe (ver
/// LoteCostoRepository.reordenarLotes), si no la fecha, más viejo primero-,
/// que todavía tenga cantidadRestante > 0. Null si no queda ninguno. Función
/// de nivel superior (no un método de la clase) y sin Firestore a propósito,
/// para poder probarla con datos de prueba sin necesitar un backend real.
LoteCostoModel? loteActivo(List<LoteCostoModel> lotes) {
  final ordenados = [...lotes]..sort(_compararLotesPorPrioridad);
  for (final lote in ordenados) {
    if (lote.cantidadRestante > 0) return lote;
  }
  return null;
}

/// Mismo criterio de orden que usa el costeo FIFO real (ver
/// LoteCostoRepository.inicializarEstado): prioridad manual si existe, si
/// no la fecha, más viejo primero. Nivel superior -no un método de la
/// clase- para que tanto [obtenerLotes] como [loteActivo] compartan
/// exactamente el mismo criterio sin duplicarlo.
int _compararLotesPorPrioridad(LoteCostoModel a, LoteCostoModel b) {
  if (a.prioridad != null && b.prioridad != null) return a.prioridad!.compareTo(b.prioridad!);
  if (a.prioridad != null) return -1;
  if (b.prioridad != null) return 1;
  return a.fecha.compareTo(b.fecha);
}
