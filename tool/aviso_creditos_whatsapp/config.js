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
};
