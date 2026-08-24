import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';

/// Lo que devuelve [ExportarInventarioOpcionesDialog] al confirmar: la
/// lista final de productos a incluir (subconjunto de los que se le pasó,
/// según lo que el usuario desmarcó) y el set de columnas elegidas.
class ExportarInventarioOpciones {
  final List<ProductoModel> productos;
  final Set<String> columnas;
  const ExportarInventarioOpciones({required this.productos, required this.columnas});
}

/// Columnas disponibles para Excel/PDF de Inventario -mismas claves que
/// espera ProductoExportService.generarExcel/generarPdfInventario. El orden
/// acá define el orden de columnas en el archivo final.
const columnasInventarioDisponibles = [
  ('codigo', 'Código'),
  ('codigoBarras', 'Código de barras'),
  ('nombre', 'Nombre'),
  ('descripcion', 'Descripción'),
  ('categoria', 'Categoría'),
  ('existencia', 'Existencia'),
  ('precioVenta', 'Precio de Venta'),
  ('precioCompra', 'Precio de Compra'),
  ('estado', 'Estado'),
];

/// Mismas columnas que ya traía el export antes de que existiera esta
/// opción -para que, si el usuario no toca nada, el archivo salga igual
/// que siempre.
const columnasInventarioPorDefecto = {'codigo', 'nombre', 'descripcion', 'categoria', 'existencia', 'precioVenta', 'precioCompra', 'estado'};

/// Antes de exportar a Excel/PDF, deja elegir CUÁLES de los productos ya
/// filtrados en pantalla van al archivo (checklist, todos marcados por
/// defecto -pedido explícito del dueño: "que pueda seleccionar qué
/// productos quiero que vayan") y qué columnas incluir. Devuelve null si
/// se cancela.
class ExportarInventarioOpcionesDialog extends StatefulWidget {
  final List<ProductoModel> productos;
  final Map<String, String> mapaCategorias;
  final String titulo;

  const ExportarInventarioOpcionesDialog({super.key, required this.productos, required this.mapaCategorias, required this.titulo});

  @override
  State<ExportarInventarioOpcionesDialog> createState() => _ExportarInventarioOpcionesDialogState();
}

class _ExportarInventarioOpcionesDialogState extends State<ExportarInventarioOpcionesDialog> {
  late Set<String> _productosSeleccionados;
  final Set<String> _columnasSeleccionadas = {...columnasInventarioPorDefecto};

  @override
  void initState() {
    super.initState();
    _productosSeleccionados = widget.productos.map((p) => p.id).toSet();
  }

  bool get _todosMarcados => _productosSeleccionados.length == widget.productos.length;

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 520;
    final anchoDialog = esMovil ? tamano.width - 32 : 480.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Elegí qué columnas y qué productos incluir', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            Text('Columnas', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (key, etiqueta) in columnasInventarioDisponibles)
                  FilterChip(
                    label: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 12)),
                    selected: _columnasSeleccionadas.contains(key),
                    selectedColor: const Color(0xFFF8D7D7),
                    checkmarkColor: const Color(0xFFC62828),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _columnasSeleccionadas.add(key);
                        } else {
                          _columnasSeleccionadas.remove(key);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Productos', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('(${_productosSeleccionados.length} de ${widget.productos.length})', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _productosSeleccionados = _todosMarcados ? {} : widget.productos.map((p) => p.id).toSet();
                  }),
                  child: Text(_todosMarcados ? 'Ninguno' : 'Todos', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFC62828))),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E2E8)), borderRadius: BorderRadius.circular(10)),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.productos.length,
                  itemBuilder: (context, i) {
                    final p = widget.productos[i];
                    return CheckboxListTile(
                      value: _productosSeleccionados.contains(p.id),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFFC62828),
                      title: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${p.codigo} · ${widget.mapaCategorias[p.idCategoria] ?? '-'}', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _productosSeleccionados.add(p.id);
                          } else {
                            _productosSeleccionados.remove(p.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _productosSeleccionados.isEmpty || _columnasSeleccionadas.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          ExportarInventarioOpciones(
                            productos: widget.productos.where((p) => _productosSeleccionados.contains(p.id)).toList(),
                            columnas: _columnasSeleccionadas,
                          ),
                        ),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Exportar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
