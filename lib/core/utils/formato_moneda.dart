import 'package:intl/intl.dart';

String formatearMoneda(double valor) {
  final formato = NumberFormat('#,##0.00', 'en_US');
  // Redondea antes de formatear: es el mismo problema que redondearMoneda
  // evita en otros lados (ver más abajo) pero como respaldo general acá,
  // para que ningún monto se muestre con arrastre de coma flotante sin
  // importar de dónde venga.
  return 'L. ${formato.format(redondearMoneda(valor))}';
}

/// Redondea un monto a centavos evitando errores de precisión binaria.
///
/// Multiplicar por 100 y usar `.round()` directamente puede fallar (ej.
/// `2.675 * 100` da `267.49999999999997` en punto flotante binario), lo que
/// produce cifras que terminan en `.99` en vez del valor correcto. Pasar por
/// `toStringAsFixed` usa la conversión decimal correctamente redondeada de
/// Dart antes de volver a un double, evitando ese problema.
double redondearMoneda(double valor) {
  return double.parse(valor.toStringAsFixed(2));
}