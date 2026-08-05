// Primer emparejamiento con WhatsApp: corré esto una sola vez
// ("npm run login" adentro de tool/reporte_whatsapp) y escaneá el código QR
// que aparece en la terminal desde el celular (WhatsApp > Dispositivos
// vinculados > Vincular un dispositivo). Después de esto la sesión queda
// guardada en auth_info/ y los envíos programados (index.js) ya no piden QR
// de nuevo.
const path = require('path');
const pino = require('pino');
const qrcode = require('qrcode-terminal');
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');

const AUTH_DIR = path.join(__dirname, 'auth_info');

async function main() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const sock = makeWASocket({ auth: state, logger: pino({ level: 'silent' }) });
  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, qr, lastDisconnect } = update;
    if (qr) {
      console.log('\nEscaneá este código QR desde WhatsApp > Dispositivos vinculados > Vincular un dispositivo:\n');
      qrcode.generate(qr, { small: true });
    }
    if (connection === 'open') {
      console.log('\n¡Listo! El número quedó vinculado. Ya podés cerrar esta ventana.');
      process.exit(0);
    }
    if (connection === 'close') {
      const motivo = lastDisconnect?.error?.output?.statusCode;
      if (motivo === DisconnectReason.loggedOut) {
        console.log('\nLa sesión se cerró. Borrá la carpeta auth_info/ y volvé a correr "npm run login".');
        process.exit(1);
      } else {
        console.log('\nConexión cortada, reintentando...');
        main();
      }
    }
  });
}

main().catch((err) => {
  console.error('Error al iniciar sesión:', err);
  process.exit(1);
});
