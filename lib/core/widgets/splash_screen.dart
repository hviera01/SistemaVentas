import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Pantalla de bienvenida con el logo, mostrada brevemente antes de
/// [siguiente] (normalmente AuthGate) mientras arranca la app. Es una
/// pantalla Flutter pura (no nativa), así que se ve igual en Android,
/// Windows y Web sin tocar la configuración nativa de cada plataforma.
class SplashScreen extends StatefulWidget {
  final Widget siguiente;

  const SplashScreen({super.key, required this.siguiente});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;
  late final Animation<double> _opacidad;
  late final Animation<double> _escala;

  @override
  void initState() {
    super.initState();
    _controlador = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _opacidad = CurvedAnimation(parent: _controlador, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    _escala = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _controlador, curve: Curves.easeOutBack));
    _controlador.forward();
    _irASiguiente();
  }

  Future<void> _irASiguiente() async {
    // Duración total pensada para que la animación se alcance a ver
    // completa incluso en equipos rápidos, sin sentirse una espera larga.
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget.siguiente,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B3D),
      body: Center(
        child: AnimatedBuilder(
          animation: _controlador,
          builder: (context, child) {
            return Opacity(
              opacity: _opacidad.value,
              child: Transform.scale(scale: _escala.value, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.superficie,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SUPERCOLOR',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                'La decisión correcta',
                style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.7), fontSize: 12, letterSpacing: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
