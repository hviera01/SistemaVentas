const path = require('path');
const pino = require('pino');
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');

const AUTH_DIR = path.join(__dirname, 'auth_info');

// Manda un documento (PDF) por WhatsApp a un número ya vinculado (ver
// login.js para el primer emparejamiento por QR). Se conecta, manda, y deja
// que quien llama cierre el proceso — pensado para correr una vez por
// invocación desde el Programador de Tareas de Windows, no como servicio
// permanente.
async function enviarDocumentoWhatsApp({ numero, buffer, nombreArchivo, caption }) {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const sock = makeWASocket({ auth: state, logger: pino({ level: 'silent' }) });
  sock.ev.on('creds.update', saveCreds);

  await new Promise((resolve, reject) => {
    sock.ev.on('connection.update', (update) => {
      if (update.connection === 'open') resolve();
      if (update.connection === 'close') {
        const motivo = update.lastDisconnect?.error?.output?.statusCode;
        if (motivo === DisconnectReason.loggedOut) {
          reject(new Error('La sesión de WhatsApp está cerrada (logout). Corré "npm run login" de nuevo en tool/reporte_whatsapp.'));
        } else {
          reject(new Error(`La conexión a WhatsApp se cerró antes de tiempo (código ${motivo ?? 'desconocido'}).`));
        }
      }
    });
  });

  const jid = `${numero}@s.whatsapp.net`;
  await sock.sendMessage(jid, { document: buffer, fileName: nombreArchivo, mimetype: 'application/pdf', caption });

  // Le da un respiro a Baileys para que el mensaje termine de mandarse antes
  // de cortar la conexión.
  await new Promise((resolve) => setTimeout(resolve, 3000));
  sock.end(undefined);
}

module.exports = { enviarDocumentoWhatsApp };
