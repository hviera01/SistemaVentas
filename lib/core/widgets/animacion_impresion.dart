import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'exito_transaccion_overlay.dart';

class AnimacionImpresion {
  AnimacionImpresion._();

  static final ValueNotifier<int> _disparo = ValueNotifier<int>(0);

  static void mostrar() => _disparo.value++;
}

class AnimacionImpresionHost extends StatefulWidget {
  final Widget child;

  const AnimacionImpresionHost({super.key, required this.child});

  @override
  State<AnimacionImpresionHost> createState() => _AnimacionImpresionHostState();
}

/// El check verde y la animación de impresión corren cada uno por su lado
/// (su propio controlador) -pedido del dueño-: si al terminar una venta
/// también se imprime, la impresora sale A LA PAR del check (al costado, o
/// debajo en pantallas angostas) en vez de una tras otra a las apuradas. Si
/// no hay impresión, sale solo el check como siempre.
class _AnimacionImpresionHostState extends State<AnimacionImpresionHost>
    with TickerProviderStateMixin {
  static const _duracionImpresion = Duration(milliseconds: 1500);
  // Con 1100ms el check quedaba bien visible apenas ~0.6s y no se
  // alcanzaba a leer -pedido del dueño-: ahora queda quieto ~1.7s (las
  // proporciones de entrada/salida en EscenaExito están ajustadas a esto).
  static const _duracionExito = Duration(milliseconds: 2200);
  static const _maxColaExito = 3;

  late final AnimationController _ctrlExito;
  late final AnimationController _ctrlImpresion;
  // Mensajes de éxito distintos que llegan seguidos se muestran uno por
  // uno (cola); la impresión, en cambio, a lo sumo deja una pendiente.
  final List<String> _colaExito = [];
  String? _exitoActual;
  int _turnoExito = 0;
  bool _imprimiendo = false;
  bool _impresionPendiente = false;

  @override
  void initState() {
    super.initState();
    _ctrlExito = AnimationController(vsync: this, duration: _duracionExito)
      ..addStatusListener((estado) {
        if (estado == AnimationStatus.completed) _siguienteExito();
      });
    _ctrlImpresion =
        AnimationController(vsync: this, duration: _duracionImpresion)
          ..addStatusListener((estado) {
            if (estado == AnimationStatus.completed) _finImpresion();
          });
    AnimacionImpresion._disparo.addListener(_alImprimir);
    ExitoTransaccion.eventos.addListener(_alExito);
  }

  @override
  void dispose() {
    AnimacionImpresion._disparo.removeListener(_alImprimir);
    ExitoTransaccion.eventos.removeListener(_alExito);
    _ctrlExito.dispose();
    _ctrlImpresion.dispose();
    super.dispose();
  }

  void _alImprimir() {
    if (!mounted) return;
    if (_imprimiendo) {
      // Varias impresiones casi juntas se muestran como una sola.
      if (_ctrlImpresion.value >= 0.7) _impresionPendiente = true;
      return;
    }
    setState(() => _imprimiendo = true);
    _ctrlImpresion.value = 0;
    _arrancarTrasFrameLiviano(_ctrlImpresion, () => _imprimiendo);
  }

  // Cuando se pide un efecto, casi siempre la pantalla de abajo acaba de
  // limpiarse o cerrarse y se está reconstruyendo: arrancar la animación en
  // ese mismo frame hace que su entrada caiga justo en el frame más pesado
  // y se vea trabada. Se espera a que ese frame termine (y uno más) y se
  // arranca desde cero ya con el hilo liviano.
  Future<void> _arrancarTrasFrameLiviano(
    AnimationController ctrl,
    bool Function() sigueVigente,
  ) async {
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || !sigueVigente()) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || !sigueVigente()) return;
    ctrl.forward(from: 0);
  }

  void _finImpresion() {
    if (!mounted) return;
    if (_impresionPendiente) {
      _impresionPendiente = false;
      _ctrlImpresion.forward(from: 0);
      return;
    }
    setState(() => _imprimiendo = false);
  }

  void _alExito() {
    if (!mounted) return;
    final evento = ExitoTransaccion.eventos.value;
    if (evento == null) return;
    if (_exitoActual == evento.mensaje && _ctrlExito.value < 0.6) return;
    if (_colaExito.contains(evento.mensaje)) return;
    if (_colaExito.length >= _maxColaExito) return;
    _colaExito.add(evento.mensaje);
    if (_exitoActual == null) _siguienteExito();
  }

  void _siguienteExito() {
    if (!mounted) return;
    if (_colaExito.isEmpty) {
      setState(() => _exitoActual = null);
      return;
    }
    final mensaje = _colaExito.removeAt(0);
    final turno = ++_turnoExito;
    setState(() => _exitoActual = mensaje);
    _ctrlExito.value = 0;
    _arrancarTrasFrameLiviano(_ctrlExito, () => turno == _turnoExito);
  }

  @override
  Widget build(BuildContext context) {
    final mensaje = _exitoActual;
    final imprimiendo = _imprimiendo;
    return Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(child: widget.child)),
        if (mensaje != null || imprimiendo)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Builder(
                  builder: (context) {
                    return Stack(
                      children: [
                        // Oscurece el fondo solo mientras se ve la impresora
                        // (el check solo, como siempre, no oscurece nada).
                        if (imprimiendo)
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _ctrlImpresion,
                              builder: (context, _) => ColoredBox(
                                color: Color.fromRGBO(
                                  0,
                                  0,
                                  0,
                                  0.38 *
                                      _EscenaImpresion.opacidad(
                                        _ctrlImpresion.value,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, restricciones) {
                            final enFila = restricciones.maxWidth >= 640;
                            final piezas = <Widget>[
                              if (mensaje != null)
                                EscenaExito(
                                  animacion: _ctrlExito,
                                  mensaje: mensaje,
                                ),
                              // AnimatedSize: al aparecer la impresora, el
                              // check se corre suave para hacerle lugar en vez
                              // de saltar de golpe.
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: imprimiendo
                                    ? Padding(
                                        padding: mensaje == null
                                            ? EdgeInsets.zero
                                            : (enFila
                                                  ? const EdgeInsets.only(
                                                      left: 36,
                                                    )
                                                  : const EdgeInsets.only(
                                                      top: 20,
                                                    )),
                                        child: RepaintBoundary(
                                          child: AnimatedBuilder(
                                            animation: _ctrlImpresion,
                                            builder: (context, _) =>
                                                _EscenaImpresion(
                                                  t: _ctrlImpresion.value,
                                                ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ];
                            return Center(
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                scrollDirection: enFila
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                child: Flex(
                                  direction: enFila
                                      ? Axis.horizontal
                                      : Axis.vertical,
                                  mainAxisSize: MainAxisSize.min,
                                  children: piezas,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EscenaImpresion extends StatelessWidget {
  final double t;

  const _EscenaImpresion({required this.t});

  static double opacidad(double t) {
    final entrada = _tramo(t, 0.0, 0.14, Curves.easeOutCubic);
    final salida = _tramo(t, 0.86, 1.0, Curves.easeIn);
    return (entrada * (1 - salida)).clamp(0.0, 1.0);
  }

  static double _tramo(
    double t,
    double desde,
    double hasta, [
    Curve curva = Curves.linear,
  ]) {
    if (t <= desde) return 0;
    if (t >= hasta) return 1;
    return curva.transform((t - desde) / (hasta - desde));
  }

  @override
  Widget build(BuildContext context) {
    final entrada = _tramo(t, 0.0, 0.14, Curves.easeOutCubic);
    final salida = _tramo(t, 0.86, 1.0, Curves.easeIn);
    final avance = _tramo(t, 0.1, 0.68, Curves.easeInOutCubic);
    final listo = _tramo(t, 0.68, 0.82, Curves.easeOutBack);
    final opacidad = (entrada * (1 - salida)).clamp(0.0, 1.0);
    final escala = 0.88 + 0.12 * entrada;

    // El fondo oscuro y el centrado los pone el host (ver
    // _AnimacionImpresionHostState.build), para poder ubicarla al lado del
    // check verde.
    return Opacity(
      opacity: opacidad,
      child: Transform.translate(
        offset: Offset(0, salida * 14),
        child: Transform.scale(
          scale: escala,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listo > 0.35 ? 'Listo' : 'Imprimiendo…',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 220,
                  height: 270,
                  child: CustomPaint(
                    painter: _ImpresoraPainter(
                      avance: avance,
                      listo: listo,
                      tiempo: t,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImpresoraPainter extends CustomPainter {
  final double avance;
  final double listo;
  final double tiempo;

  _ImpresoraPainter({
    required this.avance,
    required this.listo,
    required this.tiempo,
  });

  static const _cuerpo = Color(0xFF2E3138);
  static const _cuerpoAlto = Color(0xFF40444D);
  static const _ranura = Color(0xFF0E0F12);

  @override
  void paint(Canvas canvas, Size size) {
    final centroX = size.width / 2;
    const cuerpoTop = 22.0;
    const cuerpoBottom = 104.0;
    const ranuraY = 90.0;

    final bandeja = RRect.fromRectAndRadius(
      Rect.fromLTRB(centroX - 48, 4, centroX + 48, cuerpoTop + 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(bandeja, Paint()..color = const Color(0xFFDDE0E6));
    canvas.drawRect(
      Rect.fromLTWH(centroX - 36, 11, 72, 2.5),
      Paint()..color = const Color(0xFFB4B8C0),
    );

    final largo = 150.0 * avance;
    if (largo > 0) _dibujarPapel(canvas, centroX, ranuraY, largo);

    final cuerpo = RRect.fromRectAndRadius(
      Rect.fromLTRB(8, cuerpoTop, size.width - 8, cuerpoBottom),
      const Radius.circular(18),
    );
    canvas.drawShadow(Path()..addRRect(cuerpo), Colors.black, 6, true);
    canvas.drawRRect(cuerpo, Paint()..color = _cuerpo);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(8, cuerpoTop, size.width - 8, cuerpoTop + 26),
        const Radius.circular(18),
      ),
      Paint()..color = _cuerpoAlto,
    );
    canvas.drawRect(
      Rect.fromLTRB(8, cuerpoTop + 18, size.width - 8, cuerpoTop + 26),
      Paint()..color = _cuerpo,
    );
    canvas.drawRRect(
      cuerpo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF50555F),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(centroX - 78, ranuraY - 4, centroX + 78, ranuraY + 5),
        const Radius.circular(4),
      ),
      Paint()..color = _ranura,
    );

    final brillo = 0.45 + 0.55 * math.sin(tiempo * math.pi * 16).abs();
    final led = Offset(size.width - 34, cuerpoTop + 38);
    canvas.drawCircle(
      led,
      7,
      Paint()
        ..color = const Color(0xFFE53935).withValues(alpha: 0.22 * brillo)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      led,
      3.4,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFE53935),
          const Color(0xFF66BB6A),
          listo,
        )!.withValues(alpha: listo > 0 ? 1 : brillo),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(28.0 + i * 13, cuerpoTop + 38),
        2.6,
        Paint()..color = const Color(0xFF5B606B),
      );
    }
  }

  void _dibujarPapel(
    Canvas canvas,
    double centroX,
    double ranuraY,
    double largo,
  ) {
    const ancho = 128.0;
    final izq = centroX - ancho / 2;
    final der = centroX + ancho / 2;
    final top = ranuraY;
    final fondo = ranuraY + largo;

    const diente = 8.0;
    const profundidad = 5.0;
    final papel = Path()
      ..moveTo(izq, top)
      ..lineTo(der, top)
      ..lineTo(der, fondo);
    final dientes = (ancho / diente).round();
    for (var i = 0; i < dientes; i++) {
      final x = der - (i + 0.5) * diente;
      papel.lineTo(x, fondo + profundidad);
      papel.lineTo(der - (i + 1) * diente, fondo);
    }
    papel.close();

    canvas.drawShadow(papel, Colors.black, 4, false);
    canvas.drawPath(papel, Paint()..color = const Color(0xFFFDFDFD));

    canvas.save();
    canvas.clipPath(papel);

    final tinta = Paint()..color = const Color(0xFF9096A2);
    final tintaFuerte = Paint()..color = const Color(0xFF3A3E46);
    final tintaRoja = Paint()..color = const Color(0xFFE53935);

    void barra(double y, double x0, double w, Paint p, [double h = 3.4]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(izq + x0, y, w, h),
          Radius.circular(h / 2),
        ),
        p,
      );
    }

    barra(ranuraY + 16, 34, 60, tintaFuerte, 5);
    barra(ranuraY + 28, 44, 40, tinta, 3);
    const filas = [
      [14.0, 74.0, 22.0],
      [14.0, 58.0, 22.0],
      [14.0, 82.0, 22.0],
      [14.0, 50.0, 22.0],
    ];
    for (var i = 0; i < filas.length; i++) {
      final y = ranuraY + 46 + i * 13;
      barra(y, filas[i][0], filas[i][1], tinta);
      barra(y, ancho - 14 - filas[i][2], filas[i][2], tinta);
    }
    final yTotal = ranuraY + 46 + filas.length * 13 + 4;
    canvas.drawRect(
      Rect.fromLTWH(izq + 14, yTotal - 5, ancho - 28, 1.2),
      tinta,
    );
    barra(yTotal + 5, 14, 34, tintaFuerte, 4.4);
    barra(yTotal + 5, ancho - 14 - 38, 38, tintaRoja, 4.4);
    canvas.restore();

    if (listo > 0) {
      final centro = Offset(centroX, ranuraY + 62);
      final radio = 22 * listo.clamp(0.0, 1.15);
      canvas.drawCircle(
        centro,
        radio,
        Paint()..color = const Color(0xFF43A047),
      );
      final trazo = Path()
        ..moveTo(centro.dx - 9, centro.dy + 0.5)
        ..lineTo(centro.dx - 3, centro.dy + 7)
        ..lineTo(centro.dx + 10, centro.dy - 7);
      final metrica = trazo.computeMetrics().first;
      canvas.drawPath(
        metrica.extractPath(
          0,
          metrica.length * ((listo - 0.35) / 0.65).clamp(0.0, 1.0),
        ),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ImpresoraPainter old) =>
      old.avance != avance || old.listo != listo || old.tiempo != tiempo;
}
