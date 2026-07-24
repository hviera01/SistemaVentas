import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'negocio_model.dart';

class NegocioRepository {
  final _doc = FirebaseFirestore.instance.collection('configuracion').doc('negocio');

  // Cache en memoria de la última lectura exitosa de `obtenerNegocioActual`.
  // Antes cada acción puntual (pedir clave especial, abrir ajuste de stock,
  // generar el código de barras, etc.) esperaba una ida y vuelta nueva a
  // Firestore, y en la primera vez de la sesión esa ida y vuelta podía tardar
  // varios segundos sin que la pantalla mostrara nada mientras tanto — daba
  // la sensación de que el toque no había hecho nada. Con este cache, una
  // vez que se obtiene la configuración una vez (por ejemplo, justo después
  // del login, ver `AuthNotifier.login`), el resto de acciones de la sesión
  // la reciben al instante.
  static NegocioModel? _cache;
  static DateTime? _cacheFecha;
  // 10 minutos: no hay riesgo de quedar con datos viejos porque
  // `_invalidarCache()` se llama apenas se guarda un cambio real; este plazo
  // solo evita repetir la ida y vuelta a Firestore en acciones puntuales
  // (editar producto, ajustar stock, etc.) que antes volvían a pedirla cada
  // 30 segundos aunque nada hubiera cambiado.
  static const _vigenciaCache = Duration(minutes: 10);

  String hashClave(String clave) {
    return sha256.convert(utf8.encode(clave)).toString();
  }

  Stream<NegocioModel> obtenerNegocio() {
    return _doc.snapshots().map((snap) => NegocioModel.fromMap(snap.data()));
  }

  /// Lectura única (no suscripción en vivo) de la configuración del negocio.
  /// Se usa antes de acciones puntuales (registrar venta, imprimir, pedir
  /// clave especial) en vez de `negocioStreamProvider.future`: ese depende
  /// de que el listener en vivo llegue a emitir su primer valor, lo cual en
  /// algunas redes (sobre todo en la versión web) puede tardar mucho o no
  /// llegar nunca y dejaba la acción "cargando" para siempre. Acá, si no
  /// responde rápido, se sigue con la configuración por defecto en vez de
  /// trabar la acción.
  Future<NegocioModel> obtenerNegocioActual() async {
    final cache = _cache;
    final cacheFecha = _cacheFecha;
    if (cache != null && cacheFecha != null && DateTime.now().difference(cacheFecha) < _vigenciaCache) {
      return cache;
    }
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 8));
      final negocio = NegocioModel.fromMap(snap.data());
      _cache = negocio;
      _cacheFecha = DateTime.now();
      return negocio;
    } catch (_) {
      return cache ?? const NegocioModel();
    }
  }

  /// Invalida el cache de [obtenerNegocioActual]: se llama luego de guardar
  /// cualquier cambio a la configuración para que el resto de la sesión no
  /// siga usando datos viejos (permisos, clave especial, etc.) hasta que
  /// venza el cache por su cuenta.
  void _invalidarCache() {
    _cache = null;
    _cacheFecha = null;
  }

  Future<void> actualizarDatosGenerales({
    required String nombre,
    required String correo,
    required String rtn,
    required String cai,
    required String direccion,
    required String telefono,
    required String eslogan,
    required String rangoPrefijo,
    required String rangoDesde,
    required String rangoHasta,
    required DateTime? fechaLimiteEmision,
  }) async {
    await _doc.set({
      'nombre': nombre,
      'correo': correo,
      'rtn': rtn,
      'cai': cai,
      'direccion': direccion,
      'telefono': telefono,
      'eslogan': eslogan,
      'rangoPrefijo': rangoPrefijo,
      'rangoDesde': rangoDesde,
      'rangoHasta': rangoHasta,
      'fechaLimiteEmision': fechaLimiteEmision != null ? Timestamp.fromDate(fechaLimiteEmision) : null,
    }, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> guardarLogoColor(Uint8List bytes) async {
    await _doc.set({'logoColorBase64': base64Encode(bytes)}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> guardarLogoBn(Uint8List bytes) async {
    await _doc.set({'logoBnBase64': base64Encode(bytes)}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> actualizarPermisos(Map<String, bool> permisos) async {
    await _doc.set({'permisos': permisos}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> establecerClave(String clave) async {
    await _doc.set({'claveEspecialHash': hashClave(clave)}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> quitarClave() async {
    await _doc.set({'claveEspecialHash': ''}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> actualizarImpresoraTermica(String url, String nombre) async {
    await _doc.set({'impresoraTermicaUrl': url, 'impresoraTermicaNombre': nombre}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> actualizarImpresoraEtiquetas(String url, String nombre) async {
    await _doc.set({'impresoraEtiquetasUrl': url, 'impresoraEtiquetasNombre': nombre}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> establecerFacturaImprimirCopia(bool valor) async {
    await _doc.set({'facturaImprimirCopia': valor}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> establecerFacturaPreciosConIsv(bool valor) async {
    await _doc.set({'facturaPreciosConIsv': valor}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> establecerModoImpresion(String modo) async {
    await _doc.set({'modoImpresion': modo}, SetOptions(merge: true));
    _invalidarCache();
  }

  Future<void> actualizarImpresoraRed(String ip, int puerto) async {
    await _doc.set({'impresoraRedIp': ip, 'impresoraRedPuerto': puerto}, SetOptions(merge: true));
    _invalidarCache();
  }
}
