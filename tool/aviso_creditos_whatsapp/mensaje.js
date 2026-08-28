// Compartido entre index.js (tanda diaria) y escuchar.js (avisos manuales
// desde "Enviar aviso ahora" en VentasCreditoScreen) — mismo texto en los
// dos casos.
const { formatearMoneda } = require('./pdf');
const { nombreNegocio, cuentasPago } = require('./config');

// Líneas con las cuentas bancarias para pagar por transferencia (ver
// cuentasPago en config.js) — se ofrecen siempre, esté vencido o no, porque
// de todos modos sirve saber dónde pagar.
function lineasCuentasPago() {
  if (!cuentasPago || cuentasPago.length === 0) return [];
  return ['', 'También puede pagar por transferencia a:', ...cuentasPago.map((c) => `${c.banco}: ${c.numeroCuenta} (${c.titular})`)];
}

// Trato de "usted" en todo el mensaje -pedido explícito del dueño: más
// formal y respetuoso hacia el cliente, en vez del "vos" que tenía antes-.
//
// [vencidas] = true solo cuando TODAS las facturas del grupo están de
// verdad vencidas (ver estadoCuenta.js) — la tanda diaria siempre manda
// true (ese script solo agrupa vencidos). El envío manual puede mandar
// false si el dueño dispara el aviso de una factura que todavía no llega a
// su fecha: en ese caso el mensaje NO acusa un atraso que no existe, usa
// lenguaje neutral de "estado de cuenta".
function armarCaption(nombreCliente, facturas, saldoTotal, vencidas) {
  const plural = facturas.length === 1 ? 'factura' : 'facturas';
  const lineaAviso = vencidas
    ? `Estimado(a) ${nombreCliente}, le recordamos que tiene ${facturas.length} ${plural} de crédito vencida(s) con nosotros. Le agradecemos presentarse a cancelar lo antes posible.`
    : `Estimado(a) ${nombreCliente}, le compartimos su estado de cuenta de crédito con nosotros (${facturas.length} ${plural}).`;
  const lineaSaldo = vencidas ? `Saldo total vencido: ${formatearMoneda(saldoTotal)}` : `Saldo total: ${formatearMoneda(saldoTotal)}`;
  return [
    nombreNegocio,
    '',
    lineaAviso,
    lineaSaldo,
    '',
    'Adjunto el detalle (estado de cuenta). Si ya realizó el pago, por favor haga caso omiso a este mensaje.',
    ...lineasCuentasPago(),
  ].join('\n');
}

function nombreArchivoPdf(cliente, nombreCliente) {
  return `estado_cuenta_${(cliente?.dni || nombreCliente).replace(/[^a-zA-Z0-9]/g, '_').slice(0, 20)}.pdf`;
}

module.exports = { armarCaption, nombreArchivoPdf };
