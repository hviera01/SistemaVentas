const PDFDocument = require('pdfkit');
const { nombreNegocio } = require('./config');

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
  texto: '#1A1A1A',
  gris: '#6B7280',
  grisClaro: '#9CA3AF',
  fondoCard: '#F7F7F9',
  borde: '#E9EAEE',
  rojo: '#B91C1C',
  fondoRojo: '#FCEAEA',
};

const ANCHO_PAGINA = 612; // Letter
const MARGEN = 40;
const ANCHO_UTIL = ANCHO_PAGINA - MARGEN * 2;

// Estado de cuenta de UN cliente: sus facturas de crédito con saldo
// pendiente, fecha de vencimiento y saldo — pensado para ir adjunto al aviso
// de WhatsApp. [vencidas] = true solo si TODAS las facturas ya están
// vencidas (ver estadoCuenta.js) — ajusta los títulos/colores para no acusar
// un atraso que no existe cuando el envío manual incluye una factura que
// todavía no llega a su fecha. Cada FILA igual calcula su propio estado
// (vencida o no) sin importar ese agregado. Genera los bytes en memoria (no
// escribe a disco).
function generarPdfEstadoCuenta({ nombreCliente, cliente, telefono, facturas, saldoTotal, vencidas = true }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 0 });
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const ahora = new Date();

    // --- Cabecera ---
    const altoCabecera = 96;
    doc.rect(0, 0, ANCHO_PAGINA, altoCabecera).fill(COLOR.marca);
    doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(20).text(nombreNegocio, MARGEN, 26);
    doc.font('Helvetica').fontSize(12).fillColor('#FBE4E4').text(vencidas ? 'Estado de cuenta · Crédito vencido' : 'Estado de cuenta', MARGEN, 52);
    doc.fontSize(9.5).fillColor('#F5C6C6').text(`Generado el ${formatearFecha(ahora)}`, MARGEN, 70);

    let y = altoCabecera + 24;

    // --- Tarjeta: datos del cliente ---
    const altoCardCliente = 62;
    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardCliente, 10).fillAndStroke(COLOR.fondoCard, COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(13).text(nombreCliente, MARGEN + 18, y + 14);
    const dni = cliente?.dni ? `DNI/RTN: ${cliente.dni}` : null;
    const tel = telefono ? `Tel: ${telefono}` : null;
    const subInfo = [dni, tel].filter(Boolean).join('   ·   ');
    if (subInfo) {
      doc.font('Helvetica').fontSize(10).fillColor(COLOR.gris).text(subInfo, MARGEN + 18, y + 36);
    }
    y += altoCardCliente + 20;

    // --- Tarjeta: saldo total ---
    const altoCardSaldo = 60;
    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoCardSaldo, 10).fill(vencidas ? COLOR.fondoRojo : COLOR.fondoCard);
    doc.fillColor(vencidas ? COLOR.rojo : COLOR.gris).font('Helvetica').fontSize(10).text(vencidas ? 'SALDO VENCIDO TOTAL' : 'SALDO TOTAL', MARGEN + 18, y + 14);
    doc.fillColor(vencidas ? COLOR.rojo : COLOR.texto).font('Helvetica-Bold').fontSize(20).text(formatearMoneda(saldoTotal), MARGEN + 18, y + 30);
    const plural = facturas.length === 1 ? 'factura' : 'facturas';
    doc
      .font('Helvetica')
      .fontSize(10)
      .fillColor(vencidas ? COLOR.rojo : COLOR.gris)
      .text(`${facturas.length} ${plural} ${vencidas ? 'vencida(s)' : 'pendiente(s)'}`, MARGEN, y + 30, { width: ANCHO_UTIL - 18, align: 'right' });
    y += altoCardSaldo + 20;

    // --- Tabla: detalle de facturas ---
    const colFactura = MARGEN + 18;
    const colVencimiento = MARGEN + 190;
    const colEstado = MARGEN + 320;
    const colSaldo = MARGEN + ANCHO_UTIL - 18;

    function filaEncabezado(yFila) {
      doc
        .font('Helvetica-Bold')
        .fontSize(9)
        .fillColor(COLOR.gris)
        .text('FACTURA', colFactura, yFila)
        .text('VENCIMIENTO', colVencimiento, yFila)
        .text('ESTADO', colEstado, yFila)
        .text('SALDO', colSaldo - 90, yFila, { width: 90, align: 'right' });
    }

    // Cada fila calcula su propio estado -no depende del [vencidas] agregado
    // de arriba-: una factura puede estar vencida aunque otras del mismo
    // envío todavía no, y viceversa.
    function filaFactura(yFila, factura) {
      const dias = factura.fechaVencimiento ? Math.floor((ahora.getTime() - factura.fechaVencimiento.getTime()) / (1000 * 60 * 60 * 24)) : null;
      const filaVencida = dias !== null && dias > 0;
      const textoEstado = dias === null ? '—' : filaVencida ? `${dias} día(s) de atraso` : dias === 0 ? 'Vence hoy' : `Vence en ${Math.abs(dias)} día(s)`;
      doc
        .font('Helvetica')
        .fontSize(10.5)
        .fillColor(COLOR.texto)
        .text(factura.numeroDocumento || factura.id, colFactura, yFila, { width: 140 })
        .text(factura.fechaVencimiento ? formatearFecha(factura.fechaVencimiento) : '—', colVencimiento, yFila, { width: 120 })
        .fillColor(filaVencida ? COLOR.rojo : COLOR.gris)
        .text(textoEstado, colEstado, yFila, { width: colSaldo - 90 - colEstado })
        .fillColor(COLOR.texto)
        .font('Helvetica-Bold')
        .text(formatearMoneda(factura.saldoPendiente || 0), colSaldo - 90, yFila, { width: 90, align: 'right' });
    }

    const altoTituloTabla = 30;
    const altoFila = 24;
    const altoTabla = altoTituloTabla + facturas.length * altoFila + 20;
    doc.roundedRect(MARGEN, y, ANCHO_UTIL, altoTabla, 10).fillAndStroke('#FFFFFF', COLOR.borde);
    doc.fillColor(COLOR.texto).font('Helvetica-Bold').fontSize(12.5).text('Detalle de facturas', MARGEN + 18, y + 12);
    let yFila = y + altoTituloTabla + 6;
    filaEncabezado(yFila);
    yFila += 18;
    doc.moveTo(MARGEN + 18, yFila).lineTo(MARGEN + ANCHO_UTIL - 18, yFila).strokeColor(COLOR.borde).lineWidth(1).stroke();
    yFila += 6;
    for (const factura of facturas) {
      filaFactura(yFila, factura);
      yFila += altoFila;
    }
    y += altoTabla + 24;

    // --- Pie ---
    doc
      .font('Helvetica')
      .fontSize(8.5)
      .fillColor(COLOR.grisClaro)
      .text('Si ya realizaste el pago de alguna de estas facturas, hacé caso omiso a este aviso.', MARGEN, y, { width: ANCHO_UTIL, align: 'center' });
    doc
      .fontSize(8)
      .text(`Generado automáticamente el ${formatearFechaHora(ahora)}`, MARGEN, y + 16, { width: ANCHO_UTIL, align: 'center' });

    doc.end();
  });
}

module.exports = { generarPdfEstadoCuenta, formatearMoneda, formatearFecha };
