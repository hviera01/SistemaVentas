import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/modulos_menu.dart';
import '../models/tab_item.dart';
import '../providers/tabs_provider.dart';
import '../services/actualizacion_service.dart';
import '../utils/pantalla_builder.dart';
import '../widgets/actualizacion_dialog.dart';
import '../../features/auth/providers/auth_provider.dart';

class SideMenu extends ConsumerWidget {
  final VoidCallback onCerrar;

  const SideMenu({super.key, required this.onCerrar});

  Future<void> _buscarActualizaciones(BuildContext context) async {
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.showSnackBar(const SnackBar(content: Text('Buscando actualizaciones...'), duration: Duration(seconds: 2)));
    final actualizacion = await ActualizacionService.buscarActualizacion();
    if (!context.mounted) return;
    if (actualizacion == null) {
      mensajero.showSnackBar(const SnackBar(content: Text('Ya tenés la última versión instalada')));
      return;
    }
    mostrarDialogoActualizacion(context, actualizacion);
  }

  void _abrirSubModulo(WidgetRef ref, SubModulo sub) {
    final esVentaNueva = sub.moduleKey == 'ventas_registrar';
    final id = esVentaNueva ? 'ventas_registrar_${DateTime.now().millisecondsSinceEpoch}' : sub.moduleKey;
    ref.read(tabsProvider.notifier).abrirTab(
      TabItem(
        id: id,
        titulo: sub.titulo,
        icono: sub.icono,
        contenido: construirPantalla(sub.moduleKey, sub.titulo, sub.icono, id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final esAdmin = authState.usuario?.rol == 'Administrador';
    final modulos = obtenerModulos().where((m) {
      return m.subModulos.any((s) => esAdmin || !s.soloAdmin);
    }).toList();

    return Material(
      color: Colors.white,
      elevation: 20,
      child: SizedBox(
        width: 300,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                color: const Color(0xFFC62828),
                child: Row(
                  children: [
                    Text(
                      'MENÚ',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 1),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: onCerrar,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: modulos.length,
                  itemBuilder: (context, index) {
                    final modulo = modulos[index];
                    final disponibles = modulo.subModulos.where((s) => esAdmin || !s.soloAdmin).toList();
                    if (disponibles.length == 1) {
                      return ListTile(
                        leading: Icon(modulo.icono, color: modulo.color, size: 22),
                        title: Text(modulo.titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        onTap: () {
                          _abrirSubModulo(ref, disponibles.first);
                          onCerrar();
                        },
                      );
                    }
                    return Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(modulo.icono, color: modulo.color, size: 22),
                        title: Text(modulo.titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        children: disponibles.map((sub) {
                          return ListTile(
                            contentPadding: const EdgeInsets.only(left: 56, right: 16),
                            leading: Icon(sub.icono, size: 18, color: Colors.grey.shade600),
                            title: Text(sub.titulo, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade800)),
                            onTap: () {
                              _abrirSubModulo(ref, sub);
                              onCerrar();
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              if (ActualizacionService.aplica)
                ListTile(
                  leading: Icon(Icons.system_update_alt, color: Colors.grey.shade600, size: 20),
                  title: Text('Buscar actualizaciones', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700)),
                  onTap: () => _buscarActualizaciones(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}