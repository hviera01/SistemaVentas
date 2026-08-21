import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Cuando se entra por "?formulas=1" (ver FormulasKioskScreen y main.dart),
// esto hace que el navegador la reconozca como una app aparte de "Super
// Color" -mismo logo, pero otro nombre y otro punto de entrada- para que
// "Agregar a pantalla de inicio"/"Instalar" en el celular la instale como
// su propio ícono ("Fórmulas") en vez de mezclarse con el acceso directo
// del sistema completo. Sin esto, aunque la URL sí entra directo al kiosco
// sin pedir login, el nombre/manifest seguían siendo los de "Sistema
// Ventas" -por eso se sentía "como entrar al sistema normal"-.
void aplicarIdentidadKiosk() {
  try {
    final documento = globalContext.getProperty('document'.toJS) as JSObject;
    documento.setProperty('title'.toJS, 'Fórmulas · Super Color'.toJS);

    final enlaceManifest = (documento.callMethod('querySelector'.toJS, 'link[rel="manifest"]'.toJS) as JSObject?);
    enlaceManifest?.setProperty('href'.toJS, 'manifest_formulas.json'.toJS);

    final metaTitulo = (documento.callMethod('querySelector'.toJS, 'meta[name="apple-mobile-web-app-title"]'.toJS) as JSObject?);
    metaTitulo?.setProperty('content'.toJS, 'Fórmulas'.toJS);
  } catch (_) {
    // Si algo de esto falla (navegador raro, DOM no disponible todavía),
    // no es grave: el kiosco sigue funcionando igual, solo el ícono de
    // "instalar" quedaría con el nombre genérico del sistema.
  }
}
