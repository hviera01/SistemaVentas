import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/negocio_provider.dart';

const _tamanoMaximoBytes = 700 * 1024;

class NegocioLogoPicker extends ConsumerStatefulWidget {
  final String titulo;
  final String base64Actual;
  final bool esColor;

  const NegocioLogoPicker({super.key, required this.titulo, required this.base64Actual, required this.esColor});

  @override
  ConsumerState<NegocioLogoPicker> createState() => _NegocioLogoPickerState();
}

class _NegocioLogoPickerState extends ConsumerState<NegocioLogoPicker> {
  bool _subiendo = false;

  Future<void> _subir() async {
    final resultado = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.first;
    final bytes = archivo.bytes;
    if (bytes == null) {
      _mostrarError('No se pudo leer el archivo seleccionado');
      return;
    }
    if (bytes.length > _tamanoMaximoBytes) {
      _mostrarError('La imagen pesa demasiado (máx. 700 KB). Elegí una más liviana.');
      return;
    }

    setState(() => _subiendo = true);
    try {
      final repo = ref.read(negocioRepositoryProvider);
      if (widget.esColor) {
        await repo.guardarLogoColor(bytes);
      } else {
        await repo.guardarLogoBn(bytes);
      }
    } catch (e) {
      _mostrarError('No se pudo guardar el logo');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EAF0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB6BCC7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _construirVistaPrevia(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 128,
          child: OutlinedButton.icon(
            onPressed: _subiendo ? null : _subir,
            icon: _subiendo
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC62828)))
                : const Icon(Icons.upload_outlined, size: 16),
            label: Text(_subiendo ? 'Guardando...' : 'Subir', style: GoogleFonts.poppins(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A1A),
              side: const BorderSide(color: Color(0xFFB6BCC7)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirVistaPrevia() {
    if (widget.base64Actual.isEmpty) {
      return Icon(Icons.image_outlined, size: 34, color: Colors.grey.shade400);
    }
    try {
      final bytes = base64Decode(widget.base64Actual);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image_outlined, size: 30, color: Colors.grey.shade400),
      );
    } catch (_) {
      return Icon(Icons.broken_image_outlined, size: 30, color: Colors.grey.shade400);
    }
  }
}
