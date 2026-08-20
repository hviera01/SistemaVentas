import 'package:flutter/services.dart';

/// Fuerza mayúsculas en todo lo que se escribe: pedido explícito para que el
/// texto que queda guardado en la app sea siempre el mismo sin importar cómo
/// lo haya tecleado la persona (minúsculas, Mayúsculas Iniciales, etc.).
/// Se aplica a los TextField/TextFormField de texto libre de toda la app;
/// los campos de contraseña (obscureText) quedan afuera a propósito, porque
/// ahí sí importa exactamente lo que la persona escribió.
class MayusculasInputFormatter extends TextInputFormatter {
  const MayusculasInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == newValue.text.toUpperCase()) return newValue;
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

const mayusculasInputFormatter = MayusculasInputFormatter();
