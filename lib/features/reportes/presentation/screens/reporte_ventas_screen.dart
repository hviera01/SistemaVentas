import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/reporte_venta_model.dart';
import '../../data/reporte_export_service.dart';
import '../../providers/reportes_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/exportador.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../usuarios/providers/usuarios_provider.dart';
import '../../../ventas/presentation/screens/detalle_venta_screen.dart';

class ReporteVentasScreen extends ConsumerStatefulWidget {
  const ReporteVentasScreen({super.key});

  @override
  ConsumerState<ReporteVentasScreen> createState() => _ReporteVentasScreenState();
}

class _ReporteVentasScreenState extends ConsumerState<ReporteVentasScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = ReporteExportService();
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String _busqueda = '';
  String? _metodoPagoFiltro;
  String? _condicionFiltro;
  String? _estadoFiltro;
  String? _tipoDocumentoFiltro;
  String? _usuarioFiltro;
  bool _cargando = false;
  String? _error;
  List<ReporteVentaModel>? _ventas;

  static const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];
  static const _condiciones = ['Contado', 'Crédito'];
  static const _estados = ['Activa', 'Anulada'];
  static const _tiposDocumento = ['Factura', 'Boleta', 'Cotizacion', 'VentaSinFacturar'];

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
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
      if (mounted) setState(() => _error = 'No se pudo cargar el reporte');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _verDetalle(String idVenta) {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleVentaScreen(ventaIdInicial: idVenta)),
    );
  }

  void _aplicarBusqueda() {
    setState(() => _busqueda = _busquedaController.text.trim());
  }

  void _limpiar() {
    final ahora = DateTime.now();
    _busquedaController.clear();
    setState(() {
      _fechaInicio = DateTime(ahora.year, ahora.month, 1);
      _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
      _busqueda = '';
      _metodoPagoFiltro = null;
      _condicionFiltro = null;
      _estadoFiltro = null;
      _tipoDocumentoFiltro = null;
      _usuarioFiltro = null;
    });
    _buscar();
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

  List<ReporteVentaModel> get _listaFiltrada {
    var lista = _ventas ?? [];
    if (_busqueda.isNotEmpty) {
      lista = lista.where((v) => coincideFuzzy(v.textoBusqueda, _busqueda)).toList();
    }
    if (_metodoPagoFiltro != null) {
      lista = lista.where((v) => v.metodoPago == _metodoPagoFiltro).toList();
    }
    if (_condicionFiltro != null) {
      lista = lista.where((v) => v.condicion == _condicionFiltro).toList();
    }
    if (_estadoFiltro != null) {
      lista = lista.where((v) => v.estado == _estadoFiltro).toList();
    }
    if (_tipoDocumentoFiltro != null) {
      lista = lista.where((v) => v.tipoDocumento == _tipoDocumentoFiltro).toList();
    }
    if (_usuarioFiltro != null) {
      lista = lista.where((v) => v.usuarioRegistro == _usuarioFiltro).toList();
    }
    return lista;
  }

  Future<void> _exportarExcel() async {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    final bytes = _servicioExport.generarExcelVentas(lista);
    final fecha = DateFormat('dd-MM-yyyy').format(DateTime.now());
    await guardarOCompartirArchivo(bytes, 'Reporte_Ventas_$fecha.xlsx');
  }

  void _exportarPdf() {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Reporte de Ventas',
        nombreArchivo: 'reporte_ventas.pdf',
        generarPdf: () => _servicioExport.generarPdfVentas(lista),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _listaFiltrada;
    final totalFacturado = lista.where((v) => v.esActiva && !v.esCotizacion).fold<double>(0, (s, v) => s + v.totalAPagar);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 760;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            // NestedScrollView (en vez de CustomScrollView + SliverFillRemaining)
            // coordina el scroll del encabezado/filtros con el de la lista de
            // abajo: sin esto, la lista tiene su propio scroll independiente y,
            // en móvil, al bajar del todo dentro de ella no había forma de
            // volver a subir arrastrando (el encabezado quedaba "atrapado"
            // fuera de la pantalla).
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Text('Reporte de Ventas', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                      _statTotalFacturado(totalFacturado),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _campoFecha('Desde', _fechaInicio, () => _seleccionarFecha(true), esMovil),
                      _campoFecha('Hasta', _fechaFin, () => _seleccionarFecha(false), esMovil),
                      SizedBox(width: esMovil ? constraints.maxWidth : 280, child: _buscador()),
                      OutlinedButton.icon(
                        onPressed: _cargando ? null : _buscar,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      OutlinedButton.icon(
                        onPressed: _cargando ? null : _limpiar,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportarExcel,
                        icon: const Icon(Icons.grid_on_outlined, size: 18),
                        label: Text('Descargar Excel', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportarPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text('Descargar PDF', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 190,
                        child: _selectorGenerico('Método de pago', _metodoPagoFiltro, _metodosPago, (v) => setState(() => _metodoPagoFiltro = v)),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 190,
                        child: _selectorGenerico('Condición', _condicionFiltro, _condiciones, (v) => setState(() => _condicionFiltro = v)),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 190,
                        child: _selectorGenerico('Estado', _estadoFiltro, _estados, (v) => setState(() => _estadoFiltro = v)),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 190,
                        child: _selectorGenerico('Tipo de documento', _tipoDocumentoFiltro, _tiposDocumento, (v) => setState(() => _tipoDocumentoFiltro = v)),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 190,
                        child: ref.watch(usuariosStreamProvider).when(
                              data: (usuarios) => _selectorGenerico('Usuario', _usuarioFiltro, usuarios.map((u) => u.nombreCompleto).toList(), (v) => setState(() => _usuarioFiltro = v)),
                              loading: () => const LinearProgressIndicator(),
                              error: (e, st) => const SizedBox(),
                            ),
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
              ],
              body: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCDD1DA), width: 1.3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 26, offset: const Offset(0, 12))],
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
                                    Text('No se encontraron resultados', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                                  ],
                                ),
                              )
                            : (esMovil ? _tarjetas(lista) : _tabla(lista)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statTotalFacturado(double total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFC62828),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFFC62828).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.point_of_sale_outlined, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL FACTURADO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85), letterSpacing: 0.6)),
              Text(formatearMoneda(total), style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ],
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Flexible(
                child: Text('$label: ${formato.format(fecha)}', overflow: TextOverflow.ellipsis, maxLines: 1, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A))),
              ),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _busquedaController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por documento, cliente, método de pago...',
                hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _aplicarBusqueda(),
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
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final mostrarUsuario = ancho >= 1200;
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
                    _celdaHeader('FECHA', 2),
                    _celdaHeader('TIPO', 2),
                    _celdaHeader('DOCUMENTO', 2),
                    _celdaHeader('CLIENTE', 3),
                    _celdaHeader('TOTAL', 2),
                    if (mostrarMetodoPago) _celdaHeader('PAGO', 2),
                    if (mostrarCondicion) _celdaHeader('CONDICIÓN', 2),
                    if (mostrarUsuario) _celdaHeader('USUARIO', 2),
                    _celdaHeader('ESTADO', 2),
                  ],
                ),
              );
            }
            final v = lista[index - 1];
            return Column(
              children: [
                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                InkWell(
                  onTap: () => _verDetalle(v.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        _celda(2, v.fechaRegistro != null ? formatoFecha.format(v.fechaRegistro!) : '-', gris: true),
                        Expanded(flex: 2, child: _chipTipo(v)),
                        _celda(2, v.numeroDocumento, peso: FontWeight.w600),
                        _celda(3, v.nombreCliente),
                        _celda(2, formatearMoneda(v.totalAPagar), peso: FontWeight.w700),
                        if (mostrarMetodoPago) _celda(2, v.metodoPago, gris: true),
                        if (mostrarCondicion) _celda(2, v.condicion, gris: true),
                        if (mostrarUsuario) _celda(2, v.usuarioRegistro, gris: true),
                        Expanded(flex: 2, child: _chipEstado(v)),
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
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final v = lista[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _verDetalle(v.id),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EC))),
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
      decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $valor', style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF3F434A))),
    );
  }
}
