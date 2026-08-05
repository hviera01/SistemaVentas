# Reporte financiero semanal/mensual por WhatsApp

Script aparte de la app de Flutter (corre con Node.js) que lee Firestore
directo, arma un PDF con el resumen financiero del periodo (ventas, compras,
utilidad bruta/neta, abonos a proveedores) y lo manda por WhatsApp.

Usa WhatsApp Web "no oficial" (vinculando el número como si fuera un
celular más): **no** es la API oficial de Meta, así que no hace falta
verificar un negocio ni conseguir un número dedicado — pero tampoco es un
canal garantizado por WhatsApp, así que hay que asumir el riesgo de que en
algún momento bloqueen el número (bajo para este volumen: 1-2 mensajes por
semana a un número fijo, pero no cero).

## Instalación (una sola vez)

```
cd tool/reporte_whatsapp
npm install
npm run login
```

Va a aparecer un código QR en la terminal. Abrí WhatsApp en el celular del
número que vas a usar → **Dispositivos vinculados** → **Vincular un
dispositivo** → escaneá el QR. Cuando diga "¡Listo!" ya quedó vinculado y no
hace falta repetir esto (la sesión se guarda en `auth_info/`, que **no** se
sube a git — son credenciales sensibles).

## Probar a mano

```
npm run semanal
npm run mensual
```

Corré uno de estos a mano la primera vez para confirmar que llega el
mensaje antes de dejarlo programado.

## Configuración

Editar `config.js`:
- `numerosDestino`: lista de números que reciben el reporte (código de país
  + número, sin `+` ni espacios).
- `nombreNegocio`: el nombre que sale en el PDF.

## Programar los envíos (Programador de Tareas de Windows)

Se necesitan dos tareas — el script detecta solo el rango de fechas según
el argumento que se le pase, no según qué día es hoy.

1. Abrí **Programador de tareas** (Task Scheduler) → Crear tarea básica.
2. **Tarea semanal**:
   - Nombre: `Reporte WhatsApp Super Color - Semanal`
   - Desencadenador: Semanal, todos los sábados, a la hora que prefieras.
   - Acción: Iniciar un programa.
     - Programa/script: `node`
     - Argumentos: `index.js semanal`
     - Iniciar en: la ruta completa de esta carpeta, ej.
       `C:\Proyectos\sistema_ventas\tool\reporte_whatsapp`
3. **Tarea mensual**: igual que la anterior pero:
   - Nombre: `Reporte WhatsApp Super Color - Mensual`
   - Desencadenador: Mensual, el último día del mes (o el día 28/29/30/31
     según lo que permita el programador — lo más simple es "cada mes, el
     día 28", ya que el rango del reporte igual cubre desde el día 1 hasta
     la fecha en que corre).
   - Argumentos: `index.js mensual`
4. En ambas tareas, marcar "Ejecutar tanto si el usuario inició sesión como
   si no" solo si la PC no se apaga ni bloquea la sesión; si la PC se
   bloquea normalmente, dejarla como "solo si inició sesión" para que
   WhatsApp Web tenga la sesión de red disponible.

## Si algo falla

- `npm run semanal` o `npm run mensual` a mano muestran el error en la
  consola.
- Si dice que la sesión está cerrada ("logout"), volvé a correr
  `npm run login`.
- El cálculo del reporte replica exactamente el mismo criterio que la
  pantalla "Reporte Financiero" de la app (mismos filtros: ventas
  Activas sin cotizaciones, compras Activas, etc.) — si algún número no
  cuadra, comparar contra esa pantalla con el mismo rango de fechas.
