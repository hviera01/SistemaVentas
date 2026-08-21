import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/formula_colortrend_model.dart';
import '../../providers/formulas_colortrend_provider.dart';
import '../widgets/formula_detalle_card.dart';
import '../../../../core/utils/texto_utils.dart';

/// Buscador de fórmulas del libro físico "Color Codex Formulas" (Colortrend):
/// por código, nombre o base. Se puede abrir embebido desde Registro de
/// Colores (botón "Buscar Fórmula") o desde la app de consulta rápida sin
/// login (ver FormulasKioskScreen) -por eso no depende de nada de sesión ni
/// de Firestore, todo sale del asset local (ver formulas_colortrend_provider).
///
/// La búsqueda solo se ejecuta con Enter o el botón "Buscar" -no en cada
/// tecla-. Tocar un resultado muestra su ficha ahí mismo (a la par de la
/// lista en escritorio, debajo en celular) -ver FormulaDetalleCard para el
/// detalle "grande y centrado" que pide tocar una unidad (Cuarto/Galón/
/// Cubeta) dentro de esa ficha-. El estado de la búsqueda vive en esta
/// misma pantalla (no en un diálogo aparte), así que cambiar de pestaña
/// (ver FormulasKioskScreen) y volver no la pierde. Todo va en un solo
/// SingleChildScrollView de la pantalla completa (nada de buscador fijo
/// arriba con solo la lista scrolleando abajo).
class BuscarFormulaScreen extends ConsumerStatefulWidget {
  final bool esDialogo;
  const BuscarFormulaScreen({super.key, this.esDialogo = true});

  @override
  ConsumerState<BuscarFormulaScreen> createState() => _BuscarFormulaScreenState();
}

class _BuscarFormulaScreenState extends ConsumerState<BuscarFormulaScreen> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  FormulaColortrendModel? _seleccionada;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() => setState(() {
        _busqueda = _busquedaController.text.trim();
        _seleccionada = null;
      });

  @override
  Widget build(BuildContext context) {
    final formulasAsync = ref.watch(formulasColortrendProvider);

    final contenido = LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 760;
        return SingleChildScrollView(
          padding: EdgeInsets.all(esMovil ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.esDialogo)
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                    const SizedBox(width: 6),
                    Text('Buscar Fórmula', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                  ],
                )
              else
                Text('Buscar Fórmula', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              Text(
                'Libro Color Codex Formulas (Colortrend) — buscá por código, nombre o base y apretá Enter o Buscar.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB6BCC7))),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _busquedaController,
                              autofocus: !esMovil,
                              style: GoogleFonts.poppins(fontSize: 14),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Código, nombre o base del color...',
                                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _buscar(),
                            ),
                          ),
                          if (_busquedaController.text.isNotEmpty)
                            IconButton(
                              tooltip: 'Limpiar',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() {
                                _busqueda = '';
                                _seleccionada = null;
                                _busquedaController.clear();
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _buscar,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              formulasAsync.when(
                loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))),
                error: (e, st) => Center(child: Text('No se pudo cargar el libro de fórmulas: $e', style: GoogleFonts.poppins(color: Colors.red))),
                data: (formulas) {
                  if (_busqueda.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_outlined, size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Escribí un código, nombre o base y apretá Enter o Buscar', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    );
                  }
                  final resultados = formulas.where((f) => coincideFuzzy(f.textoBusqueda, _busqueda)).toList()
                    ..sort((a, b) => a.codigo.compareTo(b.codigo));

                  if (resultados.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('Sin resultados para "$_busqueda"', style: GoogleFonts.poppins(color: Colors.grey.shade500))),
                    );
                  }

                  if (esMovil) {
                    if (_seleccionada != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _seleccionada = null),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: Text('Ver lista (${resultados.length})', style: GoogleFonts.poppins(fontSize: 12.5)),
                          ),
                          FormulaDetalleCard(formula: _seleccionada!),
                        ],
                      );
                    }
                    return _listaResultados(resultados);
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: _listaResultados(resultados)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _seleccionada == null
                            ? Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Elegí un color de la lista', style: GoogleFonts.poppins(color: Colors.grey.shade400))))
                            : FormulaDetalleCard(formula: _seleccionada!),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    if (widget.esDialogo) {
      return Scaffold(backgroundColor: const Color(0xFFF2F3F7), body: SafeArea(child: contenido));
    }
    return Container(color: const Color(0xFFF2F3F7), child: contenido);
  }

  // Column simple, sin ListView propio: vive dentro del scroll único de la
  // pantalla completa (ver el comentario grande arriba de la clase).
  Widget _listaResultados(List<FormulaColortrendModel> resultados) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        children: [
          for (var i = 0; i < resultados.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
            ListTile(
              dense: true,
              selected: identical(resultados[i], _seleccionada),
              selectedTileColor: const Color(0xFFFCE9E9),
              title: Text('${resultados[i].codigo}  ·  ${resultados[i].nombre}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${resultados[i].base} · pág. ${resultados[i].pagina}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => setState(() => _seleccionada = resultados[i]),
            ),
          ],
        ],
      ),
    );
  }
}
