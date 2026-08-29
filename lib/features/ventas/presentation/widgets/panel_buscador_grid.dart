import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/imagen_producto_network.dart';
import 'buscar_producto_dialog.dart' show ProductoConPrecio;

/// Buscador de producto embebido (Vista "dividida" de Registrar Venta,
/// pedido explícito del dueño) — a diferencia de BuscarProductoDialog (una
/// ruta modal a pantalla completa), este vive incrustado a un costado de la
/// pantalla, con los resultados como tarjetas con foto en vez de una tabla
/// de texto. Reusa la misma búsqueda difusa (`coincideFuzzy`/
/// `textoBusqueda`) que el buscador modal, para no tener dos criterios de
/// "qué es una coincidencia" en la app.
class PanelBuscadorGrid extends ConsumerStatefulWidget {
  final void Function(ProductoConPrecio) onProductoElegido;

  const PanelBuscadorGrid({super.key, required this.onProductoElegido});

  @override
  ConsumerState<PanelBuscadorGrid> createState() => _PanelBuscadorGridState();
}

class _PanelBuscadorGridState extends ConsumerState<PanelBuscadorGrid> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  String? _seleccionadoId;

  // Mismo arreglo que Inventario/BuscarProductoDialog (ver
  // InventarioScreen._tocarFila): un solo `onTap` con doble-toque detectado
  // a mano, para que el primer toque (seleccionar) responda al instante en
  // vez de esperar la ventana de doble-tap de Flutter.
  static const _ventanaDobleTap = Duration(milliseconds: 300);
  DateTime? _ultimoTapEn;
  String? _ultimoTapId;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  double? _precioNivel1(ProductoModel p) =>
      p.precioVenta > 0 ? p.precioVenta : null;

  void _tocarTarjeta(ProductoModel p) {
    final ahora = DateTime.now();
    final esDobleTap =
        _ultimoTapId == p.id &&
        _ultimoTapEn != null &&
        ahora.difference(_ultimoTapEn!) < _ventanaDobleTap;
    _ultimoTapEn = esDobleTap ? null : ahora;
    _ultimoTapId = p.id;

    setState(() => _seleccionadoId = p.id);
    if (!esDobleTap) return;
    final precio = _precioNivel1(p);
    if (precio == null) return;
    widget.onProductoElegido(
      ProductoConPrecio(producto: p, precio: precio, nivelPrecio: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productosStreamProvider);
    final productos = productosAsync.value ?? const <ProductoModel>[];
    final consulta = _busqueda.trim();
    final lista = consulta.isEmpty
        ? const <ProductoModel>[]
        : (productos
              .where(
                (p) => p.estado && coincideFuzzy(p.textoBusqueda, consulta),
              )
              .toList()
            ..sort((a, b) => a.nombre.compareTo(b.nombre)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _busquedaController,
            autofocus: true,
            style: GoogleFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Buscar producto por nombre o código...',
              hintStyle: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFE8EAF0),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
        ),
        Expanded(
          child: consulta.isEmpty
              ? Center(
                  child: Text(
                    'Escribí para buscar un producto',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                )
              : lista.isEmpty
              ? Center(
                  child: Text(
                    'Sin resultados para "$consulta"',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                )
              : GridView.builder(
                  // MaxCrossAxisExtent (no un conteo fijo de columnas): la
                  // cantidad de columnas se ajusta sola al ancho
                  // disponible, así no hay overflow ni tarjetas
                  // apretadas sin importar si el panel mide 300px
                  // (celular) o 900px (mitad de pantalla ancha).
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 165,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: lista.length,
                  itemBuilder: (context, index) =>
                      _tarjetaProducto(lista[index]),
                ),
        ),
      ],
    );
  }

  Widget _tarjetaProducto(ProductoModel p) {
    final seleccionada = _seleccionadoId == p.id;
    final precio = _precioNivel1(p);
    final bajoStock = p.stock <= 0 && !p.esCombo;
    return InkWell(
      onTap: () => _tocarTarjeta(p),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: seleccionada ? const Color(0xFFFBEAEA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionada
                ? const Color(0xFFC62828)
                : const Color(0xFFE0E2E8),
            width: seleccionada ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: p.imagenUrl.isEmpty
                  ? Container(
                      color: const Color(0xFFF3F4F6),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey.shade400,
                        size: 32,
                      ),
                    )
                  : ImagenProductoNetwork(url: p.imagenUrl, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        precio == null ? 'Sin precio' : formatearMoneda(precio),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC62828),
                        ),
                      ),
                      if (bajoStock)
                        const Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Color(0xFFC62828),
                        )
                      else if (!p.esCombo)
                        Text(
                          p.stock.toStringAsFixed(
                            p.stock == p.stock.roundToDouble() ? 0 : 2,
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
