// Configuración del aviso automático de créditos vencidos por WhatsApp.
// No lleva credenciales de Firestore: las colecciones que este script lee y
// escribe acá (ventasCredito, clientes) tienen reglas abiertas
// (allow read, write: if true, ver firestore.rules), así que se consulta y
// actualiza directo por REST sin service account.
module.exports = {
  firebaseProjectId: 'supercolor-25505',
  nombreNegocio: 'SUPER COLOR',
  // Cada cuántos días se le repite el recordatorio a un cliente mientras su
  // crédito siga vencido (elegido por Henry: cada 3 días). Se cuenta desde
  // la última vez que se le mandó aviso a ESE cliente, no desde la fecha de
  // vencimiento de cada factura.
  intervaloDiasRecordatorio: 3,
  // Cuentas bancarias que se ofrecen en el mensaje de WhatsApp para pagar
  // por transferencia (pedido explícito de Henry). Editar acá si cambian
  // los números o el titular -no hace falta tocar mensaje.js-.
  cuentasPago: [
    { banco: 'BAC', numeroCuenta: '745760571', titular: 'Alison Paola Viera Carrasco' },
    { banco: 'Banco Atlántida', numeroCuenta: '00002010076048', titular: 'Alison Paola Viera Carrasco' },
  ],
};
