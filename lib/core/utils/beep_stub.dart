import 'package:flutter/services.dart';

/// Implementación para Android/Windows/etc. (no web): no hay una API de
/// "beep" simple y portable ahí, así que se usa el sonido de sistema más
/// parecido más una vibración corta, que en la práctica cumple el mismo
/// papel de aviso.
void beep() {
  SystemSound.play(SystemSoundType.click);
  HapticFeedback.mediumImpact();
}
