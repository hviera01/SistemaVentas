// Punto de entrada: node escuchar.js
// A diferencia de index.js (corre una vez al día y termina), este proceso
// se queda corriendo: cada pocos segundos revisa si hay créditos con
// `solicitudAvisoWhatsApp: true` (botón "Enviar aviso de WhatsApp ahora" en
// VentasCreditoScreen, ver VentaCreditoRepository.solicitarAvisoWhatsApp) y
// los manda al toque, sin esperar a la tanda diaria. Pensado para dejarse
// corriendo en la PC principal (ver README.md).
const { consultarCampoIgualA, actualizarCampos } = require('./firestore');
const { obtenerGrupoDeCredito, marcarAvisoEnviado } = require('./estadoCuenta');
const { generarPdfEstadoCuenta } = require('./pdf');
const { enviarDocumentoWhatsApp } = require('./whatsapp');
const { armarCaption, nombreArchivoPdf } = require('./mensaje');

const INTERVALO_MS = 15000;

async function procesarPendientes() {
  const pendientes = await consultarCampoIgualA({ coleccion: 'ventasCredito', campo: 'solicitudAvisoWhatsApp', valor: true });
  if (pendientes.length === 0) return;
  console.log(`${pendientes.length} solicitud(es) de aviso manual pendiente(s).`);

  for (const solicitud of pendientes) {
    try {
      // Se resuelve el grupo POR SOLICITUD (no una sola vez para todas, como
      // en index.js): a diferencia de la tanda diaria, acá se incluye
      // cualquier crédito con saldo pendiente aunque todavía no esté
      // vencido -pedido explícito del dueño-, así que conviene el estado
      // más fresco posible.
      const grupo = await obtenerGrupoDeCredito(solicitud.id);
      if (!grupo) {
        console.warn(`Crédito ${solicitud.id}: ya no tiene saldo pendiente (¿se pagó o eliminó?) — se descarta la solicitud sin mandar nada.`);
        await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false });
        continue;
      }
      if (!grupo.telefono) {
        console.warn(`Crédito ${solicitud.id} (${grupo.nombreCliente}): sin teléfono válido — se descarta la solicitud.`);
        await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false });
        continue;
      }

      console.log(`Enviando aviso manual a ${grupo.nombreCliente} (${grupo.telefono})...`);
      const pdfBuffer = await generarPdfEstadoCuenta({
        nombreCliente: grupo.nombreCliente,
        cliente: grupo.cliente,
        telefono: grupo.telefono,
        facturas: grupo.facturas,
        saldoTotal: grupo.saldoTotal,
        vencidas: grupo.vencidas,
      });
      const caption = armarCaption(grupo.nombreCliente, grupo.facturas, grupo.saldoTotal, grupo.vencidas);
      const nombreArchivo = nombreArchivoPdf(grupo.cliente, grupo.nombreCliente);
      await enviarDocumentoWhatsApp({ numero: grupo.telefono, buffer: pdfBuffer, nombreArchivo, caption });
      await marcarAvisoEnviado(grupo.facturas);
      await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false });
      console.log('Enviado.');
    } catch (err) {
      console.error(`Falló el aviso manual del crédito ${solicitud.id}:`, err);
      // OJO: no se limpia `solicitudAvisoWhatsApp` acá -queda en true a
      // propósito, para reintentarlo solo en el próximo ciclo (ej. si
      // falló por un corte de internet momentáneo).
    }
  }
}

async function main() {
  console.log(`Escuchando pedidos de aviso manual de crédito vencido (cada ${INTERVALO_MS / 1000}s). Ctrl+C para salir.`);
  const ciclo = () => procesarPendientes().catch((err) => console.error('Error revisando solicitudes:', err));
  await ciclo();
  setInterval(ciclo, INTERVALO_MS);
}

main();
