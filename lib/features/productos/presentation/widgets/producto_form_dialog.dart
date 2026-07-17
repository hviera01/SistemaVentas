import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';

class ProductoFormDialog extends ConsumerStatefulWidget {
  final ProductoModel? producto;

  const ProductoFormDialog({super.key, this.producto});

  @override
  ConsumerState<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends ConsumerState<ProductoFormDialog> {
  final _codigoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _precioCompraController = TextEditingController(text: '0');
  final _precioVentaController = TextEditingController(text: '0');
  final _precioVenta2Controller = TextEditingController();
  final _precioVenta3Controller = TextEditingController();

  String? _idCategoria;
  bool _activo = true;
  bool _mostrarNivelesExtra = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    if (p != null) {
      _codigoController.text = p.codigo;
      _codigoBarrasController.text = p.codigoBarras;
      _nombreController.text = p.nombre;
      _descripcionController.text = p.descripcion;
      _stockController.text = p.stock.toString();
      _precioCompraController.text = p.precioCompra.toString();
      _precioVentaController.text = p.precioVenta.toString();
      if (p.precioVenta2 > 0) _precioVenta2Controller.text = p.precioVenta2.toString();
      if (p.precioVenta3 > 0) _precioVenta3Controller.text = p.precioVenta3.toString();
      _mostrarNivelesExtra = p.precioVenta2 > 0 || p.precioVenta3 > 0;
      _idCategoria = p.idCategoria;
      _activo = p.estado;
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _codigoBarrasController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _stockController.dispose();
    _precioCompraController.dispose();
    _precioVentaController.dispose();
    _precioVenta2Controller.dispose();
    _precioVenta3Controller.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) {
    return double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio');
      return;
    }
    if (_idCategoria == null) {
      setState(() => _error = 'Seleccioná una categoría');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(productoRepositoryProvider);
      if (widget.producto == null) {
        final creado = await repo.crear(
          codigo: _codigoController.text,
          codigoBarras: _codigoBarrasController.text,
          nombre: nombre,
          descripcion: _descripcionController.text,
          idCategoria: _idCategoria!,
          stock: _parseDouble(_stockController.text),
          precioCompra: _parseDouble(_precioCompraController.text),
          precioVenta: _parseDouble(_precioVentaController.text),
          precioVenta2: _parseDouble(_precioVenta2Controller.text),
          precioVenta3: _parseDouble(_precioVenta3Controller.text),
          estado: _activo,
        );
        if (mounted) Navigator.pop(context, creado);
        return;
      } else {
        await repo.actualizar(
          id: widget.producto!.id,
          codigo: _codigoController.text,
          codigoBarras: _codigoBarrasController.text,
          nombre: nombre,
          descripcion: _descripcionController.text,
          idCategoria: _idCategoria!,
          precioCompra: _parseDouble(_precioCompraController.text),
          precioVenta: _parseDouble(_precioVentaController.text),
          precioVenta2: _parseDouble(_precioVenta2Controller.text),
          precioVenta3: _parseDouble(_precioVenta3Controller.text),
          estado: _activo,
        );
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
        title: Text('Eliminar producto', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este producto?', style: GoogleFonts.poppins(fontSize: 13)),
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
      await ref.read(productoRepositoryProvider).eliminar(widget.producto!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF5F6FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.producto != null;
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 540;
    final anchoDialog = esMovil ? tamano.width - 48 : 480.0;

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
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editando ? 'Editar Producto' : 'Nuevo Producto',
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codigoController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Código (opcional)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _codigoBarrasController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Código de barras').copyWith(
                              suffixIcon: IconButton(
                                tooltip: 'Escanear',
                                icon: const Icon(Icons.qr_code_scanner, size: 20),
                                onPressed: () async {
                                  final codigo = await escanearCodigoBarras(context);
                                  if (codigo == null || codigo.isEmpty || !mounted) return;
                                  setState(() => _codigoBarrasController.text = codigo);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nombreController,
                      autofocus: true,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Nombre'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _descripcionController,
                      maxLines: 2,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Descripción (opcional)'),
                    ),
                    const SizedBox(height: 14),
                    categoriasAsync.when(
                      data: (categorias) {
                        return DropdownButtonFormField<String>(
                          value: _idCategoria,
                          decoration: _decoracion('Categoría'),
                          style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                          items: categorias.map((c) {
                            return DropdownMenuItem(value: c.id, child: Text(c.descripcion));
                          }).toList(),
                          onChanged: (v) => setState(() => _idCategoria = v),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, st) => Text('Error cargando categorías', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stockController,
                            enabled: !editando,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion(editando ? 'Existencia (ajustar abajo)' : 'Existencia inicial'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _precioCompraController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Precio Compra'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _precioVentaController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Precio Venta'),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _mostrarNivelesExtra = !_mostrarNivelesExtra),
                      child: Row(
                        children: [
                          Icon(_mostrarNivelesExtra ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 18, color: const Color(0xFFC62828)),
                          const SizedBox(width: 8),
                          Text('Niveles de precio adicionales', style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFFC62828), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (_mostrarNivelesExtra) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _precioVenta2Controller,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.poppins(fontSize: 14),
                              decoration: _decoracion('Precio Venta 2'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _precioVenta3Controller,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.poppins(fontSize: 14),
                              decoration: _decoracion('Precio Venta 3'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6FA),
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
                          Switch(value: _activo, activeColor: const Color(0xFF16A34A), onChanged: (v) => setState(() => _activo = v)),
                        ],
                      ),
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }
}