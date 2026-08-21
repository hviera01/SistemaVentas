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

  @override
  Widget build(BuildContext context) {
    final formulasAsync = ref.watch(formulasColortrendProvider);

    final contenido = LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 760;
        return Padding(
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
                'Libro Color Codex Formulas (Colortrend) — buscá por código, nombre o base.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Container(
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
                        onChanged: (v) => setState(() {
                          _busqueda = v.trim();
                          _seleccionada = null;
                        }),
                        onSubmitted: (_) => setState(() {}),
                      ),
                    ),
                    if (_busqueda.isNotEmpty)
                      IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _busqueda = '';
                          _busquedaController.clear();
                          _seleccionada = null;
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: formulasAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                  error: (e, st) => Center(child: Text('No se pudo cargar el libro de fórmulas: $e', style: GoogleFonts.poppins(color: Colors.red))),
                  data: (formulas) {
                    if (_busqueda.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_outlined, size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Escribí un código, nombre o base para buscar', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    }
                    final resultados = formulas.where((f) => coincideFuzzy(f.textoBusqueda, _busqueda)).toList()
                      ..sort((a, b) => a.codigo.compareTo(b.codigo));

                    if (resultados.isEmpty) {
                      return Center(child: Text('Sin resultados para "$_busqueda"', style: GoogleFonts.poppins(color: Colors.grey.shade500)));
                    }

                    if (esMovil) {
                      if (_seleccionada != null) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextButton.icon(
                                onPressed: () => setState(() => _seleccionada = null),
                                icon: const Icon(Icons.arrow_back, size: 16),
                                label: Text('Ver lista (${resultados.length})', style: GoogleFonts.poppins(fontSize: 12.5)),
                              ),
                              FormulaDetalleCard(formula: _seleccionada!),
                            ],
                          ),
                        );
                      }
                      return _listaResultados(resultados, esMovil);
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 320, child: _listaResultados(resultados, esMovil)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _seleccionada == null
                              ? Center(child: Text('Elegí un color de la lista', style: GoogleFonts.poppins(color: Colors.grey.shade400)))
                              : SingleChildScrollView(child: FormulaDetalleCard(formula: _seleccionada!)),
                        ),
                      ],
                    );
                  },
                ),
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

  Widget _listaResultados(List<FormulaColortrendModel> resultados, bool esMovil) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: resultados.length,
        separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, i) {
          final f = resultados[i];
          return ListTile(
            dense: true,
            title: Text('${f.codigo}  ·  ${f.nombre}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('${f.base} · pág. ${f.pagina}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => setState(() => _seleccionada = f),
          );
        },
      ),
    );
  }
}
