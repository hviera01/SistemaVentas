import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'reporte_financiero_model.dart';
import '../../../core/utils/formato_moneda.dart';

const _colorPrimario = PdfColor.fromInt(0xFFC62828);

class ReporteFinancieroExportService {
  Future<Uint8List> generarPdf(ReporteFinancieroData data) async {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final formatoMes = DateFormat('MMM yyyy', 'es');
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte Financiero', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _colorPrimario)),
                  pw.SizedBox(height: 4),
                  pw.Text('Del ${formatoFecha.format(data.inicio)} al ${formatoFecha.format(data.fin)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 14),
                ],
              )
            : pw.SizedBox(),
        build: (context) => [
          _seccionResumen(data),
          _seccionGananciaPorVenta(data, formatoFecha),
          _seccionFlujo(data),
          _seccionMensual(data, formatoMes),
          _seccionRankings(data),
          _seccionProductosSinVenta(data),
          _seccionVentasPorUsuario(data),
          _seccionAbonos(data),
          _seccionRecomendacion(data),
          _seccionBalance(data),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _titulo(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
      child: pw.Text(texto, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _colorPrimario)),
    );
  }

  pw.Widget _filaValor(String etiqueta, double valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(formatearMoneda(valor), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _tabla(List<String> headers, List<List<String>> filas) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: filas,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _colorPrimario),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EAF0)),
      border: null,
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  pw.Widget _seccionResumen(ReporteFinancieroData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Resumen'),
        _filaValor('Ventas del periodo', data.ventasPeriodo),
        _filaValor('Compras del periodo', data.comprasPeriodo),
        _filaValor('Costo de ventas', data.costoVentas),
        _filaValor('Utilidad Bruta', data.utilidadBruta),
        pw.Text('Margen bruto: ${data.margenBrutoPorcentaje.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        _filaValor('Gastos (Egresos)', data.gastosPeriodo),
        _filaValor('Utilidad Neta', data.utilidadNeta),
      ],
    );
  }

  pw.Widget _seccionGananciaPorVenta(ReporteFinancieroData data, DateFormat formatoFecha) {
    final lista = data.gananciaPorVenta;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Ganancia por Venta'),
        if (lista.isEmpty)
          pw.Text('Sin ventas en el rango seleccionado.', style: const pw.TextStyle(fontSize: 9))
        else
          _tabla(
            ['Fecha', 'Documento', 'Cliente', 'Ventas', 'Costo', 'Ganancia'],
            [
              for (final v in lista.take(50))
                [
                  v.fecha != null ? formatoFecha.format(v.fecha!) : '-',
                  v.numeroDocumento,
                  v.cliente,
                  formatearMoneda(v.ventas),
                  formatearMoneda(v.costo),
                  formatearMoneda(v.ganancia),
                ],
            ],
          ),
        if (lista.length > 50) pw.Text('+ ${lista.length - 50} más...', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      ],
    );
  }

  pw.Widget _seccionFlujo(ReporteFinancieroData data) {
    final f = data.flujoEfectivo;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Flujo de Efectivo'),
        pw.Text('Lo efectivamente cobrado y pagado en el periodo (no es lo mismo que la utilidad).', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        _filaValor('Ingresos (Efectivo)', f.ingresosEfectivo),
        _filaValor('Ingresos (Tarjeta)', f.ingresosTarjeta),
        _filaValor('Ingresos (Transferencia)', f.ingresosTransferencia),
        _filaValor('Egresos (Efectivo)', f.egresosEfectivo),
        _filaValor('Egresos (Transferencia)', f.egresosTransferencia),
        _filaValor('Flujo Neto', f.neto),
      ],
    );
  }

  pw.Widget _seccionMensual(ReporteFinancieroData data, DateFormat formatoMes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Ventas vs Compras · Últimos 6 meses'),
        _tabla(
          ['Mes', 'Ventas', 'Compras'],
          [for (final p in data.serieMensual) [formatoMes.format(p.mes), formatearMoneda(p.totalVentas), formatearMoneda(p.totalCompras)]],
        ),
      ],
    );
  }

  pw.Widget _seccionRankings(ReporteFinancieroData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Ranking de Productos'),
        pw.Text('Más vendidos (cantidad)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        _tabla(['Producto', 'Cantidad'], [for (final r in data.topVendidosPorCantidad) [r.nombreProducto, _formatoCantidad(r.cantidad)]]),
        pw.SizedBox(height: 10),
        pw.Text('Más comprados (cantidad)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        _tabla(['Producto', 'Cantidad'], [for (final r in data.topCompradosPorCantidad) [r.nombreProducto, _formatoCantidad(r.cantidad)]]),
        pw.SizedBox(height: 10),
        pw.Text('Mayor ganancia', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        _tabla(['Producto', 'Ganancia'], [for (final r in data.topGananciaPorProducto) [r.nombreProducto, formatearMoneda(r.monto)]]),
      ],
    );
  }

  pw.Widget _seccionProductosSinVenta(ReporteFinancieroData data) {
    final lista = data.productosSinVenta;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Productos Sin Movimiento (${lista.length})'),
        if (lista.isEmpty)
          pw.Text('Todos los productos activos tuvieron al menos una venta en el rango.', style: const pw.TextStyle(fontSize: 9))
        else
          _tabla(
            ['Producto', 'Stock', 'Valor en inventario'],
            [for (final p in lista.take(30)) [p.nombreProducto, _formatoCantidad(p.stock), formatearMoneda(p.valorInventario)]],
          ),
      ],
    );
  }

  pw.Widget _seccionVentasPorUsuario(ReporteFinancieroData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Ventas por Usuario'),
        _tabla(
          ['Usuario', 'Transacciones', 'Total vendido'],
          [for (final u in data.ventasPorUsuario) [u.usuario, u.cantidadTransacciones.toString(), formatearMoneda(u.totalVentas)]],
        ),
      ],
    );
  }

  pw.Widget _seccionAbonos(ReporteFinancieroData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Abonos a Compras Crédito'),
        _filaValor('Total abonado a proveedores', data.totalAbonosComprasCredito),
        if (data.abonosPorProveedor.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _tabla(['Proveedor', 'Total abonado'], [for (final a in data.abonosPorProveedor) [a.proveedor, formatearMoneda(a.total)]]),
        ],
      ],
    );
  }

  pw.Widget _seccionRecomendacion(ReporteFinancieroData data) {
    final r = data.recomendacionPago;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Recomendación de Pago a Proveedores'),
        pw.Text('Son referencias, no reglas fijas.', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        _filaValor('Sugerido según caja disponible', r.sugeridoPorCaja),
        pw.Text(
          'Efectivo estimado (${formatearMoneda(r.efectivoEstimado)}) menos reserva de gastos fijos (${formatearMoneda(r.reservaGastosFijos)}) menos colchón de seguridad del 20%.',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        _filaValor('Sugerido según ventas cobradas', r.sugeridoPorVentas),
        pw.Text(
          '35% de lo cobrado en efectivo en el rango seleccionado (${formatearMoneda(r.ingresoEfectivoCobrado)}).',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _seccionBalance(ReporteFinancieroData data) {
    final b = data.balanceGeneral;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Balance General (estimado)'),
        pw.Text(
          'Aproximación con los datos disponibles: no reemplaza un balance contable formal (no incluye activos fijos ni capital aportado).',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Activos', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        _filaValor('Inventario a costo', b.inventarioACosto),
        _filaValor('Cuentas por cobrar', b.cuentasPorCobrar),
        _filaValor('Efectivo estimado', b.efectivoEstimado),
        _filaValor('Total Activos', b.totalActivos),
        pw.SizedBox(height: 8),
        pw.Text('Pasivos y Patrimonio', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        _filaValor('Cuentas por pagar', b.cuentasPorPagar),
        _filaValor('Patrimonio (estimado)', b.patrimonio),
        _filaValor('Total Pasivos + Patrimonio', b.totalPasivos + b.patrimonio),
      ],
    );
  }
}
