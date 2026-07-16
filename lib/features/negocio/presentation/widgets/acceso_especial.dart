import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/negocio_repository.dart';
import '../../providers/negocio_provider.dart';

/// Si el permiso [permisoKey] está activado y hay una clave especial configurada,
/// pide la clave antes de continuar. Si no está activado (o no hay clave configurada),
/// retorna true de inmediato sin mostrar nada.
Future<bool> verificarAccesoEspecial(BuildContext context, WidgetRef ref, String permisoKey) async {
  final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
  if (!negocio.tieneClaveEspecial || !negocio.tienePermiso(permisoKey)) {
    return true;
  }
  if (!context.mounted) return false;
  final repo = ref.read(negocioRepositoryProvider);
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ClaveEspecialDialog(hashEsperado: negocio.claveEspecialHash, repo: repo),
  );
  return ok ?? false;
}

class _ClaveEspecialDialog extends StatefulWidget {
  final String hashEsperado;
  final NegocioRepository repo;

  const _ClaveEspecialDialog({required this.hashEsperado, required this.repo});

  @override
  State<_ClaveEspecialDialog> createState() => _ClaveEspecialDialogState();
}

class _ClaveEspecialDialogState extends State<_ClaveEspecialDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final clave = _controller.text;
    if (clave.isEmpty) {
      setState(() => _error = 'Ingresá la clave');
      return;
    }
    final valido = widget.repo.hashClave(clave) == widget.hashEsperado;
    if (!valido) {
      setState(() {
        _error = 'Clave incorrecta';
        _controller.clear();
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: esMovil ? tamano.width - 48 : 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFBEAEA), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.lock_outline, color: Color(0xFFC62828), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Acceso especial requerido', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Esta acción está protegida. Ingresá la clave especial para continuar.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => _confirmar(),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Clave especial',
                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                errorText: _error,
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Cancelar', style: GoogleFonts.poppins(fontSize: 13.5)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirmar,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Confirmar', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
