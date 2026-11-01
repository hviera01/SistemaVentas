import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/color_import_service.dart';
import '../../providers/colores_provider.dart';
import '../../../../core/theme/app_colors.dart';

class ImportarColoresDialog extends ConsumerStatefulWidget {
  const ImportarColoresDialog({super.key});

  @override
  ConsumerState<ImportarColoresDialog> createState() => _ImportarColoresDialogState();
}

class _ImportarColoresDialogState extends ConsumerState<ImportarColoresDialog> {
  final _servicio = ColorImportService();

  String? _nombreArchivo;
  List<FilaImportacionColor>? _filas;
  bool _cargando = false;
  bool _importando = false;
  String? _error;
  int? _resultadoCreados;

  Future<void> _elegirArchivo() async {
    final resultado = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.first;
    final bytes = archivo.bytes;
    if (bytes == null) {
      setState(() => _error = 'No se pudo leer el archivo seleccionado');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _filas = null;
      _resultadoCreados = null;
      _nombreArchivo = archivo.name;
    });
    try {
      final filas = _servicio.leer(bytes);
      setState(() => _filas = filas);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo procesar el archivo: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _importar() async {
    final filas = _filas;
    if (filas == null || filas.isEmpty) return;
    setState(() {
      _importando = true;
      _error = null;
    });
    try {
      final creados = await ref.read(colorRepositoryProvider).importarColores(filas);
      ref.invalidate(coloresStreamProvider);
      if (mounted) setState(() => _resultadoCreados = creados);
    } catch (e) {
      setState(() => _error = 'No se pudo completar la importación: $e');
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;
    final anchoDialog = esMovil ? tamano.width - 32 : 720.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: tamano.height - 80),
        decoration: BoxDecoration(color: AppColors.superficie, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.upload_file_outlined, color: AppColors.rojo),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Importar Registro de Colores desde Excel', style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.texto)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _resultadoCreados != null ? _vistaResultado(_resultadoCreados!) : _vistaSeleccion(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
              child: _botones(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaSeleccion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Funciona con el libro histórico de colores y con el informe que exporta el sistema anterior (los encabezados pueden venir en cualquiera de los dos formatos). Cada fila del archivo se agrega como un registro nuevo; no reemplaza los que ya existen.',
          style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.gris600),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _cargando ? null : _elegirArchivo,
          icon: _cargando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.description_outlined, size: 18),
          label: Text(_cargando ? 'Leyendo...' : (_nombreArchivo == null ? 'Elegir archivo .xlsx' : 'Elegir otro archivo'), style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.texto, side: BorderSide(color: AppColors.borde), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        if (_nombreArchivo != null && !_cargando) ...[
          const SizedBox(height: 8),
          Text(_nombreArchivo!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.gris500)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.rojoSuave3, borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.rojo)),
          ),
        ],
        if (_filas != null) ...[
          const SizedBox(height: 18),
          _badge('${_filas!.length} registros listos para importar', const Color(0xFF16A34A)),
          const SizedBox(height: 14),
          Expanded(child: _tablaPrevia()),
        ],
      ],
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _tablaPrevia() {
    final filas = _filas!;
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.bordeSuave)),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: filas.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: AppColors.divisor),
        itemBuilder: (context, index) {
          final f = filas[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fila ${f.numeroFila} · ${f.cliente.isEmpty ? '(sin cliente)' : f.cliente}',
                        style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.texto),
                      ),
                      Text(
                        'Código: ${f.codigo.isEmpty ? '-' : f.codigo} · ${f.descripcion.isEmpty ? '(sin descripción)' : f.descripcion} · Fecha: ${f.fechaRegistro != null ? formatoFecha.format(f.fechaRegistro!) : '-'}',
                        style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.gris600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _vistaResultado(int creados) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text('Importación completada', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registros creados', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.gris700)),
              Text('$creados', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _botones() {
    if (_resultadoCreados != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text('Cerrar', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _importando ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.texto, side: BorderSide(color: AppColors.borde), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Cancelar', style: GoogleFonts.poppins(fontSize: 13.5)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: (_importando || _filas == null || _filas!.isEmpty) ? null : _importar,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _importando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Importar (${_filas?.length ?? 0})', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
