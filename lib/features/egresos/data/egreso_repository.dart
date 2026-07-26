import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'egreso_model.dart';
import '../../reportes/data/reporte_repository.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';
import '../../compras_credito/data/compra_credito_repository.dart';

class EgresoRepository {
  final _col = FirebaseFirestore.instance.collection('egresos');
  final _reporteRepository = ReporteRepository();
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _compraCreditoRepository = CompraCreditoRepository();

  Future<void> crear(EgresoModel egreso) async {
    await _col.add(egreso.toMap());
  }

  Future<void> actualizar(EgresoModel egreso) async {
    await _col.doc(egreso.id).update(egreso.toMap());
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  Future<List<EgresoModel>> obtenerEgresosPorRango(DateTime inicio, DateTime finInclusive) async {
    final snap = await _col
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finInclusive))
        .orderBy('fecha', descending: true)
        .get();
    return snap.docs.map((d) => EgresoModel.fromMap(d.id, d.data())).toList();
  }

  /// Junta ventas de contado, abonos a crédito (venta y compra) y egresos
  /// manuales del rango en una sola lista de movimientos, igual que el libro
  /// financiero del sistema anterior.
  Future<List<T>> _tolerante<T>(String fuente, Future<List<T>> future) {
    return future.catchError((Object e) {
      debugPrint('Libro financiero: falló la fuente "$fuente": $e');
      return <T>[];
    });
  }

  Future<List<MovimientoFinanciero>> obtenerLibroFinanciero(DateTime inicio, DateTime finInclusive) async {
    final resultados = await Future.wait([
      _tolerante('ventas', _reporteRepository.obtenerReporteVentas(inicio, finInclusive)),
      _tolerante('compras', _reporteRepository.obtenerReporteCompras(inicio, finInclusive)),
      _tolerante('abonos venta crédito', _ventaCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive)),
      _tolerante('abonos compra crédito', _compraCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive)),
      _tolerante('egresos manuales', obtenerEgresosPorRango(inicio, finInclusive)),
    ]);

    final ventas = resultados[0] as List;
    final compras = resultados[1] as List;
    final abonosVenta = resultados[2] as List;
    final abonosCompra = resultados[3] as List;
    final egresos = resultados[4] as List<EgresoModel>;

    final movimientos = <MovimientoFinanciero>[];

    for (final v in ventas) {
      if (v.estado != 'Activa' || v.condicion != 'Contado' || v.tipoDocumento == 'Cotizacion') continue;
      final descripcion = 'Doc. ${v.numeroDocumento} · ${v.nombreCliente.isEmpty ? 'Consumidor final' : v.nombreCliente}';
      if (v.metodoPago == 'Mixto' && v.pagosMixtos.isNotEmpty) {
        // Una venta con pago mixto no cae en un solo balde de
        // efectivo/tarjeta/transferencia: se reparte en un movimiento por
        // cada método, cada uno con su propio monto, para que el cierre de
        // caja cuadre con lo que de verdad entró por cada método.
        for (final pago in v.pagosMixtos) {
          movimientos.add(MovimientoFinanciero(
            fecha: v.fechaRegistro ?? DateTime.now(),
            tipoMovimiento: 'Venta (Contado)',
            descripcion: '$descripcion (mixto)',
            ingreso: pago.monto,
            metodoPago: pago.metodoPago,
            usuario: v.usuarioRegistro,
          ));
        }
      } else {
        movimientos.add(MovimientoFinanciero(
          fecha: v.fechaRegistro ?? DateTime.now(),
          tipoMovimiento: 'Venta (Contado)',
          descripcion: descripcion,
          ingreso: v.totalAPagar,
          metodoPago: v.metodoPago,
          usuario: v.usuarioRegistro,
        ));
      }
    }

    for (final c in compras) {
      if (c.condicion == 'Credito' || !c.esActiva) continue;
      movimientos.add(MovimientoFinanciero(
        fecha: c.fechaRegistro ?? DateTime.now(),
        tipoMovimiento: 'Compra (Contado)',
        descripcion: 'Doc. ${c.numeroDocumento} · ${c.razonSocial}',
        egreso: c.montoTotal,
        metodoPago: c.metodoPago,
        usuario: c.usuarioRegistro,
      ));
    }

    for (final a in abonosVenta) {
      movimientos.add(MovimientoFinanciero(
        fecha: a.fecha ?? DateTime.now(),
        tipoMovimiento: 'Abono a Crédito',
        descripcion: 'Recibo ${a.numeroRecibo}',
        ingreso: a.montoAbonado,
        metodoPago: a.metodoPago,
        usuario: a.usuario,
      ));
    }

    for (final a in abonosCompra) {
      movimientos.add(MovimientoFinanciero(
        fecha: a.fecha ?? DateTime.now(),
        tipoMovimiento: 'Abono Compra Crédito',
        descripcion: '${a.nombreProveedor} · Recibo ${a.numeroRecibo}',
        egreso: a.montoAbonado,
        metodoPago: a.metodoPago,
        usuario: a.usuario,
      ));
    }

    for (final e in egresos) {
      movimientos.add(MovimientoFinanciero(
        fecha: e.fecha,
        tipoMovimiento: 'Egreso Manual',
        descripcion: e.descripcion,
        egreso: e.monto,
        metodoPago: e.metodoPago,
        categoria: e.categoria,
        esPagado: e.esPagado,
        fechaPago: e.fechaPago,
        usuario: e.usuario,
        idEgreso: e.id,
      ));
    }

    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));
    return movimientos;
  }
}
