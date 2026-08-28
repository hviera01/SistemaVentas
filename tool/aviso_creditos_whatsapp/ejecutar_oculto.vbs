' Envoltorio para que el Programador de Tareas de Windows corra escuchar.js
' cada 2 minutos SIN mostrar ninguna ventana de consola -pedido explícito
' del dueño-. WScript.Shell.Run con el segundo parámetro en 0 = ventana
' oculta; el tercero (True) = esperar a que termine antes de que la tarea
' se dé por completada.
Set WshShell = CreateObject("WScript.Shell")
carpeta = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
WshShell.Run """C:\Program Files\nodejs\node.exe"" """ & carpeta & "\escuchar.js""", 0, True
