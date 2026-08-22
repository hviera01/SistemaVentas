import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Diálogo compacto para agregar/quitar los códigos de color de una línea
/// del carrito (una línea puede llevar más de un código, ej. una pintura
/// mezclada con dos tintes). Mismo espíritu liviano que TecladoNumericoDialog
/// -pensado para una interacción rápida en caja, no un formulario largo- pero
/// como lista simple de códigos en vez de teclado numérico. Devuelve la
/// lista final al cerrar con "Listo" (o al tocar afuera/la X: en ambos casos
/// se conserva lo ya agregado/quitado, no hay "cancelar" que descarte todo).
class CodigosColorDialog extends StatefulWidget {
  final List<String> codigosIniciales;

  const CodigosColorDialog({super.key, required this.codigosIniciales});

  @override
  State<CodigosColorDialog> createState() => _CodigosColorDialogState();
}

class _CodigosColorDialogState extends State<CodigosColorDialog> {
  late List<String> _codigos;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _codigos = [...widget.codigosIniciales];
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _agregar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _codigos.add(texto);
      _controller.clear();
    });
    _focusNode.requestFocus();
  }

  void _quitar(int index) => setState(() => _codigos.removeAt(index));

  void _cerrar() => Navigator.pop(context, _codigos);

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width < 380 ? tamano.width - 48 : 320.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: ancho,
        constraints: const BoxConstraints(maxHeight: 480),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Código(s) de color', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _cerrar),
              ],
            ),
            const SizedBox(height: 4),
            Text('Esta línea puede llevar más de un código.', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            if (_codigos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Todavía no agregaste ningún código.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _codigos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                Expanded(child: Text(_codigos[i], style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600))),
                                InkWell(
                                  onTap: () => _quitar(i),
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 16, color: Color(0xFFC62828))),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CampoTecladoCompacto(
                    controller: _controller,
                    numerico: false,
                    onSubmitted: (_) => _agregar(),
                    child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ej. C-104',
                        hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: const Color(0xFFF2F3F7),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (_) => _agregar(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _agregar,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Agregar', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _cerrar,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Listo', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
