const path = require('path');
const pino = require('pino');
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');

// Reusa la MISMA sesión de WhatsApp ya vinculada por tool/reporte_whatsapp
// (número personal de Henry) — no hace falta un login/QR aparte para este
// script, y evita tener dos sesiones "Dispositivo vinculado" del mismo
// número compitiendo. Si esa sesión se cierra, arreglar con
// "npm run login" en tool/reporte_whatsapp (no acá, este script no tiene
// login.js propio).
const AUTH_DIR = path.join(__dirname, '..', 'reporte_whatsapp', 'auth_info');

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
          reject(new Error('La sesión de WhatsApp está cerrada (logout). Corré "npm run login" en tool/reporte_whatsapp.'));
        } else {
          reject(new Error(`La conexión a WhatsApp se cerró antes de tiempo (código ${motivo ?? 'desconocido'}).`));
        }
      }
    });
  });

  const jid = `${numero}@s.whatsapp.net`;
  await sock.sendMessage(jid, { document: buffer, fileName: nombreArchivo, mimetype: 'application/pdf', caption });

  await new Promise((resolve) => setTimeout(resolve, 3000));
  sock.end(undefined);
}

module.exports = { enviarDocumentoWhatsApp };
