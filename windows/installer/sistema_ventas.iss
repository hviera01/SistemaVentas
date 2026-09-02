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
#define MyAppVersion "150"
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
; VersionInfo* pone la versión real en las Propiedades de Windows del .exe
; (clic derecho > Propiedades > Detalles) -antes quedaba en blanco/genérico,
; así que un instalador viejo guardado en Descargas con nombre parecido a
; uno nuevo era indistinguible a simple vista-.
VersionInfoVersion={#MyAppVersion}.0.0.0
VersionInfoProductVersion={#MyAppVersion}.0.0.0
VersionInfoProductName={#MyAppName}
VersionInfoDescription=Instalador de {#MyAppName} versión {#MyAppVersion}

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

[Code]
// Devuelve el número de versión ya instalada (leído del registro, lo mismo
// que muestra Windows en "Programas y características"), o 0 si no hay
// ninguna instalación previa.
function VersionYaInstalada(): Integer;
var
  sVersion: String;
begin
  Result := 0;
  if RegQueryStringValue(HKLM64, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{885ED3C7-640C-4A18-ABC1-52482C28F573}_is1', 'DisplayVersion', sVersion) then
    Result := StrToIntDef(sVersion, 0);
end;

// Bloquea instalar un .exe con versión igual o menor a la que ya está
// puesta -bug real reportado por el dueño: instalaba/reinstalaba y la app
// seguía reportando una versión vieja en el módulo de Dispositivos, muy
// probablemente porque el archivo que corría no era el último (Descargas
// se llena de instaladores con nombres casi iguales, SuperColor140.exe,
// SuperColor141.exe, etc. y antes no había forma de diferenciarlos ni de
// que el instalador se quejara). Antes esto se instalaba en silencio
// "hacia atrás" sin ningún aviso.
function InitializeSetup(): Boolean;
var
  instalada: Integer;
begin
  instalada := VersionYaInstalada();
  Result := instalada < StrToInt('{#MyAppVersion}');
  if not Result then
    MsgBox('Ya tenés instalada la versión ' + IntToStr(instalada) + ', que es igual o más nueva que este instalador (versión {#MyAppVersion}).' + #13#10 + #13#10 +
      'Este instalador es viejo -probablemente guardado de una descarga anterior en la carpeta de Descargas- y no se va a instalar, para no reemplazar la versión actual por una más vieja.' + #13#10 + #13#10 +
      'Borrá este archivo y usá "Buscar actualización" dentro del programa, o descargá de nuevo el instalador más reciente.',
      mbError, MB_OK);
end;
