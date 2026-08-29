import 'package:shared_preferences/shared_preferences.dart';

// Recuerda qué diseño de Registrar Venta eligió el usuario -pedido explícito
// del dueño: clásico, dividido, o "tipo Dynamics"- para que no haya que
// volver a elegirlo cada vez que se abre la pantalla. Mismo patrón que
// face_id_storage.dart (funciones sueltas + SharedPreferences).
const prefsRegistrarVentaVista = 'registrarVentaVista';

const registrarVentaVistaClasica = 'clasica';
const registrarVentaVistaDividida = 'dividida';
const registrarVentaVistaDynamics = 'dynamics';

Future<String> obtenerVistaGuardada() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(prefsRegistrarVentaVista) ??
      registrarVentaVistaClasica;
}

Future<void> guardarVista(String valor) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsRegistrarVentaVista, valor);
}
