import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/actualizacion_service.dart';
import '../version_app.dart';

/// Diálogo central que avisa que hay una versión nueva publicada. Se abre
/// solo (al iniciar la app, ver AppShell) o a mano desde "Buscar
/// actualizaciones" en el menú (ver SideMenu). "Después" solo cierra el
/// diálogo: no queda nada guardado, así que la próxima vez que se abra la
/// app (o se busque a mano) vuelve a preguntar si la instalada sigue sin
/// ser la más nueva -a propósito, para no complicar el flujo con "no
/// preguntar de nuevo" cuando en este negocio conviene que quede siempre al
/// día-.
Future<void> mostrarDialogoActualizacion(
  BuildContext context,
  ActualizacionDisponible actualizacion,
) {
  return showDialog(
    useRootNavigator: false,
    context: context,
    builder: (context) => PopScope(
      canPop: false,
      child: _ActualizacionDialog(actualizacion: actualizacion),
    ),
  );
}

class _ActualizacionDialog extends StatefulWidget {
  final ActualizacionDisponible actualizacion;
  const _ActualizacionDialog({required this.actualizacion});

  @override
  State<_ActualizacionDialog> createState() => _ActualizacionDialogState();
}

class _ActualizacionDialogState extends State<_ActualizacionDialog> {
  bool _descargando = false;
  double _progreso = 0;
  String? _error;

  Future<void> _actualizar() async {
    setState(() {
      _descargando = true;
      _error = null;
    });
    try {
      await ActualizacionService.descargarEInstalar(widget.actualizacion, (p) {
        if (mounted) setState(() => _progreso = p);
      });
      // Si el await termina y seguimos acá, algo falló: descargarEInstalar
      // cierra la app (exit) apenas el instalador queda lanzado.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _descargando = false;
        _error =
            'No se pudo descargar la actualización. Probá de nuevo más tarde.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Actualización disponible',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una nueva versión (v${widget.actualizacion.version}) disponible para instalar.',
              style: GoogleFonts.poppins(fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Tenés instalada la versión v$versionApp.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (widget.actualizacion.notas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.actualizacion.notas,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (_descargando) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progreso > 0 ? _progreso : null),
              const SizedBox(height: 6),
              Text(
                'Descargando...',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: _descargando
          ? const []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Después', style: GoogleFonts.poppins()),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E9E5A),
                ),
                onPressed: _actualizar,
                child: Text('Actualizar ahora', style: GoogleFonts.poppins()),
              ),
            ],
    );
  }
}
