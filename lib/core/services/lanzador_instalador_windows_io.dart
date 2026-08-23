import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show ShellExecute, SW_SHOWNORMAL;

/// Lanza el instalador de Windows (Inno Setup, pide administrador vía
/// `PrivilegesRequired=admin` en el .iss) con ShellExecute en vez de
/// Process.start/CreateProcess: ShellExecute sí sabe mostrar el aviso de
/// permisos de Windows (UAC) cuando el programa que lanza pide
/// administrador -CreateProcess, que es lo que usa Process.start por
/// debajo, lo rechaza en seco (ERROR_ELEVATION_REQUIRED) sin avisar nada si
/// quien llama no está ya elevado, que era el bug real por el que la
/// actualización de Windows nunca se terminaba de instalar-. Devuelve true
/// si Windows aceptó lanzarlo (según la documentación de Win32, un
/// resultado de ShellExecute > 32 es éxito; 32 o menos es un código de
/// error, incluido si el usuario cancela el aviso de administrador).
bool lanzarInstaladorElevado(String ruta) {
  final rutaPtr = ruta.toNativeUtf16();
  final operacionPtr = 'open'.toNativeUtf16();
  try {
    return ShellExecute(0, operacionPtr, rutaPtr, nullptr, nullptr, SW_SHOWNORMAL) > 32;
  } finally {
    calloc.free(rutaPtr);
    calloc.free(operacionPtr);
  }
}
