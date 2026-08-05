// Replica en Node (para poder correr aparte de la app de Flutter) el mismo
// cálculo que ya hace ReporteFinancieroRepository.obtenerReporte en Dart:
// mismos campos, mismos filtros (estado Activa, sin cotizaciones), mismas
// colecciones. Ver lib/features/reportes/data/reporte_financiero_repository.dart
// como referencia si el cálculo de allá cambia y hay que actualizar esto.
const { consultarPorRangoFecha } = require('./firestore');

async function calcularReporte(inicio, finInclusive) {
  const [ventas, compras, detalle, egresos, abonosCompra] = await Promise.all([
    consultarPorRangoFecha({ coleccion: 'ventas', campoFecha: 'fechaRegistro', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'compras', campoFecha: 'fechaRegistro', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'detalle', campoFecha: 'fecha', inicio, fin: finInclusive, collectionGroup: true }),
    consultarPorRangoFecha({ coleccion: 'egresos', campoFecha: 'fecha', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'abonosCompra', campoFecha: 'fecha', inicio, fin: finInclusive, collectionGroup: true }),
  ]);

  const ventasValidas = ventas.filter((v) => v.estado === 'Activa' && v.tipoDocumento !== 'Cotizacion');
  const comprasValidas = compras.filter((c) => c.estado === 'Activa');
  const comprasCredito = comprasValidas.filter((c) => c.condicion === 'Credito');

  // detalle es collectionGroup: cada doc trae _segments tipo
  // ['ventas', '{idVenta}', 'detalle', '{idItem}'] o
  // ['compras', '{idCompra}', 'detalle', '{idItem}']. Solo interesan los de
  // ventas para el costo de lo vendido (costoVentas), igual que en Dart.
  const idsVentasValidas = new Set(ventasValidas.map((v) => v.id));
  const itemsVenta = detalle.filter((d) => d._segments[0] === 'ventas' && idsVentasValidas.has(d._segments[1]));

  const ventasPeriodo = ventasValidas.reduce((s, v) => s + (v.totalAPagar || 0), 0);
  const comprasPeriodo = comprasValidas.reduce((s, c) => s + (c.totalAPagar || 0), 0);
  const comprasCreditoPeriodo = comprasCredito.reduce((s, c) => s + (c.totalAPagar || 0), 0);
  const costoVentas = itemsVenta.reduce((s, i) => s + (i.precioCompraUsado || 0) * (i.cantidad || 0), 0);
  const utilidadBruta = ventasPeriodo - costoVentas;
  const gastosPeriodo = egresos.reduce((s, e) => s + (e.monto || 0), 0);
  const utilidadNeta = utilidadBruta - gastosPeriodo;

  const totalAbonosProveedores = abonosCompra.reduce((s, a) => s + (a.montoAbonado || 0), 0);
  const porProveedor = new Map();
  for (const a of abonosCompra) {
    const proveedor = a.nombreProveedor || 'N/A';
    porProveedor.set(proveedor, (porProveedor.get(proveedor) || 0) + (a.montoAbonado || 0));
  }
  const abonosPorProveedor = [...porProveedor.entries()]
    .map(([proveedor, total]) => ({ proveedor, total }))
    .sort((a, b) => b.total - a.total);

  return {
    inicio,
    fin: finInclusive,
    cantidadVentas: ventasValidas.length,
    cantidadCompras: comprasValidas.length,
    ventasPeriodo,
    comprasPeriodo,
    comprasCreditoPeriodo,
    costoVentas,
    utilidadBruta,
    gastosPeriodo,
    utilidadNeta,
    totalAbonosProveedores,
    abonosPorProveedor,
  };
}

module.exports = { calcularReporte };
