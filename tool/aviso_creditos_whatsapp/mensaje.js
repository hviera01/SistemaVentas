// Compartido entre index.js (tanda diaria) y escuchar.js (avisos manuales
// desde "Enviar aviso ahora" en VentasCreditoScreen) — mismo texto en los
// dos casos.
const { formatearMoneda } = require('./pdf');
const { nombreNegocio } = require('./config');

// [vencidas] = true solo cuando TODAS las facturas del grupo están de
// verdad vencidas (ver estadoCuenta.js) — la tanda diaria siempre manda
// true (ese script solo agrupa vencidos). El envío manual puede mandar
// false si el dueño dispara el aviso de una factura que todavía no llega a
// su fecha: en ese caso el mensaje NO acusa un atraso que no existe, usa
// lenguaje neutral de "estado de cuenta".
function armarCaption(nombreCliente, facturas, saldoTotal, vencidas) {
  const plural = facturas.length === 1 ? 'factura' : 'facturas';
  const lineaAviso = vencidas
    ? `Hola ${nombreCliente}, te recordamos que tenés ${facturas.length} ${plural} de crédito vencida(s) con nosotros.`
    : `Hola ${nombreCliente}, te compartimos tu estado de cuenta de crédito con nosotros (${facturas.length} ${plural}).`;
  const lineaSaldo = vencidas ? `Saldo total vencido: ${formatearMoneda(saldoTotal)}` : `Saldo total: ${formatearMoneda(saldoTotal)}`;
  return [
    nombreNegocio,
    '',
    lineaAviso,
    lineaSaldo,
    '',
    'Adjunto el detalle (estado de cuenta). Si ya realizaste el pago, hacé caso omiso a este mensaje.',
  ].join('\n');
}

function nombreArchivoPdf(cliente, nombreCliente) {
  return `estado_cuenta_${(cliente?.dni || nombreCliente).replace(/[^a-zA-Z0-9]/g, '_').slice(0, 20)}.pdf`;
}

module.exports = { armarCaption, nombreArchivoPdf };
