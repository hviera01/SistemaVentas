import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identificador estable de este dispositivo/instalación, usado para que el
/// módulo de Dispositivos actualice siempre el mismo registro en vez de crear
/// uno nuevo cada vez que la app se reinicia.
///
/// En Windows se usa el nombre de la PC (estable, y le sirve al administrador
/// para reconocer de un vistazo de qué equipo se trata sin tener que abrir
/// nada más). En Android (y cualquier otra plataforma sin un nombre de host
/// útil) se genera un UUID una sola vez y se guarda en SharedPreferences,
/// reutilizándolo en cada arranque siguiente.
Future<String> obtenerIdDispositivo() async {
  if (!kIsWeb && Platform.isWindows) {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) return host;
  }
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('idDispositivo');
  if (id == null || id.isEmpty) {
    id = const Uuid().v4();
    await prefs.setString('idDispositivo', id);
  }
  return id;
}

/// true si ESTE equipo es "la PC principal" (la que tiene la impresora
/// térmica conectada de verdad) según [pcPrincipalHostname] -ver
/// NegocioModel-: vacío (no configurado, comportamiento de siempre) cuenta
/// como que sí, para no romper nada en los negocios que nunca tocaron esto.
/// Usado tanto para decidir si este equipo manda latido de presencia y
/// procesa impresiones remotas (ver AppShell) como para decidir si, al
/// fallar una impresión local, vale la pena preguntarle a Firestore si la
/// PC de verdad está encendida (ver RegistrarVentaScreen._manejarImpresion).
Future<bool> esteEquipoEsPcPrincipal(String pcPrincipalHostname) async {
  if (pcPrincipalHostname.isEmpty) return true;
  final id = await obtenerIdDispositivo();
  return id == pcPrincipalHostname;
}

String obtenerPlataforma() {
  if (kIsWeb) return 'Web';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return 'Desconocida';
}
