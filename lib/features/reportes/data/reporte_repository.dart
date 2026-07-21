import 'package:cloud_firestore/cloud_firestore.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';

class ReporteRepository {
  final _db = FirebaseFirestore.instance;

  Future<List<ReporteVentaModel>> obtenerReporteVentas(DateTime inicio, DateTime finInclusive) async {
    // El filtro de rango tiene que ir por 'fechaRegistro' (Firestore exige
    // que el primer orderBy coincida con el campo del filtro de rango), así
    // que no se puede pedirle a la propia consulta que además ordene por
    // 'creadoEn'. Se reordena acá, ya en memoria, por creadoEn descendente
    // (orden real de creación, sin importar qué fecha de negocio se haya
    // elegido para cada venta) — con fechaRegistro como respaldo en ventas
    // viejas que no tienen 'creadoEn' guardado.
    final snap = await _db
        .collection('ventas')
        .where('fechaRegistro', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fechaRegistro', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .orderBy('fechaRegistro', descending: true)
        .get();
    final lista = snap.docs.map((d) => ReporteVentaModel.fromMap(d.id, d.data())).toList();
    lista.sort((a, b) {
      final claveA = a.creadoEn ?? a.fechaRegistro ?? DateTime(0);
      final claveB = b.creadoEn ?? b.fechaRegistro ?? DateTime(0);
      return claveB.compareTo(claveA);
    });
    return lista;
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
