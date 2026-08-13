import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/webauthn.dart';
import '../../providers/auth_provider.dart';

// Claves de SharedPreferences donde queda el Face ID activado en este
// navegador (ver _ofrecerActivarFaceId/_entrarConFaceId). El código y la
// clave se guardan en base64 -no es cifrado real, solo evita que queden a
// simple vista en el storage- porque esta app no usa Firebase Auth: el
// login es código+clave contra Firestore (ver AuthRepository), así que no
// hay forma de "pasar" un login ya hecho sin volver a mandar esos dos
// datos. Quien lea el storage del navegador (por ejemplo con las
// herramientas de desarrollador) puede recuperarlos igual: Face ID acá
// evita que se vean tipeados cada vez, no reemplaza guardar algo sensible
// en un dispositivo que no sea de confianza.
const _prefsFaceIdCredencial = 'faceId_credencial';
const _prefsFaceIdCodigo = 'faceId_codigo';
const _prefsFaceIdClave = 'faceId_clave';

// Solo el navegador de un celular (no la PC, no la app de escritorio):
// ahí conviene el teclado numérico porque el código de acceso y la
// contraseña de esta app son siempre dígitos, y el teclado numérico ocupa
// menos pantalla que el completo.
bool get _esWebMovil =>
    kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _codigoController = TextEditingController();
  final _claveController = TextEditingController();
  bool _ocultarClave = true;

  // Id (base64url) del credencial de Face ID/Touch ID ya activado en este
  // navegador, o null si todavía no se activó acá. Se carga async en
  // initState porque SharedPreferences no es síncrono la primera vez.
  String? _credencialFaceId;
  bool _verificandoFaceId = false;

  @override
  void initState() {
    super.initState();
    if (_esWebMovil) _cargarCredencialFaceId();
  }

  Future<void> _cargarCredencialFaceId() async {
    final prefs = await SharedPreferences.getInstance();
    final credencial = prefs.getString(_prefsFaceIdCredencial);
    if (mounted) setState(() => _credencialFaceId = credencial);
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _claveController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    final codigo = _codigoController.text.trim();
    final clave = _claveController.text.trim();
    if (codigo.isEmpty || clave.isEmpty) return;
    await ref.read(authProvider.notifier).login(codigo, clave);
    if (!mounted) return;
    final usuario = ref.read(authProvider).usuario;
    // El login falló: el mensaje de error ya se muestra solo (ver
    // authState.error más abajo), acá no hay nada más que hacer.
    if (usuario == null) return;
    // Le avisa al navegador que el usuario ya terminó de "llenar el
    // formulario", que es la señal que usa para ofrecer guardar el usuario
    // (código de acceso, ver autofillHints más abajo) y la contraseña en su
    // gestor nativo (Guardacontraseñas de iOS, etc.) -sin esto, en una app
    // sin un <form> real como esta, ese aviso puede no llegar nunca-.
    TextInput.finishAutofillContext();
    if (_esWebMovil) await _ofrecerActivarFaceId(codigo: codigo, clave: clave);
  }

  // Justo después de un login manual exitoso (nunca antes: recién ahí se
  // tiene la clave en texto plano a mano, ver el comentario grande sobre
  // _prefsFaceIdCredencial), ofrece activar Face ID en este navegador si
  // el celular lo soporta y todavía no está activado acá. AuthGate
  // reemplaza esta pantalla por AppShell apenas cambia el estado de sesión,
  // pero el diálogo se muestra con el Navigator raíz (showDialog por
  // defecto), así que queda flotando por encima sin problema aunque la
  // pantalla de fondo cambie mientras tanto.
  Future<void> _ofrecerActivarFaceId({required String codigo, required String clave}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefsFaceIdCredencial) != null) return;
    final disponible = await webAuthnDisponible();
    if (!mounted) return;
    if (!disponible) {
      // Antes esto se salía en silencio: quien probara desde un modo donde
      // Face ID no está disponible (por ejemplo, la app agregada a Inicio
      // en iPhone, que en algunas versiones de iOS restringe WebAuthn a
      // Safari normal y no al modo "standalone") no tenía forma de saber
      // por qué nunca le salió la pregunta de activarlo.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face ID no está disponible en este modo/navegador')),
      );
      return;
    }

    // El pedido de Face ID (webAuthnRegistrar) se dispara DIRECTO desde el
    // toque en "Activar", sin ningún await antes: Safari en iPhone exige
    // que WebAuthn se pida dentro del mismo gesto del usuario (activación
    // transitoria). Si se pidiera después de cerrar este diálogo y volver
    // acá afuera, Safari lo rechaza en silencio -eso era lo que pasaba
    // antes: se tocaba "Activar" y no pasaba nada-. Por eso el diálogo
    // devuelve directamente el id del credencial (o null si canceló/falló)
    // en vez de solo un bool.
    final credencialId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Activar Face ID', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          '¿Querés entrar más rápido la próxima vez usando Face ID en este celular? Vas a poder desactivarlo desde la pantalla de login cuando quieras.',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Ahora no')),
          FilledButton(
            onPressed: () async {
              try {
                final id = await webAuthnRegistrar(usuarioId: codigo, usuarioNombre: codigo);
                if (dialogContext.mounted) Navigator.pop(dialogContext, id);
                if (id == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se pudo activar Face ID en este navegador')),
                  );
                }
              } catch (e) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo activar Face ID: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D)),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (credencialId == null || !mounted) return;

    await prefs.setString(_prefsFaceIdCredencial, credencialId);
    await prefs.setString(_prefsFaceIdCodigo, base64Encode(utf8.encode(codigo)));
    await prefs.setString(_prefsFaceIdClave, base64Encode(utf8.encode(clave)));
    setState(() => _credencialFaceId = credencialId);
  }

  Future<void> _entrarConFaceId() async {
    final credencial = _credencialFaceId;
    if (credencial == null || _verificandoFaceId) return;
    setState(() => _verificandoFaceId = true);
    try {
      final verificado = await webAuthnVerificar(credencial);
      if (!verificado) return;
      final prefs = await SharedPreferences.getInstance();
      final codigoGuardado = prefs.getString(_prefsFaceIdCodigo);
      final claveGuardada = prefs.getString(_prefsFaceIdClave);
      if (codigoGuardado == null || claveGuardada == null) return;
      final codigo = utf8.decode(base64Decode(codigoGuardado));
      final clave = utf8.decode(base64Decode(claveGuardada));
      if (!mounted) return;
      await ref.read(authProvider.notifier).login(codigo, clave);
    } finally {
      if (mounted) setState(() => _verificandoFaceId = false);
    }
  }

  // Por si el celular no es el del usuario que activó Face ID acá antes (un
  // celular compartido, por ejemplo), o simplemente ya no lo quiere más:
  // borra lo guardado en este navegador y vuelve a mostrar el formulario
  // normal de código+clave.
  Future<void> _olvidarFaceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsFaceIdCredencial);
    await prefs.remove(_prefsFaceIdCodigo);
    await prefs.remove(_prefsFaceIdClave);
    if (mounted) setState(() => _credencialFaceId = null);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tamano = MediaQuery.of(context).size;
    final anchoTarjeta = tamano.width < 480 ? tamano.width - 40 : 440.0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/fondo.jpg',
            fit: BoxFit.cover,
          ),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Image.asset(
              'assets/images/fondo.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A1230).withOpacity(0.55),
                  const Color(0xFF0A1230).withOpacity(0.80),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: anchoTarjeta,
                margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 52),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 60,
                            offset: const Offset(0, 30),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFF0F1B3D), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Image.asset(
                                  'assets/images/logo.jpg',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            'Bienvenido',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F1B3D),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ingresá con tu código de acceso',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 34),
                          AutofillGroup(
                            child: Column(
                              children: [
                                TextField(
                                  controller: _codigoController,
                                  keyboardType: _esWebMovil ? TextInputType.number : TextInputType.text,
                                  autofillHints: const [AutofillHints.username],
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: 'Código de acceso',
                                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                                    filled: true,
                                    fillColor: const Color(0xFFE8EAF0),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                TextField(
                                  controller: _claveController,
                                  obscureText: _ocultarClave,
                                  keyboardType: _esWebMovil ? TextInputType.number : TextInputType.text,
                                  autofillHints: const [AutofillHints.password],
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  onSubmitted: (_) => _iniciarSesion(),
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _ocultarClave ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _ocultarClave = !_ocultarClave),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFE8EAF0),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (authState.error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      authState.error!,
                                      style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: authState.cargando ? null : _iniciarSesion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F1B3D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              child: authState.cargando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                                    )
                                  : Text(
                                      'Ingresar',
                                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                            ),
                          ),
                          if (_esWebMovil && _credencialFaceId != null) ...[
                            const SizedBox(height: 22),
                            Center(
                              child: Column(
                                children: [
                                  Material(
                                    color: const Color(0xFFE8EAF0),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _verificandoFaceId ? null : _entrarConFaceId,
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: _verificandoFaceId
                                            ? const SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF0F1B3D)),
                                              )
                                            : const Icon(Icons.face_retouching_natural_outlined, size: 26, color: Color(0xFF0F1B3D)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Entrar con Face ID', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                                  TextButton(
                                    onPressed: _olvidarFaceId,
                                    child: Text(
                                      '¿No sos vos? Olvidar Face ID',
                                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'SUPERCOLOR · La decisión correcta',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}