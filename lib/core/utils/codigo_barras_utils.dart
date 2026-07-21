/// Invierte el texto de un código de barras (ej. "12345" -> "54321").
///
/// Corrige un caso real reportado: en algún celular (no en todos los
/// probados, así que parece del hardware/driver de cámara de ese equipo en
/// particular) el código de barras se lee al revés — arma bien el patrón
/// de barras pero arranca a decodificarlo desde el extremo contrario. No
/// hay forma de arreglar eso desde acá, así que en los lugares donde se
/// busca un producto por coincidencia exacta de código se prueba también
/// con el código invertido antes de darlo por no encontrado.
String invertirCodigoBarras(String codigo) => codigo.trim().split('').reversed.join();

/// Otras variantes válidas del mismo código de barras a probar si la
/// coincidencia exacta (y la invertida, ver invertirCodigoBarras) no
/// encuentran nada. Cubre un caso real y bien conocido: en iPhone, la
/// cámara reporta los códigos UPC-A (12 dígitos) como si fueran EAN-13,
/// agregándoles un "0" al principio -es un comportamiento de iOS/
/// AVFoundation, no un error de esta app-, mientras que Android reporta el
/// mismo código tal cual está impreso, sin ese cero. Si el catálogo tiene
/// el código guardado en el otro formato (con o sin el cero), un celular
/// nunca lo va a encontrar y el otro sí, aunque sea exactamente el mismo
/// producto.
List<String> variantesCodigoBarras(String codigo) {
  final variantes = <String>[];
  if (codigo.length == 13 && codigo.startsWith('0')) {
    variantes.add(codigo.substring(1));
  } else if (codigo.length == 12) {
    variantes.add('0$codigo');
  }
  final invertido = invertirCodigoBarras(codigo);
  if (invertido != codigo) variantes.add(invertido);
  return variantes;
}
