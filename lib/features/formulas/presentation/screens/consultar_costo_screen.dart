import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/data/tinte_lookup.dart';
import '../../../ventas/data/costo_tinte_service.dart';
import '../../../ventas/presentation/widgets/agregar_tinte_manual_dialog.dart';
import '../../../ventas/presentation/widgets/buscar_producto_dialog.dart';
import '../../../ventas/presentation/widgets/campo_cantidad_tinte.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../data/formula_colortrend_model.dart';
import '../../data/formula_tamano_utils.dart';
import '../widgets/seleccionar_formula_dialog.dart';

/// Herramienta de consulta de costo de un color preparado, SIN necesidad de
/// hacer una venta -pedido explícito del dueño-: pura lectura, no descuenta
/// stock ni escribe nada en Firestore. Dos modos:
/// - "Fórmula + producto base": elegir una fórmula real (o cargar tintes a
///   mano) + un producto base del inventario → tamaño implícito según el
///   nombre del producto (mismo criterio que Escenario A de la venta, ver
///   formula_tamano_utils.dart) → costo de tinte + costo del producto base
///   (su precioCompra vigente, no ligado a una venta real) + total.
/// - "Solo tinte": "cuánto me cuesta tanto de tal tinte", sin fórmula ni
///   producto base -solo el motor de costeo (CostoTinteService) sobre un
///   tinte y una cantidad en onzas.
class ConsultarCostoScreen extends StatefulWidget {
  const ConsultarCostoScreen({super.key});

  @override
  State<ConsultarCostoScreen> createState() => _ConsultarCostoScreenState();
}

class _ConsultarCostoScreenState extends State<ConsultarCostoScreen> {
  bool _modoSoloTinte = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final esMovil = constraints.maxWidth < 720;
            return SingleChildScrollView(
              padding: EdgeInsets.all(esMovil ? 14 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 6),
                      Text('Consultar costo de un color', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.only(left: esMovil ? 0 : 54),
                    child: Text(
                      'Solo consulta -no descuenta stock ni registra nada, es para saber cuánto cuesta antes de vender.',
                      style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _selectorModo(),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _modoSoloTinte ? const _ModoSoloTinte() : const _ModoFormulaConProducto(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _selectorModo() {
    Widget opcion(String texto, bool valor) {
      final activo = _modoSoloTinte == valor;
      return InkWell(
        onTap: () => setState(() => _modoSoloTinte = valor),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: activo ? const Color(0xFFC62828) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(texto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72))),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opcion('Fórmula + producto base', false), opcion('Solo tinte', true)]),
    );
  }
}

/// Modo "Solo tinte": elegir un tinte real + cuántas onzas → costo, sin
/// fórmula ni producto base involucrado (pedido explícito: "cuánto me
/// cuesta tanto de tal tinte").
class _ModoSoloTinte extends StatefulWidget {
  const _ModoSoloTinte();

  @override
  State<_ModoSoloTinte> createState() => _ModoSoloTinteState();
}

class _ModoSoloTinteState extends State<_ModoSoloTinte> {
  final _servicio = CostoTinteService();
  Future<List<ProductoModel>>? _futureTintes;
  ProductoModel? _tinteElegido;
  double _onzas = 0;
  ResultadoCostoTinte? _calculado;
  bool _calculando = false;
  Timer? _debounce;
  // Se cambia esta key cada vez que se "Limpia" para forzar que
  // CampoCantidadTinte se recree desde cero (Y/48avos vacíos) -el widget no
  // expone un controller propio, ver su doc.
  int _resetCantidad = 0;

  @override
  void initState() {
    super.initState();
    _futureTintes = listarProductosTinte();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // Debounce: antes se recalculaba en cada tecla del campo de onzas -una
  // ida y vuelta a Firestore por dígito escrito-, ahora se espera una pausa
  // corta antes de disparar el cálculo (mismo criterio que
  // AgregarTinteManualDialog).
  void _onCantidadCambiada(double onzas) {
    _onzas = onzas;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _calcular);
  }

  Future<void> _calcular() async {
    final tinte = _tinteElegido;
    final onzas = _onzas;
    if (tinte == null || onzas <= 0) {
      setState(() => _calculado = null);
      return;
    }
    setState(() => _calculando = true);
    final colorante = tinte.nombre.replaceFirst('COLORANTE ', '').trim();
    // productoConocido: tinte -> se salta la consulta a Firestore por
    // nombre (ya se tiene el producto exacto, elegido del dropdown).
    final resultados = await _servicio.calcular([UsoTinte(colorante: colorante, onzas: onzas, productoConocido: tinte)]);
    if (!mounted) return;
    setState(() {
      _calculado = resultados.first;
      _calculando = false;
    });
  }

  void _limpiar() {
    setState(() {
      _tinteElegido = null;
      _calculado = null;
      _onzas = 0;
      _resetCantidad++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hayAlgoQueLimpiar = _tinteElegido != null || _onzas > 0 || _calculado != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('¿Cuánto cuesta tanto de tal tinte?', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700))),
              if (hayAlgoQueLimpiar)
                TextButton.icon(
                  onPressed: _limpiar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF666A72), padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<ProductoModel>>(
            future: _futureTintes,
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828))));
              final tintes = snap.data!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ProductoModel>(
                    isExpanded: true,
                    hint: Text('Elegí un tinte...', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
                    value: _tinteElegido,
                    items: [for (final t in tintes) DropdownMenuItem(value: t, child: Text('${t.nombre}${t.descripcion.isNotEmpty ? " (${t.descripcion})" : ""}', style: GoogleFonts.poppins(fontSize: 13)))],
                    onChanged: (v) {
                      setState(() => _tinteElegido = v);
                      _calcular();
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          CampoCantidadTinte(key: ValueKey(_resetCantidad), onChanged: _onCantidadCambiada),
          const SizedBox(height: 16),
          if (_calculando) const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CircularProgressIndicator(color: Color(0xFFC62828)))),
          if (!_calculando && _calculado != null) _resumen(_calculado!),
        ],
      ),
    );
  }

  Widget _resumen(ResultadoCostoTinte r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E2E8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.cuartos.toStringAsFixed(3)} cuartos', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            r.resuelto ? 'Costo: ${formatearMoneda(r.costoTotal)}' : 'No se puede calcular -sin producto en inventario.',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: r.resuelto ? const Color(0xFF1E9E5A) : const Color(0xFFC62828)),
          ),
          if (r.advertencia != null) ...[
            const SizedBox(height: 6),
            Text(r.advertencia!, style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB45309))),
          ],
        ],
      ),
    );
  }
}

/// Modo "Fórmula + producto base": el modo completo del §8 original -elegir
/// fórmula real (o cargar tintes a mano) + producto base → costo de tinte,
/// costo del producto base, y total combinado.
class _ModoFormulaConProducto extends StatefulWidget {
  const _ModoFormulaConProducto();

  @override
  State<_ModoFormulaConProducto> createState() => _ModoFormulaConProductoState();
}

class _ModoFormulaConProductoState extends State<_ModoFormulaConProducto> {
  ProductoModel? _productoBase;
  TamanoFormula? _tamanoManual;
  final List<ResultadoCostoTinte> _tintes = [];
  bool _calculando = false;

  TamanoFormula? get _tamanoEfectivo {
    if (_productoBase == null) return null;
    return tamanoDesdeNombreProducto(_productoBase!.nombre) ?? _tamanoManual;
  }

  Future<void> _elegirProductoBase() async {
    final resultado = await Navigator.of(context).push<ProductoConPrecio>(MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoDialog()));
    if (resultado == null || !mounted) return;
    setState(() {
      _productoBase = resultado.producto;
      _tamanoManual = null;
    });
  }

  Future<void> _buscarFormula() async {
    final tamano = _tamanoEfectivo;
    if (tamano == null) return;
    final formula = await showDialog<FormulaColortrendModel>(context: context, builder: (context) => const SeleccionarFormulaDialog());
    if (formula == null || !mounted) return;
    final usos = onzasFormulaParaTamano(formula, tamano, 1);
    if (usos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Esta fórmula no tiene datos de colorante para ${etiquetaTamano(tamano)}.')));
      return;
    }
    setState(() => _calculando = true);
    final resultados = await CostoTinteService().calcular([for (final u in usos) UsoTinte(colorante: u.colorante, onzas: u.onzas)]);
    if (!mounted) return;
    setState(() {
      _tintes.addAll(resultados);
      _calculando = false;
    });
  }

  Future<void> _agregarTinteManual() async {
    // Reusa el mismo diálogo del carrito de venta (mismo motor de costeo,
    // misma UI, ver AgregarTinteManualDialog) -no hace nada de venta acá,
    // solo devuelve el cálculo.
    final resultado = await showDialog<ResultadoCostoTinte>(context: context, builder: (context) => const AgregarTinteManualDialog());
    if (resultado == null || !mounted) return;
    setState(() => _tintes.add(resultado));
  }

  void _limpiar() {
    setState(() {
      _productoBase = null;
      _tamanoManual = null;
      _tintes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final costoTinte = _tintes.fold<double>(0, (s, t) => s + t.costoTotal);
    final costoBase = _productoBase?.precioCompra ?? 0;
    final hayAlgoQueLimpiar = _productoBase != null || _tintes.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Producto base', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700))),
              if (hayAlgoQueLimpiar)
                TextButton.icon(
                  onPressed: _limpiar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF666A72), padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _elegirProductoBase,
            icon: const Icon(Icons.search, size: 16),
            label: Text(_productoBase?.nombre ?? 'Elegir producto base...', style: GoogleFonts.poppins(fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A1A),
              side: const BorderSide(color: Color(0xFFB6BCC7)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_productoBase != null && tamanoDesdeNombreProducto(_productoBase!.nombre) == null) ...[
            const SizedBox(height: 8),
            Text('No se pudo determinar el tamaño por el nombre -elegilo a mano:', style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB45309))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in TamanoFormula.values)
                  ChoiceChip(
                    label: Text(etiquetaTamano(t), style: GoogleFonts.poppins(fontSize: 11.5)),
                    selected: _tamanoManual == t,
                    onSelected: (_) => setState(() => _tamanoManual = t),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text('Tinte', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_tintes.isEmpty)
            Text('Sin tinte cargado todavía.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500))
          else
            for (final t in _tintes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Expanded(child: Text('COLORANTE ${t.colorante} · ${t.cuartos.toStringAsFixed(3)} ct', style: GoogleFonts.poppins(fontSize: 12))),
                      Text(t.resuelto ? formatearMoneda(t.costoTotal) : 'sin inventario', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: t.resuelto ? const Color(0xFF1E9E5A) : const Color(0xFFC62828))),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_calculando || _tamanoEfectivo == null) ? null : _buscarFormula,
                  icon: _calculando ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC62828))) : const Icon(Icons.menu_book_outlined, size: 16),
                  label: Text('Buscar fórmula', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFC62828)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _agregarTinteManual,
                  icon: const Icon(Icons.colorize, size: 16),
                  label: Text('Tinte manual', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
          if (_productoBase == null && _tamanoEfectivo == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Elegí un producto base primero para poder buscar una fórmula (el tamaño sale de ahí).', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
            ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          _filaCosto('Costo de tinte', costoTinte, const Color(0xFFC62828)),
          const SizedBox(height: 4),
          _filaCosto('Costo del producto base', costoBase, const Color(0xFF2B6CB0)),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          _filaCosto('Total combinado', costoTinte + costoBase, const Color(0xFF1A1A1A), grande: true),
        ],
      ),
    );
  }

  Widget _filaCosto(String etiqueta, double valor, Color color, {bool grande = false}) {
    return Row(
      children: [
        Expanded(child: Text(etiqueta, style: GoogleFonts.poppins(fontSize: grande ? 14 : 12.5, fontWeight: grande ? FontWeight.w700 : FontWeight.w500))),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: grande ? 18 : 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}
