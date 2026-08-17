// Script de una sola corrida: a los créditos que se importaron desde el
// Excel del sistema anterior (sin número de factura real, así que el
// importador les puso el índice de fila del Excel como numeroDocumento) les
// agrega la subcolección `detalle` con las líneas de producto, cruzando
// contra el histórico en D1 por nombre + monto + fecha exacta (la única
// forma confiable, ver conversación 2026-08-17).
//
// No crea créditos nuevos, no toca montoTotal ni saldoPendiente — solo
// agrega `ventasCredito/{id}/detalle/*` cuando encuentra un match con
// líneas de producto en la base vieja. Si la venta original no tenía
// detalle ahí tampoco (pasa, ~7 ventas viejas no tienen), se deja tal cual.

const WORKER_URL = 'https://supercolor-factura-scanner.factura-scanner.workers.dev';
const PROJECT_ID = 'supercolor-25505';
const FIRESTORE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// Candidatos: créditos de ventasCredito cuyo numeroDocumento es solo un
// índice de fila (1-2 dígitos), identificados a mano el 2026-08-17.
const candidatos = [
  { idCredito: '0WrjglCLI6bPnDFpyDkD', nombre: 'ADRIAN MENDOZA', monto: 810, fecha: '2025-11-19' },
  { idCredito: 'Ejh3lzN9r8XwoeMEa6UF', nombre: 'DANIEL MONTOYA', monto: 11960, fecha: '2025-07-09' },
  { idCredito: 'FDx4MhWPC6RynY0aCrl7', nombre: 'RONALD CAMAS', monto: 1750, fecha: '2026-07-16' },
  { idCredito: 'MSDzqiGeUadWOVPW2v5O', nombre: 'CAPA', monto: 700, fecha: '2026-05-12' },
  { idCredito: 'TTfnBR2HhCRPZ306VG30', nombre: 'RODOLFO ROSALEZ', monto: 680, fecha: '2026-07-16' },
  { idCredito: 'Wa5ea49QfH48hH9I3XIA', nombre: 'MAURICIO PINTOR', monto: 600, fecha: '2026-03-09' },
  { idCredito: 'gtwKieUiJ3W7ii2uGwKf', nombre: 'FERNANDO', monto: 1500, fecha: '2026-07-07' },
  { idCredito: 'jcwtEL7cW6oZ0EQmncNM', nombre: 'CONSULTORA RENACER', monto: 6250, fecha: '2026-07-10' },
];

function firestoreValue(v) {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'number') return { doubleValue: v };
  return { stringValue: String(v) };
}

async function agregarDetalle(idCredito, items) {
  for (const item of items) {
    const fields = {
      idProducto: firestoreValue(item.id_producto),
      nombreProducto: firestoreValue(item.nombre_producto ?? ''),
      precioVenta: firestoreValue(item.precio_venta ?? 0),
      cantidad: firestoreValue(item.cantidad ?? 0),
      subtotal: firestoreValue(item.subtotal ?? 0),
      origen: firestoreValue('historico'),
    };
    const res = await fetch(`${FIRESTORE_URL}/ventasCredito/${idCredito}/detalle`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields }),
    });
    if (!res.ok) {
      throw new Error(`Firestore rechazó el detalle de ${idCredito}: ${res.status} ${await res.text()}`);
    }
  }
}

async function main() {
  for (const c of candidatos) {
    const params = new URLSearchParams({ nombre: c.nombre, monto: String(c.monto), fecha: c.fecha });
    const res = await fetch(`${WORKER_URL}/historico/credito-match?${params}`);
    const { venta, detalle } = await res.json();

    if (!venta) {
      console.log(`[SIN MATCH] ${c.nombre} / L${c.monto} / ${c.fecha} — no se encontró en el histórico`);
      continue;
    }
    if (detalle.length === 0) {
      console.log(`[SIN DETALLE] ${c.nombre} (factura vieja ${venta.numero_documento}) no tenía líneas de producto en la base vieja — se deja igual`);
      continue;
    }

    await agregarDetalle(c.idCredito, detalle);
    console.log(`[OK] ${c.nombre} (factura vieja ${venta.numero_documento}): ${detalle.length} líneas agregadas a ventasCredito/${c.idCredito}/detalle`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
