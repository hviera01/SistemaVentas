// Replica en Node (para poder correr aparte de la app de Flutter) el mismo
// cálculo que ya hace ReporteFinancieroRepository.obtenerReporte en Dart:
// mismos campos, mismos filtros (estado Activa, sin cotizaciones), mismas
// colecciones. Ver lib/features/reportes/data/reporte_financiero_repository.dart
// como referencia si el cálculo de allá cambia y hay que actualizar esto.
const { consultarPorRangoFecha, consultarColeccionCompleta } = require('./firestore');

// Cuántos clientes/nombres entran en cada ranking del Resumen de Clientes
// (mismo tope que _topN en reporte_financiero_repository.dart).
const TOP_N_CLIENTES = 10;

// Días sin comprar a partir de los cuales un cliente activo se considera
// inactivo. Debe coincidir con _diasUmbralClienteInactivo en
// reporte_financiero_repository.dart (Dart) -mantenerlos sincronizados a
// mano si ese número cambia, este archivo no lo importa de allá-.
const DIAS_UMBRAL_CLIENTE_INACTIVO = 90;

// ---- Resumen de Clientes: mismo idioma que
// ReporteFinancieroRepository._agruparClientesTop/_agruparVentasSinCliente/
// _calcularClientesInactivos en Dart (ver ese archivo para los comentarios
// completos de cada regla) ----

function agruparClientesTop(ventasValidas) {
  const totalPorClave = new Map();
  const conteoPorClave = new Map();
  const nombrePorClave = new Map();
  for (const v of ventasValidas) {
    const nombre = v.nombreCliente || 'CONSUMIDOR FINAL';
    if (nombre.toUpperCase() === 'CONSUMIDOR FINAL') continue;
    const clave = v.idCliente ? `id:${v.idCliente}` : `nombre:${nombre.trim().toUpperCase()}`;
    totalPorClave.set(clave, (totalPorClave.get(clave) || 0) + (v.totalAPagar || 0));
    conteoPorClave.set(clave, (conteoPorClave.get(clave) || 0) + 1);
    if (!nombrePorClave.has(clave)) nombrePorClave.set(clave, nombre);
  }
  return [...totalPorClave.keys()]
    .map((clave) => {
      const totalComprado = totalPorClave.get(clave) || 0;
      const cantidadCompras = conteoPorClave.get(clave) || 0;
      return {
        cliente: nombrePorClave.get(clave) || '',
        totalComprado,
        cantidadCompras,
        ticketPromedio: cantidadCompras > 0 ? totalComprado / cantidadCompras : 0,
      };
    })
    .sort((a, b) => b.totalComprado - a.totalComprado)
    .slice(0, TOP_N_CLIENTES);
}

function agruparVentasSinCliente(ventasValidas) {
  const totalPorClave = new Map();
  const conteoPorClave = new Map();
  const nombrePorClave = new Map();
  for (const v of ventasValidas) {
    if (v.idCliente) continue;
    const nombre = (v.nombreCliente || '').trim();
    if (!nombre || nombre.toUpperCase() === 'CONSUMIDOR FINAL') continue;
    const clave = nombre.toUpperCase();
    totalPorClave.set(clave, (totalPorClave.get(clave) || 0) + (v.totalAPagar || 0));
    conteoPorClave.set(clave, (conteoPorClave.get(clave) || 0) + 1);
    if (!nombrePorClave.has(clave)) nombrePorClave.set(clave, nombre);
  }
  return [...totalPorClave.keys()]
    .map((clave) => ({
      nombre: nombrePorClave.get(clave) || clave,
      cantidadVentas: conteoPorClave.get(clave) || 0,
      totalComprado: totalPorClave.get(clave) || 0,
    }))
    .sort((a, b) => b.cantidadVentas - a.cantidadVentas)
    .slice(0, TOP_N_CLIENTES);
}

function calcularClientesInactivos(clientes) {
  const ahora = new Date();
  const inactivos = [];
  for (const c of clientes) {
    if (c.estado !== true) continue;
    const ultimaCompra = c.fechaUltimaCompra || null;
    if (!ultimaCompra) {
      inactivos.push({ nombreCompleto: c.nombreCompleto || '', ultimaCompra: null, diasSinComprar: null });
      continue;
    }
    const dias = Math.floor((ahora.getTime() - ultimaCompra.getTime()) / (1000 * 60 * 60 * 24));
    if (dias > DIAS_UMBRAL_CLIENTE_INACTIVO) {
      inactivos.push({ nombreCompleto: c.nombreCompleto || '', ultimaCompra, diasSinComprar: dias });
    }
  }
  // Los que nunca han comprado van al final -no hay "hace cuántos días" que
  // ordenar ahí-; entre los demás, primero los que llevan más tiempo sin
  // comprar (más urgentes de recuperar).
  inactivos.sort((a, b) => {
    if (a.diasSinComprar === null && b.diasSinComprar === null) return 0;
    if (a.diasSinComprar === null) return 1;
    if (b.diasSinComprar === null) return -1;
    return b.diasSinComprar - a.diasSinComprar;
  });
  return inactivos;
}

async function calcularReporte(inicio, finInclusive) {
  const [ventas, compras, detalle, egresos, abonosCompra, clientes] = await Promise.all([
    consultarPorRangoFecha({ coleccion: 'ventas', campoFecha: 'fechaRegistro', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'compras', campoFecha: 'fechaRegistro', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'detalle', campoFecha: 'fecha', inicio, fin: finInclusive, collectionGroup: true }),
    consultarPorRangoFecha({ coleccion: 'egresos', campoFecha: 'fecha', inicio, fin: finInclusive }),
    consultarPorRangoFecha({ coleccion: 'abonosCompra', campoFecha: 'fecha', inicio, fin: finInclusive, collectionGroup: true }),
    consultarColeccionCompleta('clientes'),
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
    clientesTop: agruparClientesTop(ventasValidas),
    ventasNoRegistradas: agruparVentasSinCliente(ventasValidas),
    clientesInactivos: calcularClientesInactivos(clientes),
  };
}

module.exports = { calcularReporte, DIAS_UMBRAL_CLIENTE_INACTIVO };
