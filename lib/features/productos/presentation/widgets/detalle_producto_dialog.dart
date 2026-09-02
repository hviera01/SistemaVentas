import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/imagen_zoom_dialog.dart';
import '../../../../core/widgets/imagen_producto_network.dart';

/// Card de solo lectura con toda la info de un producto, para consultar
/// rápido sin editar nada. Se abre con doble toque/doble clic sobre un
/// producto en Inventario (ver InventarioScreen) y se cierra con la X -para
/// modificar algo sigue estando "Editar producto" en el menú de acciones de
/// la fila-.
class DetalleProductoDialog extends StatelessWidget {
  final ProductoModel producto;
  final String categoria;
  // Solo hace falta cuando producto.esCombo: para resolver el nombre y el
  // stock actual de cada componente de la receta (que solo guarda
  // id+cantidad, ver ComponenteProductoModel).
  final Map<String, ProductoModel>? mapaProductos;

  const DetalleProductoDialog({
    super.key,
    required this.producto,
    required this.categoria,
    this.mapaProductos,
  });

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 540;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (producto.imagenUrl.isNotEmpty) ...[
                    _miniaturaProducto(context),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Text(
                      producto.nombre,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (producto.descripcion.isNotEmpty) ...[
                      Text(
                        producto.descripcion,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _fila(
                      'Código',
                      producto.codigo.isEmpty ? '-' : producto.codigo,
                    ),
                    _fila(
                      'Código de barras',
                      producto.codigoBarras.isEmpty
                          ? '-'
                          : producto.codigoBarras,
                    ),
                    _fila('Categoría', categoria),
                    _fila(
                      producto.esCombo
                          ? 'Existencia (calculada)'
                          : 'Existencia',
                      _formatearCantidad(_existenciaMostrada),
                    ),
                    const Divider(height: 28),
                    if (producto.esCombo) ...[
                      _seccionComponentes(),
                      const Divider(height: 28),
                    ],
                    _fila(
                      'Precio venta',
                      formatearMoneda(producto.precioVenta),
                    ),
                    if (producto.precioVenta2 > 0)
                      _fila(
                        'Precio venta 2',
                        formatearMoneda(producto.precioVenta2),
                      ),
                    if (producto.precioVenta3 > 0)
                      _fila(
                        'Precio venta 3',
                        formatearMoneda(producto.precioVenta3),
                      ),
                    _fila(
                      'Precio compra',
                      formatearMoneda(producto.precioCompra),
                    ),
                    const Divider(height: 28),
                    _fila('Estado', producto.estado ? 'Activo' : 'Inactivo'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _existenciaMostrada => producto.esCombo
      ? producto.stockDisponibleCombo(mapaProductos ?? const {})
      : producto.stock;

  String _formatearCantidad(double c) =>
      c.toStringAsFixed(c == c.roundToDouble() ? 0 : 2);

  Widget _seccionComponentes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compuesto por',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        ...producto.componentes.map((c) {
          final productoComponente = mapaProductos?[c.idProducto];
          final nombre =
              productoComponente?.nombre ?? '(producto ya no existe)';
          final stockComponente = productoComponente?.stock;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nombre,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Text(
                  'x${_formatearCantidad(c.cantidad)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFC62828),
                  ),
                ),
                if (stockComponente != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(hay ${_formatearCantidad(stockComponente)})',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _miniaturaProducto(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog(
        useRootNavigator: false,
        context: context,
        builder: (context) => ImagenZoomDialog(url: producto.imagenUrl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ImagenProductoNetwork(
          url: producto.imagenUrl,
          width: 56,
          height: 56,
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              etiqueta,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
