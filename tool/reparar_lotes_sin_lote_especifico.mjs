// Script de una sola corrida: repara el desalineamiento entre productos.stock
// y la suma de lotes[].cantidadRestante causado por el bug de "salida sin
// lote específico" (ver git log, arreglado en la v118 del sistema) — antes
// esa operación bajaba el stock total pero nunca tocaba los lotes, así que
// la suma de lotes quedaba MÁS ALTA que el stock real de verdad.
//
// Por defecto corre en modo REPORTE (no escribe nada). Con --aplicar sí
// escribe: consume por FIFO (más viejo primero, o por prioridad manual si
// existe -mismo criterio que LoteCostoRepository.consumir/loteActivo en la
// app-) el EXCESO de cada producto afectado (sumaLotes - stock), dejando la
// suma de lotes igual al stock real. Nunca toca productos.stock (ya es
// correcto, es lo que se usa como ancla) ni productos donde sumaLotes sea
// MENOR o igual al stock (eso es "stock viejo sin lotes asociados",
// comportamiento esperado desde antes de este bug, no algo que reparar).
//
// Uso:
//   node tool/reparar_lotes_sin_lote_especifico.mjs            (reporte)
//   node tool/reparar_lotes_sin_lote_especifico.mjs --aplicar  (repara)

const PROJECT_ID = 'supercolor-25505';
const FIRESTORE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const EPSILON = 0.005;
const APLICAR = process.argv.includes('--aplicar');

function num(fields, key) {
  const v = fields?.[key];
  if (!v) return 0;
  if ('doubleValue' in v) return v.doubleValue;
  if ('integerValue' in v) return Number(v.integerValue);
  return 0;
}

function str(fields, key) {
  return fields?.[key]?.stringValue ?? '';
}

async function listarTodos(path) {
  const docs = [];
  let pageToken;
  do {
    const params = new URLSearchParams({ pageSize: '300' });
    if (pageToken) params.set('pageToken', pageToken);
    const res = await fetch(`${FIRESTORE_URL}/${path}?${params}`);
    if (!res.ok) throw new Error(`Firestore listDocuments falló en ${path}: ${res.status} ${await res.text()}`);
    const data = await res.json();
    for (const d of data.documents ?? []) docs.push(d);
    pageToken = data.nextPageToken;
  } while (pageToken);
  return docs;
}

function idDe(doc) {
  return doc.name.split('/').pop();
}

async function actualizarCampo(path, campo, valor) {
  const params = new URLSearchParams({ 'updateMask.fieldPaths': campo });
  const res = await fetch(`${FIRESTORE_URL}/${path}?${params}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { [campo]: { doubleValue: valor } } }),
  });
  if (!res.ok) throw new Error(`Firestore PATCH falló en ${path}: ${res.status} ${await res.text()}`);
}

function compararLotes(a, b) {
  const prioA = a.fields?.prioridad ? Number(a.fields.prioridad.integerValue) : null;
  const prioB = b.fields?.prioridad ? Number(b.fields.prioridad.integerValue) : null;
  if (prioA !== null && prioB !== null) return prioA - prioB;
  if (prioA !== null) return -1;
  if (prioB !== null) return 1;
  const fechaA = a.fields?.fecha?.timestampValue ?? '';
  const fechaB = b.fields?.fecha?.timestampValue ?? '';
  return fechaA.localeCompare(fechaB);
}

async function main() {
  console.log(APLICAR ? 'MODO: APLICAR (va a escribir cambios reales)' : 'MODO: REPORTE (no escribe nada, solo muestra qué encontraría)');
  console.log('');

  const productos = await listarTodos('productos');
  console.log(`${productos.length} productos encontrados.`);
  console.log('');

  let afectados = 0;
  let totalExcesoUnidades = 0;

  for (const producto of productos) {
    const idProducto = idDe(producto);
    const nombre = str(producto.fields, 'nombre');
    const stock = num(producto.fields, 'stock');

    const lotesDocs = await listarTodos(`productos/${idProducto}/lotes`);
    if (lotesDocs.length === 0) continue;

    const sumaLotes = lotesDocs.reduce((s, l) => s + num(l.fields, 'cantidadRestante'), 0);
    const exceso = sumaLotes - stock;
    if (exceso <= EPSILON) continue;

    afectados++;
    totalExcesoUnidades += exceso;
    console.log(`[AFECTADO] ${nombre} (${idProducto}): stock=${stock}, suma de lotes=${sumaLotes.toFixed(3)}, exceso a quitar=${exceso.toFixed(3)}`);

    if (!APLICAR) continue;

    // Consume el exceso por FIFO (más viejo/prioridad primero), igual que
    // LoteCostoRepository.consumir en la app.
    const ordenados = [...lotesDocs].sort(compararLotes);
    let restante = exceso;
    for (const lote of ordenados) {
      if (restante <= 0) break;
      const actual = num(lote.fields, 'cantidadRestante');
      if (actual <= 0) continue;
      const aQuitar = Math.min(actual, restante);
      const nuevo = actual - aQuitar;
      await actualizarCampo(`productos/${idProducto}/lotes/${idDe(lote)}`, 'cantidadRestante', nuevo);
      console.log(`         lote ${idDe(lote)}: ${actual.toFixed(3)} -> ${nuevo.toFixed(3)}`);
      restante -= aQuitar;
    }

    // Sincroniza precioCompra con el lote que quede activo (mismo criterio
    // que LoteCostoRepository.sincronizarPrecioCompraActivo en la app).
    const lotesFrescos = await listarTodos(`productos/${idProducto}/lotes`);
    const activo = [...lotesFrescos].sort(compararLotes).find((l) => num(l.fields, 'cantidadRestante') > 0);
    if (activo) {
      const costoActivo = num(activo.fields, 'costoUnitario');
      await actualizarCampo(`productos/${idProducto}`, 'precioCompra', costoActivo);
      console.log(`         precioCompra sincronizado a ${costoActivo}`);
    }
  }

  console.log('');
  console.log(`Total productos afectados: ${afectados}`);
  console.log(`Total unidades de exceso encontradas: ${totalExcesoUnidades.toFixed(3)}`);
  if (!APLICAR && afectados > 0) {
    console.log('');
    console.log('Corré de nuevo con --aplicar para reparar de verdad.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
