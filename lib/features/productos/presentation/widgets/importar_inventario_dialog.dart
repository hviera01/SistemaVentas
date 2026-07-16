import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_import_service.dart';
import '../../data/producto_repository.dart';
import '../../providers/productos_provider.dart';

class ImportarInventarioDialog extends ConsumerStatefulWidget {
  const ImportarInventarioDialog({super.key});

  @override
  ConsumerState<ImportarInventarioDialog> createState() => _ImportarInventarioDialogState();
}

class _ImportarInventarioDialogState extends ConsumerState<ImportarInventarioDialog> {
  final _servicio = ProductoImportService();

  String? _nombreArchivo;
  List<FilaImportacionProducto>? _filas;
  bool _cargando = false;
  bool _importando = false;
  String? _error;
  ResumenImportacionProductos? _resumen;

  List<FilaImportacionProducto> get _validas => _filas?.where((f) => f.valido).toList() ?? [];
  List<FilaImportacionProducto> get _conError => _filas?.where((f) => !f.valido).toList() ?? [];

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
      _resumen = null;
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
    final validas = _validas;
    if (validas.isEmpty) return;
    setState(() {
      _importando = true;
      _error = null;
    });
    try {
      final resumen = await ref.read(productoRepositoryProvider).importarProductos(validas);
      ref.invalidate(productosStreamProvider);
      if (mounted) setState(() => _resumen = resumen);
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
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
                    child: const Icon(Icons.upload_file_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Importar Inventario desde Excel', style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _resumen != null ? _vistaResultado(_resumen!) : _vistaSeleccion(),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'El archivo debe tener una fila de encabezado con columnas: Código, Nombre, Descripción, Categoría, Stock (o Existencia), Precio Venta, Precio Compra y Estado. El código y la categoría emparejan con lo que ya existe; si una categoría no existe, se crea sola.',
          style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _cargando ? null : _elegirArchivo,
          icon: _cargando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.description_outlined, size: 18),
          label: Text(_cargando ? 'Leyendo...' : (_nombreArchivo == null ? 'Elegir archivo .xlsx' : 'Elegir otro archivo'), style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        if (_nombreArchivo != null && !_cargando) ...[
          const SizedBox(height: 8),
          Text(_nombreArchivo!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFCE9E9), borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFFC62828))),
          ),
        ],
        if (_filas != null) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge('${_validas.length} listas para importar', const Color(0xFF16A34A)),
              if (_conError.isNotEmpty) _badge('${_conError.length} con error (se omiten)', const Color(0xFFC62828)),
            ],
          ),
          const SizedBox(height: 14),
          _tablaPrevia(),
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
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EC))),
      child: SingleChildScrollView(
        child: Column(
          children: filas.map((f) {
            final color = f.valido ? const Color(0xFF1A1A1A) : const Color(0xFFC62828);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.valido ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fila ${f.numeroFila} · ${f.nombre.isEmpty ? '(sin nombre)' : f.nombre}',
                          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
                        ),
                        Text(
                          f.valido
                              ? 'Código: ${f.codigo.isEmpty ? '(auto)' : f.codigo} · Categoría: ${f.categoria} · Stock: ${f.stock} · Venta: ${f.precioVenta} · Compra: ${f.precioCompra}'
                              : f.error!,
                          style: GoogleFonts.poppins(fontSize: 11.5, color: f.valido ? Colors.grey.shade600 : const Color(0xFFC62828)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _vistaResultado(ResumenImportacionProductos resumen) {
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
        _filaResultado('Productos creados', resumen.creados),
        _filaResultado('Productos actualizados', resumen.actualizados),
        _filaResultado('Categorías nuevas creadas', resumen.categoriasCreadas),
      ],
    );
  }

  Widget _filaResultado(String etiqueta, int valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700)),
          Text('$valor', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _botones() {
    if (_resumen != null) {
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
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFDCDFE6)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Cancelar', style: GoogleFonts.poppins(fontSize: 13.5)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: (_importando || _validas.isEmpty) ? null : _importar,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _importando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Importar (${_validas.length})', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
