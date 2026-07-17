import 'package:cloud_firestore/cloud_firestore.dart';
import 'producto_model.dart';
import 'producto_import_service.dart';
import 'historial_stock_model.dart';
import 'historial_precio_compra_model.dart';
import 'historial_venta_producto_model.dart';
import 'lote_costo_repository.dart';

class ResumenImportacionProductos {
  final int creados;
  final int actualizados;
  final int categoriasCreadas;

  ResumenImportacionProductos({required this.creados, required this.actualizados, required this.categoriasCreadas});
}

class ProductoRepository {
  final _col = FirebaseFirestore.instance.collection('productos');
  final _colCategorias = FirebaseFirestore.instance.collection('categorias');

  Stream<List<ProductoModel>> obtenerProductos() {
    return _col.orderBy('nombre').snapshots().map((snap) {
      return snap.docs.map((d) => ProductoModel.fromMap(d.id, d.data())).toList();
    });
  }

  String _generarCodigo() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return 'PROD-${ahora.substring(ahora.length - 8)}';
  }

  Future<ProductoModel> crear({
    required String codigo,
    required String codigoBarras,
    required String nombre,
    required String descripcion,
    required String idCategoria,
    required double stock,
    required double precioCompra,
    required double precioVenta,
    required double precioVenta2,
    required double precioVenta3,
    required bool estado,
  }) async {
    var codigoFinal = codigo.trim();
    if (codigoFinal.isEmpty) {
      codigoFinal = _generarCodigo();
    } else {
      final existe = await _col.where('codigo', isEqualTo: codigoFinal).limit(1).get();
      if (existe.docs.isNotEmpty) {
        throw Exception('Ya existe un producto con ese código');
      }
    }
    final ref = await _col.add({
      'codigo': codigoFinal,
      'codigoBarras': codigoBarras.trim(),
      'nombre': nombre.trim(),
      'descripcion': descripcion.trim(),
      'idCategoria': idCategoria,
      'stock': stock,
      'precioCompra': precioCompra,
      'precioVenta': precioVenta,
      'precioVenta2': precioVenta2,
      'precioVenta3': precioVenta3,
      'estado': estado,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
    // Si el producto se crea con existencia inicial, esa cantidad también
    // necesita su propio lote de costo — si no, al venderla no hay lote que
    // consumir por FIFO y termina costeándose con el precioCompra vigente
    // en el momento de la venta (que puede ya haber cambiado por una compra
    // posterior) en vez del costo real de esa existencia inicial.
    if (stock > 0) {
      await ref.collection('lotes').add({
        'cantidadOriginal': stock,
        'cantidadRestante': stock,
        'costoUnitario': precioCompra,
        'fecha': Timestamp.fromDate(DateTime.now()),
        'origen': 'inicial',
        'idCompra': null,
      });
    }
    return ProductoModel(
      id: ref.id,
      codigo: codigoFinal,
      codigoBarras: codigoBarras.trim(),
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      idCategoria: idCategoria,
      stock: stock,
      precioCompra: precioCompra,
      precioVenta: precioVenta,
      precioVenta2: precioVenta2,
      precioVenta3: precioVenta3,
      estado: estado,
    );
  }

  Future<void> actualizar({
    required String id,
    required String codigo,
    required String codigoBarras,
    required String nombre,
    required String descripcion,
    required String idCategoria,
    required double precioCompra,
    required double precioVenta,
    required double precioVenta2,
    required double precioVenta3,
    required bool estado,
  }) async {
    final codigoFinal = codigo.trim().isEmpty ? _generarCodigo() : codigo.trim();
    final existe = await _col.where('codigo', isEqualTo: codigoFinal).limit(2).get();
    final duplicado = existe.docs.any((d) => d.id != id);
    if (duplicado) {
      throw Exception('Ya existe un producto con ese código');
    }
    await _col.doc(id).update({
      'codigo': codigoFinal,
      'codigoBarras': codigoBarras.trim(),
      'nombre': nombre.trim(),
      'descripcion': descripcion.trim(),
      'idCategoria': idCategoria,
      'precioCompra': precioCompra,
      'precioVenta': precioVenta,
      'precioVenta2': precioVenta2,
      'precioVenta3': precioVenta3,
      'estado': estado,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  /// Crea o actualiza en lote los productos de una importación desde Excel.
  /// Empareja por [FilaImportacionProducto.codigo]: si ya existe un producto
  /// con ese código se actualiza (sin tocar código de barras ni niveles de
  /// precio extra, que el Excel no trae); si no hay código o no coincide con
  /// ninguno existente, se crea un producto nuevo. Las categorías que no
  /// existan todavía se crean automáticamente.
  Future<ResumenImportacionProductos> importarProductos(List<FilaImportacionProducto> filas) async {
    final productosSnap = await _col.get();
    final idPorCodigo = <String, String>{};
    for (final d in productosSnap.docs) {
      final codigo = (d.data()['codigo'] as String? ?? '').trim().toLowerCase();
      if (codigo.isNotEmpty) idPorCodigo[codigo] = d.id;
    }

    final categoriasSnap = await _colCategorias.get();
    final idCategoriaPorNombre = <String, String>{};
    for (final d in categoriasSnap.docs) {
      final descripcion = (d.data()['descripcion'] as String? ?? '').trim().toLowerCase();
      if (descripcion.isNotEmpty) idCategoriaPorNombre[descripcion] = d.id;
    }

    var creados = 0, actualizados = 0, categoriasCreadas = 0;
    var batch = FirebaseFirestore.instance.batch();
    var operacionesEnBatch = 0;

    Future<void> descargarBatch() async {
      if (operacionesEnBatch == 0) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      operacionesEnBatch = 0;
    }

    for (final fila in filas) {
      final nombreCategoriaNorm = fila.categoria.trim().toLowerCase();
      var idCategoria = idCategoriaPorNombre[nombreCategoriaNorm];
      if (idCategoria == null) {
        final ref = _colCategorias.doc();
        batch.set(ref, {
          'descripcion': fila.categoria.trim(),
          'estado': true,
          'fechaRegistro': FieldValue.serverTimestamp(),
        });
        idCategoria = ref.id;
        idCategoriaPorNombre[nombreCategoriaNorm] = idCategoria;
        categoriasCreadas++;
        operacionesEnBatch++;
      }

      final codigoNorm = fila.codigo.trim().toLowerCase();
      final idExistente = codigoNorm.isEmpty ? null : idPorCodigo[codigoNorm];

      final datosComunes = {
        'nombre': fila.nombre.trim(),
        'descripcion': fila.descripcion.trim(),
        'idCategoria': idCategoria,
        'stock': fila.stock,
        'precioCompra': fila.precioCompra,
        'precioVenta': fila.precioVenta,
        'estado': fila.estado,
      };

      if (idExistente != null) {
        batch.update(_col.doc(idExistente), {...datosComunes, 'codigo': fila.codigo.trim()});
        actualizados++;
      } else {
        final ref = _col.doc();
        // Sin código en el Excel: se usa el id del documento (único
        // garantizado) en vez de un generador basado en la hora, que podría
        // repetirse entre varias filas sin código procesadas en el mismo
        // milisegundo dentro de este mismo lote.
        final codigoFinal = fila.codigo.trim().isEmpty ? 'PROD-${ref.id.substring(0, 8).toUpperCase()}' : fila.codigo.trim();
        batch.set(ref, {
          ...datosComunes,
          'codigo': codigoFinal,
          'codigoBarras': '',
          'precioVenta2': 0.0,
          'precioVenta3': 0.0,
          'fechaRegistro': FieldValue.serverTimestamp(),
        });
        if (codigoNorm.isNotEmpty) idPorCodigo[codigoNorm] = ref.id;
        creados++;
      }
      operacionesEnBatch++;
      if (operacionesEnBatch >= 400) await descargarBatch();
    }
    await descargarBatch();

    return ResumenImportacionProductos(creados: creados, actualizados: actualizados, categoriasCreadas: categoriasCreadas);
  }

  /// Ajusta el stock a mano (Inventario). Si sube existencia, [costoUnitario]
  /// permite registrar a qué costo entró ese stock (por ejemplo 0 si lo
  /// regalaron): crea un lote de costo nuevo con ese valor, o con el
  /// `precioCompra` vigente del producto si no se indica. Si baja
  /// existencia, consume lotes por FIFO igual que una venta, para que la
  /// cantidad restante sumada en los lotes no se desalinee del stock total.
  Future<void> ajustarStock({
    required String id,
    required double stockActual,
    required double stockNuevo,
    required String usuario,
    String motivo = '',
    double? costoUnitario,
  }) async {
    final ref = _col.doc(id);
    final lotes = LoteCostoRepository();
    final esIncremento = stockNuevo > stockActual;
    final diferencia = (stockNuevo - stockActual).abs();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final precioCompraActual = ((snap.data()?['precioCompra'] ?? 0) as num).toDouble();

      EstadoLotesProducto? estadoLotes;
      if (!esIncremento && diferencia > 0) {
        final query = await lotes.consultarLotes(id);
        estadoLotes = lotes.inicializarEstado(query);
        lotes.consumir(estadoLotes, diferencia, costoFallback: precioCompraActual);
      }

      transaction.update(ref, {'stock': stockNuevo});
      final historialRef = ref.collection('historial').doc();
      transaction.set(historialRef, {
        'stockAnterior': stockActual,
        'stockNuevo': stockNuevo,
        'usuario': usuario,
        'motivo': motivo,
        'fecha': FieldValue.serverTimestamp(),
      });

      if (esIncremento && diferencia > 0) {
        lotes.crearLote(transaction, id, cantidad: diferencia, costoUnitario: costoUnitario ?? precioCompraActual, fecha: DateTime.now(), origen: 'ajuste');
      } else if (estadoLotes != null) {
        lotes.aplicarEstado(transaction, estadoLotes);
      }
    });
  }

  /// Descuenta stock de un producto de forma atómica (lee el stock actual y lo decrementa),
  /// registrando el movimiento en el historial. Usado para reembasados y ventas.
  Future<bool> descontarStock({
    required String id,
    required double cantidad,
    required String usuario,
    required String motivo,
  }) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(_col.doc(id));
        final stockActual = ((doc.data()?['stock'] ?? 0) as num).toDouble();
        final stockNuevo = stockActual - cantidad;
        transaction.update(_col.doc(id), {'stock': stockNuevo});
        final historialRef = _col.doc(id).collection('historial').doc();
        transaction.set(historialRef, {
          'stockAnterior': stockActual,
          'stockNuevo': stockNuevo,
          'usuario': usuario,
          'motivo': motivo,
          'fecha': FieldValue.serverTimestamp(),
        });
      }, timeout: const Duration(seconds: 12));
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<List<HistorialStockModel>> obtenerHistorialStock(String idProducto) {
    return _col.doc(idProducto).collection('historial').orderBy('fecha', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => HistorialStockModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// Historial de costos del producto, en el orden en que se fueron
  /// registrando las compras que los generaron (más antiguo primero).
  Stream<List<HistorialPrecioCompraModel>> obtenerHistorialPreciosCompra(String idProducto) {
    return _col.doc(idProducto).collection('historialPreciosCompra').orderBy('fecha').snapshots().map((snap) {
      return snap.docs.map((d) => HistorialPrecioCompraModel.fromMap(d.id, d.data())).toList();
    });
  }

  /// Historial de ventas del producto, en el orden en que se fueron
  /// registrando (más antiguo primero).
  Stream<List<HistorialVentaProductoModel>> obtenerHistorialVentas(String idProducto) {
    return _col.doc(idProducto).collection('historialVentas').orderBy('fecha').snapshots().map((snap) {
      return snap.docs.map((d) => HistorialVentaProductoModel.fromMap(d.id, d.data())).toList();
    });
  }
}