' Alternativa a la tarea programada de Windows (el Programador de Tareas de
' esta PC resultó poco confiable con el disparador "repetir cada N minutos" -
' se quedaba enganchado como "Habilitado" pero dejaba de dispararse solo, dos
' veces con configuraciones distintas). Este script en cambio se pone en la
' carpeta de Inicio de Windows (shell:startup) y arranca solo al iniciar
' sesión: corre en bucle para siempre, sin depender del Programador de
' Tareas para nada. Completamente invisible (wscript.exe no abre consola, y
' cada corrida de node.exe se lanza oculta con estilo de ventana 0).
Set WshShell = CreateObject("WScript.Shell")
carpeta = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Do While True
  WshShell.Run """C:\Program Files\nodejs\node.exe"" """ & carpeta & "\escuchar.js""", 0, True
  WScript.Sleep 120000 ' 2 minutos
Loop
