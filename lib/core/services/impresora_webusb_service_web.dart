import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

// Impresión térmica ESC/POS crudo directo desde el navegador, vía WebUSB
// (navigator.usb) -sin pedirle nada a la PC principal-. Interop directo con
// la API del navegador, sin ningún paquete adicional: mismo estilo que
// webauthn_web.dart/beep_web.dart.
//
// Solo existe en Chrome/Edge (Safari y Firefox no implementan WebUSB) y solo
// alcanza a la impresora si Windows no la tiene ya tomada con un driver de
// verdad instalado (ahí WebUSB no puede abrirla, el sistema operativo se
// adelantó). El "vínculo" (permiso para hablarle a un dispositivo USB
// puntual) lo otorga el usuario una vez por navegador/perfil con el
// selector nativo que abre requestDevice, y el navegador lo recuerda solo
// -no pasa por Firestore ni por Negocio, es local a cada navegador/equipo-.
//
// Este archivo nunca lanza hacia afuera: cualquier fallo (navegador sin
// soporte, usuario canceló el selector, impresora ocupada por el sistema,
// sin dispositivo vinculado, etc.) se traga y devuelve false/null, para que
// quien llama pueda caer al respaldo de pedirle a la PC principal sin que
// la venta se bloquee.

JSObject? get _usb {
  final navigator = globalContext.getProperty('navigator'.toJS) as JSObject?;
  return navigator?.getProperty('usb'.toJS) as JSObject?;
}

class ImpresoraWebUsbService {
  Future<bool> soportado() async => _usb != null;

  Future<List<JSObject>> _dispositivosVinculados() async {
    final usb = _usb;
    if (usb == null) return [];
    try {
      final promesa = usb.callMethod('getDevices'.toJS) as JSPromise<JSAny?>;
      final resultado = await promesa.toDart;
      if (resultado == null) return [];
      final lista = (resultado as JSArray).toDart;
      return lista.whereType<JSObject>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> hayImpresoraVinculada() async =>
      (await _dispositivosVinculados()).isNotEmpty;

  Future<String?> nombreImpresoraVinculada() async {
    final dispositivos = await _dispositivosVinculados();
    if (dispositivos.isEmpty) return null;
    final nombre = dispositivos.first.getProperty('productName'.toJS);
    final texto = (nombre as JSString?)?.toDart;
    return (texto == null || texto.isEmpty) ? 'Impresora USB' : texto;
  }

  // Tiene que llamarse directo desde el onPressed de un botón (un gesto real
  // del usuario, sin ningún await antes): el navegador exige "activación de
  // usuario" reciente para mostrar el selector de dispositivo, si no lo
  // rechaza en silencio (la promesa de requestDevice queda rechazada).
  Future<bool> vincular() async {
    final usb = _usb;
    if (usb == null) return false;
    try {
      final opciones = JSObject()
        ..setProperty('filters'.toJS, <JSObject>[].toJS);
      final promesa =
          usb.callMethod('requestDevice'.toJS, opciones)
              as JSPromise<JSAny?>;
      final dispositivo = await promesa.toDart;
      return dispositivo != null;
    } catch (_) {
      // El usuario cerró el selector sin elegir nada, o no hay ningún
      // dispositivo USB disponible para elegir.
      return false;
    }
  }

  Future<void> desvincular() async {
    for (final dispositivo in await _dispositivosVinculados()) {
      try {
        // USBDevice.forget() (Chrome 101+): si no existe en este navegador,
        // getProperty('forget') da null y se lo salta sin fallar.
        if (dispositivo.getProperty('forget'.toJS) == null) continue;
        final promesa =
            dispositivo.callMethod('forget'.toJS) as JSPromise<JSAny?>;
        await promesa.toDart;
      } catch (_) {}
    }
  }

  Future<bool> imprimir({required List<int> bytes}) async {
    final dispositivos = await _dispositivosVinculados();
    if (dispositivos.isEmpty) return false;
    final dispositivo = dispositivos.first;
    var abierto = false;
    try {
      await ((dispositivo.callMethod('open'.toJS) as JSPromise<JSAny?>)
          .toDart);
      abierto = true;

      var configuracion = dispositivo.getProperty('configuration'.toJS);
      if (configuracion == null) {
        await ((dispositivo.callMethod('selectConfiguration'.toJS, 1.toJS)
                as JSPromise<JSAny?>)
            .toDart);
        configuracion = dispositivo.getProperty('configuration'.toJS);
      }
      if (configuracion == null) return false;

      final endpoint = _buscarEndpointSalida(configuracion as JSObject);
      if (endpoint == null) return false;

      await ((dispositivo.callMethod(
                    'claimInterface'.toJS,
                    endpoint.interfaceNumero.toJS,
                  )
                  as JSPromise<JSAny?>)
              .toDart);

      final datos = Uint8List.fromList(bytes).toJS;
      await ((dispositivo.callMethod(
                    'transferOut'.toJS,
                    endpoint.numero.toJS,
                    datos,
                  )
                  as JSPromise<JSAny?>)
              .toDart);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (abierto) {
        try {
          await ((dispositivo.callMethod('close'.toJS) as JSPromise<JSAny?>)
              .toDart);
        } catch (_) {}
      }
    }
  }

  // Busca el primer endpoint de salida (bulk OUT) entre las interfaces de la
  // configuración activa -es lo que espera transferOut-. La mayoría de
  // impresoras térmicas USB exponen una sola interfaz "vendor-specific" con
  // un endpoint IN (para el estado) y uno OUT (para los datos a imprimir);
  // no se filtra por clase de interfaz a propósito, para no descartar
  // impresoras que no se declaren como clase 7 (Printer) "de libro".
  _EndpointSalida? _buscarEndpointSalida(JSObject configuracion) {
    final interfaces =
        (configuracion.getProperty('interfaces'.toJS) as JSArray?)?.toDart;
    if (interfaces == null) return null;
    for (final interfazAny in interfaces) {
      final interfaz = interfazAny as JSObject?;
      if (interfaz == null) continue;
      final alternate = interfaz.getProperty('alternate'.toJS) as JSObject?;
      final endpoints =
          (alternate?.getProperty('endpoints'.toJS) as JSArray?)?.toDart;
      if (endpoints == null) continue;
      for (final endpointAny in endpoints) {
        final endpoint = endpointAny as JSObject?;
        if (endpoint == null) continue;
        final direccion =
            (endpoint.getProperty('direction'.toJS) as JSString?)?.toDart;
        if (direccion == 'out') {
          final interfaceNumero =
              (interfaz.getProperty('interfaceNumber'.toJS) as JSNumber)
                  .toDartInt;
          final numero =
              (endpoint.getProperty('endpointNumber'.toJS) as JSNumber)
                  .toDartInt;
          return _EndpointSalida(
            interfaceNumero: interfaceNumero,
            numero: numero,
          );
        }
      }
    }
    return null;
  }
}

class _EndpointSalida {
  final int interfaceNumero;
  final int numero;
  _EndpointSalida({required this.interfaceNumero, required this.numero});
}
