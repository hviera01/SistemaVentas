import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/providers/tabs_provider.dart';
import '../../../../core/models/tab_item.dart';
import '../../../../core/data/modulos_menu.dart';
import '../../../../core/utils/pantalla_builder.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _abrirSubModulo(WidgetRef ref, SubModulo sub) {
    final esVentaNueva = sub.moduleKey == 'ventas_registrar';
    final id = esVentaNueva ? 'ventas_registrar_${DateTime.now().millisecondsSinceEpoch}' : sub.moduleKey;
    ref.read(tabsProvider.notifier).abrirTab(
      TabItem(
        id: id,
        titulo: sub.titulo,
        icono: sub.icono,
        contenido: construirPantalla(sub.moduleKey, sub.titulo, sub.icono),
      ),
    );
  }

  void _manejarTap(BuildContext context, WidgetRef ref, ModuloMenu modulo, bool esAdmin) {
    final disponibles = modulo.subModulos.where((s) => esAdmin || !s.soloAdmin).toList();
    if (disponibles.isEmpty) return;
    if (disponibles.length == 1) {
      _abrirSubModulo(ref, disponibles.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 16),
                Text(modulo.titulo, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                const SizedBox(height: 8),
                ...disponibles.map((sub) {
                  return ListTile(
                    leading: Icon(sub.icono, color: modulo.color),
                    title: Text(sub.titulo, style: GoogleFonts.poppins(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _abrirSubModulo(ref, sub);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final usuario = authState.usuario;
    final esAdmin = usuario?.rol == 'Administrador';

    final modulosVisibles = obtenerModulos().where((m) {
      return m.subModulos.any((s) => esAdmin || !s.soloAdmin);
    }).toList();

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 16 : 28),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, ${usuario?.nombreCompleto ?? ''}',
                    style: GoogleFonts.poppins(fontSize: esMovil ? 20 : 24, fontWeight: FontWeight.w700, color: const Color(0xFFC62828)),
                  ),
                  const SizedBox(height: 4),
                  Text('Seleccioná una opción para comenzar', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: modulosVisibles.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: esMovil ? 180 : 270,
                      mainAxisSpacing: esMovil ? 14 : 20,
                      crossAxisSpacing: esMovil ? 14 : 20,
                      childAspectRatio: esMovil ? 0.92 : 1.15,
                    ),
                    itemBuilder: (context, index) {
                      final modulo = modulosVisibles[index];
                      return _tarjetaModulo(context, ref, modulo, esAdmin, esMovil);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tarjetaModulo(BuildContext context, WidgetRef ref, ModuloMenu modulo, bool esAdmin, bool esMovil) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _manejarTap(context, ref, modulo, esAdmin),
        child: Container(
          padding: EdgeInsets.all(esMovil ? 14 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: esMovil ? 42 : 52,
                height: esMovil ? 42 : 52,
                decoration: BoxDecoration(color: modulo.color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(modulo.icono, color: modulo.color, size: esMovil ? 20 : 26),
              ),
              SizedBox(height: esMovil ? 10 : 16),
              Text(
                modulo.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: esMovil ? 13 : 15.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 4),
              Text(
                '${modulo.subModulos.where((s) => esAdmin || !s.soloAdmin).length} opciones',
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}