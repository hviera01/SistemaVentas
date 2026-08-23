import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart' show ShellExecute, SW_SHOWNORMAL;
import '../version_app.dart';

class ActualizacionDisponible {
  final int version;
  final String urlDescarga;
  final String notas;

  ActualizacionDisponible({required this.version, required this.urlDescarga, required this.notas});
}

/// Chequea si hay una versión más nueva de la app publicada como GitHub
/// Release (el instalador/APK se sube a mano con `gh release create`, ver
/// memoria del proyecto) y, si el usuario acepta, la descarga y la instala.
/// Aplica a Windows (.exe) y Android (.apk); en Web no hay nada que
/// instalar. GitHub Releases es público así que no hace falta ningún token
/// para leerlo.
class ActualizacionService {
  static const _repo = 'hviera01/SistemaVentas';

  static bool get aplica => !kIsWeb && (Platform.isWindows || Platform.isAndroid);

  static String get _extensionEsperada => Platform.isAndroid ? '.apk' : '.exe';

  /// Última versión publicada como GitHub Release, sin importar si es más
  /// nueva que la instalada (a diferencia de buscarActualizacion()). Null si
  /// no hay internet o GitHub no responde. La usa la pantalla de
  /// Dispositivos para marcar como desactualizado cualquier equipo que
  /// reportó una versión menor a esta.
  static Future<int?> obtenerUltimaVersionPublicada() async {
    try {
      final respuesta = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
      if (respuesta.statusCode != 200) return null;
      final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final tag = (datos['tag_name'] as String? ?? '').replaceFirst('v', '');
      return int.tryParse(tag);
    } catch (_) {
      return null;
    }
  }

  /// Devuelve null si no aplica, si no hay internet/GitHub no responde, si no
  /// hay un asset para esta plataforma, o si la versión publicada no es más
  /// nueva que la instalada -en todos esos casos no hay que interrumpir el
  /// uso normal de la app-.
  static Future<ActualizacionDisponible?> buscarActualizacion() async {
    if (!aplica) return null;
    try {
      final respuesta = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
      if (respuesta.statusCode != 200) return null;
      final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final tag = (datos['tag_name'] as String? ?? '').replaceFirst('v', '');
      final version = int.tryParse(tag);
      if (version == null || version <= versionApp) return null;
      final assets = (datos['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      Map<String, dynamic>? asset;
      for (final a in assets) {
        if ((a['name'] as String? ?? '').toLowerCase().endsWith(_extensionEsperada)) {
          asset = a;
          break;
        }
      }
      final url = asset?['browser_download_url'] as String?;
      if (url == null) return null;
      return ActualizacionDisponible(
        version: version,
        urlDescarga: url,
        notas: (datos['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Descarga el instalador/APK a una carpeta temporal y lo instala.
  ///
  /// En Windows, el instalador de Inno Setup (mismo AppId que la instalación
  /// actual) reemplaza los archivos solo -por eso acá se cierra esta
  /// instancia (exit) apenas queda lanzado, para no competir por los
  /// archivos que está por sobrescribir-.
  ///
  /// En Android no hay forma de instalar sin que el usuario confirme (una
  /// restricción del sistema operativo, no hay vuelta): esto abre la
  /// pantalla del instalador de Android con el APK descargado, y ahí el
  /// usuario decide si instala. La app sigue corriendo mientras tanto.
  static Future<void> descargarEInstalar(
    ActualizacionDisponible actualizacion,
    void Function(double progreso) onProgreso,
  ) async {
    final carpetaTemp = await getTemporaryDirectory();
    final nombreArchivo = Platform.isAndroid ? 'SuperColorActualizacion.apk' : 'SuperColorActualizacion.exe';
    final archivoDestino = File('${carpetaTemp.path}${Platform.pathSeparator}$nombreArchivo');

    final cliente = http.Client();
    try {
      final peticion = await cliente.send(http.Request('GET', Uri.parse(actualizacion.urlDescarga)));
      final total = peticion.contentLength ?? 0;
      var recibido = 0;
      final sink = archivoDestino.openWrite();
      await for (final trozo in peticion.stream) {
        sink.add(trozo);
        recibido += trozo.length;
        if (total > 0) onProgreso(recibido / total);
      }
      await sink.close();
    } finally {
      cliente.close();
    }

    if (Platform.isAndroid) {
      await OpenFile.open(archivoDestino.path);
      return;
    }

    // El instalador de Inno Setup pide administrador (PrivilegesRequired=
    // admin en el .iss, así reemplaza los archivos del programa), y
    // Process.start (CreateProcess por debajo) NO puede lanzar un programa
    // así si esta app -que corre como usuario normal, sin manifest de
    // administrador- no está ya elevada: Windows lo rechaza en seco
    // (ERROR_ELEVATION_REQUIRED) sin mostrar ningún aviso de permisos, así
    // que la actualización nunca llegaba a instalarse -bug real reportado
    // por el dueño: pedía actualizar, parecía funcionar, pero al volver a
    // abrir seguía en la versión vieja-. ShellExecute sí sabe hacer esto:
    // ve que el instalador pide administrador y muestra el aviso de
    // Windows (UAC) para que el usuario lo acepte, exactamente como pasa al
    // hacer doble clic en el .exe desde el Explorador.
    final rutaPtr = archivoDestino.path.toNativeUtf16();
    final operacionPtr = 'open'.toNativeUtf16();
    try {
      final resultado = ShellExecute(0, operacionPtr, rutaPtr, nullptr, nullptr, SW_SHOWNORMAL);
      // Según la documentación de Win32, un resultado > 32 es éxito -32 o
      // menos es un código de error (ERROR_CANCELLED si el usuario cancela
      // el aviso de administrador incluido). Si el usuario cancela el UAC
      // no hay que cerrar la app: se queda como estaba, sigue pudiendo
      // reintentar.
      if (resultado <= 32) {
        throw ProcessException(archivoDestino.path, [], 'ShellExecute devolvió $resultado');
      }
    } finally {
      calloc.free(rutaPtr);
      calloc.free(operacionPtr);
    }
    exit(0);
  }
}
