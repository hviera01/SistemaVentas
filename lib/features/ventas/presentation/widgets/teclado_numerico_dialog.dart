import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Teclado numérico en pantalla para cambiar cantidad/precio/descuento a
/// clics de mouse, pensado para escritorio (Windows y web en computadora):
/// escribir con el teclado físico y darle Enter directo en el campo sigue
/// funcionando igual que siempre, esto es solo una forma alternativa para
/// quien prefiera usar el mouse. Devuelve el texto tal como quedó tecleado
/// (o null si se cancela) para no perder precisión con conversiones de ida
/// y vuelta a double.
class TecladoNumericoDialog extends StatefulWidget {
  final String titulo;
  final String valorInicial;

  const TecladoNumericoDialog({super.key, required this.titulo, required this.valorInicial});

  @override
  State<TecladoNumericoDialog> createState() => _TecladoNumericoDialogState();
}

class _TecladoNumericoDialogState extends State<TecladoNumericoDialog> {
  late String _texto;

  @override
  void initState() {
    super.initState();
    final inicial = widget.valorInicial.trim();
    _texto = inicial.isEmpty ? '0' : inicial;
  }

  void _tocarTecla(String tecla) {
    setState(() {
      if (tecla == '.' && _texto.contains('.')) return;
      if (_texto == '0' && tecla != '.') {
        _texto = tecla;
      } else {
        _texto = _texto + tecla;
      }
    });
  }

  void _borrar() {
    setState(() {
      if (_texto.length <= 1) {
        _texto = '0';
      } else {
        _texto = _texto.substring(0, _texto.length - 1);
      }
    });
  }

  void _limpiar() => setState(() => _texto = '0');

  void _confirmar() {
    if (double.tryParse(_texto) == null) return;
    Navigator.pop(context, _texto);
  }

  Widget _tecla(String etiqueta, {VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AspectRatio(
          aspectRatio: 1.3,
          child: Material(
            color: const Color(0xFFE8EAF0),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap ?? () => _tocarTecla(etiqueta),
              child: Center(
                child: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.titulo, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
              child: Text(_texto, textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Row(children: [_tecla('7'), _tecla('8'), _tecla('9')]),
            Row(children: [_tecla('4'), _tecla('5'), _tecla('6')]),
            Row(children: [_tecla('1'), _tecla('2'), _tecla('3')]),
            Row(children: [_tecla('.'), _tecla('0'), _tecla('⌫', onTap: _borrar)]),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _limpiar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A1A),
                      side: const BorderSide(color: Color(0xFFB6BCC7)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Borrar todo', style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _confirmar,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text('Listo', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
