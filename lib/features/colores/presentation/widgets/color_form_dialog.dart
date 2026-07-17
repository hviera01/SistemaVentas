import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/color_model.dart';
import '../../providers/colores_provider.dart';

class ColorFormDialog extends ConsumerStatefulWidget {
  final ColorModel? color;

  const ColorFormDialog({super.key, this.color});

  @override
  ConsumerState<ColorFormDialog> createState() => _ColorFormDialogState();
}

class _ColorFormDialogState extends ConsumerState<ColorFormDialog> {
  final _codigoController = TextEditingController();
  final _clienteController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _paginaController = TextEditingController();
  final _observacionesController = TextEditingController();

  DateTime? _fechaRegistro;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.color;
    if (c != null) {
      _codigoController.text = c.codigo;
      _clienteController.text = c.cliente;
      _descripcionController.text = c.descripcion;
      _ubicacionController.text = c.ubicacionFisica;
      _paginaController.text = c.pagina;
      _observacionesController.text = c.observaciones;
      _fechaRegistro = c.fechaRegistro;
    } else {
      _fechaRegistro = DateTime.now();
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _clienteController.dispose();
    _descripcionController.dispose();
    _ubicacionController.dispose();
    _paginaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaRegistro ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() => _fechaRegistro = fecha);
  }

  Future<void> _guardar() async {
    final cliente = _clienteController.text.trim();
    if (cliente.isEmpty) {
      setState(() => _error = 'El cliente es obligatorio');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(colorRepositoryProvider);
      if (widget.color == null) {
        await repo.crear(
          codigo: _codigoController.text.trim(),
          cliente: cliente,
          descripcion: _descripcionController.text.trim(),
          ubicacionFisica: _ubicacionController.text.trim(),
          pagina: _paginaController.text.trim(),
          fechaRegistro: _fechaRegistro,
          observaciones: _observacionesController.text.trim(),
        );
      } else {
        await repo.actualizar(
          id: widget.color!.id,
          codigo: _codigoController.text.trim(),
          cliente: cliente,
          descripcion: _descripcionController.text.trim(),
          ubicacionFisica: _ubicacionController.text.trim(),
          pagina: _paginaController.text.trim(),
          fechaRegistro: _fechaRegistro,
          observaciones: _observacionesController.text.trim(),
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
        title: Text('Eliminar registro', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este registro de color?', style: GoogleFonts.poppins(fontSize: 13)),
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
      await ref.read(colorRepositoryProvider).eliminar(widget.color!.id);
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
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.color != null;
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 540;
    final anchoDialog = esMovil ? tamano.width - 48 : 480.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
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
                    decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.palette_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editando ? 'Editar Color' : 'Nuevo Color',
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
                            autofocus: true,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Código'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _clienteController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Cliente'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _descripcionController,
                      maxLines: 2,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Descripción'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ubicacionController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Ubicación física'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _paginaController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Página'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Fecha de registro', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _fechaRegistro != null ? formatoFecha.format(_fechaRegistro!) : 'Sin definir',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _observacionesController,
                      maxLines: 3,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Observaciones'),
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
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
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
