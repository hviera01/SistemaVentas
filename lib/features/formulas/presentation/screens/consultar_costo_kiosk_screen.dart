import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'consultar_costo_screen.dart';

/// App de consulta rápida sin login -pensada para quedar como acceso
/// directo en la pantalla de inicio del celular/tablet, mismo criterio que
/// FormulasKioskScreen (ver el link con "?costos=1" en main.dart, que se
/// salta el AuthGate entero). Envuelve ConsultarCostoScreen (con
/// `esDialogo: false`, para que no traiga su propio Scaffold ni flecha de
/// "atrás" -acá no hay a dónde volver-) con el mismo encabezado rojo con
/// logo que usa FormulasKioskScreen, para que se sienta la misma familia de
/// apps de kiosco. Se conecta a Firestore igual que el sistema (las reglas
/// de `productos`/`categorias`/etc. ya son abiertas para toda la app, no
/// hay una capa de seguridad nueva que romper acá) pero no pasa por el
/// AuthGate ni pide código/clave -por eso ConsultarCostoScreen no puede
/// depender de nada de sesión/authProvider, y en efecto no depende: solo
/// lee productosStreamProvider, formulasColortrendProvider y
/// LoteCostoRepository, ninguno de los cuales usa `usuario` ni `request.auth`.
class ConsultarCostoKioskScreen extends StatelessWidget {
  const ConsultarCostoKioskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFC62828),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/images/logo_redondo.png', width: 34, height: 34, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Text('Consultar Costo', style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
            const Expanded(child: ConsultarCostoScreen(esDialogo: false)),
          ],
        ),
      ),
    );
  }
}
