/// Versión de la build de Windows instalada. Tiene que coincidir con el
/// número usado como tag de la GitHub Release (ver ActualizacionService) y
/// con MyAppVersion/OutputBaseFilename en el .iss de Inno Setup que se usó
/// para compilar este instalador. Se sube en 1 cada vez que se publica un
/// instalador nuevo.
const int versionAppWindows = 25;
