import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

enum ModoTema { claro, oscuro, sistema }

const _claveModoTema = 'modo_tema';

ModoTema modoTemaGuardado = ModoTema.claro;

Future<void> cargarModoTema() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final valor = prefs.getString(_claveModoTema);
    modoTemaGuardado = ModoTema.values.firstWhere(
      (m) => m.name == valor,
      orElse: () => ModoTema.claro,
    );
  } catch (_) {
    modoTemaGuardado = ModoTema.claro;
  }
  AppColors.oscuro = resolverOscuro(modoTemaGuardado);
}

bool resolverOscuro(ModoTema modo) {
  switch (modo) {
    case ModoTema.claro:
      return false;
    case ModoTema.oscuro:
      return true;
    case ModoTema.sistema:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  }
}

class ModoTemaNotifier extends Notifier<ModoTema> {
  @override
  ModoTema build() => modoTemaGuardado;

  Future<void> establecer(ModoTema modo) async {
    state = modo;
    modoTemaGuardado = modo;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_claveModoTema, modo.name);
    } catch (_) {}
  }
}

final modoTemaProvider = NotifierProvider<ModoTemaNotifier, ModoTema>(
  ModoTemaNotifier.new,
);

void reconstruirTodoElArbol() {
  void visitar(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visitar);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visitar);
}

ThemeData temaClaro() {
  return ThemeData(
    colorSchemeSeed: const Color(0xFF0F1B3D),
    useMaterial3: true,
  );
}

ThemeData temaOscuro() {
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F1B3D),
    brightness: Brightness.dark,
  );
  final esquema = base.copyWith(
    primary: const Color(0xFFE0504D),
    onPrimary: Colors.white,
    surface: const Color(0xFF1C1E22),
    onSurface: const Color(0xFFECEDEF),
    onSurfaceVariant: const Color(0xFFA8ACB5),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: const Color(0xFF121316),
    surfaceContainerLow: const Color(0xFF1A1C20),
    surfaceContainer: const Color(0xFF202328),
    surfaceContainerHigh: const Color(0xFF262930),
    surfaceContainerHighest: const Color(0xFF2C2F36),
    outline: const Color(0xFF4A4F58),
    outlineVariant: const Color(0xFF363A41),
  );
  return ThemeData(
    colorScheme: esquema,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF121316),
    canvasColor: const Color(0xFF1C1E22),
    dividerColor: const Color(0xFF363A41),
  );
}
