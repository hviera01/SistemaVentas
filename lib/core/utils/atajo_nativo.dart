import 'package:flutter/services.dart';

/// Puente con el código nativo de Windows (ver FlutterWindow::MessageHandler
/// en windows/runner/flutter_window.cpp): F10 sin ningún modificador es, a
/// nivel de Win32, una "tecla de sistema" igual que Alt solo. Si Flutter
/// llega a verla, el motor termina dejando que Windows procese el mensaje
/// original de todos modos y el sistema operativo entra en "modo menú" -como
/// esta app no tiene menú nativo, la siguiente tecla escrita se pierde con
/// el beep de error en vez de escribirse-. Por eso, del lado nativo, F10 se
/// traga por completo antes de que llegue a Flutter, y en su lugar se avisa
/// acá por este canal en vez de por el camino normal de teclado
/// (HardwareKeyboard nunca ve un KeyEvent de F10 en Windows).
///
/// Con varias pestañas abiertas a la vez (ver AppShell/IndexedStack) puede
/// haber más de una pantalla interesada en F10 al mismo tiempo, pero
/// MethodChannel solo admite un handler por canal: acá se registra uno solo,
/// una única vez, y se reparte a una lista de oyentes -mismo patrón que ya
/// usa HardwareKeyboard.instance.addHandler, donde cada pantalla se filtra a
/// sí misma según si es la pestaña activa-.
class AtajoNativo {
  AtajoNativo._();

  static const _canal = MethodChannel('atajos_teclado');
  static final _oyentesF10 = <void Function()>[];
  static bool _inicializado = false;

  static void _inicializar() {
    if (_inicializado) return;
    _inicializado = true;
    _canal.setMethodCallHandler((llamada) async {
      if (llamada.method == 'f10') {
        for (final oyente in List<void Function()>.of(_oyentesF10)) {
          oyente();
        }
      }
      return null;
    });
  }

  static void agregarOyenteF10(void Function() oyente) {
    _inicializar();
    _oyentesF10.add(oyente);
  }

  static void quitarOyenteF10(void Function() oyente) {
    _oyentesF10.remove(oyente);
  }
}
