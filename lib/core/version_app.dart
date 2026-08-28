/// Versión de la app instalada (Windows y Android comparten el mismo
/// número). Tiene que coincidir con el tag de la GitHub Release (ver
/// ActualizacionService) y con MyAppVersion/OutputBaseFilename en el .iss de
/// Inno Setup usado para compilar el instalador de Windows. Se sube en 1
/// cada vez que se publica una release nueva (con .exe y/o .apk).
const int versionApp = 124;
