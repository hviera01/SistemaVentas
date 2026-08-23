import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'core/widgets/imagen_producto_network.dart';
import 'features/formulas/presentation/screens/consultar_costo_kiosk_screen.dart';

// Punto de entrada APARTE de main.dart -se compila y se publica como su
// propia app web independiente en /SistemaVentas/costos/ (ver
// .github/workflows/deploy-pages.yml)-, mismo criterio exacto que
// main_formulas.dart: para que "Agregar a pantalla de inicio" instale esto
// como la app "Consultar Costo" con su propio ícono/nombre, en vez de la de
// "Sistema Ventas" (una compilación de Flutter totalmente aparte evita que
// el navegador capture el manifest.json de la app principal).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Container(
        color: Colors.white,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          'Ocurrió un error al mostrar esta pantalla:\n${details.exception}',
          style: const TextStyle(color: Colors.red, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
  GoogleFonts.config.allowRuntimeFetching = false;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  ImagenProductoNetwork.precalentar();
  runApp(const ProviderScope(child: ConsultarCostoApp()));
}

class ConsultarCostoApp extends StatelessWidget {
  const ConsultarCostoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consultar Costo · Super Color',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFC62828),
        useMaterial3: true,
      ),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const ConsultarCostoKioskScreen(),
    );
  }
}
