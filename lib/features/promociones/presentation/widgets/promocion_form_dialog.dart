import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/promocion_model.dart';
import '../../providers/promociones_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import 'seleccionar_productos_dialog.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';

const _opcionesMetodoPago = ['Todos', 'Efectivo', 'Tarjeta', 'Transferencia'];

class PromocionFormDialog extends ConsumerStatefulWidget {
  final PromocionModel? promocion;

  const PromocionFormDialog({super.key, this.promocion});

  @override
  ConsumerState<PromocionFormDialog> createState() => _PromocionFormDialogState();
}

class _PromocionFormDialogState extends ConsumerState<PromocionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _valorController = TextEditingController();
  final _cantidadRequeridaController = TextEditingController(text: '2');
  final _precioComboController = TextEditingController();
  final _precioComboMultiController = TextEditingController();
  final _cantidadRegaloController = TextEditingController(text: '1');

  TipoPromocion _tipo = TipoPromocion.porcentaje;
  List<String> _idsProductos = [];
  List<String> _nombresProductos = [];
  String _idProductoBase = '';
  String _nombreProductoBase = '';
  List<String> _idsProductosCombo = [];
  List<String> _nombresProductosCombo = [];
  List<String> _idsProductosRegalo = [];
  List<String> _nombresProductosRegalo = [];
  DateTime _fechaInicio = DateTime.now();
  DateTime? _fechaFin;
  bool _indefinida = true;
  String _alcancePago = 'Todos';
  List<String> _metodosPagoAlcance = [];
  bool _activo = true;
  bool _guardando = false;

  bool get _esEdicion => widget.promocion != null;

  @override
  void initState() {
    super.initState();
    final p = widget.promocion;
    if (p != null) {
      _nombreController.text = p.nombre;
      _tipo = p.tipo;
      _idsProductos = [...p.idsProductos];
      _nombresProductos = [...p.nombresProductos];
      _valorController.text = p.valor == 0 ? '' : (p.valor == p.valor.roundToDouble() ? p.valor.toInt().toString() : p.valor.toString());
      _idProductoBase = p.idProductoBase;
      _nombreProductoBase = p.nombreProductoBase;
      _cantidadRequeridaController.text = p.cantidadRequerida.toString();
      _precioComboController.text = p.precioCombo == 0 ? '' : p.precioCombo.toString();
      _precioComboMultiController.text = p.precioCombo == 0 ? '' : p.precioCombo.toString();
      _idsProductosCombo = [...p.idsProductosCombo];
      _nombresProductosCombo = [...p.nombresProductosCombo];
      _idsProductosRegalo = [...p.idsProductosRegalo];
      _nombresProductosRegalo = [...p.nombresProductosRegalo];
      _cantidadRegaloController.text = p.cantidadRegalo.toString();
      _fechaInicio = p.fechaInicio;
      _fechaFin = p.fechaFin;
      _indefinida = p.esIndefinida;
      _alcancePago = p.alcancePago;
      _metodosPagoAlcance = [...p.metodosPagoAlcance];
      _activo = p.activo;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _valorController.dispose();
    _cantidadRequeridaController.dispose();
    _precioComboController.dispose();
    _precioComboMultiController.dispose();
    _cantidadRegaloController.dispose();
    super.dispose();
  }

  Future<void> _elegirProductos() async {
    final elegidos = await showDialog<List>(
      context: context,
      builder: (context) => SeleccionarProductosDialog(seleccionadosIniciales: _idsProductos, titulo: 'Productos con la Promoción'),
    );
    if (elegidos == null) return;
    setState(() {
      _idsProductos = elegidos.map((p) => p.id as String).toList();
      _nombresProductos = elegidos.map((p) => p.nombre as String).toList();
    });
  }

  Future<void> _elegirProductoBase() async {
    final elegidos = await showDialog<List>(
      context: context,
      builder: (context) => SeleccionarProductosDialog(seleccionadosIniciales: _idProductoBase.isEmpty ? const [] : [_idProductoBase], maxSeleccion: 1, titulo: 'Producto Base'),
    );
    if (elegidos == null || elegidos.isEmpty) return;
    setState(() {
      _idProductoBase = elegidos.first.id as String;
      _nombreProductoBase = elegidos.first.nombre as String;
    });
  }

  Future<void> _elegirProductosCombo() async {
    final elegidos = await showDialog<List>(
      context: context,
      builder: (context) => SeleccionarProductosDialog(seleccionadosIniciales: _idsProductosCombo, titulo: 'Productos del Combo (2 o más)'),
    );
    if (elegidos == null) return;
    setState(() {
      _idsProductosCombo = elegidos.map((p) => p.id as String).toList();
      _nombresProductosCombo = elegidos.map((p) => p.nombre as String).toList();
    });
  }

  Future<void> _elegirProductosRegalo() async {
    final elegidos = await showDialog<List>(
      context: context,
      builder: (context) => SeleccionarProductosDialog(seleccionadosIniciales: _idsProductosRegalo, titulo: 'Productos de Regalo'),
    );
    if (elegidos == null) return;
    setState(() {
      _idsProductosRegalo = elegidos.map((p) => p.id as String).toList();
      _nombresProductosRegalo = elegidos.map((p) => p.nombre as String).toList();
    });
  }

  Future<void> _elegirFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : (_fechaFin ?? _fechaInicio.add(const Duration(days: 30))),
      firstDate: DateTime(2020),
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

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: esError ? const Color(0xFFC62828) : null));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final esPorcentajeOFijo = _tipo == TipoPromocion.porcentaje || _tipo == TipoPromocion.precioFijo;
    final esComboBase = _tipo == TipoPromocion.comboCantidad || _tipo == TipoPromocion.regalo;
    if (esPorcentajeOFijo && _idsProductos.isEmpty) {
      _mostrarMensaje('Seleccioná al menos un producto', esError: true);
      return;
    }
    if (esComboBase && _idProductoBase.isEmpty) {
      _mostrarMensaje('Seleccioná el producto base', esError: true);
      return;
    }
    if (_tipo == TipoPromocion.regalo && _idsProductosRegalo.isEmpty) {
      _mostrarMensaje('Seleccioná al menos un producto de regalo', esError: true);
      return;
    }
    if (_tipo == TipoPromocion.comboMultiproducto && _idsProductosCombo.length < 2) {
      _mostrarMensaje('Seleccioná al menos 2 productos para el combo', esError: true);
      return;
    }
    if (!_indefinida && _fechaFin != null && _fechaFin!.isBefore(_fechaInicio)) {
      _mostrarMensaje('La fecha de fin no puede ser anterior a la de inicio', esError: true);
      return;
    }

    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? 'Sistema';
    final promocion = PromocionModel(
      id: widget.promocion?.id ?? '',
      nombre: _nombreController.text.trim(),
      tipo: _tipo,
      idsProductos: esPorcentajeOFijo ? _idsProductos : const [],
      nombresProductos: esPorcentajeOFijo ? _nombresProductos : const [],
      valor: esPorcentajeOFijo ? (double.tryParse(_valorController.text.trim()) ?? 0) : 0,
      idProductoBase: esComboBase ? _idProductoBase : '',
      nombreProductoBase: esComboBase ? _nombreProductoBase : '',
      cantidadRequerida: esComboBase ? (int.tryParse(_cantidadRequeridaController.text.trim()) ?? 1) : 1,
      precioCombo: _tipo == TipoPromocion.comboCantidad
          ? (double.tryParse(_precioComboController.text.trim()) ?? 0)
          : (_tipo == TipoPromocion.comboMultiproducto ? (double.tryParse(_precioComboMultiController.text.trim()) ?? 0) : 0),
      idsProductosCombo: _tipo == TipoPromocion.comboMultiproducto ? _idsProductosCombo : const [],
      nombresProductosCombo: _tipo == TipoPromocion.comboMultiproducto ? _nombresProductosCombo : const [],
      idsProductosRegalo: _tipo == TipoPromocion.regalo ? _idsProductosRegalo : const [],
      nombresProductosRegalo: _tipo == TipoPromocion.regalo ? _nombresProductosRegalo : const [],
      cantidadRegalo: _tipo == TipoPromocion.regalo ? (int.tryParse(_cantidadRegaloController.text.trim()) ?? 1) : 1,
      fechaInicio: _fechaInicio,
      fechaFin: _indefinida ? null : _fechaFin,
      alcancePago: _alcancePago,
      metodosPagoAlcance: _metodosPagoAlcance,
      activo: _activo,
      creadoEn: widget.promocion?.creadoEn,
      creadoPor: widget.promocion?.creadoPor ?? usuario,
    );

    setState(() => _guardando = true);
    try {
      final repo = ref.read(promocionRepositoryProvider);
      if (_esEdicion) {
        await repo.actualizar(promocion);
      } else {
        await repo.crear(promocion);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _mostrarMensaje('Error al guardar: $e', esError: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 640 ? tamano.width - 24 : 560.0;
    final formatoFecha = DateFormat('dd/MM/yyyy');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: tamano.height - 40),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_esEdicion ? 'Editar Promoción' : 'Nueva Promoción', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _nombreController,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: _decoracion('Nombre de la promoción'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),
                Text('Tipo de promoción', style: _etiqueta()),
                const SizedBox(height: 8),
                _selectorTipo(),
                const SizedBox(height: 16),
                if (_tipo == TipoPromocion.porcentaje || _tipo == TipoPromocion.precioFijo) _bloquePorcentajeOFijo(),
                if (_tipo == TipoPromocion.comboCantidad) _bloqueCombo(),
                if (_tipo == TipoPromocion.comboMultiproducto) _bloqueComboMultiproducto(),
                if (_tipo == TipoPromocion.regalo) _bloqueRegalo(),
                const SizedBox(height: 16),
                Text('Vigencia', style: _etiqueta()),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _campoFecha('Desde', _fechaInicio, () => _elegirFecha(true), formatoFecha)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _indefinida
                          ? Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(12)),
                              child: Text('Indefinida', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                            )
                          : _campoFecha('Hasta', _fechaFin ?? _fechaInicio, () => _elegirFecha(false), formatoFecha),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: _indefinida,
                  onChanged: (v) => setState(() => _indefinida = v ?? true),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  activeColor: const Color(0xFFC62828),
                  title: Text('Sin fecha de fin (indefinida)', style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
                const SizedBox(height: 8),
                Text('Condición de la venta', style: _etiqueta()),
                const SizedBox(height: 8),
                _selectorAlcance(),
                const SizedBox(height: 14),
                Text('Método de pago', style: _etiqueta()),
                const SizedBox(height: 8),
                _selectorMetodoPago(),
                const SizedBox(height: 6),
                Text('Los dos filtros de arriba son independientes: tienen que cumplirse ambos para que la promoción aplique.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFFC62828),
                  title: Text('Promoción activa', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('Si se desactiva, no se ofrece aunque esté dentro de su vigencia.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_esEdicion ? 'Guardar Cambios' : 'Crear Promoción', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _etiqueta() => GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600);

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500),
      filled: true,
      fillColor: const Color(0xFFF2F3F7),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _selectorTipo() {
    Widget opcion(String texto, TipoPromocion tipo) {
      final activo = _tipo == tipo;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tipo = tipo),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: activo ? const Color(0xFFC62828) : const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
            child: Text(texto, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF4B4F58))),
          ),
        ),
      );
    }

    return Wrap(
      runSpacing: 6,
      children: [
        Row(children: [opcion('% Descuento', TipoPromocion.porcentaje), opcion('Precio Fijo', TipoPromocion.precioFijo)]),
        const SizedBox(width: double.infinity, height: 6),
        Row(children: [opcion('Combo por Cantidad', TipoPromocion.comboCantidad), opcion('Combo de Productos', TipoPromocion.comboMultiproducto)]),
        const SizedBox(width: double.infinity, height: 6),
        Row(children: [opcion('Regalo', TipoPromocion.regalo)]),
      ],
    );
  }

  Widget _selectorAlcance() {
    Widget opcion(String texto, String valor) {
      final activo = _alcancePago == valor;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _alcancePago = valor),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: activo ? const Color(0xFF3B82F6) : const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
            child: Text(texto, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF4B4F58))),
          ),
        ),
      );
    }

    return Row(children: [opcion('Todos', 'Todos'), opcion('Contado', 'Contado'), opcion('Crédito', 'Credito')]);
  }

  // Multi-selección: "Todos" equivale a la lista vacía (se puede combinar
  // Efectivo + Transferencia, por ejemplo, sin aceptar Tarjeta). Tocar
  // "Todos" limpia cualquier selección puntual; tocar un método puntual
  // mientras "Todos" está activo pasa a restringir solo a ese método.
  Widget _selectorMetodoPago() {
    Widget opcion(String texto, String valor) {
      final esTodos = valor == 'Todos';
      final activo = esTodos ? _metodosPagoAlcance.isEmpty : _metodosPagoAlcance.contains(valor);
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            if (esTodos) {
              _metodosPagoAlcance = [];
            } else if (_metodosPagoAlcance.contains(valor)) {
              _metodosPagoAlcance = [..._metodosPagoAlcance]..remove(valor);
            } else {
              _metodosPagoAlcance = [..._metodosPagoAlcance, valor];
            }
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: activo ? const Color(0xFF16A34A) : const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
            child: Text(texto, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF4B4F58))),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [for (final m in _opcionesMetodoPago) opcion(m, m)]),
        const SizedBox(height: 4),
        Text('Podés elegir varios métodos a la vez (ej. Efectivo y Transferencia).', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _campoFecha(String label, DateTime fecha, VoidCallback onTap, DateFormat formato) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text('$label: ${formato.format(fecha)}', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF1A1A1A))),
          ],
        ),
      ),
    );
  }

  Widget _bloquePorcentajeOFijo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_tipo == TipoPromocion.porcentaje ? 'Porcentaje de descuento' : 'Precio especial (con ISV)', style: _etiqueta()),
        const SizedBox(height: 8),
        TextFormField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _valorController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: _decoracion(_tipo == TipoPromocion.porcentaje ? 'Ej. 15 (para 15% off)' : 'Ej. 99.00'),
          validator: (v) {
            final n = double.tryParse((v ?? '').trim());
            if (n == null || n <= 0) return 'Ingresá un valor válido';
            if (_tipo == TipoPromocion.porcentaje && n > 100) return 'No puede ser mayor a 100%';
            return null;
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _elegirProductos,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text('Elegir productos (${_idsProductos.length})', style: GoogleFonts.poppins(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 13), minimumSize: const Size(double.infinity, 0)),
        ),
        if (_nombresProductos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final n in _nombresProductos) Chip(label: Text(n, style: GoogleFonts.poppins(fontSize: 11)), visualDensity: VisualDensity.compact)]),
        ],
      ],
    );
  }

  Widget _bloqueCombo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Producto base', style: _etiqueta()),
        const SizedBox(height: 8),
        _botonProducto(_nombreProductoBase, _elegirProductoBase),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _cantidadRequeridaController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: _decoracion('Cantidad llevada (N)'),
                validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 2 ? 'Mínimo 2' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _precioComboController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: _decoracion('Precio del combo'),
                validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Requerido' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Ej. "Llevando 3 unidades, se pagan L.100 en total" en vez del precio normal.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _bloqueComboMultiproducto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Productos del combo (2 o más, distintos)', style: _etiqueta()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _elegirProductosCombo,
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text('Elegir productos del combo (${_idsProductosCombo.length})', style: GoogleFonts.poppins(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 13), minimumSize: const Size(double.infinity, 0)),
        ),
        if (_nombresProductosCombo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final n in _nombresProductosCombo) Chip(label: Text(n, style: GoogleFonts.poppins(fontSize: 11)), visualDensity: VisualDensity.compact)]),
        ],
        const SizedBox(height: 12),
        TextFormField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _precioComboMultiController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: _decoracion('Precio total del combo (con ISV)'),
          validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Requerido' : null,
        ),
        const SizedBox(height: 6),
        Text('Ej. "Llevando 1 de cada producto elegido arriba, el paquete completo se paga L.250" en vez de la suma de precios normales. Se ofrece solo cuando ya están los productos completos en el carrito.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _bloqueRegalo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Producto que se debe llevar', style: _etiqueta()),
        const SizedBox(height: 8),
        _botonProducto(_nombreProductoBase, _elegirProductoBase),
        const SizedBox(height: 8),
        TextFormField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _cantidadRequeridaController,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: _decoracion('Cantidad requerida'),
          validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Mínimo 1' : null,
        ),
        const SizedBox(height: 14),
        Text('Productos que se regalan', style: _etiqueta()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _elegirProductosRegalo,
          icon: const Icon(Icons.card_giftcard_outlined, size: 18),
          label: Text('Elegir productos de regalo (${_idsProductosRegalo.length})', style: GoogleFonts.poppins(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 13), minimumSize: const Size(double.infinity, 0)),
        ),
        if (_nombresProductosRegalo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final n in _nombresProductosRegalo) Chip(label: Text(n, style: GoogleFonts.poppins(fontSize: 11)), visualDensity: VisualDensity.compact)]),
        ],
        const SizedBox(height: 8),
        TextFormField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _cantidadRegaloController,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: _decoracion('Cantidad de regalo (por cada producto)'),
          validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Mínimo 1' : null,
        ),
        const SizedBox(height: 6),
        Text('Ej. "Si lleva 2 unidades, se regala 1 de cada producto elegido" (pueden ser del mismo producto llevado o de otros).', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _botonProducto(String nombreActual, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.inventory_2_outlined, size: 18),
      label: Text(nombreActual.isEmpty ? 'Elegir producto' : nombreActual, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 12.5)),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 13), minimumSize: const Size(double.infinity, 0), alignment: Alignment.centerLeft),
    );
  }
}
