const PDFDocument = require('pdfkit');
const { nombreNegocio } = require('./config');

function formatearMoneda(valor) {
  const monto = Math.round((valor + Number.EPSILON) * 100) / 100;
  return `L.${monto.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatearFecha(fecha) {
  return fecha.toLocaleDateString('es-HN', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

// PDF simple tamaño carta con el resumen financiero del periodo. Genera los
// bytes en memoria (no escribe a disco) para poder mandarlos directo por
// WhatsApp.
function generarPdfReporte({ titulo, reporte }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 40 });
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const colorMarca = '#C62828';
    const colorGris = '#4B4F58';

    doc.fillColor(colorMarca).fontSize(18).font('Helvetica-Bold').text(nombreNegocio, { continued: false });
    doc.fillColor(colorGris).fontSize(12).font('Helvetica').text(titulo);
    doc.fontSize(9).text(`Periodo: ${formatearFecha(reporte.inicio)} al ${formatearFecha(reporte.fin)}`);
    doc.moveDown(1);

    function fila(etiqueta, valor, { destacado = false, indent = 0 } = {}) {
      doc
        .font(destacado ? 'Helvetica-Bold' : 'Helvetica')
        .fontSize(destacado ? 12 : 10.5)
        .fillColor(destacado ? colorMarca : '#1A1A1A')
        .text(`${' '.repeat(indent)}${etiqueta}`, { continued: true, width: 320 })
        .text(valor, { align: 'right' });
    }

    doc.fillColor('#1A1A1A').fontSize(13).font('Helvetica-Bold').text('Resumen del periodo');
    doc.moveDown(0.3);
    fila(`Ventas (${reporte.cantidadVentas} facturas)`, formatearMoneda(reporte.ventasPeriodo));
    fila(`Compras (${reporte.cantidadCompras} facturas)`, formatearMoneda(reporte.comprasPeriodo));
    fila('  de las cuales al crédito', formatearMoneda(reporte.comprasCreditoPeriodo), { indent: 2 });
    fila('Costo de lo vendido', formatearMoneda(reporte.costoVentas));
    fila('Utilidad bruta', formatearMoneda(reporte.utilidadBruta), { destacado: true });
    fila('Gastos (egresos)', formatearMoneda(reporte.gastosPeriodo));
    fila('Utilidad neta', formatearMoneda(reporte.utilidadNeta), { destacado: true });
    doc.moveDown(1);

    doc.fillColor('#1A1A1A').fontSize(13).font('Helvetica-Bold').text('Abonos a proveedores (compras a crédito)');
    doc.moveDown(0.3);
    if (reporte.abonosPorProveedor.length === 0) {
      doc.font('Helvetica').fontSize(10.5).fillColor(colorGris).text('Sin abonos a proveedores en este periodo.');
    } else {
      for (const a of reporte.abonosPorProveedor) {
        fila(a.proveedor, formatearMoneda(a.total));
      }
      doc.moveDown(0.2);
      fila('Total abonado a proveedores', formatearMoneda(reporte.totalAbonosProveedores), { destacado: true });
    }

    doc.moveDown(1.5);
    doc.font('Helvetica-Oblique').fontSize(8.5).fillColor('#6B7280').text('Reporte generado automáticamente.');

    doc.end();
  });
}

module.exports = { generarPdfReporte, formatearMoneda, formatearFecha };
