import 'package:cloud_firestore/cloud_firestore.dart';

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
  void crearLote(
    Transaction transaction,
    String idProducto, {
    required double cantidad,
    required double costoUnitario,
    required DateTime fecha,
    required String origen,
    String? idCompra,
  }) {
    if (cantidad <= 0) return;
    final ref = colLotes(idProducto).doc();
    transaction.set(ref, {
      'cantidadOriginal': cantidad,
      'cantidadRestante': cantidad,
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

  /// Arma el estado de trabajo a partir del resultado de [consultarLotes].
  /// Cuando el carrito tiene más de una línea del mismo producto, las dos
  /// deben consumir del mismo estado en vez de cada una partir de la query
  /// original: si no, contarían dos veces la misma capacidad de un lote.
  EstadoLotesProducto inicializarEstado(QuerySnapshot<Map<String, dynamic>> query) {
    final estado = <DocumentReference<Map<String, dynamic>>, EstadoLote>{};
    for (final doc in query.docs) {
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
}
