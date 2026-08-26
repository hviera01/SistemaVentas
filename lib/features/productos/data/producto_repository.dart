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
    String imagenUrl = '',
    bool esCombo = false,
    List<ComponenteProductoModel> componentes = const [],
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
      'imagenUrl': imagenUrl,
      'esCombo': esCombo,
      'componentes': componentes.map((c) => c.toMap()).toList(),
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
      imagenUrl: imagenUrl,
      esCombo: esCombo,
      componentes: componentes,
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
    String imagenUrl = '',
    // Solo se envían al editar un combo ya existente (ver
    // ProductoFormDialog): el tipo de producto no se puede cambiar después
    // de creado, pero la receta de componentes sí se puede seguir ajustando
    // -agregar, quitar o cambiar cantidades- desde la misma pantalla de
    // edición.
    bool? esCombo,
    List<ComponenteProductoModel>? componentes,
  }) async {
    final codigoFinal = codigo.trim().isEmpty ? _generarCodigo() : codigo.trim();
    final existe = await _col.where('codigo', isEqualTo: codigoFinal).limit(2).get();
    final duplicado = existe.docs.any((d) => d.id != id);
    if (duplicado) {
      throw Exception('Ya existe un producto con ese código');
    }
    final datos = {
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
      'imagenUrl': imagenUrl,
    };
    if (esCombo != null) datos['esCombo'] = esCombo;
    if (componentes != null) datos['componentes'] = componentes.map((c) => c.toMap()).toList();
    await _col.doc(id).update(datos);
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
      if (d.data()['esCombo'] == true) continue;
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
  /// Ingreso manual de existencia (Inventario): igual que si viniera de una
  /// compra, queda como su propio lote de costo (ver LoteCostoRepository),
  /// para que una salida futura -manual o por venta- pueda costearse con el
  /// costo real de este ingreso puntual.
  Future<void> registrarIngreso({
    required String id,
    required double cantidad,
    required double costoUnitario,
    required String usuario,
    String motivo = '',
  }) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a 0');
    final ref = _col.doc(id);
    final lotes = LoteCostoRepository();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final stockActual = ((snap.data()?['stock'] ?? 0) as num).toDouble();
      final stockNuevo = stockActual + cantidad;

      transaction.update(ref, {'stock': stockNuevo});
      final historialRef = ref.collection('historial').doc();
      transaction.set(historialRef, {
        'stockAnterior': stockActual,
        'stockNuevo': stockNuevo,
        'usuario': usuario,
        'motivo': motivo.trim().isEmpty ? 'Ingreso manual' : motivo.trim(),
        'fecha': FieldValue.serverTimestamp(),
      });
      lotes.crearLote(transaction, id, cantidad: cantidad, costoUnitario: costoUnitario, fecha: DateTime.now(), origen: 'ajuste');
    });
    await lotes.sincronizarPrecioCompraActivo(id);
  }

  /// Salida manual de existencia (Inventario). Si el usuario elige un lote
  /// específico, sale de ahí (con su propio costo). Si elige "sin lote
  /// específico" ([idLote] null -pensado para stock viejo que quedó sin
  /// lotes asociados-, pero disponible siempre), consume por FIFO de los
  /// lotes con existencia (más viejo primero, mismo motor que una venta) en
  /// vez de solo bajar el stock total sin tocarlos -bug real reportado por
  /// el dueño: antes eso desalineaba "cuánto suman los lotes" contra el
  /// stock de verdad apenas el producto ya tenía lotes de por medio-.
  Future<void> registrarSalida({
    required String id,
    required double cantidad,
    String? idLote,
    required String usuario,
    String motivo = '',
  }) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a 0');
    final ref = _col.doc(id);
    final lotes = LoteCostoRepository();
    final loteRef = idLote == null ? null : lotes.colLotes(id).doc(idLote);
    // La query de lotes no puede ir DENTRO de la transacción (Firestore no
    // deja queries transaccionales del cliente, ver
    // LoteCostoRepository.consultarLotes), así que se lanza en paralelo con
    // la lectura transaccional del producto en vez de esperarlas en serie.
    final futureQueryLotes = idLote == null ? lotes.consultarLotes(id) : null;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapProducto = await transaction.get(ref);
      final stockActual = ((snapProducto.data()?['stock'] ?? 0) as num).toDouble();

      if (loteRef != null) {
        final snapLote = await transaction.get(loteRef);
        if (!snapLote.exists) throw Exception('Ese lote ya no existe, actualizá e intentá de nuevo');
        final restanteLote = ((snapLote.data()?['cantidadRestante'] ?? 0) as num).toDouble();
        if (cantidad > restanteLote) {
          throw Exception('Ese lote solo tiene ${restanteLote.toStringAsFixed(restanteLote == restanteLote.roundToDouble() ? 0 : 2)} unidades disponibles');
        }
        transaction.update(loteRef, {'cantidadRestante': restanteLote - cantidad});
      } else {
        if (cantidad > stockActual) {
          throw Exception('No hay suficiente existencia sin lote específico');
        }
        final precioCompraActual = ((snapProducto.data()?['precioCompra'] ?? 0) as num).toDouble();
        final estado = lotes.inicializarEstado(await futureQueryLotes!);
        lotes.consumir(estado, cantidad, costoFallback: precioCompraActual);
        lotes.aplicarEstado(transaction, estado);
      }

      final stockNuevo = stockActual - cantidad;
      transaction.update(ref, {'stock': stockNuevo});
      final historialRef = ref.collection('historial').doc();
      transaction.set(historialRef, {
        'stockAnterior': stockActual,
        'stockNuevo': stockNuevo,
        'usuario': usuario,
        'motivo': motivo.trim().isEmpty ? 'Salida manual' : motivo.trim(),
        'fecha': FieldValue.serverTimestamp(),
      });
    });
    await lotes.sincronizarPrecioCompraActivo(id);
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

  /// Se pide con `.get()` puntual en vez de `.snapshots()`: es un historial
  /// de solo lectura (se abre para revisar el pasado, no cambia mientras el
  /// diálogo está abierto) así que no vale la pena mantener un listener en
  /// vivo cobrando lecturas por cada movimiento nuevo de CUALQUIER producto
  /// mientras el diálogo sigue abierto.
  Future<List<HistorialStockModel>> obtenerHistorialStock(String idProducto) async {
    final snap = await _col.doc(idProducto).collection('historial').orderBy('fecha', descending: true).get();
    return snap.docs.map((d) => HistorialStockModel.fromMap(d.id, d.data())).toList();
  }

  /// Historial de costos del producto, en el orden en que se fueron
  /// registrando las compras que los generaron (más antiguo primero).
  /// Ídem `.get()` puntual: es de solo lectura.
  Future<List<HistorialPrecioCompraModel>> obtenerHistorialPreciosCompra(String idProducto) async {
    final snap = await _col.doc(idProducto).collection('historialPreciosCompra').orderBy('fecha').get();
    return snap.docs.map((d) => HistorialPrecioCompraModel.fromMap(d.id, d.data())).toList();
  }

  /// Historial de ventas del producto, en el orden en que se fueron
  /// registrando (más antiguo primero). Ídem `.get()` puntual: es de solo
  /// lectura.
  Future<List<HistorialVentaProductoModel>> obtenerHistorialVentas(String idProducto) async {
    final snap = await _col.doc(idProducto).collection('historialVentas').orderBy('fecha').get();
    return snap.docs.map((d) => HistorialVentaProductoModel.fromMap(d.id, d.data())).toList();
  }
}