/// Implementación para Windows/Android/iOS (no web): WebUSB es una API de
/// navegador, así que acá no hay nada que ofrecer -esas plataformas ya
/// imprimen crudo por su propia vía (ImpresoraUsbWindowsService/
/// ImpresoraRedService), no necesitan esto-.
class ImpresoraWebUsbService {
  Future<bool> soportado() async => false;

  Future<bool> hayImpresoraVinculada() async => false;

  Future<String?> nombreImpresoraVinculada() async => null;

  Future<bool> vincular() async => false;

  Future<void> desvincular() async {}

  Future<bool> imprimir({required List<int> bytes}) async => false;
}
