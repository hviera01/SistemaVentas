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
