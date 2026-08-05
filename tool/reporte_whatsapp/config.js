// Configuración del reporte semanal/mensual por WhatsApp.
// No lleva credenciales de Firestore: las reglas de la colección que se
// leen acá (ventas, compras, egresos, comprasCredito/abonosCompra) son
// abiertas (allow read: if true, ver firestore.rules), así que se consulta
// directo por REST sin service account.
module.exports = {
  firebaseProjectId: 'supercolor-25505',
  nombreNegocio: 'SUPER COLOR',
  // Números de WhatsApp que reciben el reporte, en formato internacional sin
  // "+" ni espacios (código de país + número).
  numerosDestino: ['50432566571'],
};
