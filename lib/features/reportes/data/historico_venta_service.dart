import 'dart:convert';
import 'package:http/http.dart' as http;
import 'reporte_venta_model.dart';
import '../../ventas/data/item_venta_model.dart';

/// Cliente del Worker de Cloudflare que sirve el volcado congelado del
/// sistema anterior (SQL Server local `DB_SUPERCOLOR`, tablas VENTA y
/// DETALLE_VENTA) desde una base D1. Esa base ya no se actualiza —el sistema
/// viejo dejó de ser la fuente de verdad el 2026-07-17— así que solo se
/// consulta cuando el rango pedido toca fechas anteriores al corte.
///
/// Cualquier falla de red se trata como "sin datos históricos para este
/// rango" en vez de reventar el reporte completo: es un dato complementario,
/// no la fuente principal (esa sigue siendo Firestore).
class HistoricoVentaService {
  static const _baseUrl = 'https://supercolor-factura-scanner.factura-scanner.workers.dev';
  static const _timeout = Duration(seconds: 12);

  /// Última venta real del sistema anterior. Todo lo desde acá en adelante
  /// es del sistema actual (Firestore) — ver conversación 2026-08-17.
  static final corteHistorico = DateTime.utc(2026, 7, 17, 22, 23, 35, 328);

  bool _tocaHistorico(DateTime inicio, DateTime finInclusive) => inicio.toUtc().isBefore(corteHistorico);

  Future<List<ReporteVentaModel>> obtenerVentas(DateTime inicio, DateTime finInclusive) async {
    if (!_tocaHistorico(inicio, finInclusive)) return const [];
    final hasta = finInclusive.toUtc().isBefore(corteHistorico) ? finInclusive.toUtc() : corteHistorico.subtract(const Duration(milliseconds: 1));
    try {
      final uri = Uri.parse('$_baseUrl/historico/ventas').replace(queryParameters: {
        'desde': inicio.toUtc().toIso8601String(),
        'hasta': hasta.toIso8601String(),
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      return lista.map((e) => ReporteVentaModel.fromHistorico(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Detalle de todas las ventas históricas de un rango, agrupado por id de
  /// venta (ya con el prefijo `historico:` que usa [ReporteVentaModel.id]).
  /// Una sola llamada HTTP en vez de una por venta.
  Future<Map<String, List<ItemVentaModel>>> obtenerDetallePorRango(DateTime inicio, DateTime finInclusive) async {
    if (!_tocaHistorico(inicio, finInclusive)) return const {};
    final hasta = finInclusive.toUtc().isBefore(corteHistorico) ? finInclusive.toUtc() : corteHistorico.subtract(const Duration(milliseconds: 1));
    try {
      final uri = Uri.parse('$_baseUrl/historico/detalle-rango').replace(queryParameters: {
        'desde': inicio.toUtc().toIso8601String(),
        'hasta': hasta.toIso8601String(),
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return const {};
      final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      final porVenta = <String, List<ItemVentaModel>>{};
      for (final fila in lista) {
        final data = fila as Map<String, dynamic>;
        final id = 'historico:${data['id_venta']}';
        porVenta.putIfAbsent(id, () => []).add(ItemVentaModel.fromHistoricoMap(data));
      }
      return porVenta;
    } catch (_) {
      return const {};
    }
  }

  /// Detalle de una sola venta histórica (usado al abrir el detalle de una
  /// fila marcada `origen: historico` en Reporte de Ventas).
  Future<List<ItemVentaModel>> obtenerDetalleDeVenta(String idHistorico) async {
    final idVenta = idHistorico.replaceFirst('historico:', '');
    try {
      final uri = Uri.parse('$_baseUrl/historico/detalle').replace(queryParameters: {'idVenta': idVenta});
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      return lista.map((e) => ItemVentaModel.fromHistoricoMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}
