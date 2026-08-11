import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Selector de productos reusado por el formulario de promociones: con
/// [maxSeleccion] = 1 se comporta como selector único (producto base /
/// producto regalo); sin límite, como selector múltiple (porcentaje /
/// precio fijo).
class SeleccionarProductosDialog extends ConsumerStatefulWidget {
  final List<String> seleccionadosIniciales;
  final int? maxSeleccion;
  final String titulo;

  const SeleccionarProductosDialog({super.key, this.seleccionadosIniciales = const [], this.maxSeleccion, this.titulo = 'Seleccionar Productos'});

  @override
  ConsumerState<SeleccionarProductosDialog> createState() => _SeleccionarProductosDialogState();
}

class _SeleccionarProductosDialogState extends ConsumerState<SeleccionarProductosDialog> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  late Set<String> _seleccionados;

  @override
  void initState() {
    super.initState();
    _seleccionados = widget.seleccionadosIniciales.toSet();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _alternar(ProductoModel p) {
    setState(() {
      final esUnico = widget.maxSeleccion == 1;
      if (_seleccionados.contains(p.id)) {
        _seleccionados.remove(p.id);
      } else {
        if (esUnico) _seleccionados.clear();
        _seleccionados.add(p.id);
      }
    });
  }

  void _confirmar(List<ProductoModel> productos) {
    final elegidos = productos.where((p) => _seleccionados.contains(p.id)).toList();
    Navigator.pop(context, elegidos);
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productosStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final anchoDialog = tamano.width < 640 ? tamano.width - 24 : 560.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 40 : 600.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: productosAsync.when(
          data: (productos) {
            final activos = productos.where((p) => p.estado).toList();
            final filtrados = _busqueda.isEmpty ? activos : activos.where((p) => coincideFuzzy(p.textoBusqueda, _busqueda)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700))),
                    Text('${_seleccionados.length} seleccionado(s)', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _busquedaController,
                          style: GoogleFonts.poppins(fontSize: 13),
                          decoration: InputDecoration(hintText: 'Buscar producto...', border: InputBorder.none, isDense: true),
                          onChanged: (v) => setState(() => _busqueda = v.trim()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtrados.isEmpty
                      ? Center(child: Text('Sin productos', style: GoogleFonts.poppins(color: Colors.grey.shade500)))
                      : ListView.separated(
                          itemCount: filtrados.length,
                          separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final p = filtrados[i];
                            final marcado = _seleccionados.contains(p.id);
                            return CheckboxListTile(
                              value: marcado,
                              onChanged: (_) => _alternar(p),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text('${p.codigo} · ${formatearMoneda(p.precioVenta)}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                              activeColor: const Color(0xFFC62828),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _seleccionados.isEmpty ? null : () => _confirmar(activos),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Confirmar selección', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
          error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
        ),
      ),
    );
  }
}
