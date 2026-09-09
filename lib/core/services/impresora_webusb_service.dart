// WebUSB (navigator.usb) es una API de navegador: no existe en Windows/
// Android/iOS nativos, y package:web/dart:js_interop para esto ni
// compilarían ahí. Mismo patrón que webauthn.dart/tablet_utils.dart: un
// stub para todo lo que no sea web.
export 'impresora_webusb_service_stub.dart'
    if (dart.library.html) 'impresora_webusb_service_web.dart';
