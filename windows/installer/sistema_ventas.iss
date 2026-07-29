; Instalador de Windows para Super Color, generado con Inno Setup 6.
;
; El AppId de acá abajo es NUEVO (no existe copia previa de este .iss en el
; repo ni en esta máquina, ver historial del chat). Los instaladores hasta
; la v28 se generaban con otro script que se perdió, con otro AppId, así que
; quien actualice desde una versión <=28 va a terminar con una instalación
; nueva (separada) en vez de un reemplazo en el mismo lugar -no hay forma de
; evitar eso sin el AppId original-. De acá en adelante, mientras se siga
; usando este mismo .iss (y no se le cambie el AppId), las actualizaciones
; sí van a reemplazar la instalación en el mismo lugar correctamente.
;
; Uso: compilar con
;   flutter build windows --release
;   iscc windows\installer\sistema_ventas.iss
; El .exe resultante queda en windows\installer\Output\SuperColor<version>.exe
; -subirlo a mano al release de GitHub junto con el .apk, ver
; ActualizacionService y version_app.dart-.

#define MyAppName "Super Color"
#define MyAppVersion "29"
#define MyAppPublisher "Super Color"
#define MyAppExeName "sistema_ventas.exe"
#define MyReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{60E690E9-61D3-4E6E-972C-041E70F0C7F6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=Output
OutputBaseFilename=SuperColor{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el Escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#MyReleaseDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyReleaseDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
