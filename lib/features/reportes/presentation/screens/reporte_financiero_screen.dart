import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/reporte_financiero_model.dart';
import '../../data/reporte_financiero_export_service.dart';
import '../../providers/reportes_provider.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/reporte_financiero_secciones.dart';

typedef _SeccionBuilder = Widget Function(ReporteFinancieroData data, bool esMovil);

const _tabs = <(String, IconData, _SeccionBuilder)>[
  ('Utilidad', Icons.trending_up_outlined, seccionUtilidad),
  ('Flujo de Efectivo', Icons.account_balance_wallet_outlined, seccionFlujoEfectivo),
  ('Comparación Mensual', Icons.calendar_month_outlined, seccionComparacionMensual),
  ('Ranking de Productos', Icons.leaderboard_outlined, seccionRankingProductos),
  ('Sin Movimiento', Icons.inventory_2_outlined, seccionProductosSinVenta),
  ('Ventas por Usuario', Icons.people_outline, seccionVentasPorUsuario),
  ('Abonos a Proveedores', Icons.payments_outlined, seccionAbonosComprasCredito),
  ('Recomendación de Pago', Icons.lightbulb_outline, seccionRecomendacionPago),
  ('Balance General', Icons.account_balance_outlined, seccionBalanceGeneral),
];

/// Reporte Financiero: un solo módulo del menú, con todas sus secciones
/// como pestañas internas — un único rango de fechas y un único cálculo
/// (`ReporteFinancieroData`) alimenta todas las pestañas, así que cambiar de
/// pestaña no dispara ninguna consulta nueva.
class ReporteFinancieroScreen extends ConsumerStatefulWidget {
  const ReporteFinancieroScreen({super.key});

  @override
  ConsumerState<ReporteFinancieroScreen> createState() => _ReporteFinancieroScreenState();
}

class _ReporteFinancieroScreenState extends ConsumerState<ReporteFinancieroScreen> {
  final _servicioExport = ReporteFinancieroExportService();
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  bool _cargando = false;
  String? _error;
  ReporteFinancieroData? _data;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
    _generar();
  }

  Future<void> _generar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final finInclusive = DateTime(_fechaFin.year, _fechaFin.month, _fechaFin.day, 23, 59, 59);
      final data = await ref.read(reporteFinancieroRepositoryProvider).obtenerReporte(_fechaInicio, finInclusive);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo generar el reporte: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : _fechaFin,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
      } else {
        _fechaFin = fecha;
      }
    });
  }

  void _descargarPdf() {
    final data = _data;
    if (data == null) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Reporte Financiero',
        nombreArchivo: 'reporte_financiero.pdf',
        generarPdf: () => _servicioExport.generarPdf(data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: EdgeInsets.all(esMovil ? 14 : 24), child: _encabezado(esMovil)),
              if (_cargando) const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))),
              if (_error != null) Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red))))),
              if (!_cargando && _error == null && _data != null) Expanded(child: _tabsYContenido(_data!, esMovil)),
            ],
          );
        },
      ),
    );
  }

  Widget _tabsYContenido(ReporteFinancieroData data, bool esMovil) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelColor: const Color(0xFFC62828),
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: const Color(0xFFC62828),
              labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
              tabs: [for (final t in _tabs) Tab(icon: Icon(t.$2, size: 18), text: t.$1)],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in _tabs)
                  SingleChildScrollView(
                    padding: EdgeInsets.all(esMovil ? 14 : 24),
                    child: t.$3(data, esMovil),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    final formato = DateFormat('dd/MM/yyyy');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text('Reporte Financiero', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        _campoFecha('Desde', _fechaInicio, () => _seleccionarFecha(true), formato),
        _campoFecha('Hasta', _fechaFin, () => _seleccionarFecha(false), formato),
        OutlinedButton.icon(
          onPressed: _cargando ? null : _generar,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text('Generar', style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        FilledButton.icon(
          onPressed: _data == null ? null : _descargarPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text('Descargar PDF completo', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ],
    );
  }

  Widget _campoFecha(String label, DateTime fecha, VoidCallback onTap, DateFormat formato) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text('$label: ${formato.format(fecha)}', style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A))),
          ],
        ),
      ),
    );
  }
}
