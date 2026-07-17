import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/categoria_model.dart';
import '../../providers/categorias_provider.dart';

class CategoriaFormDialog extends ConsumerStatefulWidget {
  final CategoriaModel? categoria;

  const CategoriaFormDialog({super.key, this.categoria});

  @override
  ConsumerState<CategoriaFormDialog> createState() => _CategoriaFormDialogState();
}

class _CategoriaFormDialogState extends ConsumerState<CategoriaFormDialog> {
  final _descripcionController = TextEditingController();
  bool _activo = true;
  bool _controlaStock = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.categoria != null) {
      _descripcionController.text = widget.categoria!.descripcion;
      _activo = widget.categoria!.estado;
      _controlaStock = widget.categoria!.controlaStock;
    }
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionController.text.trim();
    if (descripcion.isEmpty) {
      setState(() => _error = 'La descripción es obligatoria');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(categoriaRepositoryProvider);
      if (widget.categoria == null) {
        await repo.crear(descripcion, _activo, controlaStock: _controlaStock);
      } else {
        await repo.actualizar(widget.categoria!.id, descripcion, _activo, controlaStock: _controlaStock);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar categoría', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar esta categoría?', style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardando = true);
    try {
      await ref.read(categoriaRepositoryProvider).eliminar(widget.categoria!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.categoria != null;
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.category_outlined, color: Color(0xFFC62828)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    editando ? 'Editar Categoría' : 'Nueva Categoría',
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _descripcionController,
              autofocus: true,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Descripción',
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text('Estado', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700)),
                  const Spacer(),
                  Text(
                    _activo ? 'Activo' : 'Inactivo',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _activo ? const Color(0xFF16A34A) : Colors.grey.shade500),
                  ),
                  Switch(
                    value: _activo,
                    activeColor: const Color(0xFF16A34A),
                    onChanged: (v) => setState(() => _activo = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Controla existencia',
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                  Switch(
                    value: _controlaStock,
                    activeColor: const Color(0xFF16A34A),
                    onChanged: (v) => setState(() => _controlaStock = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _controlaStock
                  ? 'Al vender, se descuenta del inventario y se avisa si no hay existencia suficiente.'
                  : 'No se descuenta del inventario ni se bloquea la venta por existencia 0. Usalo para servicios o productos preparados al momento (ej. pintura preparada).',
              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (editando)
                  IconButton(
                    onPressed: _guardando ? null : _eliminar,
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828).withOpacity(0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _guardando ? null : () => Navigator.pop(context),
                  child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                      : Text('Guardar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}