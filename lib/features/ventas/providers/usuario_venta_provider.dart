import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/usuario_model.dart';

/// Usuario al que se le atribuye la venta de esta pestaña, cuando es
/// distinto del usuario de la sesión (ver botón "cambiar usuario" en
/// registrar_venta_screen). null significa que se usa el usuario de la
/// sesión (authProvider). Se scopea por pestaña vía ProviderScope en
/// pantalla_builder.dart, igual que carritoVentaProvider, así que cambiarlo
/// en una pestaña no afecta a las demás ni a la sesión principal.
class UsuarioVentaOverrideNotifier extends Notifier<UsuarioModel?> {
  @override
  UsuarioModel? build() => null;

  void cambiar(UsuarioModel usuario) => state = usuario;

  void quitar() => state = null;
}

final usuarioVentaOverrideProvider = NotifierProvider<UsuarioVentaOverrideNotifier, UsuarioModel?>(UsuarioVentaOverrideNotifier.new);
