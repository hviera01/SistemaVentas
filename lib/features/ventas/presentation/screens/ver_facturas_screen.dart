import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../reportes/data/reporte_venta_model.dart';
import '../../../reportes/providers/reportes_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../reportes/data/historico_venta_service.dart';
import 'detalle_venta_screen.dart';

/// "Ver Facturas" -pedido explícito del dueño: reemplaza al viejo botón
/// "Ver Detalle" (que solo dejaba buscar UNA venta por número). Arranca
/// mostrando la lista de HOY (ventas y cotizaciones, con su estado
/// -incluidas las anuladas-), con los mismos filtros/búsqueda que el
/// Reporte de Ventas (reusa ReporteRepository.obtenerReporteVentas, mismo
/// dato) pero sin el total facturado ni los botones de exportar -esto es
/// para ubicar rápido una factura puntual y abrirla, no para sacar un
/// reporte-. Tocar una fila abre DetalleVentaScreen directo (imprimir,
/// anular, duplicar, etc. desde ahí, sin tener que pasar por Reportes).
class VerFacturasScreen extends ConsumerStatefulWidget {
  const VerFacturasScreen({super.key});

  @override
  ConsumerState<VerFacturasScreen> createState() => _VerFacturasScreenState();
}

class _VerFacturasScreenState extends ConsumerState<VerFacturasScreen> {
  final _busquedaController = TextEditingController();
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String _busqueda = '';
  String? _estadoFiltro;
  String? _tipoDocumentoFiltro;
  bool _cargando = false;
  String? _error;
  List<ReporteVentaModel>? _ventas;

  static const _estados = ['Activa', 'Anulada'];
  static const _tiposDocumento = ['Factura', 'Boleta', 'Cotizacion', 'VentaSinFacturar'];

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _fechaInicio = DateTime(hoy.year, hoy.month, hoy.day);
    _fechaFin = DateTime(hoy.year, hoy.month, hoy.day);
    _buscar();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final finInclusive = DateTime(_fechaFin.year, _fechaFin.month, _fechaFin.day, 23, 59, 59);
      final ventas = await ref.read(reporteRepositoryProvider).obtenerReporteVentas(_fechaInicio, finInclusive);
      if (mounted) setState(() => _ventas = ventas);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar la lista');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _verDetalle(ReporteVentaModel venta) {
    if (venta.esHistorica) {
      _verDetalleHistorico(venta);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleVentaScreen(ventaIdInicial: venta.id)),
    );
  }

  /// Las ventas del sistema anterior no existen como documento de Firestore
  /// (viven en D1, ver HistoricoVentaService), así que no se puede abrir
  /// DetalleVentaScreen para ellas — solo consulta, sin reimpresión/anular.
  void _verDetalleHistorico(ReporteVentaModel venta) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Venta ${venta.numeroDocumento}'),
        content: SizedBox(
          width: 420,
          child: FutureBuilder(
            future: HistoricoVentaService().obtenerDetalleDeVenta(venta.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final items = snapshot.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${venta.nombreCliente} · ${venta.condicion}', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('Total: ${formatearMoneda(venta.totalAPagar)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(height: 20),
                  if (items.isEmpty)
                    const Text('Esta venta del sistema anterior no tiene el detalle de productos guardado.')
                  else
                    ...items.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${i.cantidad.toStringAsFixed(0)}x ${i.nombreProducto}')),
                              Text(formatearMoneda(redondearMoneda(i.subtotal * 1.15))),
                            ],
                          ),
                        )),
                  const SizedBox(height: 8),
                  Text('Venta del sistema anterior — solo consulta.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar'))],
      ),
    );
  }

  void _aplicarBusqueda() => setState(() => _busqueda = _busquedaController.text.trim());

  void _limpiar() {
    final hoy = DateTime.now();
    _busquedaController.clear();
    setState(() {
      _fechaInicio = DateTime(hoy.year, hoy.month, hoy.day);
      _fechaFin = DateTime(hoy.year, hoy.month, hoy.day);
      _busqueda = '';
      _estadoFiltro = null;
      _tipoDocumentoFiltro = null;
    });
    _buscar();
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(context: context, initialDate: esInicio ? _fechaInicio : _fechaFin, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
      } else {
        _fechaFin = fecha;
      }
    });
  }

  List<ReporteVentaModel> get _listaFiltrada {
    var lista = _ventas ?? [];
    if (_busqueda.isNotEmpty) lista = lista.where((v) => coincideFuzzy(v.textoBusqueda, _busqueda)).toList();
    if (_estadoFiltro != null) lista = lista.where((v) => v.estado == _estadoFiltro).toList();
    if (_tipoDocumentoFiltro != null) lista = lista.where((v) => v.tipoDocumento == _tipoDocumentoFiltro).toList();
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final lista = _listaFiltrada;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final esMovil = constraints.maxWidth < 760;
            return Padding(
              padding: EdgeInsets.all(esMovil ? 14 : 26),
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(child: Text('Ver Facturas', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)))),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(child: const SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _campoFecha('Desde', _fechaInicio, () => _seleccionarFecha(true), esMovil),
                        _campoFecha('Hasta', _fechaFin, () => _seleccionarFecha(false), esMovil),
                        SizedBox(width: esMovil ? constraints.maxWidth : 300, child: _buscador()),
                        OutlinedButton.icon(
                          onPressed: _cargando ? null : _buscar,
                          icon: const Icon(Icons.search, size: 18),
                          label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13)),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        OutlinedButton.icon(
                          onPressed: _cargando ? null : _limpiar,
                          icon: const Icon(Icons.close, size: 18),
                          label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 13)),
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(child: const SizedBox(height: 10)),
                  SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(width: esMovil ? constraints.maxWidth : 190, child: _selectorGenerico('Estado', _estadoFiltro, _estados, (v) => setState(() => _estadoFiltro = v))),
                        SizedBox(width: esMovil ? constraints.maxWidth : 190, child: _selectorGenerico('Tipo de documento', _tipoDocumentoFiltro, _tiposDocumento, (v) => setState(() => _tipoDocumentoFiltro = v))),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(child: const SizedBox(height: 16)),
                ],
                body: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 26, offset: const Offset(0, 12))],
                  ),
                  child: _cargando
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))
                      : _error != null
                          ? Center(child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red)))
                          : lista.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
                                      const SizedBox(height: 12),
                                      Text('No se encontraron facturas', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                                    ],
                                  ),
                                )
                              : (esMovil ? _tarjetas(lista) : _tabla(lista)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _campoFecha(String label, DateTime fecha, VoidCallback onTap, bool esMovil) {
    final formato = DateFormat('dd/MM/yyyy');
    return SizedBox(
      width: esMovil ? double.infinity : 200,
      child: InkWell(
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
              Flexible(child: Text('$label: ${formato.format(fecha)}', overflow: TextOverflow.ellipsis, maxLines: 1, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorGenerico(String etiqueta, String? valor, List<String> opciones, void Function(String?) onChanged) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: valor,
          isExpanded: true,
          hint: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('$etiqueta: Todos', style: GoogleFonts.poppins(fontSize: 13))),
            ...opciones.map((o) => DropdownMenuItem<String?>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buscador() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: CampoTecladoCompacto(
              controller: _busquedaController,
              numerico: false,
              onSubmitted: (_) => _aplicarBusqueda(),
              titulo: 'Buscar por número, cliente, método de pago...',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _busquedaController,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por número, cliente, método de pago...',
                  hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _aplicarBusqueda(),
              ),
            ),
          ),
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _aplicarBusqueda),
        ],
      ),
    );
  }

  Widget _chipTipo(ReporteVentaModel v) {
    final esCotizacion = v.esCotizacion;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: esCotizacion ? const Color(0xFFFFF6D8) : const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(8)),
      child: Text(v.tipoDocumento, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: esCotizacion ? const Color(0xFF92720B) : const Color(0xFF3B82F6))),
    );
  }

  Widget _chipEstado(ReporteVentaModel v) {
    final anulada = !v.esActiva;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: anulada ? const Color(0xFFFCE4E4) : const Color(0xFFE8F8EE), borderRadius: BorderRadius.circular(8)),
      child: Text(v.estado, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: anulada ? const Color(0xFFC62828) : const Color(0xFF16A34A))),
    );
  }

  Widget _tabla(List<ReporteVentaModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final mostrarCondicion = ancho >= 1050;
        final mostrarMetodoPago = ancho >= 900;

        return ListView.builder(
          itemCount: lista.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFECEEF3), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                child: Row(
                  children: [
                    _celdaHeader('FECHA', 3),
                    _celdaHeader('TIPO', 2),
                    _celdaHeader('DOCUMENTO', 2),
                    _celdaHeader('CLIENTE', 3),
                    _celdaHeader('TOTAL', 2),
                    if (mostrarMetodoPago) _celdaHeader('PAGO', 2),
                    if (mostrarCondicion) _celdaHeader('CONDICIÓN', 2),
                    _celdaHeader('ESTADO', 2),
                    const SizedBox(width: 24),
                  ],
                ),
              );
            }
            final v = lista[index - 1];
            return Column(
              children: [
                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                InkWell(
                  onTap: () => _verDetalle(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        _celda(3, v.fechaRegistro != null ? formatoFecha.format(v.fechaRegistro!) : '-', gris: true),
                        Expanded(flex: 2, child: _chipTipo(v)),
                        _celda(2, v.numeroDocumento, peso: FontWeight.w600),
                        _celda(3, v.nombreCliente),
                        _celda(2, formatearMoneda(v.totalAPagar), peso: FontWeight.w700),
                        if (mostrarMetodoPago) _celda(2, v.metodoPago, gris: true),
                        if (mostrarCondicion) _celda(2, v.condicion, gris: true),
                        Expanded(flex: 2, child: _chipEstado(v)),
                        SizedBox(
                          width: 24,
                          child: v.pendienteImpresion ? Tooltip(message: 'Pendiente de impresión', child: Icon(Icons.print_disabled_outlined, size: 16, color: Colors.amber.shade800)) : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF666A72), letterSpacing: 0.3)),
    );
  }

  Widget _celda(int flex, String texto, {bool gris = false, FontWeight peso = FontWeight.w400}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(texto, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: peso, color: gris ? Colors.grey.shade600 : const Color(0xFF1A1A1A))),
      ),
    );
  }

  Widget _tarjetas(List<ReporteVentaModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final v = lista[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _verDetalle(v),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.nombreCliente.isEmpty ? 'Sin cliente' : v.nombreCliente, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                          Text('Doc. ${v.numeroDocumento}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    Text(formatearMoneda(v.totalAPagar), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipTipo(v),
                    _chipEstado(v),
                    _chipInfo('Pago', v.metodoPago),
                    _chipInfo('Fecha', v.fechaRegistro != null ? formatoFecha.format(v.fechaRegistro!) : '-'),
                    if (v.pendienteImpresion)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.print_disabled_outlined, size: 13, color: Colors.amber.shade800),
                            const SizedBox(width: 4),
                            Text('Pendiente de impresión', style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade900)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chipInfo(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $valor', style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF3F434A))),
    );
  }
}
