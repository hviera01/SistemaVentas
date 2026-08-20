import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/face_id_storage.dart';
import '../../../../core/utils/webauthn.dart';
import '../../../../core/widgets/face_id_icon.dart';
import '../../providers/auth_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

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
    final credencial = await credencialFaceIdGuardada();
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
    // La activación de Face ID en sí ya NO se ofrece acá (ver Negocio >
    // "Face ID en este celular"): justo después de un login exitoso,
    // AuthGate reemplaza esta pantalla por AppShell casi de inmediato, y
    // cualquier await de por medio (SharedPreferences, WebAuthn) le daba
    // tiempo de sobra a esa transición para desmontar LoginScreen antes de
    // llegar a mostrar nada -por eso a veces "no pasaba nada" al loguearse-.
    // Negocio es una pantalla estable que no se cierra sola, así que ahí sí
    // se puede activar con confianza.
  }

  Future<void> _entrarConFaceId() async {
    final credencial = _credencialFaceId;
    if (credencial == null || _verificandoFaceId) return;
    setState(() => _verificandoFaceId = true);
    try {
      final verificado = await webAuthnVerificar(credencial);
      if (!verificado) return;
      final credenciales = await credencialesLoginGuardadas();
      if (credenciales == null) return;
      if (!mounted) return;
      await ref.read(authProvider.notifier).login(credenciales.codigo, credenciales.clave);
    } finally {
      if (mounted) setState(() => _verificandoFaceId = false);
    }
  }

  // Por si el celular no es el del usuario que activó Face ID acá antes (un
  // celular compartido, por ejemplo), o simplemente ya no lo quiere más:
  // borra lo guardado en este navegador y vuelve a mostrar el formulario
  // normal de código+clave.
  Future<void> _olvidarFaceId() async {
    await olvidarCredencialesFaceId();
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
                          CampoTecladoCompacto(
                            controller: _codigoController,
                            numerico: false,
                            titulo: 'Código de acceso',
                            child: TextField(
                            inputFormatters: [mayusculasInputFormatter],
                            autocorrect: false,
                            enableSuggestions: false,
                            controller: _codigoController,
                            keyboardType: _esWebMovil ? TextInputType.number : TextInputType.text,
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
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _claveController,
                            obscureText: _ocultarClave,
                            keyboardType: _esWebMovil ? TextInputType.number : TextInputType.text,
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
                                            : const FaceIdIcon(size: 26, color: Color(0xFF0F1B3D)),
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