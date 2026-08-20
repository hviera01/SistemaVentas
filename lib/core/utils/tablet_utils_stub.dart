// Windows/APK: nunca hace falta esta señal aparte (ver tablet_utils.dart,
// solo se consulta cuando defaultTargetPlatform ya dio macOS en web, algo
// que no pasa fuera de un navegador).
bool esDispositivoTactil() => false;
