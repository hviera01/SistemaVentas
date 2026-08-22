// Cliente mínimo de Firestore por REST (sin firebase-admin ni service
// account): las colecciones que este script lee tienen reglas abiertas
// (allow read: if true), igual que se comprobó a mano con curl al arreglar
// el bug de "Unir Facturas" — así que alcanza con pedirle a la API pública
// de Firestore, sin autenticación.
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

// Convierte "projects/PID/databases/(default)/documents/ventas/abc123" en
// { id: 'abc123', segments: ['ventas', 'abc123'] } — los segmentos sirven
// para saber, en una query de collectionGroup, de qué colección raíz y de
// qué documento padre vino cada resultado (ver detallePorRango en
// reporte.js).
function partesDesdeNombre(nombreCompleto) {
  const idx = nombreCompleto.indexOf('/documents/');
  const relativo = nombreCompleto.slice(idx + '/documents/'.length);
  const segments = relativo.split('/');
  return { id: segments[segments.length - 1], segments };
}

function timestampValue(fecha) {
  return { timestampValue: fecha.toISOString() };
}

function filtroRangoFecha(campo, inicio, fin) {
  return {
    compositeFilter: {
      op: 'AND',
      filters: [
        { fieldFilter: { field: { fieldPath: campo }, op: 'GREATER_THAN_OR_EQUAL', value: timestampValue(inicio) } },
        { fieldFilter: { field: { fieldPath: campo }, op: 'LESS_THAN_OR_EQUAL', value: timestampValue(fin) } },
      ],
    },
  };
}

// Ejecuta una structuredQuery contra runQuery y devuelve los documentos ya
// decodificados a objetos planos de JS, con `id` y `_segments` (ruta
// relativa) agregados.
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

async function consultarPorRangoFecha({ coleccion, campoFecha, inicio, fin, collectionGroup = false }) {
  return runQuery({
    from: [{ collectionId: coleccion, allDescendants: collectionGroup }],
    where: filtroRangoFecha(campoFecha, inicio, fin),
  });
}

// Trae TODOS los documentos de una colección, sin filtro de fecha -para
// 'clientes' en el Resumen de Clientes del reporte (reporte.js), que
// necesita el registro completo de cada cliente (fechaUltimaCompra, estado),
// no solo lo que cayó dentro del rango de fechas del reporte-. Un
// `structuredQuery` sin `where` en la API de Firestore devuelve la colección
// completa, así que alcanza con omitirlo.
async function consultarColeccionCompleta(coleccion) {
  return runQuery({ from: [{ collectionId: coleccion, allDescendants: false }] });
}

module.exports = { runQuery, consultarPorRangoFecha, consultarColeccionCompleta, filtroRangoFecha, timestampValue };
