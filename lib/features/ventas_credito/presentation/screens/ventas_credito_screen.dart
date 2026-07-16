import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../data/venta_credito_model.dart';
import '../../data/abono_model.dart';
import '../../data/venta_credito_export_service.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/exportador.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../widgets/registrar_credito_dialog.dart';
import '../widgets/registrar_abono_dialog.dart';
import '../widgets/unir_facturas_dialog.dart';
import '../widgets/historial_abonos_dialog.dart';
import '../../../ventas/presentation/screens/detalle_venta_screen.dart';

class VentasCreditoScreen extends ConsumerStatefulWidget {
  const VentasCreditoScreen({super.key});

  @override
  ConsumerState<VentasCreditoScreen> createState() => _VentasCreditoScreenState();
}

class _VentasCreditoScreenState extends ConsumerState<VentasCreditoScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = VentaCreditoExportService();
  String? _filaSeleccionada;
  final Set<String> _seleccionadosParaUnir = {};
  List<VentaCreditoModel> _listaCompleta = [];
  List<VentaCreditoModel> _listaActual = [];

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() {
    ref.read(ventasCreditoBusquedaProvider.notifier).actualizar(_busquedaController.text.trim());
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(ventasCreditoBusquedaProvider.notifier).actualizar('');
  }

  void _alternarSeleccionUnir(String id) {
    setState(() {
      if (_seleccionadosParaUnir.contains(id)) {
        _seleccionadosParaUnir.remove(id);
      } else {
        _seleccionadosParaUnir.add(id);
      }
    });
  }

  void _abrirRegistrarCredito() {
    showDialog(context: context, builder: (context) => const RegistrarCreditoDialog());
  }

  Future<void> _abrirRegistrarAbono(VentaCreditoModel credito) async {
    final abono = await showDialog<AbonoModel>(
      context: context,
      builder: (context) => RegistrarAbonoDialog(credito: credito),
    );
    if (abono == null || !mounted) return;
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty
        ? null
        : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Recibo de abono',
        nombreArchivo: 'recibo_${credito.numeroDocumento}.pdf',
        generarPdf: () => _servicioExport.generarPdfRecibo(credito, abono, negocio),
        impresora: impresora,
      ),
    );
  }

  void _abrirHistorial(VentaCreditoModel credito) {
    showDialog(context: context, builder: (context) => HistorialAbonosDialog(credito: credito));
  }

  Future<void> _eliminar(VentaCreditoModel credito) async {
    final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasCreditoEliminar);
    if (!autorizado || !mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar crédito', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este crédito? Esta acción no se puede deshacer.', style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ref.read(ventaCreditoRepositoryProvider).eliminar(credito.id);
    setState(() => _seleccionadosParaUnir.remove(credito.id));
  }

  Future<void> _unirFacturas() async {
    final seleccionadas = _listaCompleta.where((c) => _seleccionadosParaUnir.contains(c.id)).toList();
    if (seleccionadas.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccioná al menos dos facturas para unir')));
      return;
    }
    final noElegibles = seleccionadas.where((f) => f.liquidada);
    if (noElegibles.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solo se pueden unir facturas con saldo pendiente')));
      return;
    }
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => UnirFacturasDialog(facturas: seleccionadas),
    );
    if (resultado == true) {
      setState(() => _seleccionadosParaUnir.clear());
    }
  }

  void _manejarAccion(String valor, VentaCreditoModel credito) {
    switch (valor) {
      case 'abono':
        _abrirRegistrarAbono(credito);
        break;
      case 'historial':
        _abrirHistorial(credito);
        break;
      case 'detalle':
        _verDetalleVenta(credito);
        break;
      case 'eliminar':
        _eliminar(credito);
        break;
    }
  }

  void _verDetalleVenta(VentaCreditoModel credito) {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleVentaScreen(ventaIdInicial: credito.id)),
    );
  }

  List<PopupMenuEntry<String>> _opcionesMenu(VentaCreditoModel credito) {
    return [
      if (!credito.liquidada) _opcionMenu(valor: 'abono', icono: Icons.payments_outlined, texto: 'Registrar abono'),
      _opcionMenu(valor: 'historial', icono: Icons.history, texto: 'Ver historial de abonos'),
      _opcionMenu(valor: 'detalle', icono: Icons.receipt_long_outlined, texto: 'Ver detalle de venta'),
      const PopupMenuDivider(),
      _opcionMenu(valor: 'eliminar', icono: Icons.delete_outline, texto: 'Eliminar'),
    ];
  }

  PopupMenuItem<String> _opcionMenu({required String valor, required IconData icono, required String texto}) {
    return PopupMenuItem<String>(
      value: valor,
      height: 42,
      child: Row(children: [Icon(icono, size: 18, color: const Color(0xFF4B4F58)), const SizedBox(width: 10), Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF25272B)))]),
    );
  }

  Future<void> _exportarExcel() async {
    if (_listaActual.isEmpty) return;
    final bytes = _servicioExport.generarExcel(_listaActual);
    final fecha = DateFormat('dd-MM-yyyy').format(DateTime.now());
    await guardarOCompartirArchivo(bytes, 'Ventas_Credito_$fecha.xlsx');
  }

  void _exportarPdf() {
    if (_listaActual.isEmpty) return;
    final lista = List<VentaCreditoModel>.from(_listaActual);
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Ventas a Crédito',
        nombreArchivo: 'ventas_credito.pdf',
        generarPdf: () => _servicioExport.generarPdfListado(lista),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creditosAsync = ref.watch(ventasCreditoStreamProvider);
    final busqueda = ref.watch(ventasCreditoBusquedaProvider);
    final vista = ref.watch(ventasCreditoVistaProvider);

    List<VentaCreditoModel>? listaFiltrada;
    if (creditosAsync.hasValue) {
      final creditos = creditosAsync.value!;
      _listaCompleta = creditos;
      var lista = creditos.where((c) => !c.fusionada).toList();
      if (vista == 'debe') {
        lista = lista.where((c) => !c.liquidada).toList();
      } else if (vista == 'liquidada') {
        lista = lista.where((c) => c.liquidada).toList();
      }
      if (busqueda.isNotEmpty) {
        lista = lista.where((c) => coincideFuzzy(c.textoBusqueda, busqueda)).toList();
      }
      listaFiltrada = lista;
      _listaActual = lista;
    }

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 760;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Text('Ventas a Crédito', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                      if (listaFiltrada != null) _statTotalPendiente(listaFiltrada),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: esMovil ? constraints.maxWidth : 200, child: _selectorVista(vista)),
                      SizedBox(width: esMovil ? constraints.maxWidth : 300, child: _buscador(busqueda)),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(ventasCreditoStreamProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFDCDFE6)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportarExcel,
                        icon: const Icon(Icons.grid_on_outlined, size: 18),
                        label: Text('Descargar Excel', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFDCDFE6)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportarPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text('Descargar PDF', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFDCDFE6)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _seleccionadosParaUnir.length >= 2 ? _unirFacturas : null,
                        icon: const Icon(Icons.call_merge_outlined, size: 18),
                        label: Text(_seleccionadosParaUnir.isEmpty ? 'Unir Facturas' : 'Unir Facturas (${_seleccionadosParaUnir.length})', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFDCDFE6)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _abrirRegistrarCredito,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Registrar Crédito', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCDD1DA), width: 1.3),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 26, offset: const Offset(0, 12))],
                    ),
                    child: creditosAsync.when(
                      data: (creditos) {
                        final lista = listaFiltrada!;

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.credit_score_outlined, size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('No hay créditos para mostrar', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                              ],
                            ),
                          );
                        }

                        return esMovil ? _tarjetas(lista) : _tabla(lista);
                      },
                      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statTotalPendiente(List<VentaCreditoModel> lista) {
    final total = lista.fold<double>(0, (s, c) => s + c.saldoPendiente);
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
          const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL PENDIENTE', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85), letterSpacing: 0.6)),
              Text(formatearMoneda(total), style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectorVista(String vista) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCDFE6))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: vista,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: const [
            DropdownMenuItem(value: 'debe', child: Text('Deben')),
            DropdownMenuItem(value: 'liquidada', child: Text('Liquidadas')),
            DropdownMenuItem(value: 'todas', child: Text('Todas')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref.read(ventasCreditoVistaProvider.notifier).actualizar(v);
          },
        ),
      ),
    );
  }

  Widget _buscador(String busqueda) {
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
                hintText: 'Buscar por factura o cliente...',
                hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _buscar(),
            ),
          ),
          if (busqueda.isNotEmpty) IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.close, size: 18), onPressed: _limpiarBusqueda),
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _buscar),
        ],
      ),
    );
  }

  Widget _chipEstado(VentaCreditoModel c) {
    if (c.liquidada) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFE8F8EE), borderRadius: BorderRadius.circular(8)),
        child: Text('Liquidada', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A))),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(8)),
          child: Text('Debe', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF3B82F6))),
        ),
        if (c.vencida)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFFCE4E4), borderRadius: BorderRadius.circular(8)),
            child: Text('Vencida', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFC62828))),
          ),
      ],
    );
  }

  Widget _tabla(List<VentaCreditoModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final mostrarFechaRegistro = ancho >= 1050;
        final mostrarMontoTotal = ancho >= 900;

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
                    const SizedBox(width: 34),
                    if (mostrarFechaRegistro) _celdaHeader('FECHA REGISTRO', 2),
                    _celdaHeader('FACTURA', 2),
                    _celdaHeader('CLIENTE', 3),
                    if (mostrarMontoTotal) _celdaHeader('MONTO TOTAL', 2),
                    _celdaHeader('SALDO PENDIENTE', 2),
                    _celdaHeader('VENCIMIENTO', 2),
                    _celdaHeader('ESTADO', 2),
                    const SizedBox(width: 56),
                  ],
                ),
              );
            }
            final credito = lista[index - 1];
            final seleccionada = _filaSeleccionada == credito.id;
            final marcado = _seleccionadosParaUnir.contains(credito.id);
            return Column(
              children: [
                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                InkWell(
                  onTap: () => setState(() => _filaSeleccionada = seleccionada ? null : credito.id),
                  child: Container(
                    color: seleccionada ? const Color(0xFFFBEAEA) : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Checkbox(
                            value: marcado,
                            onChanged: (_) => _alternarSeleccionUnir(credito.id),
                            activeColor: const Color(0xFFC62828),
                          ),
                        ),
                        if (mostrarFechaRegistro) _celda(2, credito.fechaRegistro != null ? formatoFecha.format(credito.fechaRegistro!) : '-', gris: true),
                        _celda(2, credito.numeroDocumento, peso: FontWeight.w600),
                        _celda(3, credito.nombreCliente),
                        if (mostrarMontoTotal) _celda(2, formatearMoneda(credito.montoTotal), gris: true),
                        _celda(2, formatearMoneda(credito.saldoPendiente), peso: FontWeight.w700),
                        _celda(2, credito.fechaVencimiento != null ? formatoFecha.format(credito.fechaVencimiento!) : '-', gris: true),
                        Expanded(flex: 2, child: _chipEstado(credito)),
                        SizedBox(width: 56, child: _celdaAcciones(credito)),
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
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: peso, color: gris ? Colors.grey.shade600 : const Color(0xFF1A1A1A)),
        ),
      ),
    );
  }

  Widget _celdaAcciones(VentaCreditoModel credito) {
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFDFE1E6))), child: const Icon(Icons.more_vert, size: 19, color: Color(0xFF454950))),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      position: PopupMenuPosition.under,
      onSelected: (valor) => _manejarAccion(valor, credito),
      itemBuilder: (context) => _opcionesMenu(credito),
    );
  }

  Widget _tarjetas(List<VentaCreditoModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final credito = lista[index];
        final seleccionada = _filaSeleccionada == credito.id;
        final marcado = _seleccionadosParaUnir.contains(credito.id);
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _filaSeleccionada = seleccionada ? null : credito.id),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: seleccionada ? const Color(0xFFFBEAEA) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: seleccionada ? const Color(0xFFC62828) : const Color(0xFFE5E7EC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Checkbox(
                        value: marcado,
                        onChanged: (_) => _alternarSeleccionUnir(credito.id),
                        activeColor: const Color(0xFFC62828),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(credito.nombreCliente, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                          Text('Factura ${credito.numeroDocumento}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    _celdaAcciones(credito),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipInfo('Monto total', formatearMoneda(credito.montoTotal)),
                    _chipInfo('Saldo pendiente', formatearMoneda(credito.saldoPendiente)),
                    _chipInfo('Vence', credito.fechaVencimiento != null ? formatoFecha.format(credito.fechaVencimiento!) : '-'),
                    _chipEstado(credito),
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
