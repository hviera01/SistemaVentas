import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/egreso_model.dart';
import '../../data/egreso_export_service.dart';
import '../../providers/egresos_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/exportador.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';

class IngresosEgresosScreen extends ConsumerStatefulWidget {
  const IngresosEgresosScreen({super.key});

  @override
  ConsumerState<IngresosEgresosScreen> createState() => _IngresosEgresosScreenState();
}

class _IngresosEgresosScreenState extends ConsumerState<IngresosEgresosScreen> {
  final _servicioExport = EgresoExportService();
  final _busquedaController = TextEditingController();
  final _montoController = TextEditingController();
  final _descripcionController = TextEditingController();

  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String _busqueda = '';
  String? _tipoFiltro;
  String? _metodoFiltro;
  String? _categoriaFiltro;
  String? _pagadoFiltro;

  String _idEditando = '';
  DateTime _fechaEgreso = DateTime.now();
  String _metodoPago = 'Efectivo';
  String _categoria = 'Negocio';
  bool _esPagado = true;
  DateTime _fechaPago = DateTime.now();

  bool _cargando = false;
  List<MovimientoFinanciero>? _movimientos;

  static const _tipos = ['Venta (Contado)', 'Compra (Contado)', 'Abono a Crédito', 'Abono Compra Crédito', 'Egreso Manual'];
  static const _metodos = ['Efectivo', 'Transferencia', 'Tarjeta'];
  static const _categorias = ['Negocio', 'Casa'];

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
    _cargar();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _montoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final finInclusive = DateTime(_fechaFin.year, _fechaFin.month, _fechaFin.day, 23, 59, 59);
      final movimientos = await ref.read(egresoRepositoryProvider).obtenerLibroFinanciero(_fechaInicio, finInclusive);
      if (mounted) setState(() => _movimientos = movimientos);
    } catch (e) {
      _mostrarMensaje('No se pudo cargar el libro financiero: $e', esError: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<MovimientoFinanciero> get _listaFiltrada {
    var lista = _movimientos ?? [];
    if (_busqueda.isNotEmpty) {
      lista = lista.where((m) => coincideFuzzy('${m.descripcion} ${m.tipoMovimiento} ${m.metodoPago} ${m.usuario}', _busqueda)).toList();
    }
    if (_tipoFiltro != null) lista = lista.where((m) => m.tipoMovimiento == _tipoFiltro).toList();
    if (_metodoFiltro != null) lista = lista.where((m) => m.metodoPago == _metodoFiltro).toList();
    if (_categoriaFiltro != null) lista = lista.where((m) => m.categoria == _categoriaFiltro).toList();
    if (_pagadoFiltro != null) {
      final quierePagado = _pagadoFiltro == 'Pagado';
      lista = lista.where((m) => !m.esEgresoManual || m.esPagado == quierePagado).toList();
    }
    return lista;
  }

  void _limpiarFormulario() {
    _idEditando = '';
    _montoController.clear();
    _descripcionController.clear();
    _metodoPago = 'Efectivo';
    _categoria = 'Negocio';
    _esPagado = true;
    _fechaEgreso = DateTime.now();
    _fechaPago = DateTime.now();
  }

  Future<void> _registrarEgreso() async {
    final monto = double.tryParse(_montoController.text.replaceAll(',', '').trim()) ?? 0;
    if (monto <= 0) {
      _mostrarMensaje('Monto inválido', esError: true);
      return;
    }
    if (_descripcionController.text.trim().isEmpty) {
      _mostrarMensaje('Ingrese una descripción', esError: true);
      return;
    }
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? 'Sistema';
    final egreso = EgresoModel(
      id: _idEditando,
      fecha: _fechaEgreso,
      monto: monto,
      descripcion: _descripcionController.text.trim(),
      usuario: usuario,
      metodoPago: _metodoPago,
      categoria: _categoria,
      esPagado: _esPagado,
      fechaPago: _esPagado ? _fechaPago : null,
    );
    try {
      final repo = ref.read(egresoRepositoryProvider);
      if (_idEditando.isEmpty) {
        await repo.crear(egreso);
        _mostrarMensaje('Egreso registrado');
      } else {
        await repo.actualizar(egreso);
        _mostrarMensaje('Egreso actualizado');
      }
      setState(_limpiarFormulario);
      await _cargar();
    } catch (e) {
      _mostrarMensaje('Error al registrar el egreso: $e', esError: true);
    }
  }

  Future<void> _eliminarEgreso() async {
    if (_idEditando.isEmpty) {
      _mostrarMensaje('Seleccione un egreso manual', esError: true);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar este egreso?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await ref.read(egresoRepositoryProvider).eliminar(_idEditando);
      _mostrarMensaje('Egreso eliminado');
      setState(_limpiarFormulario);
      await _cargar();
    } catch (e) {
      _mostrarMensaje('Error al eliminar el egreso: $e', esError: true);
    }
  }

  void _seleccionarMovimiento(MovimientoFinanciero m) {
    if (!m.esEgresoManual) {
      setState(_limpiarFormulario);
      return;
    }
    setState(() {
      _idEditando = m.idEgreso;
      _fechaEgreso = m.fecha;
      _montoController.text = m.egreso.toStringAsFixed(2);
      _descripcionController.text = m.descripcion;
      _metodoPago = _metodos.contains(m.metodoPago) ? m.metodoPago : 'Efectivo';
      _categoria = _categorias.contains(m.categoria) ? m.categoria : 'Negocio';
      _esPagado = m.esPagado;
      _fechaPago = m.fechaPago ?? DateTime.now();
    });
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
    await _cargar();
  }

  Future<void> _exportarExcel() async {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    final bytes = _servicioExport.generarExcelLibro(lista);
    final fecha = DateFormat('dd-MM-yyyy').format(DateTime.now());
    await guardarOCompartirArchivo(bytes, 'Libro_Financiero_$fecha.xlsx');
  }

  void _exportarPdf() {
    final lista = _listaFiltrada;
    if (lista.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Libro Financiero',
        nombreArchivo: 'libro_financiero.pdf',
        generarPdf: () => _servicioExport.generarPdfLibro(lista, _fechaInicio, _fechaFin),
      ),
    );
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: esError ? const Color(0xFFC62828) : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _listaFiltrada;
    final totales = TotalesLibro.desde(lista);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: esMovil
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _encabezado(),
                        const SizedBox(height: 16),
                        _formularioEgreso(),
                        const SizedBox(height: 16),
                        _filtros(esMovil, constraints.maxWidth),
                        const SizedBox(height: 12),
                        _totalesFila(totales, esMovil),
                        const SizedBox(height: 12),
                        SizedBox(height: 420, child: _lista(lista)),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _encabezado(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 340, child: _formularioEgreso()),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _filtros(esMovil, constraints.maxWidth),
                                  const SizedBox(height: 12),
                                  _totalesFila(totales, esMovil),
                                  const SizedBox(height: 12),
                                  Expanded(child: _lista(lista)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _encabezado() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text('Ingresos y Egresos', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        OutlinedButton.icon(
          onPressed: _exportarExcel,
          icon: const Icon(Icons.grid_on_outlined, size: 18),
          label: Text('Excel', style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        OutlinedButton.icon(
          onPressed: _exportarPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text('PDF', style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ],
    );
  }

  Widget _formularioEgreso() {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_idEditando.isEmpty ? 'Registrar egreso manual' : 'Editar egreso', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _campoTexto('Monto', _montoController, teclado: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 10),
          _campoTexto('Descripción', _descripcionController),
          const SizedBox(height: 10),
          _dropdown('Método de pago', _metodoPago, _metodos, (v) => setState(() => _metodoPago = v!)),
          const SizedBox(height: 10),
          _dropdown('Categoría', _categoria, _categorias, (v) => setState(() => _categoria = v!)),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final fecha = await showDatePicker(context: context, initialDate: _fechaEgreso, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (fecha == null) return;
              setState(() => _fechaEgreso = DateTime(fecha.year, fecha.month, fecha.day, _fechaEgreso.hour, _fechaEgreso.minute));
            },
            child: _campoEstatico('Fecha', formatoFecha.format(_fechaEgreso)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(value: _esPagado, onChanged: (v) => setState(() => _esPagado = v ?? true)),
              Text('Pagado', style: GoogleFonts.poppins(fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _eliminarEgreso,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Eliminar', style: GoogleFonts.poppins(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _registrarEgreso,
                  icon: Icon(_idEditando.isEmpty ? Icons.add : Icons.save_outlined, size: 16),
                  label: Text(_idEditando.isEmpty ? 'Registrar' : 'Guardar', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ],
          ),
          if (_idEditando.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () => setState(_limpiarFormulario), child: const Text('Cancelar edición')),
          ],
        ],
      ),
    );
  }

  Widget _filtros(bool esMovil, double anchoTotal) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _campoFecha('Desde', _fechaInicio, () => _seleccionarFecha(true)),
        _campoFecha('Hasta', _fechaFin, () => _seleccionarFecha(false)),
        SizedBox(width: esMovil ? anchoTotal - 28 : 260, child: _buscador()),
        SizedBox(width: esMovil ? anchoTotal - 28 : 180, child: _selectorGenerico('Tipo', _tipoFiltro, _tipos, (v) => setState(() => _tipoFiltro = v))),
        SizedBox(width: esMovil ? anchoTotal - 28 : 160, child: _selectorGenerico('Método', _metodoFiltro, _metodos, (v) => setState(() => _metodoFiltro = v))),
        SizedBox(width: esMovil ? anchoTotal - 28 : 160, child: _selectorGenerico('Categoría', _categoriaFiltro, _categorias, (v) => setState(() => _categoriaFiltro = v))),
        SizedBox(width: esMovil ? anchoTotal - 28 : 160, child: _selectorGenerico('Estado', _pagadoFiltro, const ['Pagado', 'No pagado'], (v) => setState(() => _pagadoFiltro = v))),
      ],
    );
  }

  Widget _totalesFila(TotalesLibro totales, bool esMovil) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statChip('Ingresos', totales.ingresos, const Color(0xFF16A34A)),
        _statChip('A proveedores', totales.aProveedores, const Color(0xFFF59E0B)),
        _statChip('Gastos negocio', totales.gastosNegocio, const Color(0xFFC62828)),
        _statChip('Gastos casa', totales.gastosCasa, const Color(0xFF8B5CF6)),
        _statChip('Utilidad', totales.utilidad, const Color(0xFF1A1A1A)),
      ],
    );
  }

  Widget _statChip(String etiqueta, double valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
          Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _lista(List<MovimientoFinanciero> lista) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)));
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No se encontraron movimientos', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: lista.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final m = lista[index];
          final seleccionado = m.esEgresoManual && m.idEgreso == _idEditando;
          return InkWell(
            onTap: () => _seleccionarMovimiento(m),
            child: Container(
              color: seleccionado ? const Color(0xFFFBEAEA) : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(formatoFecha.format(m.fecha), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
                  Expanded(flex: 2, child: Text(m.tipoMovimiento, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600))),
                  Expanded(flex: 3, child: Text(m.descripcion, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(m.ingreso == 0 ? '' : formatearMoneda(m.ingreso), style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600))),
                  Expanded(flex: 2, child: Text(m.egreso == 0 ? '' : formatearMoneda(m.egreso), style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828), fontWeight: FontWeight.w600))),
                  Expanded(flex: 2, child: Text(m.metodoPago, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _campoTexto(String etiqueta, TextEditingController controller, {TextInputType? teclado}) {
    return TextField(
      controller: controller,
      keyboardType: teclado,
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        labelText: etiqueta,
        labelStyle: GoogleFonts.poppins(fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFE8EAF0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _campoEstatico(String etiqueta, String valor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text('$etiqueta: $valor', style: GoogleFonts.poppins(fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _dropdown(String etiqueta, String valor, List<String> opciones, void Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: opciones.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _campoFecha(String label, DateTime fecha, VoidCallback onTap) {
    final formato = DateFormat('dd/MM/yyyy');
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
            child: TextField(
              controller: _busquedaController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(hintText: 'Buscar...', hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400), border: InputBorder.none, isDense: true),
              onChanged: (v) => setState(() => _busqueda = v.trim()),
            ),
          ),
        ],
      ),
    );
  }
}
