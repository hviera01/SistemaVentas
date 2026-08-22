import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/reporte_financiero_model.dart';
import '../../../../core/utils/formato_moneda.dart';

const colorVentasFinanciero = Color(0xFFC62828);
const colorComprasFinanciero = Color(0xFFF59E0B);
const _paletaUsuarios = [Color(0xFFC62828), Color(0xFF0EA5A4), Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF22C55E)];
const _colorOtros = Color(0xFF64748B);

String formatoCantidadFinanciero(double cantidad) {
  if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
  return cantidad.toStringAsFixed(2);
}

Widget _tarjeta({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFC7CBD3)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: child,
  );
}

Widget _explicacion(String texto) {
  return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(texto, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)));
}

Widget _stat(String titulo, double valor, Color color, {String? sub}) {
  return Container(
    width: 210,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85), letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
        if (sub != null) Text(sub, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.85))),
      ],
    ),
  );
}

Widget _flechaOperacion(IconData icono) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Icon(icono, color: Colors.grey.shade400, size: 22),
  );
}

Widget _filaValor(String etiqueta, double valor) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
      Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
    ],
  );
}

Widget _leyenda(String texto, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(texto, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700)),
    ],
  );
}

// ---------- Utilidad Bruta y Neta ----------

Widget seccionUtilidad(ReporteFinancieroData data, bool esMovil) {
  final filaBruta = Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    runSpacing: 10,
    children: [
      _stat('Ventas (con ISV)', data.ventasPeriodo, colorVentasFinanciero),
      _flechaOperacion(Icons.remove),
      _stat('Costo de Ventas', data.costoVentas, const Color(0xFF64748B)),
      _flechaOperacion(Icons.drag_handle),
      _stat('Utilidad Bruta', data.utilidadBruta, const Color(0xFF16A34A), sub: '${data.margenBrutoPorcentaje.toStringAsFixed(1)}% margen'),
    ],
  );
  final filaNeta = Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    runSpacing: 10,
    children: [
      _stat('Utilidad Bruta', data.utilidadBruta, const Color(0xFF16A34A)),
      _flechaOperacion(Icons.remove),
      _stat('Gastos (Egresos)', data.gastosPeriodo, const Color(0xFF64748B)),
      _flechaOperacion(Icons.drag_handle),
      _stat('Utilidad Neta', data.utilidadNeta, data.utilidadNeta >= 0 ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
    ],
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Utilidad bruta: lo que dejan las ventas después de su costo. Utilidad neta: la utilidad bruta después de los gastos operativos registrados en Egresos.'),
      Text('VENTAS − COSTOS = UTILIDAD BRUTA', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.3)),
      const SizedBox(height: 10),
      filaBruta,
      const SizedBox(height: 20),
      Text('UTILIDAD BRUTA − GASTOS = UTILIDAD NETA', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.3)),
      const SizedBox(height: 10),
      filaNeta,
      const SizedBox(height: 24),
      Text('Ganancia por Venta', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Cada venta individual del periodo, con su costo y ganancia.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      _tabaGananciaPorVenta(data.gananciaPorVenta, esMovil),
    ],
  );
}

Widget _tabaGananciaPorVenta(List<GananciaPorVenta> lista, bool esMovil) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Sin ventas en el rango seleccionado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final formatoFecha = DateFormat('dd/MM/yyyy');
  return _tarjeta(
    child: Column(
      children: [
        Row(
          children: [
            SizedBox(width: 90, child: Text('FECHA', style: _estiloHeaderTabla())),
            Expanded(flex: 2, child: Text('DOCUMENTO / CLIENTE', style: _estiloHeaderTabla())),
            if (!esMovil) Expanded(child: Text('VENTAS', textAlign: TextAlign.right, style: _estiloHeaderTabla())),
            if (!esMovil) Expanded(child: Text('COSTO', textAlign: TextAlign.right, style: _estiloHeaderTabla())),
            Expanded(child: Text('GANANCIA', textAlign: TextAlign.right, style: _estiloHeaderTabla())),
            SizedBox(width: 55, child: Text('MARGEN', textAlign: TextAlign.right, style: _estiloHeaderTabla())),
          ],
        ),
        Divider(height: 16, color: Colors.grey.shade300),
        for (final v in lista.take(50)) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(v.fecha != null ? formatoFecha.format(v.fecha!) : '-', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600))),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.numeroDocumento, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(v.cliente, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (!esMovil) Expanded(child: Text(formatearMoneda(v.ventas), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12))),
                if (!esMovil) Expanded(child: Text(formatearMoneda(v.costo), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
                Expanded(child: Text(formatearMoneda(v.ganancia), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: v.ganancia >= 0 ? const Color(0xFF16A34A) : const Color(0xFFC62828)))),
                SizedBox(width: 55, child: Text('${v.margenPorcentaje.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600))),
              ],
            ),
          ),
          if (v != lista.take(50).last) Divider(height: 1, color: Colors.grey.shade200),
        ],
        if (lista.length > 50) Padding(padding: const EdgeInsets.only(top: 10), child: Text('+ ${lista.length - 50} más...', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500))),
      ],
    ),
  );
}

TextStyle _estiloHeaderTabla() => GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.3);

// ---------- Flujo de Efectivo ----------

Widget seccionFlujoEfectivo(ReporteFinancieroData data, bool esMovil) {
  final flujo = data.flujoEfectivo;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Lo efectivamente cobrado y pagado en el periodo — no es lo mismo que la utilidad (esa mide lo vendido, esta mide lo cobrado).'),
      _tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _filaValor('Ingresos (Efectivo)', flujo.ingresosEfectivo),
                _filaValor('Ingresos (Tarjeta)', flujo.ingresosTarjeta),
                _filaValor('Ingresos (Transferencia)', flujo.ingresosTransferencia),
                _filaValor('Egresos (Efectivo)', flujo.egresosEfectivo),
                _filaValor('Egresos (Transferencia)', flujo.egresosTransferencia),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(color: flujo.neto >= 0 ? const Color(0xFF16A34A) : const Color(0xFFC62828), borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('FLUJO NETO', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(formatearMoneda(flujo.neto), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ---------- Comparación mensual ----------

Widget seccionComparacionMensual(ReporteFinancieroData data, bool esMovil) {
  final serie = data.serieMensual;
  final maximo = serie.fold<double>(0, (m, p) => [m, p.totalVentas, p.totalCompras].reduce((a, b) => a > b ? a : b));
  final formatoMes = DateFormat('MMM yy', 'es');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Ventas y compras de los últimos 6 meses, terminando en el mes actual (independiente del rango de fechas de arriba).'),
      _tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [_leyenda('Ventas', colorVentasFinanciero), const SizedBox(width: 16), _leyenda('Compras', colorComprasFinanciero)]),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maximo <= 0 ? 100 : maximo * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(formatearMoneda(rod.toY), GoogleFonts.poppins(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= serie.length) return const SizedBox();
                          return Padding(padding: const EdgeInsets.only(top: 8), child: Text(formatoMes.format(serie[i].mes), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade600)));
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < serie.length; i++)
                      BarChartGroupData(x: i, barsSpace: 4, barRods: [
                        BarChartRodData(toY: serie[i].totalVentas, color: colorVentasFinanciero, width: 12, borderRadius: BorderRadius.circular(4)),
                        BarChartRodData(toY: serie[i].totalCompras, color: colorComprasFinanciero, width: 12, borderRadius: BorderRadius.circular(4)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final p in serie)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(width: 70, child: Text(formatoMes.format(p.mes), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
                    Expanded(child: Text('Ventas: ${formatearMoneda(p.totalVentas)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700))),
                    Expanded(child: Text('Compras: ${formatearMoneda(p.totalCompras)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

// ---------- Ranking de productos ----------

Widget seccionRankingProductos(ReporteFinancieroData data, bool esMovil) {
  final columnas = [
    _tablaRanking('Más vendidos (cantidad)', data.topVendidosPorCantidad, esCantidad: true),
    _tablaRanking('Más comprados (cantidad)', data.topCompradosPorCantidad, esCantidad: true),
    _tablaRanking('Mayor ganancia', data.topGananciaPorProducto, esCantidad: false),
  ];
  final grilla = esMovil
      ? Column(children: [for (final c in columnas) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in columnas) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))]);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_explicacion('Top 10 de todo el rango de fechas seleccionado.'), grilla],
  );
}

Widget _tablaRanking(String titulo, List<RankingProducto> lista, {required bool esCantidad}) {
  final maximo = lista.isEmpty ? 1.0 : (esCantidad ? lista.first.cantidad : lista.first.monto).abs();
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (lista.isEmpty) Text('Sin datos en el rango', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
        for (final item in lista) _filaRanking(item, maximo, esCantidad: esCantidad),
      ],
    ),
  );
}

Widget _filaRanking(RankingProducto item, double maximo, {required bool esCantidad}) {
  final valor = esCantidad ? item.cantidad : item.monto;
  final proporcion = maximo <= 0 ? 0.0 : (valor.abs() / maximo).clamp(0.0, 1.0);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            Text(esCantidad ? formatoCantidadFinanciero(valor) : formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: proporcion, minHeight: 6, backgroundColor: const Color(0xFFF0F1F5), color: colorVentasFinanciero),
        ),
      ],
    ),
  );
}

// ---------- Productos sin venta ----------

Widget seccionProductosSinVenta(ReporteFinancieroData data, bool esMovil) {
  final lista = data.productosSinVenta;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Productos activos que no tuvieron ninguna venta en el rango de fechas seleccionado.'),
      _tarjeta(
        child: lista.isEmpty
            ? Text('Todos los productos activos tuvieron al menos una venta en el rango.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${lista.length} producto(s) sin movimiento — valor total en inventario: ${formatearMoneda(lista.fold<double>(0, (s, p) => s + p.valorInventario))}',
                      style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  for (final p in lista.take(30))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(child: Text(p.nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 90, child: Text('Stock: ${formatoCantidadFinanciero(p.stock)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
                          SizedBox(width: 110, child: Text(formatearMoneda(p.valorInventario), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  if (lista.length > 30) Padding(padding: const EdgeInsets.only(top: 8), child: Text('+ ${lista.length - 30} más...', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500))),
                ],
              ),
      ),
    ],
  );
}

// ---------- Ventas por usuario ----------

Widget seccionVentasPorUsuario(ReporteFinancieroData data, bool esMovil) {
  final lista = data.ventasPorUsuario;
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Sin ventas en el rango seleccionado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final top = lista.take(5).toList();
  final resto = lista.skip(5).toList();
  final otrosTotal = resto.fold<double>(0, (s, u) => s + u.totalVentas);
  final total = lista.fold<double>(0, (s, u) => s + u.totalVentas);

  final segmentos = <MapEntry<String, double>>[
    for (final u in top) MapEntry(u.usuario, u.totalVentas),
    if (otrosTotal > 0) MapEntry('Otros', otrosTotal),
  ];

  final grafico = SizedBox(
    height: 180,
    width: 180,
    child: PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          for (var i = 0; i < segmentos.length; i++)
            PieChartSectionData(
              value: segmentos[i].value,
              color: i < top.length ? _paletaUsuarios[i % _paletaUsuarios.length] : _colorOtros,
              title: total <= 0 ? '' : '${(segmentos[i].value / total * 100).toStringAsFixed(0)}%',
              titleStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              radius: 55,
            ),
        ],
      ),
    ),
  );

  final tabla = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lista.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: i < top.length ? _paletaUsuarios[i % _paletaUsuarios.length] : _colorOtros, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(lista[i].usuario, style: GoogleFonts.poppins(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
              Text('${lista[i].cantidadTransacciones} vtas.', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
              const SizedBox(width: 10),
              SizedBox(width: 100, child: Text(formatearMoneda(lista[i].totalVentas), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
            ],
          ),
        ),
    ],
  );

  return _tarjeta(
    child: esMovil
        ? Column(children: [Center(child: grafico), const SizedBox(height: 16), tabla])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [grafico, const SizedBox(width: 24), Expanded(child: tabla)]),
  );
}

// ---------- Abonos a compras crédito ----------

Widget seccionAbonosComprasCredito(ReporteFinancieroData data, bool esMovil) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Total enviado a proveedores como abono de compras a crédito en el rango seleccionado.'),
      _tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TOTAL ABONADO A PROVEEDORES', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(formatearMoneda(data.totalAbonosComprasCredito), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
            if (data.abonosPorProveedor.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final a in data.abonosPorProveedor)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(a.proveedor, style: GoogleFonts.poppins(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                      Text(formatearMoneda(a.total), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

// ---------- Recomendación de pago ----------

Widget seccionRecomendacionPago(ReporteFinancieroData data, bool esMovil) {
  final r = data.recomendacionPago;
  final tarjetas = [
    _tarjetaRecomendacion(
      'Según caja disponible',
      r.sugeridoPorCaja,
      'Efectivo estimado (${formatearMoneda(r.efectivoEstimado)}) menos reserva de gastos fijos (${formatearMoneda(r.reservaGastosFijos)}) menos un colchón de seguridad del 20%.',
    ),
    _tarjetaRecomendacion(
      'Según ventas cobradas',
      r.sugeridoPorVentas,
      '35% de lo cobrado en efectivo en el rango seleccionado (${formatearMoneda(r.ingresoEfectivoCobrado)}).',
    ),
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Dos referencias distintas para decidir cuánto abonar a proveedores sin quedarte sin flujo — son sugerencias, no reglas fijas.'),
      esMovil
          ? Column(children: [for (final t in tarjetas) Padding(padding: const EdgeInsets.only(bottom: 12), child: t)])
          : Row(children: [for (final t in tarjetas) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: t))]),
    ],
  );
}

Widget _tarjetaRecomendacion(String titulo, double monto, String explicacion) {
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        Text(formatearMoneda(monto), style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
        const SizedBox(height: 8),
        Text(explicacion, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600)),
      ],
    ),
  );
}

// ---------- Balance general ----------

Widget seccionBalanceGeneral(ReporteFinancieroData data, bool esMovil) {
  final b = data.balanceGeneral;
  final activos = _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVOS', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A), letterSpacing: 0.4)),
        const SizedBox(height: 10),
        _filaBalance('Inventario a costo', b.inventarioACosto),
        _filaBalance('Cuentas por cobrar', b.cuentasPorCobrar),
        _filaBalance('Efectivo estimado', b.efectivoEstimado),
        const Divider(height: 20),
        _filaBalance('Total Activos', b.totalActivos, negrita: true),
      ],
    ),
  );
  final pasivosYPatrimonio = _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PASIVOS Y PATRIMONIO', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFC62828), letterSpacing: 0.4)),
        const SizedBox(height: 10),
        _filaBalance('Cuentas por pagar', b.cuentasPorPagar),
        _filaBalance('Patrimonio (estimado)', b.patrimonio),
        const Divider(height: 20),
        _filaBalance('Total Pasivos + Patrimonio', b.totalPasivos + b.patrimonio, negrita: true),
      ],
    ),
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion('Aproximación con los datos disponibles: no reemplaza un balance contable formal (no incluye activos fijos ni capital aportado).'),
      esMovil
          ? Column(children: [activos, const SizedBox(height: 12), pasivosYPatrimonio])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: activos), const SizedBox(width: 12), Expanded(child: pasivosYPatrimonio)]),
    ],
  );
}

// ---------- Inteligencia de Negocios ----------

Widget seccionInteligenciaNegocio(ReporteFinancieroData data, bool esMovil) {
  final ia = data.inteligenciaNegocio;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion(
        'Analítica pensada para decisiones: hacia dónde van las ventas, qué tan rentable es el negocio, qué conviene reponer primero y a qué proveedor priorizar. Se calcula con los mismos datos del resto del reporte, sin consultas adicionales. El ranking de productos por rentabilidad está en la pestaña "Ranking de Productos".',
      ),
      _tarjetaPronostico(ia.pronosticoVentas, data),
      const SizedBox(height: 16),
      _tarjetaComparacionMesAnterior(data.serieMensual),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _statMini('Rotación de inventario', '${ia.rotacionInventario.toStringAsFixed(2)}x', 'Veces que se vendió el inventario completo en el periodo', const Color(0xFF3B82F6)),
          _statMini('Ticket promedio', formatearMoneda(ia.ticketPromedio), 'Venta promedio por transacción', const Color(0xFF16A34A)),
          _statMini('Valor de stock muerto', formatearMoneda(ia.valorStockMuerto), 'Inventario a costo sin ninguna venta en el periodo', const Color(0xFF64748B)),
        ],
      ),
      const SizedBox(height: 20),
      Text('Composición de la Venta', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('De cada Lempira vendido en el periodo, cuánto se fue en costo de venta, cuánto en gastos y cuánto quedó de utilidad neta.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      _graficoComposicionVenta(data, esMovil),
      const SizedBox(height: 20),
      Text('Tendencia de Margen Bruto Mensual', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Margen aproximado por mes: (ventas − compras) ÷ ventas. Usa compras del mes como estimado del costo, no el costo exacto de lo vendido.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      _graficoTendenciaMargen(data.serieMensual),
      const SizedBox(height: 20),
      Text('Sugerencia de Compras', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(
        'Productos activos que, a su ritmo de venta reciente, se agotarían en menos de $_diasUmbralReposicionTexto días. Se avisa cuando el proveedor asociado tiene cuentas vencidas.',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 10),
      _tablaSugerenciasCompra(ia.sugerenciasCompra, esMovil),
      const SizedBox(height: 20),
      Text('Clientes que Más Compran', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text('Top 10 por monto comprado en el periodo (no incluye Consumidor Final).', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      _tablaClientesTop(ia.clientesTop),
    ],
  );
}

const _diasUmbralReposicionTexto = '14';

Widget _tarjetaPronostico(PronosticoVentas p, ReporteFinancieroData data) {
  final colorTendencia = p.tendenciaMensual == 0 ? Colors.grey.shade500 : (p.tendenciaAlAlza ? const Color(0xFF16A34A) : const Color(0xFFC62828));
  final iconoTendencia = p.tendenciaMensual == 0 ? Icons.trending_flat : (p.tendenciaAlAlza ? Icons.trending_up : Icons.trending_down);
  // Utilidad neta proyectada: aplica el margen neto real de este periodo
  // (utilidadNeta / ventasPeriodo) al monto de ventas pronosticado. Es una
  // extrapolación simple -asume que gastos y costos guardan la misma
  // proporción el próximo mes-, no una proyección contable formal.
  final margenNetoActual = data.ventasPeriodo <= 0 ? 0.0 : data.utilidadNeta / data.ventasPeriodo;
  final utilidadProyectada = p.montoEstimado * margenNetoActual;
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRONÓSTICO · PRÓXIMO MES', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            Text(formatearMoneda(p.montoEstimado), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: colorTendencia.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoTendencia, size: 15, color: colorTendencia),
                  const SizedBox(width: 4),
                  Text(
                    p.tendenciaMensual == 0 ? 'Sin tendencia clara' : '${formatearMoneda(p.tendenciaMensual.abs())}/mes',
                    style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: colorTendencia),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${p.metodo} · promedio de los últimos meses: ${formatearMoneda(p.promedioUltimosMeses)}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
        const Divider(height: 24),
        Text('UTILIDAD NETA PROYECTADA', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        Text(formatearMoneda(utilidadProyectada), style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
        const SizedBox(height: 4),
        Text('Aplica el margen neto de este periodo (${(margenNetoActual * 100).toStringAsFixed(1)}%) al pronóstico de ventas. Estimado, no proyección contable.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
      ],
    ),
  );
}

/// Compara el último mes cerrado de [serie] contra el anterior (ventas y
/// compras), con variación porcentual — distinto de la sección
/// "Comparación mensual" del reporte, que muestra el histórico completo
/// sin resaltar el cambio mes a mes.
Widget _tarjetaComparacionMesAnterior(List<PuntoMensual> serie) {
  if (serie.length < 2) {
    return _tarjeta(child: Text('Se necesitan al menos 2 meses de historial para comparar.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final actual = serie[serie.length - 1];
  final anterior = serie[serie.length - 2];
  final formatoMes = DateFormat('MMMM yyyy', 'es');
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_capitalizar(formatoMes.format(actual.mes))} vs. ${_capitalizar(formatoMes.format(anterior.mes))}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _comparacionVariacion('Ventas', actual.totalVentas, anterior.totalVentas, colorVentasFinanciero),
            _comparacionVariacion('Compras', actual.totalCompras, anterior.totalCompras, colorComprasFinanciero),
          ],
        ),
      ],
    ),
  );
}

String _capitalizar(String texto) => texto.isEmpty ? texto : '${texto[0].toUpperCase()}${texto.substring(1)}';

Widget _comparacionVariacion(String etiqueta, double actual, double anterior, Color color) {
  final variacion = anterior <= 0 ? null : ((actual - anterior) / anterior) * 100;
  final subio = variacion != null && variacion >= 0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(formatearMoneda(actual), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
          if (variacion != null) ...[
            const SizedBox(width: 8),
            Icon(subio ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
            Text('${variacion.abs().toStringAsFixed(1)}%', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: subio ? const Color(0xFF16A34A) : const Color(0xFFC62828))),
          ],
        ],
      ),
    ],
  );
}

/// Dona con la composición de cada Lempira vendido en el periodo: costo de
/// ventas, gastos operativos y lo que queda de utilidad neta. Usa los
/// mismos totales que ya se muestran arriba del reporte (Ventas, Costo de
/// Ventas, Gastos, Utilidad Neta), solo que en formato visual.
Widget _graficoComposicionVenta(ReporteFinancieroData data, bool esMovil) {
  final ventas = data.ventasPeriodo;
  if (ventas <= 0) {
    return _tarjeta(child: Text('Sin ventas en el periodo para calcular la composición.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final costo = data.costoVentas.clamp(0, ventas).toDouble();
  final gastos = data.gastosPeriodo.clamp(0, ventas).toDouble();
  final utilidad = (ventas - costo - gastos).clamp(0, ventas).toDouble();
  final segmentos = [
    ('Costo de ventas', costo, const Color(0xFFF59E0B)),
    ('Gastos', gastos, const Color(0xFF8B5CF6)),
    ('Utilidad neta', utilidad, const Color(0xFF16A34A)),
  ].where((s) => s.$2 > 0).toList();

  return _tarjeta(
    child: esMovil
        ? Column(children: [_donaComposicion(segmentos, ventas), const SizedBox(height: 16), _leyendaComposicion(segmentos, ventas)])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _donaComposicion(segmentos, ventas),
              const SizedBox(width: 24),
              Expanded(child: _leyendaComposicion(segmentos, ventas)),
            ],
          ),
  );
}

Widget _donaComposicion(List<(String, double, Color)> segmentos, double total) {
  return SizedBox(
    height: 170,
    width: 170,
    child: PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 45,
        sections: [
          for (final s in segmentos)
            PieChartSectionData(
              value: s.$2,
              color: s.$3,
              title: '${(s.$2 / total * 100).toStringAsFixed(0)}%',
              titleStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              radius: 50,
            ),
        ],
      ),
    ),
  );
}

Widget _leyendaComposicion(List<(String, double, Color)> segmentos, double total) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final s in segmentos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(s.$1, style: GoogleFonts.poppins(fontSize: 12.5))),
              Text(formatearMoneda(s.$2), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
    ],
  );
}

/// Línea de margen bruto aproximado mes a mes, para ver si el negocio viene
/// mejorando o empeorando su rentabilidad relativa (no solo el monto de
/// ventas, que es lo que ya muestra "Comparación mensual").
Widget _graficoTendenciaMargen(List<PuntoMensual> serie) {
  if (serie.length < 2) {
    return _tarjeta(child: Text('Se necesitan al menos 2 meses de historial para ver una tendencia.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final formatoMes = DateFormat('MMM yy', 'es');
  final puntos = <FlSpot>[
    for (var i = 0; i < serie.length; i++)
      if (serie[i].totalVentas > 0) FlSpot(i.toDouble(), ((serie[i].totalVentas - serie[i].totalCompras) / serie[i].totalVentas) * 100),
  ];
  if (puntos.length < 2) {
    return _tarjeta(child: Text('No hay suficientes meses con ventas para calcular la tendencia.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final minY = puntos.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  final maxY = puntos.map((p) => p.y).reduce((a, b) => a > b ? a : b);
  return _tarjeta(
    child: SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: (minY - 5).clamp(-100, 100).toDouble(),
          maxY: (maxY + 5).clamp(-100, 100).toDouble(),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem('${s.y.toStringAsFixed(1)}%', GoogleFonts.poppins(color: Colors.white, fontSize: 11))).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(0)}%', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= serie.length) return const SizedBox();
                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text(formatoMes.format(serie[i].mes), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade600)));
                },
              ),
            ),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: puntos,
              isCurved: true,
              color: const Color(0xFF16A34A),
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: const Color(0xFF16A34A).withOpacity(0.08)),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _statMini(String titulo, String valor, String explicacion, Color color) {
  return Container(
    width: 230,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        Text(valor, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
        const SizedBox(height: 4),
        Text(explicacion, style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
      ],
    ),
  );
}

Widget _tablaSugerenciasCompra(List<SugerenciaCompra> lista, bool esMovil) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Ningún producto activo está por agotarse a su ritmo de venta reciente.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  return _tarjeta(
    child: Column(
      children: [
        for (final s in lista) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(s.nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(child: Text('Stock: ${formatoCantidadFinanciero(s.stockActual)}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600))),
                    Expanded(
                      child: Text(
                        '${s.diasParaAgotarse.toStringAsFixed(0)} día(s)',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: s.diasParaAgotarse <= 3 ? const Color(0xFFC62828) : const Color(0xFFF59E0B)),
                      ),
                    ),
                  ],
                ),
                if (s.proveedor != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(s.proveedorAlDia ? Icons.check_circle_outline : Icons.warning_amber_outlined, size: 13, color: s.proveedorAlDia ? const Color(0xFF16A34A) : const Color(0xFFC62828)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          s.proveedorAlDia
                              ? 'Proveedor: ${s.proveedor} · al día'
                              : 'Proveedor: ${s.proveedor} · tiene cuentas vencidas por ${formatearMoneda(s.deudaVencidaProveedor)}, priorizar el pago antes de comprarle más',
                          style: GoogleFonts.poppins(fontSize: 11, color: s.proveedorAlDia ? Colors.grey.shade600 : const Color(0xFFC62828)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text('Sin proveedor reciente registrado para este producto.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ],
            ),
          ),
          if (s != lista.last) Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    ),
  );
}

Widget _tablaClientesTop(List<ClienteTop> lista) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Sin compras de clientes identificados en el rango seleccionado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final maximo = lista.first.totalComprado;
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in lista)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c.cliente, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    Text('${c.cantidadCompras} compra(s)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(width: 10),
                    SizedBox(width: 100, child: Text(formatearMoneda(c.totalComprado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maximo <= 0 ? 0 : (c.totalComprado / maximo).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF0F1F5),
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// ---------- Clientes (mejores clientes, no registrados, inactivos) ----------

const _diasInactivoTexto = '90';

Widget seccionClientes(ReporteFinancieroData data, bool esMovil) {
  final ia = data.inteligenciaNegocio;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _explicacion(
        'Mejores clientes, ventas a nombres que todavía no quedaron vinculados a un cliente registrado, y clientes activos que llevan más de $_diasInactivoTexto días sin comprar. Se calcula con los mismos datos del resto del reporte, sin consultas adicionales.',
      ),
      Text('Mejores Clientes', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(
        'Top 10 por monto comprado en el periodo (agrupado por el cliente vinculado cuando existe; si no, por el nombre tal como se escribió). No incluye Consumidor Final.',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 10),
      _tablaMejoresClientesConTicket(ia.clientesTop),
      const SizedBox(height: 20),
      Text('Ventas a Nombres No Registrados', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(
        'Nombres tipeados en la venta que no quedaron vinculados a ningún cliente registrado. Debería ir bajando con el tiempo, ya que las ventas nuevas con nombre se auto-registran solas.',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 10),
      _tablaVentasNoRegistradas(ia.ventasNoRegistradas),
      const SizedBox(height: 20),
      Text('Clientes Inactivos', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(
        'Clientes activos con más de $_diasInactivoTexto días sin comprar, o que nunca han comprado (independiente del rango de fechas de arriba: se calcula sobre la fecha de última compra de cada cliente).',
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 10),
      _listaClientesInactivos(ia.clientesInactivos),
    ],
  );
}

Widget _tablaMejoresClientesConTicket(List<ClienteTop> lista) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Sin compras de clientes identificados en el rango seleccionado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  final maximo = lista.first.totalComprado;
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in lista)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c.cliente, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    Text('${c.cantidadCompras} compra(s)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(width: 10),
                    SizedBox(width: 100, child: Text(formatearMoneda(c.totalComprado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Ticket promedio: ${formatearMoneda(c.ticketPromedio)}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maximo <= 0 ? 0 : (c.totalComprado / maximo).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF0F1F5),
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _tablaVentasNoRegistradas(List<VentaSinCliente> lista) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Todas las ventas con nombre quedaron vinculadas a un cliente registrado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  return _tarjeta(
    child: Column(
      children: [
        for (final v in lista) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(v.nombre, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                Text('${v.cantidadVentas} venta(s)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(width: 10),
                SizedBox(width: 100, child: Text(formatearMoneda(v.totalComprado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          if (v != lista.last) Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    ),
  );
}

Widget _listaClientesInactivos(List<ClienteInactivo> lista) {
  if (lista.isEmpty) {
    return _tarjeta(child: Text('Ningún cliente activo lleva más de $_diasInactivoTexto días sin comprar.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)));
  }
  return _tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${lista.length} cliente(s) inactivo(s)', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        for (final c in lista.take(30))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(c.nombreCompleto, style: GoogleFonts.poppins(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                Text(
                  c.diasSinComprar == null ? 'Nunca ha comprado' : 'Hace ${c.diasSinComprar} días',
                  style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        if (lista.length > 30) Padding(padding: const EdgeInsets.only(top: 8), child: Text('+ ${lista.length - 30} más...', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500))),
      ],
    ),
  );
}

Widget _filaBalance(String etiqueta, double valor, {bool negrita = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400)),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: negrita ? FontWeight.w800 : FontWeight.w600)),
      ],
    ),
  );
}
