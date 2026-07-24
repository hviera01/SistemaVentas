import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../productos/presentation/widgets/producto_form_dialog.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Buscador de productos para Compras: a diferencia del de Ventas no maneja
/// niveles de precio de venta, sino el costo de compra registrado en el
/// producto (que igual se puede editar después en la fila del carrito).
class BuscarProductoCompraDialog extends ConsumerStatefulWidget {
  const BuscarProductoCompraDialog({super.key});

  @override
  ConsumerState<BuscarProductoCompraDialog> createState() => _BuscarProductoCompraDialogState();
}

class _BuscarProductoCompraDialogState extends ConsumerState<BuscarProductoCompraDialog> {
  final _busquedaController = TextEditingController();
  final _focusNodeLista = FocusNode();
  // Sin `autofocus`: en Windows, pedir el foco durante el primer build (que
  // es lo que hace `autofocus`) compite con la animación de apertura de
  // esta pantalla y se pierde la primera tecla que se escribe. Pidiéndolo a
  // mano después del primer frame (mismo mecanismo que ya usa
  // registrar_venta_screen para este mismo problema) el foco queda firme
  // antes de que llegue cualquier tecla.
  final _focusBusqueda = FocusNode();
  String _busquedaAplicada = '';
  List<ProductoModel> _listaActual = [];
  String? _filaSeleccionada;

  // Cachea el resultado del filtro: sin esto, cada setState (por ejemplo,
  // solo resaltar una fila al hacer clic o mover la selección con las
  // flechas) volvía a recorrer todo el catálogo con coincideFuzzy dentro de
  // build(), aunque la búsqueda no hubiera cambiado. Eso era lo que se
  // sentía "pesado y lento" al seleccionar.
  List<ProductoModel>? _productosCacheados;
  String? _busquedaFiltroCacheada;

  // Una GlobalKey por fila visible (indexada por posición en _listaActual)
  // para poder pedirle a la lista que haga scroll hasta la fila resaltada al
  // navegar con las flechas del teclado, aunque haya quedado fuera de la
  // vista.
  final Map<int, GlobalKey> _clavesFila = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusBusqueda.requestFocus();
    });
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _focusNodeLista.dispose();
    _focusBusqueda.dispose();
    super.dispose();
  }

  List<ProductoModel> _filtrar(List<ProductoModel> productos) {
    if (identical(productos, _productosCacheados) && _busquedaFiltroCacheada == _busquedaAplicada) {
      return _listaActual;
    }
    _productosCacheados = productos;
    _busquedaFiltroCacheada = _busquedaAplicada;
    return productos.where((p) => p.estado && coincideFuzzy(p.textoBusqueda, _busquedaAplicada)).toList();
  }

  void _moverSeleccion(int delta) {
    if (_listaActual.isEmpty) return;
    final indiceActual = _filaSeleccionada == null ? -1 : _listaActual.indexWhere((p) => p.id == _filaSeleccionada);
    var nuevoIndice = indiceActual + delta;
    if (nuevoIndice < 0) nuevoIndice = 0;
    if (nuevoIndice >= _listaActual.length) nuevoIndice = _listaActual.length - 1;
    setState(() => _filaSeleccionada = _listaActual[nuevoIndice].id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _clavesFila[nuevoIndice]?.currentContext;
      if (contexto != null) Scrollable.ensureVisible(contexto, duration: const Duration(milliseconds: 120), alignment: 0.5);
    });
  }

  KeyEventResult _manejarTeclado(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moverSeleccion(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moverSeleccion(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _seleccionarAlPresionarEnter();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _tomarFocoLista() {
    if (!_focusNodeLista.hasFocus) _focusNodeLista.requestFocus();
  }

  void _confirmarSeleccion(ProductoModel producto) {
    Navigator.pop(context, producto);
  }

  void _seleccionarAlPresionarEnter() {
    if (_listaActual.isEmpty) return;
    final resaltado = _listaActual.where((p) => p.id == _filaSeleccionada).toList();
    _confirmarSeleccion(resaltado.isNotEmpty ? resaltado.first : _listaActual.first);
  }

  /// La búsqueda no filtra en vivo: solo se aplica al presionar Enter o
  /// tocar el botón de buscar. Si el texto tiene una sola coincidencia (por
  /// ejemplo, un código exacto leído con lector de código de barras) se
  /// agrega directo, sin necesidad de un segundo Enter para confirmar.
  void _buscar() {
    final texto = _busquedaController.text.trim();
    setState(() {
      _busquedaAplicada = texto;
      _filaSeleccionada = null;
      _clavesFila.clear();
    });
    if (texto.isEmpty) return;
    final productos = ref.read(productosStreamProvider).value ?? [];
    final coincidencias = productos.where((p) => p.estado && coincideFuzzy(p.textoBusqueda, texto)).toList();
    if (coincidencias.length == 1) {
      _confirmarSeleccion(coincidencias.first);
    }
  }

  Future<void> _crearProductoNuevo() async {
    final nuevo = await showDialog<ProductoModel>(context: context, builder: (context) => const ProductoFormDialog());
    if (nuevo == null || !mounted) return;
    _confirmarSeleccion(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productosStreamProvider);
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final categoriasLista = categoriasAsync.value ?? <dynamic>[];
    final mapaCategorias = {for (final c in categoriasLista) c.id as String: c.descripcion as String};

    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(esMovil ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Buscar Producto', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.only(left: esMovil ? 0 : 54),
                child: Text(
                  'Enter en el buscador busca · doble clic o Enter en la lista agrega el producto resaltado',
                  style: GoogleFonts.poppins(fontSize: esMovil ? 11.5 : 12.5, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: esMovil ? double.infinity : 400,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB6BCC7))),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _busquedaController,
                              focusNode: _focusBusqueda,
                              style: GoogleFonts.poppins(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Escribí y presioná Enter para buscar...',
                                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _buscar(),
                            ),
                          ),
                          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _buscar),
                        ],
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _crearProductoNuevo,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text('Producto Nuevo', style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFC62828)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFC7CBD3)),
                  ),
                  child: Focus(
                    focusNode: _focusNodeLista,
                    onKeyEvent: _manejarTeclado,
                    child: productosAsync.when(
                      data: (productos) {
                        if (_busquedaAplicada.isEmpty) {
                          _listaActual = [];
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('Escribí algo y presioná Enter para buscar', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                              ],
                            ),
                          );
                        }

                        final lista = _filtrar(productos);
                        _listaActual = lista;
                        if (lista.isEmpty) {
                          return Center(
                            child: Text('No se encontraron productos', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!esMovil) ...[
                              _encabezadoTabla(),
                              const SizedBox(height: 10),
                              Divider(height: 1, color: Colors.grey.shade300),
                            ],
                            Expanded(
                              child: ListView.separated(
                                itemCount: lista.length,
                                separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (context, i) {
                                  final p = lista[i];
                                  return esMovil ? _tarjetaMovil(i, p, mapaCategorias) : _filaTabla(i, p, mapaCategorias);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezadoTabla() {
    final estilo = GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 6, child: Text('Descripción', style: estilo)),
        Expanded(flex: 3, child: Text('Categoría', style: estilo)),
        Expanded(flex: 3, child: Text('Costo', textAlign: TextAlign.right, style: estilo)),
        Expanded(flex: 2, child: Text('Existencia', textAlign: TextAlign.center, style: estilo)),
      ],
    );
  }

  Widget _filaTabla(int indice, ProductoModel p, Map<String, String> mapaCategorias) {
    final seleccionada = _filaSeleccionada == p.id;
    return Material(
      key: _clavesFila.putIfAbsent(indice, () => GlobalKey()),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _tomarFocoLista();
          setState(() => _filaSeleccionada = p.id);
        },
        onDoubleTap: () => _confirmarSeleccion(p),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: seleccionada ? const Color(0xFFFBEAEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: seleccionada ? Border.all(color: const Color(0xFFC62828), width: 1.4) : Border.all(color: Colors.transparent, width: 1.4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 2, child: Text(p.codigo, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600))),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(p.nombre, softWrap: true, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(mapaCategorias[p.idCategoria] ?? '-', softWrap: true, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(formatearMoneda(p.precioCompra), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF2B6CB0))),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      p.stock.toStringAsFixed(p.stock == p.stock.roundToDouble() ? 0 : 2),
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E9E5A)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaMovil(int indice, ProductoModel p, Map<String, String> mapaCategorias) {
    final seleccionada = _filaSeleccionada == p.id;
    return Material(
      key: _clavesFila.putIfAbsent(indice, () => GlobalKey()),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _tomarFocoLista();
          setState(() => _filaSeleccionada = p.id);
        },
        onDoubleTap: () => _confirmarSeleccion(p),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: seleccionada ? const Color(0xFFFBEAEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: seleccionada ? Border.all(color: const Color(0xFFC62828), width: 1.4) : Border.all(color: Colors.transparent, width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombre, softWrap: true, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${p.codigo} · ${mapaCategorias[p.idCategoria] ?? '-'}', softWrap: true, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Existencia: ${p.stock.toStringAsFixed(p.stock == p.stock.roundToDouble() ? 0 : 2)}',
                      style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E9E5A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(formatearMoneda(p.precioCompra), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF2B6CB0))),
            ],
          ),
        ),
      ),
    );
  }
}
