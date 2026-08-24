import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/lote_costo_repository.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/data/tinte_lookup.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../ventas/data/costo_tinte_service.dart';
import '../../../ventas/presentation/widgets/agregar_tinte_manual_dialog.dart';
import '../../../ventas/presentation/widgets/buscar_producto_dialog.dart';
import '../../../ventas/presentation/widgets/campo_margen_precio_venta.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../data/formula_colortrend_model.dart';
import '../../data/formula_tamano_utils.dart';
import '../../providers/formulas_colortrend_provider.dart';
import '../widgets/seleccionar_formula_dialog.dart';

/// Herramienta de consulta de costo de un color preparado, SIN necesidad de
/// hacer una venta -pedido explícito del dueño-: pura lectura, no descuenta
/// stock ni escribe nada en Firestore. Tres modos:
/// - "Fórmula + producto base": elegir una fórmula real (o cargar tintes a
///   mano) + un producto base del inventario → tamaño implícito según el
///   nombre del producto (mismo criterio que Escenario A de la venta, ver
///   formula_tamano_utils.dart) → costo de tinte + costo del producto base
///   (su precioCompra vigente, no ligado a una venta real) + total + ¿a
///   cuánto venderlo? (margen/precio, ver CampoMargenPrecioVenta).
/// - "Solo tinte": "cuánto me cuesta tanto de tal tinte", sin fórmula ni
///   producto base -solo el motor de costeo (CostoTinteService) sobre un
///   tinte y una cantidad en onzas- + ¿a cuánto venderlo?
/// - "Promedios por base": costo promedio de tinte agrupado por el "base" de
///   la fórmula (Pastel/Deep/Accent/Tint Base) y por tamaño, para tener una
///   referencia rápida de precio base sin revisar cada una de las ~1500
///   fórmulas a mano (ver _ModoPromediosPorBase).
class ConsultarCostoScreen extends StatefulWidget {
  // true (default): pantalla completa con su propio Scaffold/SafeArea y
  // flecha de "atrás" -uso normal, empujada con Navigator desde dentro del
  // sistema (ver ColoresScreen/RegistrarVentaScreen). false: contenido
  // "pelado" (sin Scaffold ni flecha propia) para embeberse dentro de otra
  // pantalla que ya trae su propio Scaffold/encabezado -ver
  // ConsultarCostoKioskScreen, mismo criterio que BuscarFormulaScreen.esDialogo.
  final bool esDialogo;

  const ConsultarCostoScreen({super.key, this.esDialogo = true});

  @override
  State<ConsultarCostoScreen> createState() => _ConsultarCostoScreenState();
}

enum _ModoConsulta { formula, soloTinte, promedios }

class _ConsultarCostoScreenState extends State<ConsultarCostoScreen> {
  _ModoConsulta _modo = _ModoConsulta.formula;

  @override
  Widget build(BuildContext context) {
    final contenido = LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 720;
        return SingleChildScrollView(
          padding: EdgeInsets.all(esMovil ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.esDialogo)
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                    const SizedBox(width: 6),
                    Text('Consultar costo de un color', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                  ],
                )
              else
                Text('Consultar costo de un color', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Padding(
                padding: EdgeInsets.only(left: (widget.esDialogo && !esMovil) ? 54 : 0),
                child: Text(
                  'Solo consulta -no descuenta stock ni registra nada, es para saber cuánto cuesta antes de vender.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 16),
              _selectorModo(),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _modo == _ModoConsulta.promedios ? 720 : 560),
                // IndexedStack en vez de un switch que arma un widget nuevo
                // por modo: un switch destruye por completo el State del
                // modo que se deja (_productoBase, la lista de tintes
                // cargados, etc.) y arranca uno vacío al volver -pedido
                // explícito del dueño: cambiar de pestaña y volver tiene
                // que respetar lo que ya tenía puesto-. Los 3 modos quedan
                // montados todo el tiempo, solo se oculta el que no está
                // activo.
                child: IndexedStack(
                  index: _modo.index,
                  children: const [_ModoFormulaConProducto(), _ModoSoloTinte(), _ModoPromediosPorBase()],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!widget.esDialogo) return Container(color: const Color(0xFFF2F3F7), child: contenido);
    return Scaffold(backgroundColor: const Color(0xFFF2F3F7), body: SafeArea(child: contenido));
  }

  Widget _selectorModo() {
    Widget opcion(String texto, _ModoConsulta valor) {
      final activo = _modo == valor;
      return InkWell(
        onTap: () => setState(() => _modo = valor),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            opcion('Fórmula + producto base', _ModoConsulta.formula),
            opcion('Solo tinte', _ModoConsulta.soloTinte),
            opcion('Promedios por base', _ModoConsulta.promedios),
          ],
        ),
      ),
    );
  }
}

/// Modo "Solo tinte": una entintada personalizada armada a mano, SIN libro
/// de fórmulas ni producto base -pedido explícito del dueño: a veces se
/// mezcla a ojo "tanto Y de B, tanto Y de V, tanto Y de AXX" sin que
/// corresponda a ningún código del libro-, así que la lista de tintes es
/// growable (una entrada por cada tinte que se le fue echando), igual que
/// _ModoFormulaConProducto -mismo widget de agregar (AgregarTinteManualDialog),
/// misma fila por tinte con su "x" para quitar, mismo total sumado abajo-.
/// La única diferencia real con _ModoFormulaConProducto es que acá no hay
/// "Buscar fórmula" (no aplica, por definición de este modo) ni producto
/// base.
class _ModoSoloTinte extends StatefulWidget {
  const _ModoSoloTinte();

  @override
  State<_ModoSoloTinte> createState() => _ModoSoloTinteState();
}

class _ModoSoloTinteState extends State<_ModoSoloTinte> {
  final List<ResultadoCostoTinte> _tintes = [];
  // Ver el comentario equivalente en _ModoFormulaConProductoState._resetMargen:
  // fuerza a CampoMargenPrecioVenta a recrearse desde cero al "Limpiar".
  int _resetMargen = 0;

  Future<void> _agregarTinte() async {
    final resultado = await showDialog<ResultadoCostoTinte>(context: context, builder: (context) => const AgregarTinteManualDialog());
    if (resultado == null || !mounted) return;
    setState(() => _tintes.add(resultado));
  }

  void _quitarTinte(int index) {
    setState(() => _tintes.removeAt(index));
  }

  void _limpiar() {
    setState(() {
      _tintes.clear();
      _resetMargen++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final costoTotal = _tintes.fold<double>(0, (s, t) => s + t.costoTotal);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Entintada personalizada (sin código de fórmula)', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700))),
              if (_tintes.isNotEmpty)
                TextButton.icon(
                  onPressed: _limpiar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF666A72), padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('"Tanto Y de tal tinte, tanto Y de tal otro..." -uno o varios tintes mezclados a ojo, sin fórmula del libro.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          if (_tintes.isEmpty)
            Text('Sin tinte cargado todavía.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500))
          else
            for (var i = 0; i < _tintes.length; i++) _filaTinte(i, _tintes[i]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _agregarTinte,
            icon: const Icon(Icons.colorize, size: 16),
            label: Text('Agregar tinte', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_tintes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Costo total de la entintada', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700))),
                Text(formatearMoneda(costoTotal), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E9E5A))),
              ],
            ),
          ],
          if (costoTotal > 0) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('¿A cuánto puedo venderlo?', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            CampoMargenPrecioVenta(key: ValueKey('margen_$_resetMargen'), costoBase: costoTotal, onPrecioVentaCambiado: (_) {}),
          ],
        ],
      ),
    );
  }

  Widget _filaTinte(int index, ResultadoCostoTinte t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: t.resuelto ? const Color(0xFFF8F9FB) : const Color(0xFFFCE9E9), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('COLORANTE ${t.colorante} · ${t.cuartos.toStringAsFixed(3)} ct', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(
                    t.resuelto ? formatearMoneda(t.costoTotal) : 'sin producto en inventario',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: t.resuelto ? const Color(0xFF1E9E5A) : const Color(0xFFC62828)),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => _quitarTinte(index),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 16, color: Color(0xFFC62828))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modo "Fórmula + producto base": el modo completo del §8 original -elegir
/// fórmula real (o cargar tintes a mano) + producto base → costo de tinte,
/// costo del producto base, total combinado, y ¿a cuánto venderlo?.
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
  // Ver el comentario equivalente en _ModoSoloTinteState._resetCantidad:
  // fuerza a CampoMargenPrecioVenta a recrearse desde cero al "Limpiar".
  int _resetMargen = 0;

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
      _resetMargen++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final costoTinte = _tintes.fold<double>(0, (s, t) => s + t.costoTotal);
    final costoBase = _productoBase?.precioCompra ?? 0;
    final costoCombinado = costoTinte + costoBase;
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
          const SizedBox(height: 8),
          _filaCosto('Costo de tinte', costoTinte, const Color(0xFFC62828)),
          const SizedBox(height: 4),
          _filaCosto('Costo del producto base', costoBase, const Color(0xFF2B6CB0)),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          _filaCosto('Total combinado', costoCombinado, const Color(0xFF1A1A1A), grande: true),
          if (costoCombinado > 0) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('¿A cuánto puedo venderlo?', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            CampoMargenPrecioVenta(
              // El producto base cambia el precio de arranque del
              // calculador -no solo el "Limpiar"-, así que también entra en
              // la key para que se recree con el precio correcto al elegir
              // otro producto base.
              key: ValueKey('margen_${_resetMargen}_${_productoBase?.id}'),
              costoBase: costoCombinado,
              // Precio de venta YA registrado del producto base -pedido
              // explícito del dueño: el calculador arranca mostrando ESE
              // precio, no costo+0% de margen. ProductoModel.precioVenta se
              // guarda CON ISV (ver CarritoVentaNotifier.agregarProductoDirecto,
              // que lo usa directo como "precioConIsv"), pero acá se compara
              // contra un costo SIN ISV (costoCombinado, viene de
              // precioCompra/FIFO) -sin esta conversión el margen mostrado
              // salía inflado por el 15% de ISV mezclado adentro.
              precioVentaInicial: _productoBase != null && _productoBase!.precioVenta > 0 ? _productoBase!.precioVenta / 1.15 : null,
              onPrecioVentaCambiado: (_) {},
            ),
          ],
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

/// Modo "Promedios por base": pedido explícito del dueño -con ~1500
/// fórmulas del libro no es viable revisar el costo de tinte de cada una a
/// mano antes de fijar precios base. Acá se ve el costo PROMEDIO de tinte,
/// agrupado por el "base" de la fórmula (Pastel/Deep/Accent/Tint Base,
/// los 4 valores reales del dataset) y por tamaño (Cuarto/Galón/Quinto), con
/// cuántas fórmulas entraron en cada promedio -para poder juzgar qué tan
/// representativo es-.
///
/// Para no disparar miles de lecturas a Firestore (una consulta de costo
/// FIFO por colorante y por fórmula sería ~1500 fórmulas × varios
/// colorantes cada una), el costo actual por cuarto se trae UNA SOLA VEZ
/// para los ~12 productos de tinte reales (en paralelo, ver
/// _costoPorCuartoDeTintesReales), y con ese mapa ya en memoria se recorre
/// toda la lista de fórmulas (también ya cacheada en memoria por
/// formulasColortrendProvider, no se vuelve a leer el asset) sin ninguna
/// otra consulta a Firestore.
// Los 4 valores reales de FormulaColortrendModel.base en el dataset
// (confirmado contra assets/data/formulas_colortrend.json). Cualquier otro
// valor -no debería haber, pero por las dudas- cae en "Otra" en vez de
// perderse en silencio.
const _basesConocidas = ['Pastel Base', 'Deep Base', 'Accent Base', 'Tint Base'];
const _tamanosPromedios = [TamanoFormula.cuarto, TamanoFormula.galon, TamanoFormula.quinto];

typedef _PromedioBaseTamano = ({double promedio, int incluidas, int excluidas, double minimo, double maximo});

Future<Map<String, double>> _costoPorCuartoDeTintesReales(Ref ref) async {
  final productos = await ref.watch(productosStreamProvider.future);
  final tintes = productos.where((p) => p.idCategoria == idCategoriaTintes && p.estado).toList();
  final repo = LoteCostoRepository();
  final snapshots = await Future.wait(tintes.map((p) => repo.consultarLotes(p.id)));
  final mapa = <String, double>{};
  for (var i = 0; i < tintes.length; i++) {
    final producto = tintes[i];
    final estado = repo.inicializarEstado(snapshots[i]);
    // Costo de consumir 1 cuarto completo con el estado de lotes vigente
    // ahora mismo -un "costo unitario actual" representativo, mismo motor
    // FIFO que usa CostoTinteService en cualquier otro lado de la app.
    final costoPorCuarto = repo.consumir(estado, 1.0, costoFallback: producto.precioCompra);
    final colorante = normalizarColorante(producto.nombre.replaceFirst('COLORANTE ', ''));
    mapa[colorante] = costoPorCuarto;
  }
  return mapa;
}

/// Se calcula una sola vez por sesión de la app (provider normal, sin
/// autoDispose -mismo criterio que formulasColortrendProvider/
/// productosStreamProvider) y se reusa cada vez que se entra a este modo:
/// antes se recalculaba desde cero (12 consultas de lotes a Firestore +
/// recorrer ~1500 fórmulas) CADA VEZ que se montaba el widget -por ejemplo
/// al cambiar a otro modo y volver, porque el switch de _ConsultarCostoScreenState
/// no usa IndexedStack y por lo tanto destruye/recrea el State-, que era la
/// demora real que reportó el dueño ("a promedio por base le cuesta mucho
/// también cargar").
final _promediosPorBaseProvider = FutureProvider<Map<String, Map<TamanoFormula, _PromedioBaseTamano>>>((ref) async {
  // Límite de tiempo total: sin esto, una conexión lenta o cortada a mitad
  // de una consulta a Firestore (get() no tiene timeout propio) dejaba este
  // modo cargando para siempre, sin ningún mensaje de error ni forma de
  // reintentar -bug real reportado desde la versión web (Pages), donde la
  // red del que consulta puede ser bastante más lenta/inestable que en la
  // app de escritorio.
  return Future(() async {
    final costoPorCuarto = await _costoPorCuartoDeTintesReales(ref);
    final formulas = await ref.watch(formulasColortrendProvider.future);
    return _calcularPromediosDesde(costoPorCuarto, formulas);
  }).timeout(
    const Duration(seconds: 25),
    onTimeout: () => throw Exception('La consulta tardó demasiado -probá con mejor conexión, o entrá de nuevo a este modo para reintentar.'),
  );
});

Map<String, Map<TamanoFormula, _PromedioBaseTamano>> _calcularPromediosDesde(Map<String, double> costoPorCuarto, List<FormulaColortrendModel> formulas) {

  // sumas[base][tamano] = (sumaDeCosto, incluidas, excluidas, minimo, maximo)
  // -minimo/maximo dan el rango real de costo dentro de ese grupo, para que
  // se vea que un color puntual bien arriba o abajo del promedio no es un
  // error: el gasto de tinte varía mucho de un color a otro dentro de la
  // misma base.
  final sumas = <String, Map<TamanoFormula, (double, int, int, double, double)>>{
    for (final base in [..._basesConocidas, 'Otra']) base: {for (final t in _tamanosPromedios) t: (0.0, 0, 0, double.infinity, 0.0)},
  };

  for (final formula in formulas) {
    final base = _basesConocidas.contains(formula.base) ? formula.base : 'Otra';
    for (final tamano in _tamanosPromedios) {
      final usos = onzasFormulaParaTamano(formula, tamano, 1);
      final actual = sumas[base]![tamano]!;
      if (usos.isEmpty) {
        // Sin datos de colorante del libro para este tamaño -no cuenta ni
        // a favor ni en contra del promedio, solo se anota como excluida.
        sumas[base]![tamano] = (actual.$1, actual.$2, actual.$3 + 1, actual.$4, actual.$5);
        continue;
      }
      var costoFormula = 0.0;
      var completa = true;
      for (final u in usos) {
        final costo = costoPorCuarto[normalizarColorante(u.colorante)];
        if (costo == null) {
          // Un colorante de esta fórmula no tiene producto de tinte real
          // en inventario (o sin lotes con costo) -no se suma parcial: se
          // excluye la fórmula ENTERA de este tamaño para no subestimar el
          // promedio con un costo incompleto.
          completa = false;
          break;
        }
        costoFormula += (u.onzas / CostoTinteService.onzasPorCuarto) * costo;
      }
      sumas[base]![tamano] = completa
          ? (
              actual.$1 + costoFormula,
              actual.$2 + 1,
              actual.$3,
              costoFormula < actual.$4 ? costoFormula : actual.$4,
              costoFormula > actual.$5 ? costoFormula : actual.$5,
            )
          : (actual.$1, actual.$2, actual.$3 + 1, actual.$4, actual.$5);
    }
  }

  return {
    for (final entry in sumas.entries)
      entry.key: {
        for (final t in entry.value.entries)
          t.key: (
            promedio: t.value.$2 > 0 ? t.value.$1 / t.value.$2 : 0.0,
            incluidas: t.value.$2,
            excluidas: t.value.$3,
            minimo: t.value.$2 > 0 ? t.value.$4 : 0.0,
            maximo: t.value.$2 > 0 ? t.value.$5 : 0.0,
          ),
      },
  };
}

class _ModoPromediosPorBase extends ConsumerStatefulWidget {
  const _ModoPromediosPorBase();

  @override
  ConsumerState<_ModoPromediosPorBase> createState() => _ModoPromediosPorBaseState();
}

class _ModoPromediosPorBaseState extends ConsumerState<_ModoPromediosPorBase> {
  static const _tamanos = _tamanosPromedios;

  @override
  Widget build(BuildContext context) {
    final promedios = ref.watch(_promediosPorBaseProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Costo promedio de tinte por tipo de base y tamaño', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Promedio sobre todas las fórmulas del libro de ese tipo de base, con el costo FIFO vigente ahora mismo de cada tinte -para tener una referencia de precio base sin revisar cada fórmula una por una.',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (promedios.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No se pudo calcular: ${promedios.error}', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(_promediosPorBaseProvider),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text('Reintentar', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFC62828))),
                  ),
                ],
              ),
            )
          else if (promedios.value != null)
            _tabla(promedios.value!)
          else
            const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))),
        ],
      ),
    );
  }

  Widget _tabla(Map<String, Map<TamanoFormula, _PromedioBaseTamano>> datos) {
    final otraTieneAlgo = (datos['Otra']?.values.any((v) => v.incluidas > 0 || v.excluidas > 0)) ?? false;
    final bases = [..._basesConocidas, if (otraTieneAlgo) 'Otra'];
    // En móvil, una tabla de 4 columnas (Base + 3 tamaños, cada una con
    // monto+rango+cantidad de fórmulas) no entra sin scroll horizontal
    // incómodo -pedido explícito del dueño-: ahí se arma en cambio una
    // tarjeta por base, con los 3 tamaños apilados adentro.
    final esMovil = MediaQuery.sizeOf(context).width < 560;
    if (esMovil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final base in bases) _tarjetaBaseMovil(base, datos[base])],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: const Color(0xFFE0E2E8), borderRadius: BorderRadius.circular(8)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF2F3F7)),
            children: [
              _celdaEncabezado('Base'),
              for (final t in _tamanos) _celdaEncabezado(etiquetaTamano(t)),
            ],
          ),
          for (final base in bases)
            TableRow(
              children: [
                _celdaBase(base),
                for (final t in _tamanos) _celdaValor(datos[base]?[t]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tarjetaBaseMovil(String base, Map<TamanoFormula, _PromedioBaseTamano>? valores) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E2E8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(base, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final t in _tamanos) _filaValorMovil(etiquetaTamano(t), valores?[t]),
        ],
      ),
    );
  }

  Widget _filaValorMovil(String etiquetaTamano, _PromedioBaseTamano? valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(etiquetaTamano, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600))),
          Expanded(
            child: valor == null || valor.incluidas == 0
                ? Text('Sin datos', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatearMoneda(valor.promedio), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1E9E5A))),
                      Text(_detalleValor(valor), style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _celdaEncabezado(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _celdaBase(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _celdaValor(_PromedioBaseTamano? valor) {
    if (valor == null || valor.incluidas == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text('Sin datos', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatearMoneda(valor.promedio), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1E9E5A))),
          Text(_detalleValor(valor), style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // "Rango": muestra hasta dónde puede llegar un color puntual dentro de la
  // misma base/tamaño -pedido explícito del dueño, que vio un color bien
  // arriba del promedio y dudó si era un error. No lo es: el gasto de tinte
  // varía mucho de un color a otro, así que ver el máximo real (no solo el
  // promedio) da contexto de una.
  String _detalleValor(_PromedioBaseTamano valor) {
    final rango = 'rango ${formatearMoneda(valor.minimo)}-${formatearMoneda(valor.maximo)}';
    return valor.excluidas > 0 ? '${valor.incluidas} fórmulas, $rango (${valor.excluidas} excluidas)' : '${valor.incluidas} fórmulas, $rango';
  }
}
