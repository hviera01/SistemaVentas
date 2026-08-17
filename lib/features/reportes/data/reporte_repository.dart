import 'package:cloud_firestore/cloud_firestore.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';
import 'historico_venta_service.dart';

class ReporteRepository {
  final _db = FirebaseFirestore.instance;
  final _historicoService = HistoricoVentaService();

  Future<List<ReporteVentaModel>> obtenerReporteVentas(DateTime inicio, DateTime finInclusive) async {
    // El filtro de rango tiene que ir por 'fechaRegistro' (Firestore exige
    // que el primer orderBy coincida con el campo del filtro de rango), así
    // que no se puede pedirle a la propia consulta que además ordene por
    // 'creadoEn'. Se reordena acá, ya en memoria, por creadoEn descendente
    // (orden real de creación, sin importar qué fecha de negocio se haya
    // elegido para cada venta) — con fechaRegistro como respaldo en ventas
    // viejas que no tienen 'creadoEn' guardado.
    //
    // En paralelo se pide el tramo histórico (sistema anterior, vía D1/Worker)
    // por si el rango toca fechas de antes del 2026-07-17 — ver
    // HistoricoVentaService. Nunca se dispara si el rango es todo posterior
    // al corte, así que el día a día no paga ningún costo extra.
    final snapFuture = _db
        .collection('ventas')
        .where('fechaRegistro', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fechaRegistro', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .orderBy('fechaRegistro', descending: true)
        .get();
    final historicoFuture = _historicoService.obtenerVentas(inicio, finInclusive);

    final snap = await snapFuture;
    final historico = await historicoFuture;

    final lista = [
      ...snap.docs.map((d) => ReporteVentaModel.fromMap(d.id, d.data())),
      ...historico,
    ];
    lista.sort((a, b) {
      final claveA = a.creadoEn ?? a.fechaRegistro ?? DateTime(0);
      final claveB = b.creadoEn ?? b.fechaRegistro ?? DateTime(0);
      return claveB.compareTo(claveA);
    });
    return lista;
  }

  /// Versión en vivo de [obtenerReporteVentas], para tarjetas de resumen
  /// (ej. venta del día/mes en Inicio) que deben actualizarse solas cuando
  /// se registra o anula una venta, sin necesidad de refrescar la pantalla.
  Stream<List<ReporteVentaModel>> observarReporteVentas(DateTime inicio, DateTime finInclusive) {
    return _db
        .collection('ventas')
        .where('fechaRegistro', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fechaRegistro', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .snapshots()
        .map((snap) => snap.docs.map((d) => ReporteVentaModel.fromMap(d.id, d.data())).toList());
  }

  Future<List<ReporteCompraModel>> obtenerReporteCompras(DateTime inicio, DateTime finInclusive, {String? idProveedor}) async {
    Query<Map<String, dynamic>> query = _db
        .collection('compras')
        .where('fechaRegistro', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fechaRegistro', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive));
    final snap = await query.orderBy('fechaRegistro', descending: true).get();
    var lista = snap.docs.map((d) => ReporteCompraModel.fromMap(d.id, d.data())).toList();
    if (idProveedor != null && idProveedor.isNotEmpty) {
      lista = lista.where((c) => c.idProveedor == idProveedor).toList();
    }
    return lista;
  }
}
