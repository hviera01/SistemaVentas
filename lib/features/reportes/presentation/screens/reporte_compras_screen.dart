import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/reporte_compra_model.dart';
import '../../data/reporte_export_service.dart';
import '../../providers/reportes_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/exportador.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../proveedores/providers/proveedores_provider.dart';
import '../../../usuarios/providers/usuarios_provider.dart';

class ReporteComprasScreen extends ConsumerStatefulWidget {
  const ReporteComprasScreen({super.key});

  @override
  ConsumerState<ReporteComprasScreen> createState() => _ReporteComprasScreenState();
}

class _ReporteComprasScreenState extends ConsumerState<ReporteComprasScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = ReporteExportService();
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String? _idProveedorFiltro;
  String _busqueda = '';
  String? _metodoPagoFiltro;
  String? _condicionFiltro;
  String? _usuarioFiltro;
  bool _cargando = false;
  String? _error;
  List<ReporteCompraModel>? _compras;

  static const _metodosPago = ['Efectivo', 'Transferencia', 'Tarjeta', 'Cheque'];
  static const _condiciones = ['Contado', 'Crédito'];

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
      final compras = await ref.read(reporteRepositoryProvider).obtenerReporteCompras(_fechaInicio, finInclusive, idProveedor: _idProveedorFiltro);
      if (mounted) setState(() => _compras = compras);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el reporte');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
      _idProveedorFiltro = null;
      _busqueda = '';
      _metodoPagoFiltro = null;
      _condicionFiltro = null;
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

  List<ReporteCompraModel> get _listaFiltrada {
    var lista = _compras ?? [];
    if (_busqueda.isNotEmpty) {
      lista = lista.where((c) => coincideFuzzy(c.textoBusqueda, _busqueda)).toList();
    }
    if (_metodoPagoFiltro != null) {
      lista = lista.where((c) => c.metodoPago == _metodoPagoFiltro).toList();
    }
    if (_condicionFiltro != null) {
      lista = lista.where((c) => c.condicion == _condicionFiltro).toList();
    }
    if (_usuarioFiltro != null) {
      lista = lista.where((c) => c.usuarioRegistro == _usuarioFiltro).toList();
    }
    return lista;
  }

  Future<void> _exportarExcel() async {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    final bytes = _servicioExport.generarExcelCompras(lista);
    final fecha = DateFormat('dd-MM-yyyy').format(DateTime.now());
    await guardarOCompartirArchivo(bytes, 'Reporte_Compras_$fecha.xlsx');
  }

  void _exportarPdf() {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Reporte de Compras',
        nombreArchivo: 'reporte_compras.pdf',
        generarPdf: () => _servicioExport.generarPdfCompras(lista),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _listaFiltrada;
    final totalFacturado = lista.fold<double>(0, (s, c) => s + c.montoTotal);
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 760;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Text('Reporte de Compras', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
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
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 220,
                        child: proveedoresAsync.when(
                          data: (proveedores) => _selectorProveedor(proveedores),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, st) => const SizedBox(),
                        ),
                      ),
                      SizedBox(width: esMovil ? constraints.maxWidth : 260, child: _buscador()),
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
                                    Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.grey.shade300),
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
          const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 24),
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

  Widget _selectorProveedor(List<dynamic> proveedores) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _idProveedorFiltro,
          isExpanded: true,
          hint: Text('Todos los proveedores', style: GoogleFonts.poppins(fontSize: 13)),
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('Todos los proveedores', style: GoogleFonts.poppins(fontSize: 13))),
            ...proveedores.map((p) => DropdownMenuItem<String?>(value: p.id as String, child: Text(p.razonSocial as String, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (v) => setState(() => _idProveedorFiltro = v),
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
                hintText: 'Buscar por factura, proveedor...',
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

  Widget _tabla(List<ReporteCompraModel> lista) {
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
                    _celdaHeader('FACTURA', 2),
                    _celdaHeader('PROVEEDOR', 3),
                    _celdaHeader('MONTO', 2),
                    if (mostrarMetodoPago) _celdaHeader('PAGO', 2),
                    if (mostrarCondicion) _celdaHeader('CONDICIÓN', 2),
                    if (mostrarUsuario) _celdaHeader('USUARIO', 2),
                  ],
                ),
              );
            }
            final c = lista[index - 1];
            return Column(
              children: [
                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      _celda(2, c.fechaRegistro != null ? formatoFecha.format(c.fechaRegistro!) : '-', gris: true),
                      _celda(2, c.noFactura.isEmpty ? '-' : c.noFactura, peso: FontWeight.w600),
                      _celda(3, c.razonSocial),
                      _celda(2, formatearMoneda(c.montoTotal), peso: FontWeight.w700),
                      if (mostrarMetodoPago) _celda(2, c.metodoPago, gris: true),
                      if (mostrarCondicion) _celda(2, c.condicion, gris: true),
                      if (mostrarUsuario) _celda(2, c.usuarioRegistro, gris: true),
                    ],
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

  Widget _tarjetas(List<ReporteCompraModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final c = lista[index];
        return Container(
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
                        Text(c.razonSocial.isEmpty ? 'Sin proveedor' : c.razonSocial, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                        Text('Factura ${c.noFactura}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Text(formatearMoneda(c.montoTotal), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chipInfo('Pago', c.metodoPago),
                  _chipInfo('Condición', c.condicion),
                  _chipInfo('Fecha', c.fechaRegistro != null ? formatoFecha.format(c.fechaRegistro!) : '-'),
                ],
              ),
            ],
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
