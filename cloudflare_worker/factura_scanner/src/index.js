// Este Worker cumple DOS papeles distintos, sin relación entre sí, que
// terminaron viviendo en el mismo proyecto de Cloudflare por comodidad:
//
// 1) Intermediario entre la app (web móvil, Registrar Compra > Escanear
//    Factura) y la API de Claude (Anthropic): existe solo para que la API
//    key nunca quede expuesta en el navegador (el proyecto de Firebase de
//    Super Color no puede pasar a plan Blaze, así que no hay Cloud
//    Functions propias; este Worker gratuito de Cloudflare cumple el mismo
//    papel). La app manda 1+ fotos (páginas de una misma factura) en
//    base64 vía POST a la raíz; este Worker arma el pedido a Claude con el
//    prompt + una "tool" que fuerza la forma exacta de la respuesta
//    (encabezado + líneas de producto), y devuelve ese JSON ya parseado.
//
// 2) Lectura de solo lectura sobre D1 (`supercolor-historico`), que
//    contiene el volcado congelado de VENTA/DETALLE_VENTA del sistema
//    anterior (SQL Server local), desde 2025-07-09 hasta 2026-07-17 22:23
//    (justo antes de que arrancara el sistema actual en Firestore). Esa
//    base no vuelve a actualizarse: el sistema viejo ya no es la fuente de
//    verdad, así que no hay sync recurrente. Rutas GET bajo /historico/*,
//    públicas (sin auth), igual que las colecciones de Firestore que ya se
//    leen así en este proyecto (ver tool/reporte_whatsapp/firestore.js).

// ---------- 1) Escaneo de factura con Claude (POST a la raíz) ----------

const ORIGENES_PERMITIDOS = new Set([
  'https://hviera01.github.io',
]);

const MODELO = 'claude-sonnet-5';
const MAX_IMAGENES = 6;

const PROMPT = `Sos un asistente que lee facturas de compra fotografiadas (de proveedores de pintura, en Honduras) y extrae sus datos en JSON, usando la herramienta "extraer_factura". Te van a llegar 1 o más fotos que son páginas de la MISMA factura, en orden.

Reglas para el encabezado:
- proveedorNombre: el nombre de la EMPRESA QUE EMITE la factura (el proveedor/vendedor), no el receptor/comprador. Usá el nombre comercial corto si aparece (por ejemplo "Lanco" en vez de "Lanco Honduras S.A.") salvo que solo aparezca la razón social completa.
- proveedorRtn: el RTN del proveedor (emisor), no el del receptor.
- numeroFactura: el número de factura tal como aparece MÁS GRANDE/DESTACADO arriba (por ejemplo, si dice "FACTURA N°.000-001-01-00061737", el número de factura es SOLO "00061737", la parte final después del último guión, no el prefijo del correlativo autorizado).
- fecha: la fecha de emisión de la factura, en formato YYYY-MM-DD.
- condicionVenta: "Contado" o "Credito" según lo que diga la factura (puede decir "Condición de Venta").
- fechaVencimiento: si condicionVenta es "Credito" y la factura muestra una fecha de vencimiento/vence, ponela en formato YYYY-MM-DD. Si es "Contado" o no aparece, null.

Reglas para cada línea de producto (no incluyas totales, subtotales ni impuestos):
- codigo: el código de producto tal como aparece impreso. Si no hay, null.
- nombre: la descripción tal como aparece impresa, sin inventar nada.
- unidad: si hay una columna separada de unidad de medida (por ejemplo GLN, CUBETA, UND, CJA, LTS), ponela acá tal cual. Si no hay esa columna, null.
- cantidad: la cantidad numérica de esa línea.
- precioUnitario: el precio unitario ANTES de aplicar el descuento de esa línea (el precio de lista, tal como aparece impreso en la columna de precio). NUNCA restes el descuento del precio ni reportes un precio ya rebajado: el descuento va aparte, en descuentoPorcentaje.
- descuentoPorcentaje: el % de descuento de esa línea si la factura tiene una columna de descuento/rebaja para esa línea (por ejemplo "Descuentos y rebajas otorgados"). Si no hay descuento, 0.
- Verificación: cantidad × precioUnitario × (1 - descuentoPorcentaje/100) tiene que dar el total de esa línea tal como aparece impreso en la factura (columna "Total línea" o equivalente). Si no coincide, es señal de que pusiste el precio ya rebajado en vez del precio de lista: corregilo antes de responder.

Si alguna foto es ilegible o falta un dato, usá null para ese campo en vez de inventar. No agregues texto fuera de la herramienta.`;

const TOOL = {
  name: 'extraer_factura',
  description: 'Registra los datos extraídos de la factura de compra fotografiada.',
  input_schema: {
    type: 'object',
    properties: {
      proveedorNombre: { type: ['string', 'null'] },
      proveedorRtn: { type: ['string', 'null'] },
      numeroFactura: { type: ['string', 'null'] },
      fecha: { type: ['string', 'null'], description: 'Formato YYYY-MM-DD' },
      condicionVenta: { type: ['string', 'null'], enum: ['Contado', 'Credito', null] },
      fechaVencimiento: { type: ['string', 'null'], description: 'Formato YYYY-MM-DD, solo si condicionVenta es Credito' },
      items: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            codigo: { type: ['string', 'null'] },
            nombre: { type: 'string' },
            unidad: { type: ['string', 'null'] },
            cantidad: { type: 'number' },
            precioUnitario: { type: 'number' },
            descuentoPorcentaje: { type: 'number' },
          },
          required: ['nombre', 'cantidad', 'precioUnitario'],
        },
      },
    },
    required: ['items'],
  },
};

function encabezadosCorsEscaneo(origin) {
  const permitido = ORIGENES_PERMITIDOS.has(origin) ? origin : '';
  return {
    'Access-Control-Allow-Origin': permitido,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-App-Secret',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function respuestaJsonEscaneo(cuerpo, status, origin) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json', ...encabezadosCorsEscaneo(origin) },
  });
}

async function manejarEscaneoFactura(request, env) {
  const origin = request.headers.get('Origin') || '';

  // Candado simple: no evita un ataque dedicado (la key del secreto
  // también viaja en el bundle del navegador), pero sí filtra el ruido de
  // cualquiera que encuentre la URL del Worker por curiosidad. La
  // protección de verdad contra un abuso real es el límite de gasto
  // mensual configurado en la cuenta de Anthropic.
  const secretoRecibido = request.headers.get('X-App-Secret') || '';
  if (secretoRecibido !== env.APP_SHARED_SECRET) {
    return respuestaJsonEscaneo({ error: 'NO_AUTORIZADO' }, 401, origin);
  }

  let cuerpo;
  try {
    cuerpo = await request.json();
  } catch {
    return respuestaJsonEscaneo({ error: 'CUERPO_INVALIDO' }, 400, origin);
  }

  const imagenes = Array.isArray(cuerpo?.images) ? cuerpo.images : [];
  if (imagenes.length === 0) {
    return respuestaJsonEscaneo({ error: 'SIN_IMAGENES' }, 400, origin);
  }
  if (imagenes.length > MAX_IMAGENES) {
    return respuestaJsonEscaneo({ error: 'DEMASIADAS_IMAGENES', maximo: MAX_IMAGENES }, 400, origin);
  }

  const bloquesImagen = imagenes.map((img) => ({
    type: 'image',
    source: { type: 'base64', media_type: img.mimeType || 'image/jpeg', data: img.data },
  }));

  const pedidoClaude = {
    model: MODELO,
    max_tokens: 4096,
    tools: [TOOL],
    tool_choice: { type: 'tool', name: 'extraer_factura' },
    messages: [
      {
        role: 'user',
        content: [{ type: 'text', text: PROMPT }, ...bloquesImagen],
      },
    ],
  };

  let respuestaClaude;
  try {
    respuestaClaude = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(pedidoClaude),
    });
  } catch {
    return respuestaJsonEscaneo({ error: 'ERROR_RED_CLAUDE' }, 502, origin);
  }

  if (respuestaClaude.status === 429) {
    // Límite de uso alcanzado (o crédito agotado, Anthropic usa el mismo
    // código): la app debe avisarle al cajero que por ahora no puede usar
    // el escaneo, en vez de quedarse esperando o fallar en silencio.
    return respuestaJsonEscaneo({ error: 'LIMITE_AGOTADO' }, 429, origin);
  }
  if (respuestaClaude.status === 529) {
    // Sobrecarga temporal del lado de Anthropic: se resuelve solo
    // reintentando en un rato (visto con Gemini durante las pruebas).
    return respuestaJsonEscaneo({ error: 'MODELO_SOBRECARGADO' }, 503, origin);
  }
  if (!respuestaClaude.ok) {
    const detalle = await respuestaClaude.text().catch(() => '');
    // "credit balance is too low" viene como 400 de Anthropic: se trata
    // igual que "límite agotado" porque para el cajero es el mismo aviso
    // ("no se puede usar el escaneo ahora").
    if (detalle.toLowerCase().includes('credit balance')) {
      return respuestaJsonEscaneo({ error: 'LIMITE_AGOTADO' }, 429, origin);
    }
    return respuestaJsonEscaneo({ error: 'ERROR_CLAUDE', detalle: detalle.slice(0, 500) }, 502, origin);
  }

  const datos = await respuestaClaude.json();
  const bloqueHerramienta = datos?.content?.find((b) => b.type === 'tool_use' && b.name === 'extraer_factura');
  if (!bloqueHerramienta) {
    return respuestaJsonEscaneo({ error: 'SIN_RESPUESTA_CLAUDE' }, 502, origin);
  }

  return respuestaJsonEscaneo(bloqueHerramienta.input, 200, origin);
}

// ---------- 2) Histórico del sistema anterior, vía D1 (GET /historico/*) ----------

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

// Cada fila trae `origen: "historico"` explícito para que el lado Flutter
// nunca la confunda con una venta de Firestore, ni siquiera si coincide el
// numeroDocumento (los rangos de numeración de ambos sistemas se traslapan).
function marcarOrigen(fila) {
  return { ...fila, origen: 'historico' };
}

async function listarVentas(db, url) {
  const desde = url.searchParams.get('desde');
  const hasta = url.searchParams.get('hasta');
  if (!desde || !hasta) {
    return json({ error: 'Parámetros requeridos: desde, hasta (ISO 8601)' }, 400);
  }
  const { results } = await db
    .prepare(
      `SELECT v.*, (SELECT COUNT(*) FROM detalle_venta d WHERE d.id_venta = v.id_venta) AS cantidad_productos
       FROM ventas v
       WHERE v.fecha_registro >= ? AND v.fecha_registro <= ?
       ORDER BY v.fecha_registro`
    )
    .bind(desde, hasta)
    .all();
  return json(results.map(marcarOrigen));
}

async function detalleDeVenta(db, url) {
  const idVenta = url.searchParams.get('idVenta');
  if (!idVenta) return json({ error: 'Parámetro requerido: idVenta' }, 400);
  const { results } = await db
    .prepare('SELECT * FROM detalle_venta WHERE id_venta = ? ORDER BY id_detalle_venta')
    .bind(idVenta)
    .all();
  return json(results);
}

// Detalle de TODAS las ventas de un rango en una sola consulta, igual que el
// collectionGroup('detalle') que ya usa ReporteFinancieroRepository para
// Firestore — evita que un reporte con muchas ventas viejas dispare una
// llamada HTTP por cada una.
async function detalleDeRango(db, url) {
  const desde = url.searchParams.get('desde');
  const hasta = url.searchParams.get('hasta');
  if (!desde || !hasta) {
    return json({ error: 'Parámetros requeridos: desde, hasta (ISO 8601)' }, 400);
  }
  const { results } = await db
    .prepare(
      `SELECT d.* FROM detalle_venta d
       INNER JOIN ventas v ON v.id_venta = d.id_venta
       WHERE v.fecha_registro >= ? AND v.fecha_registro <= ?
       ORDER BY d.id_venta, d.id_detalle_venta`
    )
    .bind(desde, hasta)
    .all();
  return json(results);
}

// Usado por el script de backfill de créditos viejos: como el Excel
// importado no traía número de factura para varias filas, la única forma
// confiable de encontrar la venta original es cruzar por cliente + monto +
// fecha exacta (ver conversación del 2026-08-17).
async function buscarCredito(db, url) {
  const nombre = url.searchParams.get('nombre');
  const monto = url.searchParams.get('monto');
  const fecha = url.searchParams.get('fecha'); // YYYY-MM-DD
  if (!nombre || !monto || !fecha) {
    return json({ error: 'Parámetros requeridos: nombre, monto, fecha (YYYY-MM-DD)' }, 400);
  }
  const { results } = await db
    .prepare(
      `SELECT * FROM ventas
       WHERE condicion = 'Credito'
         AND UPPER(TRIM(nombre_cliente)) = UPPER(TRIM(?))
         AND ABS(monto_total - ?) < 0.01
         AND substr(fecha_registro, 1, 10) = ?`
    )
    .bind(nombre, monto, fecha)
    .all();
  if (results.length === 0) return json({ venta: null, detalle: [] });
  const venta = results[0];
  const { results: detalle } = await db
    .prepare('SELECT * FROM detalle_venta WHERE id_venta = ? ORDER BY id_detalle_venta')
    .bind(venta.id_venta)
    .all();
  return json({ venta, detalle });
}

// ---------- Router ----------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      // El preflight de un POST (escaneo de factura) usa el CORS
      // restringido a ORIGENES_PERMITIDOS; cualquier otro (los GET de
      // /historico/*) usa el CORS abierto.
      const metodoPedido = request.headers.get('Access-Control-Request-Method') || '';
      if (metodoPedido === 'POST') {
        return new Response(null, { status: 204, headers: encabezadosCorsEscaneo(request.headers.get('Origin') || '') });
      }
      return new Response(null, { headers: JSON_HEADERS });
    }

    if (request.method === 'POST') return manejarEscaneoFactura(request, env);

    if (url.pathname === '/historico/ventas') return listarVentas(env.DB_HISTORICO, url);
    if (url.pathname === '/historico/detalle') return detalleDeVenta(env.DB_HISTORICO, url);
    if (url.pathname === '/historico/detalle-rango') return detalleDeRango(env.DB_HISTORICO, url);
    if (url.pathname === '/historico/credito-match') return buscarCredito(env.DB_HISTORICO, url);

    return json({ error: 'Ruta no encontrada' }, 404);
  },
};
