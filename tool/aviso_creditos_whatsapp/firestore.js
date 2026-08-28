// Cliente mínimo de Firestore por REST (sin firebase-admin ni service
// account) — mismo patrón que tool/reporte_whatsapp/firestore.js: las
// colecciones que este script lee y escribe tienen reglas abiertas
// (allow read, write: if true), así que alcanza con la API pública de
// Firestore, sin autenticación.
const { firebaseProjectId } = require('./config');

const BASE_URL = `https://firestore.googleapis.com/v1/projects/${firebaseProjectId}/databases/(default)/documents`;

function decodeValue(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('nullValue' in value) return null;
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  return null;
}

function decodeFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields || {})) {
    out[key] = decodeValue(value);
  }
  return out;
}

function partesDesdeNombre(nombreCompleto) {
  const idx = nombreCompleto.indexOf('/documents/');
  const relativo = nombreCompleto.slice(idx + '/documents/'.length);
  const segments = relativo.split('/');
  return { id: segments[segments.length - 1], segments };
}

async function runQuery(structuredQuery) {
  const res = await fetch(`${BASE_URL}:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!res.ok) {
    throw new Error(`Firestore runQuery falló (${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  const documentos = [];
  for (const item of data) {
    if (!item.document) continue;
    const { id, segments } = partesDesdeNombre(item.document.name);
    documentos.push({ id, _segments: segments, ...decodeFields(item.document.fields) });
  }
  return documentos;
}

// Trae TODOS los documentos de una colección, sin filtro — alcanza para
// 'ventasCredito' y 'clientes' porque el volumen de créditos activos es
// chico (no son miles de documentos como 'ventas').
async function consultarColeccionCompleta(coleccion) {
  return runQuery({ from: [{ collectionId: coleccion, allDescendants: false }] });
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  throw new Error(`Tipo no soportado para escribir en Firestore: ${typeof value}`);
}

// Consulta una colección filtrando por un campo == valor — se usa en
// escuchar.js para encontrar créditos con `solicitudAvisoWhatsApp: true`
// sin traer toda la colección en cada ciclo de sondeo.
async function consultarCampoIgualA({ coleccion, campo, valor }) {
  return runQuery({
    from: [{ collectionId: coleccion, allDescendants: false }],
    where: { fieldFilter: { field: { fieldPath: campo }, op: 'EQUAL', value: encodeValue(valor) } },
  });
}

// Actualiza SOLO los campos indicados de un documento (updateMask), sin
// tocar el resto — se usa para marcar `ultimoAvisoEnviado` en un crédito sin
// arriesgar pisar `saldoPendiente` u otro campo si en el momento de leer y
// escribir alguien más modificó el documento.
async function actualizarCampos(coleccion, id, campos) {
  const fields = {};
  for (const [k, v] of Object.entries(campos)) fields[k] = encodeValue(v);
  const mask = Object.keys(campos)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const res = await fetch(`${BASE_URL}/${coleccion}/${id}?${mask}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    throw new Error(`Firestore patch falló (${res.status}): ${await res.text()}`);
  }
}

module.exports = { runQuery, consultarColeccionCompleta, consultarCampoIgualA, actualizarCampos };
