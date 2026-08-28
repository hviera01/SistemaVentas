# Aviso de créditos vencidos por WhatsApp

Script aparte de la app de Flutter (Node.js) que revisa los créditos de
clientes vencidos en Firestore y le manda a cada cliente, por WhatsApp, su
estado de cuenta en PDF (facturas vencidas, días de atraso, saldo total).

Son DOS scripts separados, ambos con el mismo formato: corren una vez,
revisan, mandan lo que les toque, y terminan (nada se queda corriendo en
segundo plano) — cada uno programado con una frecuencia distinta:
- `index.js` — pensado para una vez al día.
- `escuchar.js` — pensado para cada 2 minutos: revisa si el dueño tocó
  "Enviar estado de cuenta por WhatsApp" en Ventas Crédito (dentro de la
  app) y lo manda sin esperar al día siguiente. Ver "Envío manual" abajo.

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

## Envío manual ("Enviar estado de cuenta por WhatsApp")

En Ventas Crédito, cualquier factura con saldo pendiente y teléfono cargado
tiene esa opción en su menú (⋮). Al tocarla, la app solo marca el pedido en
Firestore (`solicitudAvisoWhatsApp: true` en ese documento de
`ventasCredito`) — **no manda nada por sí sola**. Para que de verdad se
mande hace falta que algo esté corriendo `escuchar.js` cada 2 minutos en la
PC principal (ver "Cómo dejarlo corriendo" abajo).

**Cómo saber si está funcionando**: cada vez que corre, `escuchar.js` manda
un latido a Firestore (`presenciaAvisoWhatsapp/escuchador`). La app lo
chequea antes de avisar "se manda en un par de minutos" — si el último
latido tiene más de 4 minutos, avisa de inmediato con un mensaje rojo (el
pedido igual queda guardado, se manda solo en la próxima corrida). Si el
envío falla por otro motivo (sesión de WhatsApp cerrada, número inválido,
sin saldo pendiente ya, etc.), el motivo real queda guardado en
`errorAvisoWhatsApp` de ese crédito y aparece en Ventas Crédito (ícono rojo
junto al nombre en la tabla, o un aviso debajo de la tarjeta en móvil) — no
hace falta abrir la consola de la PC para saber qué pasó.

**Cómo dejarlo corriendo — carpeta de Inicio de Windows (recomendado):**

El Programador de Tareas de Windows resultó poco confiable en la PC del
dueño con el disparador "repetir cada N minutos" (quedaba mostrándose
"Habilitado" y bien configurado, pero dejaba de dispararse solo después de
un rato — pasó dos veces, con configuraciones distintas). En vez de pelear
con eso, `escuchar_loop.vbs` hace lo mismo por su cuenta, sin depender del
Programador de Tareas para nada: corre en bucle infinito (esperando 2
minutos entre corrida y corrida) y se lanza solo poniéndolo en la carpeta
de Inicio de Windows.

1. `Windows + R` → escribir `shell:startup` → Enter (abre la carpeta de
   Inicio del usuario actual).
2. Copiar ahí `tool/aviso_creditos_whatsapp/escuchar_loop.vbs`.
3. Doble clic sobre esa copia para arrancarlo ya mismo (no hace falta
   cerrar sesión) — no debería abrir ninguna ventana, eso es buena señal.

Con esto, cada inicio de sesión en esa PC lo vuelve a arrancar solo, y se
queda corriendo para siempre sin ningún límite de tiempo que configurar ni
nada que se pueda "revertir solo" como pasaba con el Programador de Tareas.

**Alternativa (Programador de Tareas, por si se prefiere)**: se puede
programar `node.exe escuchar.js` (sin el bucle, ese script corre una vez y
termina) con `/SC MINUTE /MO 2` desde una consola de **Administrador**
(`schtasks /Create /TN "..." /TR "..." /SC MINUTE /MO 2 /F` — NO uses el
asistente gráfico "Crear tarea básica", ahí es donde daba error), pero en
la práctica el bucle en la carpeta de Inicio resultó más confiable en esta
PC.

## Si algo falla

- Si dice que la sesión está cerrada ("logout"), correr
  `npm run login` en `tool/reporte_whatsapp` (no en esta carpeta) para
  volver a vincular el número — ambos scripts comparten esa sesión.
- Si un cliente no recibió el aviso, revisar en la consola si salió como
  "Sin teléfono válido" — hay que abrir su factura en Ventas Crédito y
  usar "Agregar teléfono"/"Editar teléfono" (no hace falta que el crédito
  esté vinculado a un cliente registrado para esto).
