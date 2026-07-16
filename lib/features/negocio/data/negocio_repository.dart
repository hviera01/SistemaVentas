import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'negocio_model.dart';

class NegocioRepository {
  final _doc = FirebaseFirestore.instance.collection('configuracion').doc('negocio');

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
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 8));
      return NegocioModel.fromMap(snap.data());
    } catch (_) {
      return const NegocioModel();
    }
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
  }

  Future<void> guardarLogoColor(Uint8List bytes) async {
    await _doc.set({'logoColorBase64': base64Encode(bytes)}, SetOptions(merge: true));
  }

  Future<void> guardarLogoBn(Uint8List bytes) async {
    await _doc.set({'logoBnBase64': base64Encode(bytes)}, SetOptions(merge: true));
  }

  Future<void> actualizarPermisos(Map<String, bool> permisos) async {
    await _doc.set({'permisos': permisos}, SetOptions(merge: true));
  }

  Future<void> establecerClave(String clave) async {
    await _doc.set({'claveEspecialHash': hashClave(clave)}, SetOptions(merge: true));
  }

  Future<void> quitarClave() async {
    await _doc.set({'claveEspecialHash': ''}, SetOptions(merge: true));
  }

  Future<void> actualizarImpresoraTermica(String url, String nombre) async {
    await _doc.set({'impresoraTermicaUrl': url, 'impresoraTermicaNombre': nombre}, SetOptions(merge: true));
  }

  Future<void> actualizarImpresoraEtiquetas(String url, String nombre) async {
    await _doc.set({'impresoraEtiquetasUrl': url, 'impresoraEtiquetasNombre': nombre}, SetOptions(merge: true));
  }
}
