import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Cuando se entra por "?formulas=1" (ver FormulasKioskScreen y main.dart),
// esto solo cambia el título de la pestaña -cosmético-. El "Agregar a
// pantalla de inicio" con nombre/ícono propios YA NO depende de esto: se
// resolvió con una página estática aparte (ver web/formulas/index.html),
// porque cambiar el manifest.json con JavaScript ya adentro de la app de
// Flutter llegaba tarde -el navegador ya había decidido instalar con el
// manifest.json original de la carpeta raíz antes de que este código
// llegara a correr-.
void aplicarIdentidadKiosk() {
  try {
    final documento = globalContext.getProperty('document'.toJS) as JSObject;
    documento.setProperty('title'.toJS, 'Fórmulas · Super Color'.toJS);
  } catch (_) {
    // Cosmético nada más: si falla, el kiosco sigue funcionando igual.
  }
}
