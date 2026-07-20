import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../data/escaneo_remoto_repository.dart';
import '../../../../core/utils/beep.dart';

/// Pantalla que abre el celular al escanear el QR que muestra la PC (ver
/// EscanearRemotoDialog): no pide iniciar sesión (se llega acá directo desde
/// main.dart cuando la URL trae `?escanear=`, antes de mostrar el login), y
/// manda cada código de barras leído a la sesión de Firestore que la PC está
/// escuchando en vivo. Se queda escaneando: no hay que volver a abrir la
/// cámara para cada producto.
class EscaneoRemotoScreen extends StatefulWidget {
  final String codigo;

  const EscaneoRemotoScreen({super.key, required this.codigo});

  @override
  State<EscaneoRemotoScreen> createState() => _EscaneoRemotoScreenState();
}

class _EscaneoRemotoScreenState extends State<EscaneoRemotoScreen> {
  final _repo = EscaneoRemotoRepository();
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  StreamSubscription<bool>? _suscripcionSesion;

  bool _verificando = true;
  bool _sesionValida = false;
  int _enviados = 0;
  String? _ultimoEnviado;

  bool _yaAvisoConectado = false;

  // Mientras está en true se ignora cualquier detección nueva: es la
  // pausa que sigue a cada envío (con beep + aviso grande en pantalla) para
  // que el usuario tenga tiempo de notar que ya se mandó ese código antes
  // de que la cámara pueda volver a leer el mismo (o el siguiente) sin que
  // se dé cuenta.
  bool _mostrandoConfirmacion = false;

  @override
  void initState() {
    super.initState();
    // Suscripción en vivo (no una comprobación única al abrir): la sesión
    // solo deja de existir cuando en la PC se toca "Finalizar escaneo" o se
    // cierra la pestaña de venta — no por cerrar la ventanita del QR — y
    // esto se entera al instante en cualquiera de esos casos, aunque la
    // cámara del celular siga abierta.
    _suscripcionSesion = _repo.existeSesionEnVivo(widget.codigo).listen((existe) {
      if (!mounted) return;
      setState(() {
        _sesionValida = existe;
        _verificando = false;
      });
      // Le avisa a la PC que el celular ya llegó a la cámara para que
      // pueda cerrar sola la ventanita del QR, sin que el usuario tenga
      // que hacerlo a mano.
      if (existe && !_yaAvisoConectado) {
        _yaAvisoConectado = true;
        _repo.marcarConectado(widget.codigo);
      }
    });
  }

  @override
  void dispose() {
    _suscripcionSesion?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _alDetectar(BarcodeCapture captura) {
    if (!_sesionValida || _mostrandoConfirmacion) return;
    final codigos = captura.barcodes;
    if (codigos.isEmpty) return;
    final valor = codigos.first.rawValue;
    if (valor == null || valor.isEmpty) return;

    _repo.enviarCodigo(widget.codigo, valor);
    reproducirBeep();
    setState(() {
      _enviados++;
      _ultimoEnviado = valor;
      _mostrandoConfirmacion = true;
    });
    // Mientras dure esta pausa se ignora cualquier otra detección (ver
    // _alDetectar de arriba): le da tiempo al usuario a ver el aviso "✓
    // Enviado" en pantalla y alejar el celular del código antes de que la
    // cámara pueda volver a leerlo (o leer el siguiente) sin darse cuenta.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _mostrandoConfirmacion = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    if (!_sesionValida) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  _enviados > 0
                      ? 'Se cerró la ventana de escaneo en la PC. Si querés seguir agregando productos, volvé a la PC y abrí el QR de nuevo.'
                      : 'Este código de escaneo ya no es válido. Volvé a la PC y abrí el QR de nuevo.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Escáner remoto', style: GoogleFonts.poppins(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, estado, child) {
                return Icon(estado.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off);
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _alDetectar,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorDetails?.message ?? 'No se pudo acceder a la cámara. Revisá los permisos del navegador.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: _mostrandoConfirmacion ? const Color(0xFF4CAF50) : Colors.white.withValues(alpha: 0.85), width: _mostrandoConfirmacion ? 4 : 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          // Aviso grande en el centro de la pantalla mientras dura la pausa
          // de confirmación (ver _alDetectar): junto con el beep, es lo que
          // evita que el usuario pase el mismo código dos veces sin notarlo.
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _mostrandoConfirmacion ? 1 : 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 34),
                      const SizedBox(height: 6),
                      Text('Código enviado', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      if (_ultimoEnviado != null)
                        Text(_ultimoEnviado!, style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)]),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Apuntá la cámara al código de barras', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (_ultimoEnviado != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(20)),
                      child: Text('✓ Enviado: $_ultimoEnviado', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 6),
                  Text('$_enviados código(s) enviado(s) a la caja', style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
