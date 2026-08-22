const PDFDocument = require('pdfkit');
const { nombreNegocio } = require('./config');
const { DIAS_UMBRAL_CLIENTE_INACTIVO } = require('./reporte');

function formatearMoneda(valor) {
  const monto = Math.round((valor + Number.EPSILON) * 100) / 100;
  return `L.${monto.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatearFecha(fecha) {
  return fecha.toLocaleDateString('es-HN', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function formatearFechaHora(fecha) {
  return fecha.toLocaleString('es-HN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

const COLOR = {
  marca: '#C62828',
  marcaOscuro: '#8E1B1B',
  texto: '#1A1A1A',
  gris: '#6B7280',
  grisClaro: '#9CA3AF',
  fondoCard: '#F7F7F9',
  borde: '#E9EAEE',
  verde: '#15803D',
  fondoVerde: '#EAF7EF',
  rojo: '#B91C1C',
  fondoRojo: '#FCEAEA',
};

const ANCHO_PAGINA = 612; // Letter
const MARGEN = 40;
const ANCHO_UTIL = ANCHO_PAGINA - MARGEN * 2;

// PDF con estética de "dashboard": cabecera de color de marca a todo el
// ancho, tarjetas KPI con los 3 números que más importan de un vistazo, y
// el resto del detalle en tarjetas con fondo suave en vez de texto plano.
// Genera los bytes en memoria (no escribe a disco) para mandarlos directo
// por WhatsApp.
function generarPdfReporte({ titulo, reporte }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 0 });
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // --- Cabecera ---
    const altoCabecera = 96;
    doc.rect(0, 0, ANCHO_PAGINA, altoCabecera).fill(COLOR.marca);
    doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(20).text(nombreNegocio, MARGEN, 26);
    doc.font('Helvetica').fontSize(12).fillColor('#FBE4E4').text(titulo, MARGEN, 52);
    doc.fontSize(9.5).fillColor('#F5C6C6').text(`Periodo: ${formatearFecha(reporte.inicio)} al ${formatearFecha(reporte.fin)}`, MARGEN, 70);

    let y = altoCabecera + 24;

    // --- Tarjetas KPI (Ventas / Utilidad bruta / Utilidad neta) ---
    const kpis = [
      { etiqueta: 'Ventas del periodo', valor: reporte.ventasPeriodo, sub: `${reporte.cantidadVentas} facturas` },
      { etiqueta: 'Utilidad bruta', valor: reporte.utilidadBruta, sub: null },
      { etiqueta: 'Utilidad neta', valor: reporte.utilidadNeta, sub: null, resaltarSigno: true },
    ];
    const espacioKpi = 12;
    const anchoKpi = (ANCHO_UTIL - espacioKpi * (kpis.length - 1)) / kpis.length;
    const altoKpi = 70;
    kpis.forEach((kpi, i) => {
      const x = MARGEN + i * (anchoKpi + espacioKpi);
      const negativo = kpi.resaltarSigno && kpi.valor < 0;
      const fondo = kpi.resaltarSigno ? (negativo ? COLOR.fondoRojo : COLOR.fondoVerde) : COLOR.fondoCard;
      const colorValor = kpi.resaltarSigno ? (negativo ? COLOR.rojo : COLOR.verde) : COLOR.texto;
      doc.roundedRect(x, y, anchoKpi, altoKpi, 10).fill(fondo);
      doc.fillColor(COLOR.gris).font('Helvetica').fontSize(9).text(kpi.etiqueta.toUpperCase(), x + 14, y + 12, { width: anchoKpi - 28 });
      doc.fillColor(colorValor).font('Helvetica-Bold').fontSize(15).text(formatearMoneda(kpi.valor), x + 14, y + 30, { width: anchoKpi - 28 });
      if (kpi.sub) doc.fillColor(COLOR.grisClaro).font('Helvetica').fontSize(8.5).text(kpi.sub, x + 14, y + 52, { width: anchoKpi - 28 });
    });
    y += altoKpi + 26;

    // --- Tarjeta: Detalle del periodo ---
    function filaDetalle(yFila, etiqueta, valor, { destacado = false, indent = 0 } = {}) {
      doc
        .font(destacado ? 'Helvetica-Bold' : 'Helvetica')
        .fontSize(destacado ? 11.5 : 10.5)
        .fillColor(destacado ? COLOR.marca : COLOR.texto)
        .text(`${' '.repeat(indent)}${etiqueta}`, MARGEN + 18, yFila, { continued: true, width: 320 })
        .text(valor, { align: 'right', width: ANCHO_UTIL - 36 - 320 });
    }

    const filasDetalle = [
      { etiqueta: `Ventas (${reporte.cantidadVentas} facturas)`, valor: reporte.ventasPeriodo },
      { etiqueta: `Compras (${reporte.cantidadCompras} facturas)`, valor: reporte.comprasPeriodo },
      { etiqueta: 'de las cuales al crédito', valor: reporte.comprasCreditoPeriodo, indent: 2 },
      { etiqueta: 'Costo de lo vendido', valor: reporte.costoVentas },
      { etiqueta: 'Utilidad bruta', valor: reporte.utilidadBruta, destacado: true },
      { etiqueta: 'Gastos (egresos)', valor: reporte.gastosPeriodo },
      { etiqueta: 'Utilidad neta', valor: reporte.utilidadNeta, destacado: true },
    ];
    const altoTituloCard = 34;
    const altoFila = 22;
    const altoCardDetalle = altoTituloCard + filasDetalle.length * altoFila + 12;

    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardDetalle, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text('Detalle del periodo', MARGEN + 18, y + 14);
    let yFila = y + altoTituloCard;
    for (const f of filasDetalle) {
      filaDetalle(yFila, f.etiqueta, formatearMoneda(f.valor), { indent: f.indent ?? 0, destacado: f.destacado ?? false });
      yFila += altoFila;
    }
    y += altoCardDetalle + 20;

    // --- Tarjeta: Abonos a proveedores ---
    const sinAbonos = reporte.abonosPorProveedor.length === 0;
    const altoCardProveedores = sinAbonos
      ? altoTituloCard + 26
      : altoTituloCard + reporte.abonosPorProveedor.length * altoFila + altoFila + 12;

    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardProveedores, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text('Abonos a proveedores (compras a crédito)', MARGEN + 18, y + 14);
    yFila = y + altoTituloCard;
    if (sinAbonos) {
      doc.font('Helvetica').fontSize(10).fillColor(COLOR.gris).text('Sin abonos a proveedores en este periodo.', MARGEN + 18, yFila);
    } else {
      for (const a of reporte.abonosPorProveedor) {
        filaDetalle(yFila, a.proveedor, formatearMoneda(a.total));
        yFila += altoFila;
      }
      // Línea separadora antes del total.
      doc.moveTo(MARGEN + 18, yFila + 2).lineTo(MARGEN + ANCHO_UTIL - 18, yFila + 2).strokeColor(COLOR.borde).lineWidth(1).stroke();
      filaDetalle(yFila + 8, 'Total abonado a proveedores', formatearMoneda(reporte.totalAbonosProveedores), { destacado: true });
    }
    y += altoCardProveedores + 20;

    // Las tarjetas de arriba ya venían asumiendo que todo cabe en una sola
    // página (nunca hubo paginación en este archivo); las 3 tarjetas nuevas
    // de Resumen de Clientes sí pueden empujar el contenido más allá del
    // alto de una página Carta (792pt), así que cada una se asegura antes de
    // dibujarse de que le alcance el espacio, y si no, abre una página
    // nueva -mismo tamaño/margen que la primera- y sigue ahí.
    const ALTO_PAGINA = 792; // Letter
    const MARGEN_INFERIOR_SEGURO = 70;
    function asegurarEspacio(alturaNecesaria) {
      if (y + alturaNecesaria > ALTO_PAGINA - MARGEN_INFERIOR_SEGURO) {
        doc.addPage({ size: 'LETTER', margin: 0 });
        y = MARGEN;
      }
    }

    // --- Tarjeta: Resumen de Clientes · Mejores clientes (Top 5) ---
    const mejoresClientes = (reporte.clientesTop || []).slice(0, 5);
    const sinMejoresClientes = mejoresClientes.length === 0;
    const altoCardMejoresClientes = sinMejoresClientes ? altoTituloCard + 26 : altoTituloCard + mejoresClientes.length * altoFila + 12;
    asegurarEspacio(altoCardMejoresClientes);

    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardMejoresClientes, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text('Resumen de Clientes · Mejores clientes (Top 5)', MARGEN + 18, y + 14);
    yFila = y + altoTituloCard;
    if (sinMejoresClientes) {
      doc.font('Helvetica').fontSize(10).fillColor(COLOR.gris).text('Sin compras de clientes identificados en este periodo.', MARGEN + 18, yFila);
    } else {
      for (const c of mejoresClientes) {
        filaDetalle(yFila, c.cliente, `${formatearMoneda(c.totalComprado)} · ticket ${formatearMoneda(c.ticketPromedio)}`);
        yFila += altoFila;
      }
    }
    y += altoCardMejoresClientes + 20;

    // --- Tarjeta: Ventas a nombres no registrados (Top 5) ---
    const noRegistrados = (reporte.ventasNoRegistradas || []).slice(0, 5);
    const sinNoRegistrados = noRegistrados.length === 0;
    const altoCardNoRegistrados = sinNoRegistrados ? altoTituloCard + 26 : altoTituloCard + noRegistrados.length * altoFila + 12;
    asegurarEspacio(altoCardNoRegistrados);

    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardNoRegistrados, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text('Ventas a nombres no registrados (Top 5)', MARGEN + 18, y + 14);
    yFila = y + altoTituloCard;
    if (sinNoRegistrados) {
      doc.font('Helvetica').fontSize(10).fillColor(COLOR.gris).text('Todas las ventas con nombre quedaron vinculadas a un cliente registrado.', MARGEN + 18, yFila);
    } else {
      for (const v of noRegistrados) {
        filaDetalle(yFila, v.nombre, `${formatearMoneda(v.totalComprado)} · ${v.cantidadVentas} venta(s)`);
        yFila += altoFila;
      }
    }
    y += altoCardNoRegistrados + 20;

    // --- Tarjeta: Clientes inactivos ---
    const inactivos = reporte.clientesInactivos || [];
    const inactivosAMostrar = inactivos.slice(0, 8);
    const sinInactivos = inactivos.length === 0;
    const hayMasInactivos = inactivos.length > inactivosAMostrar.length;
    const altoCardInactivos = sinInactivos
      ? altoTituloCard + 26
      : altoTituloCard + 22 + inactivosAMostrar.length * altoFila + (hayMasInactivos ? altoFila : 0) + 12;
    asegurarEspacio(altoCardInactivos);

    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardInactivos, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text(`Clientes inactivos (+${DIAS_UMBRAL_CLIENTE_INACTIVO} días sin comprar)`, MARGEN + 18, y + 14);
    yFila = y + altoTituloCard;
    if (sinInactivos) {
      doc.font('Helvetica').fontSize(10).fillColor(COLOR.gris).text(`Ningún cliente activo lleva más de ${DIAS_UMBRAL_CLIENTE_INACTIVO} días sin comprar.`, MARGEN + 18, yFila);
    } else {
      doc.font('Helvetica-Bold').fontSize(10.5).fillColor(COLOR.marca).text(`${inactivos.length} cliente(s) inactivo(s)`, MARGEN + 18, yFila);
      yFila += 22;
      for (const c of inactivosAMostrar) {
        const detalle = c.diasSinComprar === null ? 'Nunca ha comprado' : `Hace ${c.diasSinComprar} días`;
        filaDetalle(yFila, c.nombreCompleto, detalle);
        yFila += altoFila;
      }
      if (hayMasInactivos) {
        doc.font('Helvetica').fontSize(9).fillColor(COLOR.grisClaro).text(`+ ${inactivos.length - inactivosAMostrar.length} más...`, MARGEN + 18, yFila);
      }
    }
    y += altoCardInactivos + 20;

    // --- Pie ---
    doc.font('Helvetica').fontSize(8).fillColor(COLOR.grisClaro).text(`Generado automáticamente el ${formatearFechaHora(new Date())}`, MARGEN, y, { width: ANCHO_UTIL, align: 'center' });

    doc.end();
  });
}

module.exports = { generarPdfReporte, formatearMoneda, formatearFecha };
