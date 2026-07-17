import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/usuario_model.dart';
import '../../providers/usuarios_provider.dart';
import '../widgets/usuario_form_dialog.dart';

class UsuariosScreen extends ConsumerWidget {
  const UsuariosScreen({super.key});

  void _abrirFormulario(BuildContext context, [UsuarioModel? usuario]) {
    showDialog(
      context: context,
      builder: (context) => UsuarioFormDialog(usuario: usuario),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuariosAsync = ref.watch(usuariosStreamProvider);
    final busqueda = ref.watch(usuarioBusquedaProvider);

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
                    'Usuarios',
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
                  border: Border.all(color: const Color(0xFFB6BCC7), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.13),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: usuariosAsync.when(
                      data: (usuarios) {
                        final filtrados = usuarios.where((u) {
                          final texto = busqueda.toLowerCase();
                          return u.nombreCompleto.toLowerCase().contains(texto) || u.documento.toLowerCase().contains(texto);
                        }).toList();

                        if (filtrados.isEmpty) {
                          return Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_alt_outlined, size: 56, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text('No hay usuarios', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          );
                        }

                        return esMovil ? _tarjetas(context, filtrados) : _tabla(context, filtrados);
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

  Widget _tabla(BuildContext context, List<UsuarioModel> lista) {
    return ListView.builder(
      itemCount: lista.length + 1,
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
                Expanded(flex: 3, child: Text('NOMBRE', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('DOCUMENTO', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('ROL', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('ESTADO', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5))),
                const SizedBox(width: 40),
              ],
            ),
          );
        }
        final usuario = lista[index - 1];
        return Column(
          children: [
            if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
            InkWell(
              onTap: () => _abrirFormulario(context, usuario),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        usuario.nombreCompleto,
                        style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        usuario.documento,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        usuario.rol,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        constraints: const BoxConstraints(maxWidth: 80),
                        decoration: BoxDecoration(
                          color: usuario.estado ? const Color(0xFFE8F8EE) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          usuario.estado ? 'Activo' : 'Inactivo',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: usuario.estado ? const Color(0xFF16A34A) : Colors.grey.shade600),
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
  }

  Widget _tarjetas(BuildContext context, List<UsuarioModel> lista) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final u = lista[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _abrirFormulario(context, u),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC7CBD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        u.nombreCompleto,
                        style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipInfo('Documento', u.documento),
                    _chipInfo('Rol', u.rol),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: u.estado ? const Color(0xFFE8F8EE) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        u.estado ? 'Activo' : 'Inactivo',
                        style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: u.estado ? const Color(0xFF16A34A) : Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chipInfo(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $valor', style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF3F434A))),
    );
  }

  Widget _buscador(WidgetRef ref, String busqueda) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o documento...',
                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => ref.read(usuarioBusquedaProvider.notifier).actualizar(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonRefrescar(WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => ref.invalidate(usuariosStreamProvider),
      icon: const Icon(Icons.refresh, size: 18),
      label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1A1A1A),
        side: const BorderSide(color: Color(0xFFB6BCC7)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _botonNuevo(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _abrirFormulario(context),
      icon: const Icon(Icons.add, size: 18),
      label: Text('Nuevo Usuario', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC62828),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
