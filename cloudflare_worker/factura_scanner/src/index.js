// Intermediario entre la app (web móvil, Registrar Compra > Escanear
// Factura) y la API de Claude (Anthropic): existe solo para que la API key
// nunca quede expuesta en el navegador (el proyecto de Firebase de Super
// Color no puede pasar a plan Blaze, así que no hay Cloud Functions
// propias; este Worker gratuito de Cloudflare cumple el mismo papel).
//
// La app manda 1+ fotos (páginas de una misma factura) en base64; este
// Worker arma el pedido a Claude con el prompt + una "tool" que fuerza la
// forma exacta de la respuesta (encabezado + líneas de producto), y
// devuelve ese JSON ya parseado.

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

function encabezadosCors(origin) {
  const permitido = ORIGENES_PERMITIDOS.has(origin) ? origin : '';
  return {
    'Access-Control-Allow-Origin': permitido,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-App-Secret',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function respuestaJson(cuerpo, status, origin) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json', ...encabezadosCors(origin) },
  });
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: encabezadosCors(origin) });
    }
    if (request.method !== 'POST') {
      return respuestaJson({ error: 'METODO_NO_PERMITIDO' }, 405, origin);
    }

    // Candado simple: no evita un ataque dedicado (la key del secreto
    // también viaja en el bundle del navegador), pero sí filtra el ruido de
    // cualquiera que encuentre la URL del Worker por curiosidad. La
    // protección de verdad contra un abuso real es el límite de gasto
    // mensual configurado en la cuenta de Anthropic.
    const secretoRecibido = request.headers.get('X-App-Secret') || '';
    if (secretoRecibido !== env.APP_SHARED_SECRET) {
      return respuestaJson({ error: 'NO_AUTORIZADO' }, 401, origin);
    }

    let cuerpo;
    try {
      cuerpo = await request.json();
    } catch {
      return respuestaJson({ error: 'CUERPO_INVALIDO' }, 400, origin);
    }

    const imagenes = Array.isArray(cuerpo?.images) ? cuerpo.images : [];
    if (imagenes.length === 0) {
      return respuestaJson({ error: 'SIN_IMAGENES' }, 400, origin);
    }
    if (imagenes.length > MAX_IMAGENES) {
      return respuestaJson({ error: 'DEMASIADAS_IMAGENES', maximo: MAX_IMAGENES }, 400, origin);
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
      return respuestaJson({ error: 'ERROR_RED_CLAUDE' }, 502, origin);
    }

    if (respuestaClaude.status === 429) {
      // Límite de uso alcanzado (o crédito agotado, Anthropic usa el mismo
      // código): la app debe avisarle al cajero que por ahora no puede usar
      // el escaneo, en vez de quedarse esperando o fallar en silencio.
      return respuestaJson({ error: 'LIMITE_AGOTADO' }, 429, origin);
    }
    if (respuestaClaude.status === 529) {
      // Sobrecarga temporal del lado de Anthropic: se resuelve solo
      // reintentando en un rato (visto con Gemini durante las pruebas).
      return respuestaJson({ error: 'MODELO_SOBRECARGADO' }, 503, origin);
    }
    if (!respuestaClaude.ok) {
      const detalle = await respuestaClaude.text().catch(() => '');
      // "credit balance is too low" viene como 400 de Anthropic: se trata
      // igual que "límite agotado" porque para el cajero es el mismo aviso
      // ("no se puede usar el escaneo ahora").
      if (detalle.toLowerCase().includes('credit balance')) {
        return respuestaJson({ error: 'LIMITE_AGOTADO' }, 429, origin);
      }
      return respuestaJson({ error: 'ERROR_CLAUDE', detalle: detalle.slice(0, 500) }, 502, origin);
    }

    const datos = await respuestaClaude.json();
    const bloqueHerramienta = datos?.content?.find((b) => b.type === 'tool_use' && b.name === 'extraer_factura');
    if (!bloqueHerramienta) {
      return respuestaJson({ error: 'SIN_RESPUESTA_CLAUDE' }, 502, origin);
    }

    return respuestaJson(bloqueHerramienta.input, 200, origin);
  },
};
