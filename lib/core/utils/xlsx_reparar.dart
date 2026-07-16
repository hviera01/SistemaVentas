import 'dart:convert';
import 'package:archive/archive.dart';

/// El paquete `excel` escribe (y algunos otros programas también) las rutas
/// de las relaciones internas del .xlsx con un "/" inicial
/// ("/xl/styles.xml"), pero el lector de `excel` arma la ruta como "xl/" +
/// esa cadena sin quitar esa barra, y termina buscando "xl//xl/styles.xml",
/// que no existe. El archivo puede tener todos los datos correctos pero ser
/// ilegible para el paquete (se reporta como "Damaged Excel file") aunque
/// abra sin problema en Excel/Google Sheets/LibreOffice, que son más
/// tolerantes. Esto corrige esas rutas quitando el prefijo "/xl/" de los
/// Target en cualquier archivo de relaciones (.rels) del paquete .xlsx.
List<int> repararRutasXlsx(List<int> bytes) {
  try {
    final archivoOriginal = ZipDecoder().decodeBytes(bytes);
    var huboCambios = false;
    final archivoNuevo = Archive();
    for (final f in archivoOriginal.files) {
      if (f.name.endsWith('.rels')) {
        final contenido = utf8.decode(f.content as List<int>);
        final corregido = contenido.replaceAll('Target="/xl/', 'Target="');
        if (corregido != contenido) {
          huboCambios = true;
          final data = utf8.encode(corregido);
          archivoNuevo.addFile(ArchiveFile(f.name, data.length, data));
          continue;
        }
      }
      archivoNuevo.addFile(ArchiveFile(f.name, f.size, f.content));
    }
    if (!huboCambios) return bytes;
    return ZipEncoder().encode(archivoNuevo) ?? bytes;
  } catch (_) {
    return bytes;
  }
}
