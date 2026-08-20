import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Teclado de texto en pantalla, chico y con letras y números juntos (a
/// diferencia del teclado nativo del sistema, que en tablet ocupa media
/// pantalla) -ver CampoTecladoCompacto, que es quien lo abre. Mismo espíritu
/// que TecladoNumericoDialog: funciona a toques o con teclado físico
/// (Backspace y Enter para confirmar). Como toda la app fuerza mayúsculas
/// (ver MayusculasInputFormatter), acá no hace falta tecla de mayús/minús:
/// todo entra siempre en mayúsculas.
class TecladoTextoDialog extends StatefulWidget {
  final String titulo;
  final String valorInicial;

  const TecladoTextoDialog({super.key, required this.titulo, required this.valorInicial});

  @override
  State<TecladoTextoDialog> createState() => _TecladoTextoDialogState();
}

class _TecladoTextoDialogState extends State<TecladoTextoDialog> {
  late String _texto;
  final _focusNode = FocusNode();

  static const _filaDigitos = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _filaQ = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const _filaA = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  static const _filaZ = ['Z', 'X', 'C', 'V', 'B', 'N', 'M', '-', '.', '/'];

  @override
  void initState() {
    super.initState();
    _texto = widget.valorInicial;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _escribir(String caracter) => setState(() => _texto += caracter);

  void _espacio() => setState(() => _texto += ' ');

  void _borrar() {
    if (_texto.isEmpty) return;
    setState(() => _texto = _texto.substring(0, _texto.length - 1));
  }

  void _limpiar() => setState(() => _texto = '');

  void _confirmar() => Navigator.pop(context, _texto);

  KeyEventResult _manejarTeclaFisica(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final tecla = event.logicalKey;
    if (tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) {
      _confirmar();
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.backspace) {
      _borrar();
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    final caracter = event.character;
    if (caracter != null && caracter.isNotEmpty && caracter.length == 1) {
      _escribir(caracter.toUpperCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _tecla(String etiqueta, {VoidCallback? onTap, int flex = 1, Color? color}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: AspectRatio(
          aspectRatio: flex == 1 ? 0.9 : 3.2,
          child: Material(
            color: color ?? const Color(0xFFE8EAF0),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap ?? () => _escribir(etiqueta),
              child: Center(
                child: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _manejarTeclaFisica(node, event),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(18),
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
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _texto.isEmpty ? ' ' : _texto,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [for (final d in _filaDigitos) _tecla(d), _tecla('⌫', onTap: _borrar, color: const Color(0xFFFCE4E4))]),
              Row(children: [for (final l in _filaQ) _tecla(l)]),
              Row(children: [const Spacer(), for (final l in _filaA) _tecla(l), const Spacer()]),
              Row(children: [for (final l in _filaZ) _tecla(l)]),
              const SizedBox(height: 6),
              Row(
                children: [
                  _tecla('espacio', onTap: _espacio, flex: 4),
                  const SizedBox(width: 4),
                  _tecla('borrar todo', onTap: _limpiar, flex: 2, color: const Color(0xFFFCE4E4)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
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
        ),
      ),
    );
  }
}
