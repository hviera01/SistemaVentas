// Punto de entrada: node index.js semanal | node index.js mensual
// Pensado para dispararse desde el Programador de Tareas de Windows (ver
// README.md de esta carpeta) — corre una vez, manda el reporte, y termina.
const { calcularReporte } = require('./reporte');
const { generarPdfReporte, formatearMoneda, formatearFecha } = require('./pdf');
const { enviarDocumentoWhatsApp } = require('./whatsapp');
const { numerosDestino, nombreNegocio } = require('./config');

function finDelDia(fecha) {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate(), 23, 59, 59, 999);
}

function inicioDelDia(fecha) {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate(), 0, 0, 0, 0);
}

// "semanal": los últimos 7 días terminando hoy (para que no importe si un
// sábado se corre un poco tarde o se reintenta, siempre cubre la semana
// completa hacia atrás). "mensual": desde el día 1 del mes actual hasta hoy
// — pensado para dispararse el último día del mes.
function calcularRango(tipo) {
  const hoy = new Date();
  if (tipo === 'mensual') {
    const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    return { inicio, fin: finDelDia(hoy), titulo: 'Reporte financiero mensual' };
  }
  const inicio = inicioDelDia(new Date(hoy.getTime() - 6 * 24 * 60 * 60 * 1000));
  return { inicio, fin: finDelDia(hoy), titulo: 'Reporte financiero semanal' };
}

function armarCaption(reporte, titulo) {
  return [
    `${nombreNegocio} · ${titulo}`,
    `${formatearFecha(reporte.inicio)} al ${formatearFecha(reporte.fin)}`,
    '',
    `Ventas: ${formatearMoneda(reporte.ventasPeriodo)}`,
    `Compras: ${formatearMoneda(reporte.comprasPeriodo)} (crédito: ${formatearMoneda(reporte.comprasCreditoPeriodo)})`,
    `Utilidad bruta: ${formatearMoneda(reporte.utilidadBruta)}`,
    `Utilidad neta: ${formatearMoneda(reporte.utilidadNeta)}`,
    `Abonado a proveedores: ${formatearMoneda(reporte.totalAbonosProveedores)}`,
  ].join('\n');
}

async function main() {
  const tipo = process.argv[2];
  if (tipo !== 'semanal' && tipo !== 'mensual') {
    console.error('Uso: node index.js semanal | node index.js mensual');
    process.exit(1);
  }

  const { inicio, fin, titulo } = calcularRango(tipo);
  console.log(`Calculando reporte ${tipo}: ${formatearFecha(inicio)} al ${formatearFecha(fin)}...`);
  const reporte = await calcularReporte(inicio, fin);

  console.log('Generando PDF...');
  const pdfBuffer = await generarPdfReporte({ titulo, reporte });
  const nombreArchivo = `reporte_${tipo}_${fin.toISOString().slice(0, 10)}.pdf`;
  const caption = armarCaption(reporte, titulo);

  for (const numero of numerosDestino) {
    console.log(`Enviando a ${numero}...`);
    await enviarDocumentoWhatsApp({ numero, buffer: pdfBuffer, nombreArchivo, caption });
    console.log(`Enviado a ${numero}.`);
  }

  console.log('Listo.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Falló el envío del reporte:', err);
  process.exit(1);
});
