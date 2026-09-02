import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ejecuta [accion] y, si falla (por ejemplo por un timeout de red), muestra
/// un diálogo bien visible en el centro de la pantalla explicando que
/// probablemente falló la conexión a internet, con la opción de reintentar
/// la misma acción sin tener que cerrar el formulario y perder lo escrito.
///
/// Antes, cuando fallaba una acción como guardar un producto, el error solo
/// se mostraba como un texto chico en el formulario, y a veces ni quedaba
/// claro si el cambio se había hecho o no. Este diálogo lo deja explícito.
///
/// Devuelve el resultado de [accion] si tuvo éxito, o null si el usuario
/// tocó "Cancelar" en vez de reintentar.
Future<T?> ejecutarConReintento<T>(
  BuildContext context,
  Future<T> Function() accion,
) async {
  while (true) {
    try {
      return await accion();
    } catch (e) {
      if (!context.mounted) return null;
      final esTimeout = e is TimeoutException;
      final reintentar = await showDialog<bool>(
        useRootNavigator: false,
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.wifi_off_outlined, color: Color(0xFFC62828)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No se pudo guardar',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            esTimeout
                ? 'Parece que falló la conexión a internet. Todavía no se guardó el cambio: podés reintentar sin perder lo que escribiste.'
                : 'Ocurrió un error y no se guardó el cambio. Podés reintentar sin perder lo que escribiste.\n\n${e.toString().replaceAll('Exception: ', '')}',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar', style: GoogleFonts.poppins()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Reintentar', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );
      if (reintentar != true) return null;
      // Vuelve a intentar accion() en la siguiente vuelta del while.
    }
  }
}
