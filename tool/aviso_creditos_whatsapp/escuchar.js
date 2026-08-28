// Punto de entrada: node escuchar.js
// A diferencia de index.js (tarea diaria, un rango fijo de fechas), este
// corre igual de rápido -revisa, manda lo que haya pendiente, y TERMINA-
// pero está pensado para programarse cada 2 minutos (Programador de Tareas,
// /SC MINUTE /MO 2) en vez de una vez al día, para que "Enviar estado de
// cuenta por WhatsApp" (botón en VentasCreditoScreen, ver
// VentaCreditoRepository.solicitarAvisoWhatsApp) se despache pronto sin
// depender de un proceso que se quede corriendo para siempre -eso sí le daba
// problemas al Programador de Tareas de Windows (error "argumentos no
// válidos" al combinar disparador "al iniciar sesión" con "sin límite de
// tiempo de ejecución"), este formato (correr y terminar, programado cada
// pocos minutos) es el mismo que ya usa tool/reporte_whatsapp sin líos.
const { consultarCampoIgualA, actualizarCampos } = require('./firestore');
const { obtenerGrupoDeCredito, marcarAvisoEnviado } = require('./estadoCuenta');
const { generarPdfEstadoCuenta } = require('./pdf');
const { enviarDocumentoWhatsApp } = require('./whatsapp');
const { armarCaption, nombreArchivoPdf } = require('./mensaje');

// Latido de presencia (mismo patrón que `presenciaImpresion` en la app
// Flutter, ver PresenciaImpresionRepository): si la tarea programada se
// desactiva o falla seguido, la app puede avisar que no hay quién despache
// el aviso en vez de dejarlo pedido en silencio -bug real reportado por el
// dueño-. Con esta tarea corriendo cada 2 minutos, un latido reciente
// significa "la tarea programada sigue viva" (ver PresenciaAvisoWhatsapp
// Repository.umbralConectada, tiene que ser bastante mayor a 2 minutos para
// no marcar falso "desconectado" entre corridas).
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
      // propósito, para reintentarlo solo en la próxima corrida (2 minutos
      // después), ej. si falló por un corte de internet momentáneo-, pero SÍ
      // se deja guardado el motivo para que VentasCreditoScreen lo muestre.
      await actualizarCampos('ventasCredito', solicitud.id, { errorAvisoWhatsApp: motivo }).catch(() => {});
    }
  }
}

async function main() {
  await enviarLatido();
  await procesarPendientes();
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Falló la corrida de escuchar.js:', err);
    process.exit(1);
  });
