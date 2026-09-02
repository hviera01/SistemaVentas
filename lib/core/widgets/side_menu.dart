import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/modulos_menu.dart';
import '../providers/actualizacion_provider.dart';
import '../services/actualizacion_service.dart';
import '../utils/abrir_submodulo.dart';
import '../widgets/actualizacion_dialog.dart';
import '../../features/auth/providers/auth_provider.dart';

class SideMenu extends ConsumerWidget {
  final VoidCallback onCerrar;

  const SideMenu({super.key, required this.onCerrar});

  Future<void> _buscarActualizaciones(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.showSnackBar(
      const SnackBar(
        content: Text('Buscando actualizaciones...'),
        duration: Duration(seconds: 2),
      ),
    );
    final actualizacion = await ActualizacionService.buscarActualizacion();
    if (!context.mounted) return;
    if (actualizacion == null) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('Ya tenés la última versión instalada')),
      );
      return;
    }
    ref
        .read(actualizacionDisponibleProvider.notifier)
        .establecer(actualizacion);
    mostrarDialogoActualizacion(context, actualizacion);
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                color: const Color(0xFFC62828),
                child: Row(
                  children: [
                    Text(
                      'MENÚ',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
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
                    final disponibles = modulo.subModulos
                        .where((s) => esAdmin || !s.soloAdmin)
                        .toList();
                    if (disponibles.length == 1) {
                      return ListTile(
                        leading: Icon(
                          modulo.icono,
                          color: modulo.color,
                          size: 22,
                        ),
                        title: Text(
                          modulo.titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          abrirSubModulo(context, ref, disponibles.first);
                          onCerrar();
                        },
                      );
                    }
                    return Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Icon(
                          modulo.icono,
                          color: modulo.color,
                          size: 22,
                        ),
                        title: Text(
                          modulo.titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: disponibles.map((sub) {
                          return ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 56,
                              right: 16,
                            ),
                            leading: Icon(
                              sub.icono,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            title: Text(
                              sub.titulo,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            onTap: () {
                              abrirSubModulo(context, ref, sub);
                              onCerrar();
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              if (ActualizacionService.aplica) ...[
                Builder(
                  builder: (context) {
                    final actualizacion = ref.watch(
                      actualizacionDisponibleProvider,
                    );
                    final hayActualizacion = actualizacion != null;
                    final colorVerde = const Color(0xFF1E9E5A);
                    return ListTile(
                      leading: Icon(
                        hayActualizacion
                            ? Icons.system_update
                            : Icons.system_update_alt,
                        color: hayActualizacion
                            ? colorVerde
                            : Colors.grey.shade600,
                        size: 20,
                      ),
                      title: Text(
                        hayActualizacion
                            ? 'Actualización disponible'
                            : 'Buscar actualizaciones',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: hayActualizacion
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: hayActualizacion
                              ? colorVerde
                              : Colors.grey.shade700,
                        ),
                      ),
                      subtitle: hayActualizacion
                          ? Text(
                              'v${actualizacion.version} · tocá para instalar',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: colorVerde,
                              ),
                            )
                          : null,
                      onTap: () => hayActualizacion
                          ? mostrarDialogoActualizacion(context, actualizacion)
                          : _buscarActualizaciones(context, ref),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
