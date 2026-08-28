' Alternativa a la tarea programada de Windows (el Programador de Tareas de
' esta PC resultó poco confiable con el disparador "repetir cada N minutos" -
' se quedaba enganchado como "Habilitado" pero dejaba de dispararse solo, dos
' veces con configuraciones distintas). Este script en cambio se pone en la
' carpeta de Inicio de Windows (shell:startup) y arranca solo al iniciar
' sesión: corre en bucle para siempre, sin depender del Programador de
' Tareas para nada. Completamente invisible (wscript.exe no abre consola, y
' cada corrida de node.exe se lanza oculta con estilo de ventana 0).
'
' OJO: la ruta de escuchar.js va FIJA (no calculada con
' WScript.ScriptFullName) a propósito -este archivo se copia a la carpeta de
' Inicio de Windows, que es un lugar DISTINTO de donde vive escuchar.js, así
' que calcularla en base a dónde corre este mismo script apuntaba mal
' (buscaba escuchar.js adentro de la carpeta de Inicio, no lo encontraba, y
' node.exe fallaba en silencio -sin ventana visible, no había forma de
' notarlo- así que nunca mandaba el latido de presencia).
Set WshShell = CreateObject("WScript.Shell")

Do While True
  WshShell.Run """C:\Program Files\nodejs\node.exe"" ""C:\Proyectos\sistema_ventas\tool\aviso_creditos_whatsapp\escuchar.js""", 0, True
  WScript.Sleep 120000 ' 2 minutos
Loop
