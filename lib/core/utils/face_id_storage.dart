import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Claves de SharedPreferences donde queda el Face ID activado en este
// navegador (ver LoginScreen y NegocioScreen: la activación puede pasar
// desde cualquiera de las dos). El código y la clave se guardan en base64
// -no es cifrado real, solo evita que queden a simple vista en el storage-
// porque esta app no usa Firebase Auth: el login es código+clave contra
// Firestore (ver AuthRepository), así que no hay forma de "pasar" un login
// ya hecho sin volver a mandar esos dos datos. Quien lea el storage del
// navegador (por ejemplo con las herramientas de desarrollador) puede
// recuperarlos igual: Face ID acá evita que se vean tipeados cada vez, no
// reemplaza guardar algo sensible en un dispositivo que no sea de
// confianza.
const prefsFaceIdCredencial = 'faceId_credencial';
const prefsFaceIdCodigo = 'faceId_codigo';
const prefsFaceIdClave = 'faceId_clave';

Future<void> guardarCredencialesFaceId({
  required String credencialId,
  required String codigo,
  required String clave,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsFaceIdCredencial, credencialId);
  await prefs.setString(prefsFaceIdCodigo, base64Encode(utf8.encode(codigo)));
  await prefs.setString(prefsFaceIdClave, base64Encode(utf8.encode(clave)));
}

Future<void> olvidarCredencialesFaceId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(prefsFaceIdCredencial);
  await prefs.remove(prefsFaceIdCodigo);
  await prefs.remove(prefsFaceIdClave);
}

Future<String?> credencialFaceIdGuardada() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(prefsFaceIdCredencial);
}

class CredencialesLogin {
  final String codigo;
  final String clave;
  CredencialesLogin({required this.codigo, required this.clave});
}

Future<CredencialesLogin?> credencialesLoginGuardadas() async {
  final prefs = await SharedPreferences.getInstance();
  final codigo = prefs.getString(prefsFaceIdCodigo);
  final clave = prefs.getString(prefsFaceIdClave);
  if (codigo == null || clave == null) return null;
  return CredencialesLogin(codigo: utf8.decode(base64Decode(codigo)), clave: utf8.decode(base64Decode(clave)));
}
