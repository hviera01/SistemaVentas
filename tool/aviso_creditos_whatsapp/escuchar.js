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

// Latido de presencia (mismo patrón que `presenciaImpresion` en la app
// Flutter, ver PresenciaImpresionRepository): sin esto, si nadie deja este
// proceso corriendo, el botón "Enviar estado de cuenta por WhatsApp" quedaba
// marcando el pedido en silencio y nunca se enteraba nadie de que no había
// quién lo despachara -bug real reportado por el dueño-. La app chequea
// `presenciaAvisoWhatsapp/escuchador` (PresenciaAvisoWhatsappRepository)
// antes de avisar que "se manda en unos segundos".
async function enviarLatido() {
  try {
    await actualizarCampos('presenciaAvisoWhatsapp', 'escuchador', { ultimoLatido: new Date() });
  } catch (err) {
    console.error('No se pudo mandar el latido de presencia:', err.message || err);
  }
}

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
        const motivo = 'Ya no tiene saldo pendiente (¿se pagó, liquidó o eliminó?).';
        console.warn(`Crédito ${solicitud.id}: ${motivo} — se descarta la solicitud sin mandar nada.`);
        await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false, errorAvisoWhatsApp: motivo });
        continue;
      }
      if (!grupo.telefono) {
        const motivo = 'Sin teléfono cargado en este crédito — agregalo con "Editar teléfono" e intentá de nuevo.';
        console.warn(`Crédito ${solicitud.id} (${grupo.nombreCliente}): ${motivo}`);
        await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false, errorAvisoWhatsApp: motivo });
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
      // Limpia `errorAvisoWhatsApp` acá también -por si un intento anterior
      // de ESTE mismo crédito había fallado y quedó ese mensaje viejo
      // pegado en pantalla-.
      await actualizarCampos('ventasCredito', solicitud.id, { solicitudAvisoWhatsApp: false, errorAvisoWhatsApp: null });
      console.log('Enviado.');
    } catch (err) {
      const motivo = err.message || String(err);
      console.error(`Falló el aviso manual del crédito ${solicitud.id}:`, err);
      // OJO: no se limpia `solicitudAvisoWhatsApp` acá -queda en true a
      // propósito, para reintentarlo solo en el próximo ciclo (ej. si
      // falló por un corte de internet momentáneo)-, pero SÍ se deja
      // guardado el motivo para que VentasCreditoScreen lo muestre.
      await actualizarCampos('ventasCredito', solicitud.id, { errorAvisoWhatsApp: motivo }).catch(() => {});
    }
  }
}

async function main() {
  console.log(`Escuchando pedidos de aviso manual de crédito vencido (cada ${INTERVALO_MS / 1000}s). Ctrl+C para salir.`);
  const ciclo = () => {
    enviarLatido();
    procesarPendientes().catch((err) => console.error('Error revisando solicitudes:', err));
  };
  ciclo();
  setInterval(ciclo, INTERVALO_MS);
}

main();
