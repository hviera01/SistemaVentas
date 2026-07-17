import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/categoria_model.dart';
import '../../providers/categorias_provider.dart';
import '../widgets/categoria_form_dialog.dart';

class CategoriasScreen extends ConsumerWidget {
  const CategoriasScreen({super.key});

  void _abrirFormulario(BuildContext context, [CategoriaModel? categoria]) {
    showDialog(
      context: context,
      builder: (context) => CategoriaFormDialog(categoria: categoria),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final busqueda = ref.watch(categoriaBusquedaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 16 : 28),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Text(
                    'Categorías',
                    style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: esMovil
                      ? _buscador(ref, busqueda)
                      : Row(
                          children: [
                            Expanded(child: _buscador(ref, busqueda)),
                            const SizedBox(width: 12),
                            _botonRefrescar(ref),
                            const SizedBox(width: 12),
                            _botonNuevo(context),
                          ],
                        ),
                ),
                if (esMovil) ...[
                  SliverToBoxAdapter(child: const SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(child: _botonRefrescar(ref)),
                        const SizedBox(width: 10),
                        Expanded(child: _botonNuevo(context)),
                      ],
                    ),
                  ),
                ],
                SliverToBoxAdapter(child: const SizedBox(height: 20)),
              ],
              body: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCDFE6), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: categoriasAsync.when(
                      data: (categorias) {
                        final filtradas = categorias.where((c) {
                          return c.descripcion.toLowerCase().contains(busqueda.toLowerCase());
                        }).toList();

                        if (filtradas.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.category_outlined, size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('No hay categorías', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: filtradas.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F8),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text('DESCRIPCIÓN', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                                    Expanded(flex: 1, child: Text('ESTADO', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                                    const SizedBox(width: 40),
                                  ],
                                ),
                              );
                            }
                            final categoria = filtradas[index - 1];
                            return Column(
                              children: [
                                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                                InkWell(
                                  onTap: () => _abrirFormulario(context, categoria),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: esMovil ? 14 : 20, vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            categoria.descripcion,
                                            style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            constraints: const BoxConstraints(maxWidth: 80),
                                            decoration: BoxDecoration(
                                              color: categoria.estado ? const Color(0xFFE8F8EE) : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              categoria.estado ? 'Activo' : 'Inactivo',
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: categoria.estado ? const Color(0xFF16A34A) : Colors.grey.shade600),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 30,
                                          child: Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }

  Widget _buscador(WidgetRef ref, String busqueda) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDFE6)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por descripción...',
                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => ref.read(categoriaBusquedaProvider.notifier).actualizar(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonRefrescar(WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => ref.invalidate(categoriasStreamProvider),
      icon: const Icon(Icons.refresh, size: 18),
      label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1A1A1A),
        side: const BorderSide(color: Color(0xFFDCDFE6)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _botonNuevo(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _abrirFormulario(context),
      icon: const Icon(Icons.add, size: 18),
      label: Text('Nueva Categoría', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC62828),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}