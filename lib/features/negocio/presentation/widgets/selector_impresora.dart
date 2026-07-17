import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

/// El plugin `printing` solo implementa listado de impresoras del sistema
/// operativo en Windows/macOS/Linux; en Android/iOS/web no hay method
/// channel para esto, así que ni se intenta.
bool get _listadoImpresorasDisponible =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class SelectorImpresora extends StatefulWidget {
  final String titulo;
  final String urlActual;
  final String nombreActual;
  final void Function(String url, String nombre) onSeleccionar;

  const SelectorImpresora({
    super.key,
    required this.titulo,
    required this.urlActual,
    required this.nombreActual,
    required this.onSeleccionar,
  });

  @override
  State<SelectorImpresora> createState() => _SelectorImpresoraState();
}

class _SelectorImpresoraState extends State<SelectorImpresora> {
  List<Printer> _impresoras = [];
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarImpresoras();
  }

  Future<void> _cargarImpresoras() async {
    if (!_listadoImpresorasDisponible) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await Printing.listPrinters();
      if (mounted) setState(() => _impresoras = lista);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo obtener la lista de impresoras');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneActual = widget.urlActual.isNotEmpty;
    final opciones = [..._impresoras];
    if (tieneActual && !opciones.any((p) => p.url == widget.urlActual)) {
      opciones.insert(0, Printer(url: widget.urlActual, name: '${widget.nombreActual} (desconectada)', isAvailable: false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)))),
            if (_listadoImpresorasDisponible)
              IconButton(
                tooltip: 'Actualizar lista',
                onPressed: _cargando ? null : _cargarImpresoras,
                icon: _cargando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: Text('Sin impresora seleccionada', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
              value: tieneActual ? widget.urlActual : null,
              style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
              items: opciones.map((p) => DropdownMenuItem(value: p.url, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (url) {
                if (url == null) return;
                final impresora = opciones.firstWhere((p) => p.url == url);
                widget.onSeleccionar(impresora.url, impresora.name);
              },
            ),
          ),
        ),
        if (!_listadoImpresorasDisponible) ...[
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'No se puede elegir acá desde el navegador (limitación del navegador, no un error). No hace falta: si activás "Imprimir directo, sin preguntar", el navegador abre su propio diálogo de impresión con todas las impresoras del equipo.'
                : 'No disponible en este dispositivo. En el celular usá la impresora de red (más abajo) en vez de esta lista.',
            style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.red.shade700)),
        ] else if (!_cargando && _impresoras.isEmpty) ...[
          const SizedBox(height: 4),
          Text('No se detectaron impresoras en este equipo', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
        ],
      ],
    );
  }
}
