import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/actualizacion_service.dart';

/// Última actualización detectada como disponible (por el chequeo automático
/// al abrir la app o por "Buscar actualizaciones" en el menú, ver
/// AppShell/SideMenu). Sirve para que el menú se pinte en verde mientras
/// haya una actualización pendiente, incluso si el usuario cerró el diálogo
/// con "Después" -no se limpia sola: la única forma de que desaparezca es
/// instalar la actualización (lo que cierra y reabre la app) o volver a
/// chequear y que ya no haya ninguna más nueva-.
class ActualizacionDisponibleNotifier extends Notifier<ActualizacionDisponible?> {
  @override
  ActualizacionDisponible? build() => null;

  void establecer(ActualizacionDisponible? actualizacion) {
    state = actualizacion;
  }
}

final actualizacionDisponibleProvider = NotifierProvider<ActualizacionDisponibleNotifier, ActualizacionDisponible?>(
  ActualizacionDisponibleNotifier.new,
);
