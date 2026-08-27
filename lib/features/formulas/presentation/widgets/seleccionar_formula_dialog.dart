import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/formula_colortrend_model.dart';
import '../../providers/formulas_colortrend_provider.dart';
import '../../../../core/utils/texto_utils.dart';

/// Diálogo compacto para elegir UNA fórmula real del libro Color Codex
/// (mismo buscador fuzzy que ya usa BuscarFormulaScreen, ver
/// texto_utils.coincideFuzzy), pensado para insertarse dentro de otro flujo
/// -Código Color de una línea de venta, o la herramienta de consulta de
/// costo- en vez de navegar a una pantalla completa. Devuelve la fórmula
/// elegida al tocarla, o null si se cierra sin elegir.
class SeleccionarFormulaDialog extends ConsumerStatefulWidget {
  const SeleccionarFormulaDialog({super.key});

  @override
  ConsumerState<SeleccionarFormulaDialog> createState() => _SeleccionarFormulaDialogState();
}

class _SeleccionarFormulaDialogState extends ConsumerState<SeleccionarFormulaDialog> {
  final _controller = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formulasAsync = ref.watch(formulasColortrendProvider);
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width < 460 ? tamano.width - 40 : 420.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: ancho,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Buscar fórmula', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Código, nombre o base del color del libro Color Codex.', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej. C-104',
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: const Color(0xFFF2F3F7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => _busqueda = v.trim()),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: formulasAsync.when(
                loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))),
                error: (e, st) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No se pudo cargar el libro de fórmulas: $e', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => ref.invalidate(formulasColortrendProvider),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text('Reintentar', style: GoogleFonts.poppins(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (formulas) {
                  if (_busqueda.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Escribí algo para buscar', style: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 12.5))),
                    );
                  }
                  final resultados = formulas.where((f) => coincideFuzzy(f.textoBusqueda, _busqueda)).toList()..sort((a, b) => a.codigo.compareTo(b.codigo));
                  if (resultados.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Sin resultados para "$_busqueda"', style: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 12.5))),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: resultados.length,
                    separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) {
                      final f = resultados[i];
                      return ListTile(
                        dense: true,
                        title: Text('${f.codigo}  ·  ${f.nombre}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        subtitle: Text('${f.base} · pág. ${f.pagina}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.pop<FormulaColortrendModel>(context, f),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
