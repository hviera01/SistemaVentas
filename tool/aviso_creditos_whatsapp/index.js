// Punto de entrada: node index.js [--prueba=NUMERO]
// Pensado para dispararse una vez al día desde el Programador de Tareas de
// Windows (ver README.md de esta carpeta) — revisa todos los créditos
// vencidos, agrupa por teléfono (cada crédito trae el suyo propio, ver
// VentaCreditoModel.telefono en Dart), y a quien le toque aviso hoy (ver
// intervaloDiasRecordatorio en config.js) le manda su estado de cuenta en
// PDF por WhatsApp.
const { obtenerClientesConCreditoVencido, marcarAvisoEnviado } = require('./estadoCuenta');
const { generarPdfEstadoCuenta } = require('./pdf');
const { enviarDocumentoWhatsApp } = require('./whatsapp');
const { armarCaption, nombreArchivoPdf } = require('./mensaje');

async function main() {
  // --prueba=50499999999: manda todos los avisos pendientes de hoy a ESE
  // número en vez de al teléfono real del cliente, y NO actualiza
  // `ultimoAvisoEnviado` en Firestore -para poder probar el contenido de los
  // mensajes sin gastar un "turno" de recordatorio real ni mandarle nada a
  // un cliente real-.
  const argPrueba = process.argv.find((a) => a.startsWith('--prueba='));
  const numeroPrueba = argPrueba ? argPrueba.slice('--prueba='.length) : null;
  if (numeroPrueba) console.log(`Modo prueba: todo se manda a ${numeroPrueba}, sin marcar aviso enviado.`);

  console.log('Buscando créditos vencidos...');
  const clientes = await obtenerClientesConCreditoVencido();
  const pendientes = clientes.filter((c) => c.necesitaAviso);

  if (pendientes.length === 0) {
    console.log('No hay clientes con crédito vencido pendientes de aviso hoy.');
    return;
  }
  console.log(`${pendientes.length} cliente(s) con aviso pendiente hoy.`);

  for (const item of pendientes) {
    const { cliente, nombreCliente, telefono, facturas, saldoTotal, vencidas } = item;
    const destino = numeroPrueba || telefono;
    if (!destino) {
      console.warn(`Sin teléfono válido para "${nombreCliente}" (facturas: ${facturas.map((f) => f.numeroDocumento).join(', ')}) — se omite.`);
      continue;
    }

    console.log(`Generando PDF para ${nombreCliente}...`);
    const pdfBuffer = await generarPdfEstadoCuenta({ nombreCliente, cliente, telefono, facturas, saldoTotal, vencidas });
    const caption = armarCaption(nombreCliente, facturas, saldoTotal, vencidas);
    const nombreArchivo = nombreArchivoPdf(cliente, nombreCliente);

    console.log(`Enviando a ${nombreCliente} (${destino})...`);
    await enviarDocumentoWhatsApp({ numero: destino, buffer: pdfBuffer, nombreArchivo, caption });
    console.log('Enviado.');

    if (!numeroPrueba) {
      await marcarAvisoEnviado(facturas);
    }
  }

  console.log('Listo.');
}

main().catch((err) => {
  console.error('Falló el envío de avisos de crédito:', err);
  process.exit(1);
});
