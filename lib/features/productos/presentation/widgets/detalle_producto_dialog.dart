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

  const DetalleProductoDialog({
    super.key,
    required this.producto,
    required this.categoria,
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
        constraints: const BoxConstraints(maxHeight: 560),
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
                      'Existencia',
                      producto.stock.toStringAsFixed(
                        producto.stock == producto.stock.roundToDouble()
                            ? 0
                            : 2,
                      ),
                    ),
                    const Divider(height: 28),
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

  Widget _miniaturaProducto(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog(context: context, builder: (context) => ImagenZoomDialog(url: producto.imagenUrl)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ImagenProductoNetwork(url: producto.imagenUrl, width: 56, height: 56),
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
