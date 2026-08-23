; Instalador de Windows para Super Color, generado con Inno Setup 6.
;
; El .iss original con el que se generaron los instaladores hasta la v28 no
; estaba versionado y se perdió (ver historial del chat). Este es un
; reemplazo reconstruido a mano, pero con el mismo AppId, nombre y carpeta
; de instalación que la instalación real (sacados del registro de Windows,
; HKLM\...\Uninstall\{885ED3C7-640C-4A18-ABC1-52482C28F573}_is1, en una PC
; que ya tenía Super Color instalado) para que las actualizaciones sigan
; reemplazando en el mismo lugar en vez de crear una instalación duplicada.
;
; Uso: compilar con
;   flutter build windows --release
;   iscc windows\installer\sistema_ventas.iss
; El .exe resultante queda en windows\installer\Output\SuperColor<version>.exe
; -subirlo a mano al release de GitHub junto con el .apk, ver
; ActualizacionService y version_app.dart-.

#define MyAppName "Super Color Nuevo"
#define MyAppVersion "98"
#define MyAppExeName "sistema_ventas.exe"
#define MyReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{885ED3C7-640C-4A18-ABC1-52482C28F573}
AppName={#MyAppName}
AppVerName={#MyAppName} version {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher=My Company, Inc.
AppPublisherURL=https://www.example.com/
AppSupportURL=https://www.example.com/
AppUpdatesURL=https://www.example.com/
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
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion; Excludes: "data\*"
Source: "{#MyReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
