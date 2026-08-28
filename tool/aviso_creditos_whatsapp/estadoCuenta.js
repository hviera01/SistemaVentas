// Arma, por destino de WhatsApp, el estado de cuenta de créditos — mismo
// criterio que VentaCreditoModel.vencida en Dart (ver
// lib/features/ventas_credito/data/venta_credito_model.dart): no liquidada
// (saldoPendiente > 0), con fechaVencimiento, y ya pasada.
const { consultarColeccionCompleta, actualizarCampos } = require('./firestore');
const { intervaloDiasRecordatorio } = require('./config');

function diasEntre(desde, hasta) {
  return Math.floor((hasta.getTime() - desde.getTime()) / (1000 * 60 * 60 * 24));
}

function esVencida(factura, ahora) {
  return (factura.saldoPendiente || 0) > 0 && !!factura.fechaVencimiento && ahora > factura.fechaVencimiento;
}

// Cada crédito (VentaCreditoModel.telefono, ver Dart) trae su propio
// teléfono, capturado a mano en Registrar Venta o en "Editar teléfono" de
// Ventas Crédito — texto libre, normalmente 8 dígitos hondureños sueltos, a
// veces con espacios/guiones. Baileys necesita el formato internacional
// completo sin "+".
function normalizarNumero(telefono) {
  if (!telefono) return null;
  const digitos = String(telefono).replace(/\D/g, '');
  if (!digitos) return null;
  if (digitos.length === 8) return `504${digitos}`;
  if (digitos.startsWith('504') && digitos.length === 11) return digitos;
  if (digitos.length > 8) return `504${digitos.slice(-8)}`;
  return null;
}

// Agrupa por teléfono + identidad del cliente (idCliente, o documentoCliente
// real, o el nombre como último respaldo) — NO solo por cliente: el teléfono
// es propio de cada factura y dos facturas del "mismo" cliente podrían tener
// números distintos si se cargaron con contactos diferentes. Si coincide
// teléfono E identidad, se manda un solo mensaje con todas esas facturas; si
// dos clientes distintos comparten teléfono, quedan en mensajes separados
// (cada uno con su propio nombre). Las facturas sin teléfono quedan cada una
// en su propio grupo, para reportarlas una por una como omitidas.
function agruparPorDestino(facturasFiltradas, clientesPorId, ahora) {
  const porDestino = new Map();
  for (const credito of facturasFiltradas) {
    const telefono = normalizarNumero(credito.telefono);
    const documentoReal = credito.documentoCliente && credito.documentoCliente !== 'N/A' ? credito.documentoCliente : null;
    const identidad = credito.idCliente || documentoReal || (credito.nombreCliente || '').trim().toUpperCase();
    const clave = telefono ? `${telefono}::${identidad}` : `sin-telefono::${credito.id}`;
    if (!porDestino.has(clave)) {
      const cliente = credito.idCliente ? clientesPorId.get(credito.idCliente) || null : null;
      porDestino.set(clave, { telefono, nombreCliente: credito.nombreCliente || 'Cliente', cliente, facturas: [] });
    }
    porDestino.get(clave).facturas.push(credito);
  }

  const resultado = [];
  for (const { telefono, nombreCliente, cliente, facturas } of porDestino.values()) {
    facturas.sort((a, b) => (a.fechaVencimiento?.getTime() || 0) - (b.fechaVencimiento?.getTime() || 0));
    // Si a CUALQUIERA de las facturas de este grupo nunca se le avisó, o ya
    // pasó el intervalo desde su último aviso, el grupo entra en la tanda de
    // hoy — y al mandarse el aviso se sincroniza `ultimoAvisoEnviado` en
    // TODAS sus facturas (ver marcarAvisoEnviado), así la cadencia de
    // recordatorios queda compartida en vez de desfasada por factura.
    const necesitaAviso = facturas.some((f) => {
      if (!f.ultimoAvisoEnviado) return true;
      return diasEntre(f.ultimoAvisoEnviado, ahora) >= intervaloDiasRecordatorio;
    });
    resultado.push({
      cliente,
      nombreCliente: cliente?.nombreCompleto || nombreCliente,
      telefono,
      facturas,
      saldoTotal: facturas.reduce((s, f) => s + (f.saldoPendiente || 0), 0),
      // Wording correcto en el mensaje/PDF: si TODAS las facturas del grupo
      // están de verdad vencidas se puede hablar de "crédito vencido"; si
      // alguna todavía no llega a su fecha (ver más abajo,
      // obtenerGrupoDeCredito la puede incluir a propósito), el mensaje usa
      // lenguaje neutral de "estado de cuenta" en vez de acusar un atraso
      // que no existe.
      vencidas: facturas.every((f) => esVencida(f, ahora)),
      necesitaAviso,
    });
  }
  return resultado;
}

// Para la tanda diaria (index.js): SOLO créditos ya vencidos.
async function obtenerClientesConCreditoVencido() {
  const [creditos, clientes] = await Promise.all([
    consultarColeccionCompleta('ventasCredito'),
    consultarColeccionCompleta('clientes'),
  ]);
  const clientesPorId = new Map(clientes.map((c) => [c.id, c]));
  const ahora = new Date();
  const vencidos = creditos.filter((c) => esVencida(c, ahora));
  return agruparPorDestino(vencidos, clientesPorId, ahora);
}

// Para "Enviar aviso ahora" / "Enviar estado de cuenta" manual (escuchar.js):
// cualquier crédito con saldo pendiente, esté vencido o no -pedido explícito
// del dueño: poder mandarlo aunque la factura todavía no se haya vencido-.
// Devuelve el grupo (teléfono + demás facturas del mismo cliente/teléfono
// con saldo pendiente) que contiene [idCredito], o null si esa factura ya
// no tiene saldo pendiente (se liquidó/eliminó) o no se encuentra.
async function obtenerGrupoDeCredito(idCredito) {
  const [creditos, clientes] = await Promise.all([
    consultarColeccionCompleta('ventasCredito'),
    consultarColeccionCompleta('clientes'),
  ]);
  const clientesPorId = new Map(clientes.map((c) => [c.id, c]));
  const ahora = new Date();
  const conSaldo = creditos.filter((c) => (c.saldoPendiente || 0) > 0);
  const grupos = agruparPorDestino(conSaldo, clientesPorId, ahora);
  return grupos.find((g) => g.facturas.some((f) => f.id === idCredito)) || null;
}

async function marcarAvisoEnviado(facturas) {
  const ahora = new Date();
  await Promise.all(facturas.map((f) => actualizarCampos('ventasCredito', f.id, { ultimoAvisoEnviado: ahora })));
}

module.exports = { obtenerClientesConCreditoVencido, obtenerGrupoDeCredito, marcarAvisoEnviado, normalizarNumero };
