import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/proveedor_model.dart';
import '../../providers/proveedores_provider.dart';

class ProveedorFormDialog extends ConsumerStatefulWidget {
  final ProveedorModel? proveedor;

  const ProveedorFormDialog({super.key, this.proveedor});

  @override
  ConsumerState<ProveedorFormDialog> createState() => _ProveedorFormDialogState();
}

class _ProveedorFormDialogState extends ConsumerState<ProveedorFormDialog> {
  final _rtnController = TextEditingController();
  final _razonSocialController = TextEditingController();
  final _correoController = TextEditingController();
  final _telefonoController = TextEditingController();
  bool _activo = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.proveedor;
    if (p != null) {
      _rtnController.text = p.rtn;
      _razonSocialController.text = p.razonSocial;
      _correoController.text = p.correo;
      _telefonoController.text = p.telefono;
      _activo = p.estado;
    }
  }

  @override
  void dispose() {
    _rtnController.dispose();
    _razonSocialController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final razonSocial = _razonSocialController.text.trim();
    if (razonSocial.isEmpty) {
      setState(() => _error = 'La razón social es obligatoria');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(proveedorRepositoryProvider);
      if (widget.proveedor == null) {
        await repo.crear(
          rtn: _rtnController.text.trim(),
          razonSocial: razonSocial,
          correo: _correoController.text.trim(),
          telefono: _telefonoController.text.trim(),
          estado: _activo,
        );
      } else {
        await repo.actualizar(
          id: widget.proveedor!.id,
          rtn: _rtnController.text.trim(),
          razonSocial: razonSocial,
          correo: _correoController.text.trim(),
          telefono: _telefonoController.text.trim(),
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
        title: Text('Eliminar proveedor', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este proveedor?', style: GoogleFonts.poppins(fontSize: 13)),
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
      await ref.read(proveedorRepositoryProvider).eliminar(widget.proveedor!.id);
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
    final editando = widget.proveedor != null;
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 640),
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
                    child: const Icon(Icons.local_shipping_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editando ? 'Editar Proveedor' : 'Nuevo Proveedor',
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
                    TextField(
                      controller: _rtnController,
                      autofocus: true,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('RTN (opcional)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _razonSocialController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Razón social'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _correoController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Correo electrónico (opcional)'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _telefonoController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('Teléfono (opcional)'),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
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
                            activeThumbColor: const Color(0xFF16A34A),
                            onChanged: (v) => setState(() => _activo = v),
                          ),
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
