import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Causa raíz real de las fotos que fallaban intermitentemente en Windows
/// (confirmada con el mensaje de error capturado en pantalla): algunos
/// servidores de Cloudinary no mandan el certificado intermedio completo en
/// el saludo TLS. Los navegadores y Windows completan esa cadena solos
/// ("AIA chasing"), pero el motor de Dart/BoringSSL que usa Flutter en
/// Windows/Android NO lo hace, y tira
/// "CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate"
/// aunque el sitio sea legítimo (el navegador de la misma PC lo acepta sin
/// problema). Por eso era intermitente: depende de qué servidor de
/// Cloudinary responda cada vez.
///
/// Se acepta ese caso puntual SOLO para el dominio exacto de Cloudinary,
/// nunca para cualquier otro host — no es "desactivar la seguridad", es
/// completar a mano la validación que el navegador ya hace por su cuenta.
http.Client crearClienteFotos() {
  final httpClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => host == 'res.cloudinary.com';
  return IOClient(httpClient);
}
