import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Entrada estructurada de cantidad de tinte en la notación real de la
/// máquina tintométrica del negocio -pedido explícito del dueño-: el dial
/// marca unidades enteras "Y" y cada una se subdivide en 48 partes
/// ("48avos", 0-47), ej. "5Y30" = 5 enteros + 30/48. A propósito NO es un
/// campo de texto único donde se escriba "5.30": eso es propenso a error y
/// además un campo decimal de verdad malinterpretaría "5.30" como 5.3 onzas
/// reales en vez de 5 + 30/48 = 5.625. Acá van dos campos numéricos chicos
/// lado a lado, y el resultado (onzas = Y + avos/48.0) se entrega ya
/// combinado por [onChanged] -el que la usa no necesita saber nada de la
/// notación interna-.
///
/// Para "limpiar" los campos desde afuera (ver los botones "Limpiar" ya
/// existentes en las pantallas que usan esto) se usa el truco estándar de
/// Flutter de cambiar la `key` del widget -eso fuerza que se recree desde
/// cero con los campos vacíos- en vez de exponer un controller propio.
class CampoCantidadTinte extends StatefulWidget {
  /// Se llama con las onzas ya combinadas cada vez que cambia Y o los
  /// 48avos (incluido al construirse, si [valorInicial] no es nulo/cero, no
  /// hace falta: el valor inicial ya lo conoce quien construye el widget).
  final ValueChanged<double> onChanged;

  /// Valor inicial en onzas, si se quiere prellenar (ej. al reabrir sobre
  /// un valor ya cargado). Se descompone una sola vez en Y/48avos al crear
  /// el widget -no reacciona a cambios posteriores de este valor, para eso
  /// está el truco de la `key` mencionado arriba.
  final double? valorInicial;

  const CampoCantidadTinte({super.key, required this.onChanged, this.valorInicial});

  @override
  State<CampoCantidadTinte> createState() => _CampoCantidadTinteState();
}

class _CampoCantidadTinteState extends State<CampoCantidadTinte> {
  static const avosPorUnidad = 48;

  late final TextEditingController _ctrlY;
  late final TextEditingController _ctrlAvos;

  @override
  void initState() {
    super.initState();
    final inicial = widget.valorInicial ?? 0;
    final y = inicial.floor().clamp(0, 999999);
    final avos = ((inicial - inicial.floor()) * avosPorUnidad).round().clamp(0, avosPorUnidad - 1);
    _ctrlY = TextEditingController(text: y == 0 ? '' : '$y');
    _ctrlAvos = TextEditingController(text: avos == 0 ? '' : '$avos');
  }

  @override
  void dispose() {
    _ctrlY.dispose();
    _ctrlAvos.dispose();
    super.dispose();
  }

  void _emitir() {
    final y = int.tryParse(_ctrlY.text) ?? 0;
    final avos = int.tryParse(_ctrlAvos.text) ?? 0;
    widget.onChanged(y + avos / avosPorUnidad);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _campo(_ctrlY, 'Y')),
        const SizedBox(width: 10),
        Expanded(child: _campo(_ctrlAvos, '48avos', maximo: avosPorUnidad - 1)),
      ],
    );
  }

  Widget _campo(TextEditingController ctrl, String etiqueta, {int? maximo}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      // El límite de 0-47 en "48avos" se rechaza a medida que se escribe
      // (no se deja ni entrar el dígito que se pasaría del dial real) en
      // vez de dejarlo entrar y recortarlo después -así no hay un valor
      // "inválido" visible ni un salto raro de cursor.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, if (maximo != null) _LimiteInputFormatter(maximo)],
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        labelText: etiqueta,
        labelStyle: GoogleFonts.poppins(fontSize: 12.5),
        filled: true,
        fillColor: const Color(0xFFF2F3F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      onChanged: (_) => _emitir(),
    );
  }
}

/// Rechaza cualquier valor que supere [maximo] mientras se escribe -devuelve
/// el valor viejo, sin dejar pasar el cambio- en vez de dejarlo entrar y
/// recortarlo después.
class _LimiteInputFormatter extends TextInputFormatter {
  final int maximo;
  const _LimiteInputFormatter(this.maximo);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final valor = int.tryParse(newValue.text);
    if (valor == null || valor > maximo) return oldValue;
    return newValue;
  }
}
