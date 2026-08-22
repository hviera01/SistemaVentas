// Para imprimir por ESC/POS (ver VentaTicketEscPosService y
// TicketEscPosPreview): a diferencia de normalizarTexto (que además pone
// todo en minúscula, pensado para comparar/buscar) esto conserva
// mayúsculas/minúsculas tal cual -solo saca tildes, diéresis y signos de
// apertura- porque muchas impresoras térmicas no tienen la página de
// códigos correcta configurada para acentos y los imprimen mal (un
// caracter random en vez de la letra, o corta la línea ahí).
const _mapaTildesImpresion = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
  '¡': '', '¿': '',
};

String quitarTildes(String texto) {
  var resultado = texto;
  _mapaTildesImpresion.forEach((k, v) => resultado = resultado.replaceAll(k, v));
  return resultado;
}

String normalizarTexto(String texto) {
  final mapaAcentos = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n',
  };
  var resultado = texto.toLowerCase();
  mapaAcentos.forEach((k, v) {
    resultado = resultado.replaceAll(k, v);
  });
  return resultado.trim();
}

int distanciaLevenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final matriz = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) matriz[i][0] = i;
  for (var j = 0; j <= b.length; j++) matriz[0][j] = j;
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final costo = a[i - 1] == b[j - 1] ? 0 : 1;
      final opciones = [matriz[i - 1][j] + 1, matriz[i][j - 1] + 1, matriz[i - 1][j - 1] + costo];
      matriz[i][j] = opciones.reduce((v, e) => v < e ? v : e);
    }
  }
  return matriz[a.length][b.length];
}

/// Normaliza un nombre de cliente para compararlo por igualdad tolerando
/// diferencias de mayúsculas/minúsculas, tildes y espacios de más -pedido
/// explícito del dueño: VentaRepository._resolverIdCliente comparaba el
/// nombre tal cual se tipeó (ya en mayúsculas, por mayusculasInputFormatter)
/// contra ClienteModel.nombreCompleto tal cual está guardado en Firestore.
/// Un cliente cargado antes de que existiera ese formateo -o parcheado a
/// mano en Firestore con otra capitalización, como pasó con un cliente real
/// de este negocio- no calzaba con el mismo nombre tipeado después: la venta
/// terminaba creando un cliente DUPLICADO (o, en casos límite, sin vincular
/// ninguno) en vez de reusar el ya existente, y esa venta aparecía como "sin
/// cliente" en el reporte financiero aunque el cliente ya estuviera
/// registrado. No reusa normalizarTexto tal cual porque esa además se usa
/// para búsqueda fuzzy por palabra y no colapsa espacios de más en medio del
/// texto -acá sí hace falta, para que "Ronald  Camas" (dos espacios) también
/// calce con "Ronald Camas".
String normalizarNombreCliente(String texto) {
  return normalizarTexto(texto).replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool coincideFuzzy(String textoCompleto, String consulta) {
  final textoNorm = normalizarTexto(textoCompleto);
  final consultaNorm = normalizarTexto(consulta);
  if (consultaNorm.isEmpty) return true;
  final palabrasTexto = textoNorm.split(RegExp(r'\s+'));
  final palabrasConsulta = consultaNorm.split(RegExp(r'\s+'));
  for (final palabraConsulta in palabrasConsulta) {
    if (palabraConsulta.isEmpty) continue;
    final coincideAlguna = palabrasTexto.any((palabraTexto) {
      if (palabraTexto.isEmpty) return false;
      // Que la palabra buscada aparezca dentro de una palabra del producto
      // (permite escribir solo el principio o una parte). Antes también se
      // aceptaba al revés (palabra del producto dentro de la búsqueda), lo
      // que hacía que una palabra corta cualquiera del producto -"on", "rex",
      // etc.- calzara adentro de algo como "rexona" y trajera resultados sin
      // ninguna relación real.
      if (palabraTexto.contains(palabraConsulta)) return true;
      // Sin tolerancia si la palabra buscada tiene algún dígito: son casos
      // de código (ej. "SC-1332"), donde un caracter de diferencia es
      // literalmente otro producto, no un error de tipeo a perdonar (a
      // diferencia de una palabra de texto libre mal escrita). Antes esto
      // dejaba pasar códigos parecidos por Levenshtein y el filtro traía de
      // más con búsquedas que deberían haber sido puntuales.
      if (RegExp(r'[0-9]').hasMatch(palabraConsulta)) return false;
      // Tolerancia a errores de tipeo: nada para palabras muy cortas (ahí
      // cualquier letra distinta ya es otra palabra), un poco más para
      // palabras largas.
      final tolerancia = palabraConsulta.length <= 4 ? 0 : (palabraConsulta.length <= 7 ? 1 : 2);
      if (tolerancia == 0) return false;
      return distanciaLevenshtein(palabraTexto, palabraConsulta) <= tolerancia;
    });
    if (!coincideAlguna) return false;
  }
  return true;
}