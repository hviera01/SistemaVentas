# Aviso de créditos vencidos por WhatsApp

Script aparte de la app de Flutter (Node.js) que revisa los créditos de
clientes vencidos en Firestore y le manda a cada cliente, por WhatsApp, su
estado de cuenta en PDF (facturas vencidas, días de atraso, saldo total).

Son DOS programas separados, para dos formas de dispararlo:
- `index.js` — corre una vez, revisa todo, manda lo que le toque, y
  termina. Pensado para la tarea diaria programada.
- `escuchar.js` — se queda corriendo, revisando cada 15s si el dueño tocó
  "Enviar aviso de WhatsApp ahora" en Ventas Crédito (dentro de la app), y
  lo manda al toque sin esperar al día siguiente. Ver "Envío manual" abajo.

**No necesita login propio**: reusa la sesión de WhatsApp ya vinculada por
`tool/reporte_whatsapp` (el número personal de Henry), así que no hay que
escanear ningún QR para este script — solo hace falta que esa carpeta ya
tenga `auth_info/` con la sesión activa.

## Cómo decide a quién avisar

- Un crédito está "vencido" con el mismo criterio que usa la app:
  `saldoPendiente > 0` y `fechaVencimiento` ya pasada.
- Cada crédito trae su PROPIO teléfono (`VentaCreditoModel.telefono`,
  capturado en Registrar Venta o editable después en Ventas Crédito con
  "Editar teléfono") — es independiente del teléfono del cliente en el
  módulo Clientes, a propósito. Se agrupa por ese teléfono + el mismo
  cliente: si el mismo cliente tiene varias facturas vencidas con el mismo
  número, le llega **un solo mensaje** con todas, no uno por factura.
- El primer aviso sale apenas se detecta la primera factura vencida.
  Mientras el saldo siga vencido, se vuelve a avisar cada
  `intervaloDiasRecordatorio` días (`config.js`, hoy en 3) — se guarda la
  fecha del último aviso en el campo `ultimoAvisoEnviado` de cada documento
  `ventasCredito` (campo nuevo, no rompe nada existente).
- Si un crédito no tiene teléfono cargado, se omite y se avisa por
  consola — hay que agregárselo desde Ventas Crédito ("Agregar teléfono")
  para que empiece a recibir avisos.

## Instalación (una sola vez)

```
cd tool/aviso_creditos_whatsapp
npm install
```

## Probar a mano antes de dejarlo programado

**Importante**: probar primero con `--prueba` para no gastarle un
recordatorio real a un cliente ni mandarle nada a un número equivocado.

```
node index.js --prueba=50499999999
```

Esto manda TODOS los avisos pendientes de hoy a ese número (reemplazá por
tu propio celular), con el contenido real de cada estado de cuenta, pero
**sin** actualizar `ultimoAvisoEnviado` en Firestore — se puede correr las
veces que haga falta sin gastar el "turno" del recordatorio real.

Cuando el contenido se vea bien, correr sin `--prueba` para el envío real:

```
node index.js
```

## Configuración

Editar `config.js`:
- `nombreNegocio`: el nombre que sale en el PDF y en el mensaje.
- `intervaloDiasRecordatorio`: cada cuántos días se repite el aviso a un
  cliente mientras siga con saldo vencido.

## Programar el envío diario (Programador de Tareas de Windows)

1. Abrí **Programador de tareas** → Crear tarea básica.
2. Nombre: `Aviso Créditos Vencidos WhatsApp Super Color`.
3. Desencadenador: Diario, a la hora que prefieras (ej. 9:00 AM).
4. Acción: Iniciar un programa.
   - Programa/script: `node`
   - Argumentos: `index.js`
   - Iniciar en: la ruta completa de esta carpeta, ej.
     `C:\Proyectos\sistema_ventas\tool\aviso_creditos_whatsapp`
5. Igual que la tarea de `reporte_whatsapp`: dejarla "solo si inició sesión"
   si la PC se bloquea normalmente (WhatsApp Web necesita la sesión de red
   disponible).
6. **Si la PC está apagada a la hora programada** (ej. 9:00 AM), por
   defecto el Programador de Tareas simplemente se salta esa ejecución — NO
   se pospone sola. Para que sí se dispare apenas se prenda la PC (aunque
   sea horas después), en la pestaña **Configuración** de la tarea marcar
   "Ejecutar la tarea tan pronto como sea posible después de una hora de
   inicio programada perdida". Con esto, si un día la PC arranca a las 11am,
   el aviso de ese día sale a las 11am en vez de perderse — igual conviene
   activar lo mismo en las tareas de `reporte_whatsapp` si no está ya.

## Envío manual ("Enviar aviso de WhatsApp ahora")

En Ventas Crédito, cualquier factura vencida con teléfono cargado tiene esa
opción en su menú (⋮). Al tocarla, la app solo marca el pedido en
Firestore (`solicitudAvisoWhatsApp: true` en ese documento de
`ventasCredito`) — **no manda nada por sí sola**. Para que de verdad se
mande hace falta que `escuchar.js` esté corriendo en la PC principal:

```
cd tool/aviso_creditos_whatsapp
npm run escuchar
```

Se queda corriendo en esa ventana (Ctrl+C para pararlo), revisando cada 15
segundos si hay algún pedido pendiente. Si querés que esto funcione siempre
sin tener que abrir una ventana a mano, se puede dejar programado igual que
la tarea diaria, pero con un desencadenador distinto:

1. Programador de tareas → Crear tarea básica.
2. Nombre: `Escuchar Avisos Crédito WhatsApp Super Color`.
3. Desencadenador: **Al iniciar sesión** (no diario — este proceso se queda
   corriendo, no termina solo).
4. Acción: Iniciar un programa.
   - Programa/script: `node`
   - Argumentos: `escuchar.js`
   - Iniciar en: `C:\Proyectos\sistema_ventas\tool\aviso_creditos_whatsapp`
5. En "Configuración" de la tarea, desmarcar cualquier límite de tiempo de
   ejecución (por defecto el Programador de Tareas corta las tareas después
   de 3 días) — Propiedades → Configuración → "Detener la tarea si se
   ejecuta durante más de" → desmarcar.

## Si algo falla

- Si dice que la sesión está cerrada ("logout"), correr
  `npm run login` en `tool/reporte_whatsapp` (no en esta carpeta) para
  volver a vincular el número — ambos scripts comparten esa sesión.
- Si un cliente no recibió el aviso, revisar en la consola si salió como
  "Sin teléfono válido" — hay que abrir su factura en Ventas Crédito y
  usar "Agregar teléfono"/"Editar teléfono" (no hace falta que el crédito
  esté vinculado a un cliente registrado para esto).
