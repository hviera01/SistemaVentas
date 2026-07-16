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

/// Resultado de elegir un producto (y el nivel de precio con el que se va a
/// vender) desde el buscador.
class ProductoConPrecio {
  final ProductoModel producto;
  final double precio;
  final int nivelPrecio;

  ProductoConPrecio({required this.producto, required this.precio, required this.nivelPrecio});
}

class BuscarProductoDialog extends ConsumerStatefulWidget {
  const BuscarProductoDialog({super.key});

  @override
  ConsumerState<BuscarProductoDialog> createState() => _BuscarProductoDialogState();
}

class _BuscarProductoDialogState extends ConsumerState<BuscarProductoDialog> {
  final _busquedaController = TextEditingController();
  final _focusNodeLista = FocusNode();
  String _busquedaAplicada = '';
  List<ProductoModel> _listaActual = [];
  String? _filaSeleccionada;
  int _nivelActivo = 1;

  @override
  void dispose() {
    _busquedaController.dispose();
    _focusNodeLista.dispose();
    super.dispose();
  }

  void _moverSeleccion(int delta) {
    if (_listaActual.isEmpty) return;
    final indiceActual = _filaSeleccionada == null ? -1 : _listaActual.indexWhere((p) => p.id == _filaSeleccionada);
    var nuevoIndice = indiceActual + delta;
    if (nuevoIndice < 0) nuevoIndice = 0;
    if (nuevoIndice >= _listaActual.length) nuevoIndice = _listaActual.length - 1;
    setState(() => _filaSeleccionada = _listaActual[nuevoIndice].id);
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

  double? _precioNivel(ProductoModel p, int nivel) {
    final valor = switch (nivel) {
      2 => p.precioVenta2,
      3 => p.precioVenta3,
      _ => p.precioVenta,
    };
    return valor > 0 ? valor : null;
  }

  /// Precio con el que se agrega el producto: el nivel activo elegido en el
  /// selector de arriba, o el primero disponible si ese nivel no está
  /// configurado para este producto en particular.
  ({double precio, int nivel})? _precioActivo(ProductoModel p) {
    final directo = _precioNivel(p, _nivelActivo);
    if (directo != null) return (precio: directo, nivel: _nivelActivo);
    for (final nivel in [1, 2, 3]) {
      final precio = _precioNivel(p, nivel);
      if (precio != null) return (precio: precio, nivel: nivel);
    }
    return null;
  }

  void _confirmarSeleccion(ProductoModel producto) {
    final precio = _precioActivo(producto);
    if (precio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este producto no tiene un precio configurado')),
      );
      return;
    }
    Navigator.pop(context, ProductoConPrecio(producto: producto, precio: precio.precio, nivelPrecio: precio.nivel));
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
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCDFE6))),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _busquedaController,
                              autofocus: true,
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
                  _selectorNivelPrecio(),
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
                    border: Border.all(color: const Color(0xFFE5E7EC)),
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

                      final lista = productos.where((p) => p.estado && coincideFuzzy(p.textoBusqueda, _busquedaAplicada)).toList();
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
                                return esMovil ? _tarjetaMovil(p, mapaCategorias) : _filaTabla(p, mapaCategorias);
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

  Widget _selectorNivelPrecio() {
    Widget opcion(String texto, int nivel) {
      final activo = _nivelActivo == nivel;
      return InkWell(
        onTap: () => setState(() => _nivelActivo = nivel),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: activo ? const Color(0xFFC62828) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            texto,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72)),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCDFE6))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion('Precio 1', 1),
          opcion('Precio 2', 2),
          opcion('Precio 3', 3),
        ],
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
        Expanded(flex: 3, child: Text('Precio', textAlign: TextAlign.right, style: estilo)),
        Expanded(flex: 2, child: Text('Existencia', textAlign: TextAlign.center, style: estilo)),
      ],
    );
  }

  Widget _celdaPrecio(ProductoModel p) {
    final precio = _precioActivo(p);
    if (precio == null) {
      return Text('—', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatearMoneda(precio.precio), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF2B6CB0))),
        if (precio.nivel != _nivelActivo) Text('Nivel ${precio.nivel}', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _filaTabla(ProductoModel p, Map<String, String> mapaCategorias) {
    final bajoStock = p.stock <= 0;
    final seleccionada = _filaSeleccionada == p.id;
    return Material(
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
                child: Align(alignment: Alignment.centerRight, child: _celdaPrecio(p)),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(color: bajoStock ? const Color(0xFFFCE4E4) : const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      p.stock.toStringAsFixed(p.stock == p.stock.roundToDouble() ? 0 : 2),
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: bajoStock ? const Color(0xFFC62828) : const Color(0xFF1E9E5A)),
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

  Widget _tarjetaMovil(ProductoModel p, Map<String, String> mapaCategorias) {
    final bajoStock = p.stock <= 0;
    final seleccionada = _filaSeleccionada == p.id;
    return Material(
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
                    decoration: BoxDecoration(color: bajoStock ? const Color(0xFFFCE4E4) : const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Existencia: ${p.stock.toStringAsFixed(p.stock == p.stock.roundToDouble() ? 0 : 2)}',
                      style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: bajoStock ? const Color(0xFFC62828) : const Color(0xFF1E9E5A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _celdaPrecio(p),
            ],
          ),
        ),
      ),
    );
  }
}
