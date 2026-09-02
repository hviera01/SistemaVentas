import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/modulos_menu.dart';
import '../models/tab_item.dart';
import '../providers/tabs_provider.dart';
import 'pantalla_builder.dart';

/// Abre la pestaña de [sub], compartido por SideMenu y HomeScreen.
///
/// Ventas y Compras (Registrar) permiten varias pestañas simultáneas a la vez
/// -pedido explícito del dueño-, así que esos dos siempre abren una pestaña
/// nueva sin preguntar nada, exactamente igual que antes de este cambio. El
/// resto de módulos sigue usando una sola pestaña a la vez: si ya está
/// abierta y el usuario vuelve a tocarla, se le pregunta si quiere seguir
/// trabajando ahí o abrir una pestaña nueva aparte (quedando entonces dos
/// pestañas de ese mismo módulo, cada una independiente).
void abrirSubModulo(BuildContext context, WidgetRef ref, SubModulo sub) {
  final esRegistroMultiple =
      sub.moduleKey == 'ventas_registrar' ||
      sub.moduleKey == 'compras_registrar';
  if (esRegistroMultiple) {
    final id = '${sub.moduleKey}_${DateTime.now().millisecondsSinceEpoch}';
    ref
        .read(tabsProvider.notifier)
        .abrirTab(
          TabItem(
            id: id,
            titulo: sub.titulo,
            icono: sub.icono,
            contenido: construirPantalla(
              sub.moduleKey,
              sub.titulo,
              sub.icono,
              id,
            ),
          ),
        );
    return;
  }

  final yaAbierta = ref
      .read(tabsProvider)
      .tabs
      .any((t) => t.id == sub.moduleKey);
  if (!yaAbierta) {
    ref
        .read(tabsProvider.notifier)
        .abrirTab(
          TabItem(
            id: sub.moduleKey,
            titulo: sub.titulo,
            icono: sub.icono,
            contenido: construirPantalla(
              sub.moduleKey,
              sub.titulo,
              sub.icono,
              sub.moduleKey,
            ),
          ),
        );
    return;
  }

  showDialog(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          '${sub.titulo} ya está abierto',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          '¿Querés seguir trabajando en esa pestaña o abrir una pestaña nueva aparte?',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref
                  .read(tabsProvider.notifier)
                  .seleccionarTabPorId(sub.moduleKey);
            },
            child: Text(
              'Seguir ahí',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              final id =
                  '${sub.moduleKey}_${DateTime.now().millisecondsSinceEpoch}';
              ref
                  .read(tabsProvider.notifier)
                  .abrirTab(
                    TabItem(
                      id: id,
                      titulo: sub.titulo,
                      icono: sub.icono,
                      contenido: construirPantalla(
                        sub.moduleKey,
                        sub.titulo,
                        sub.icono,
                        id,
                      ),
                    ),
                  );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Abrir pestaña nueva'),
          ),
        ],
      );
    },
  );
}
