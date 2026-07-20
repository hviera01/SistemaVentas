import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Teclado numérico en pantalla para cambiar cantidad/precio/descuento a
/// clics de mouse, pensado para escritorio (Windows y web en computadora).
/// Funciona de las dos formas a la vez: a clics en los botones, o escribiendo
/// con el teclado físico (números, punto, Backspace y Enter para confirmar,
/// igual que escribir directo en el campo). El primer dígito que se toca o
/// tipea después de abrir reemplaza el valor que ya traía (no escribe
/// encima), como en cualquier calculadora. Devuelve el texto tal como quedó
/// (o null si se cancela) para no perder precisión con conversiones de ida y
/// vuelta a double.
class TecladoNumericoDialog extends StatefulWidget {
  final String titulo;
  final String valorInicial;

  const TecladoNumericoDialog({super.key, required this.titulo, required this.valorInicial});

  @override
  State<TecladoNumericoDialog> createState() => _TecladoNumericoDialogState();
}

class _TecladoNumericoDialogState extends State<TecladoNumericoDialog> {
  late String _texto;
  bool _recienAbierto = true;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final inicial = widget.valorInicial.trim();
    _texto = inicial.isEmpty ? '0' : inicial;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _tocarTecla(String tecla) {
    setState(() {
      // El primer toque después de abrir empieza un número nuevo en vez de
      // escribir pegado al valor que ya traía el campo.
      if (_recienAbierto) {
        _recienAbierto = false;
        _texto = tecla == '.' ? '0.' : tecla;
        return;
      }
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
      _recienAbierto = false;
      if (_texto.length <= 1) {
        _texto = '0';
      } else {
        _texto = _texto.substring(0, _texto.length - 1);
      }
    });
  }

  void _limpiar() => setState(() {
        _recienAbierto = false;
        _texto = '0';
      });

  void _confirmar() {
    if (double.tryParse(_texto) == null) return;
    Navigator.pop(context, _texto);
  }

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
    final digito = _digitoDeTecla(tecla);
    if (digito != null) {
      _tocarTecla(digito);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.period || tecla == LogicalKeyboardKey.numpadDecimal || tecla == LogicalKeyboardKey.comma) {
      _tocarTecla('.');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _digitoDeTecla(LogicalKeyboardKey tecla) {
    final numpad = {
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
    };
    return numpad[tecla];
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
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _manejarTeclaFisica(node, event),
      child: Dialog(
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
      ),
    );
  }
}
