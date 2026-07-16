import 'package:excel/excel.dart' as xls;
import '../../../core/utils/xlsx_reparar.dart';

class FilaImportacionProducto {
  final int numeroFila;
  final String codigo;
  final String nombre;
  final String descripcion;
  final String categoria;
  final double stock;
  final double precioVenta;
  final double precioCompra;
  final bool estado;
  final String? error;

  FilaImportacionProducto({
    required this.numeroFila,
    required this.codigo,
    required this.nombre,
    required this.descripcion,
    required this.categoria,
    required this.stock,
    required this.precioVenta,
    required this.precioCompra,
    required this.estado,
    this.error,
  });

  bool get valido => error == null;
}

class ProductoImportService {
  static const _sinonimos = <String, List<String>>{
    'codigo': ['codigo'],
    'nombre': ['nombre'],
    'descripcion': ['descripcion'],
    'categoria': ['categoria'],
    'stock': ['stock', 'existencia'],
    'precioVenta': ['precioventa', 'preciodeventa'],
    'precioCompra': ['preciocompra', 'preciodecompra'],
    'estado': ['estado'],
  };

  String _normalizar(String texto) {
    var t = texto.trim().toLowerCase();
    const conAcento = 'áéíóúñ';
    const sinAcento = 'aeioun';
    for (var i = 0; i < conAcento.length; i++) {
      t = t.replaceAll(conAcento[i], sinAcento[i]);
    }
    return t.replaceAll(RegExp(r'\s+'), '');
  }

  double? _parseDoubleOpcional(String texto) {
    final limpio = texto.trim().replaceAll(',', '').replaceAll('L', '').replaceAll('Lps.', '').trim();
    if (limpio.isEmpty) return 0;
    return double.tryParse(limpio);
  }

  bool _parseEstado(String texto) {
    final t = texto.trim().toLowerCase();
    return t != 'inactivo' && t != 'no' && t != 'false' && t != '0';
  }

  /// Lee un .xlsx y devuelve las filas encontradas (válidas o con error).
  /// Lanza [FormatException] si el archivo no se pudo leer en absoluto.
  List<FilaImportacionProducto> leer(List<int> bytes) {
    xls.Excel excel;
    try {
      excel = xls.Excel.decodeBytes(bytes);
    } catch (_) {
      try {
        excel = xls.Excel.decodeBytes(repararRutasXlsx(bytes));
      } catch (_) {
        throw const FormatException(
          'No se pudo leer el archivo. Abrilo en Google Sheets (gratis, sin instalar nada), '
          'descargalo de nuevo como .xlsx (Archivo → Descargar → Microsoft Excel) y volvé a subirlo.',
        );
      }
    }

    if (excel.tables.isEmpty) {
      throw const FormatException('El archivo no tiene ninguna hoja con datos.');
    }
    final hoja = excel.tables[excel.tables.keys.first]!;
    if (hoja.maxRows < 2) {
      throw const FormatException('El archivo no tiene filas de datos (solo encabezado o está vacío).');
    }

    final encabezado = hoja.rows.first;
    final indicePorCampo = <String, int>{};
    for (var col = 0; col < encabezado.length; col++) {
      final valor = encabezado[col]?.value?.toString() ?? '';
      final normalizado = _normalizar(valor);
      for (final entrada in _sinonimos.entries) {
        if (entrada.value.contains(normalizado) && !indicePorCampo.containsKey(entrada.key)) {
          indicePorCampo[entrada.key] = col;
        }
      }
    }

    if (!indicePorCampo.containsKey('nombre')) {
      throw const FormatException('No encontré una columna "Nombre" en el archivo. Revisá que la primera fila tenga los encabezados.');
    }

    String celda(List<xls.Data?> fila, String campo) {
      final indice = indicePorCampo[campo];
      if (indice == null || indice >= fila.length) return '';
      return fila[indice]?.value?.toString() ?? '';
    }

    final filas = <FilaImportacionProducto>[];
    for (var i = 1; i < hoja.rows.length; i++) {
      final fila = hoja.rows[i];
      if (fila.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) continue;

      final nombre = celda(fila, 'nombre').trim();
      final categoria = celda(fila, 'categoria').trim();
      final stockTexto = celda(fila, 'stock');
      final precioVentaTexto = celda(fila, 'precioVenta');
      final precioCompraTexto = celda(fila, 'precioCompra');

      String? error;
      if (nombre.isEmpty) {
        error = 'El nombre está vacío';
      } else if (nombre == '0') {
        error = 'Fila inválida (nombre "0", parece un dato de prueba)';
      } else if (categoria.isEmpty) {
        error = 'La categoría está vacía';
      }

      final stock = _parseDoubleOpcional(stockTexto);
      final precioVenta = _parseDoubleOpcional(precioVentaTexto);
      final precioCompra = _parseDoubleOpcional(precioCompraTexto);
      if (error == null && stock == null) error = 'Existencia inválida: "$stockTexto"';
      if (error == null && precioVenta == null) error = 'Precio de venta inválido: "$precioVentaTexto"';
      if (error == null && precioCompra == null) error = 'Precio de compra inválido: "$precioCompraTexto"';

      // Existencias negativas se registran en 0: no tiene sentido cargar un
      // producto nuevo (o actualizar uno) con stock negativo desde el Excel.
      final stockFinal = (stock ?? 0) < 0 ? 0.0 : (stock ?? 0);

      filas.add(FilaImportacionProducto(
        numeroFila: i + 1,
        codigo: celda(fila, 'codigo').trim(),
        nombre: nombre,
        descripcion: celda(fila, 'descripcion').trim(),
        categoria: categoria,
        stock: stockFinal,
        precioVenta: precioVenta ?? 0,
        precioCompra: precioCompra ?? 0,
        estado: _parseEstado(celda(fila, 'estado')),
        error: error,
      ));
    }
    return filas;
  }
}
