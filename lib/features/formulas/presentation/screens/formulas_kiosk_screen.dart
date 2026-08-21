import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../colores/data/color_model.dart';
import '../../../colores/providers/colores_provider.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../clientes/providers/clientes_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import 'buscar_formula_screen.dart';

/// App de consulta rápida sin login -pensada para que quede como acceso
/// directo en la pantalla de inicio del celular/tablet (ver el link con
/// "?formulas=1" en main.dart, que hace justo eso: se salta el AuthGate
/// entero). Lo principal es buscar fórmulas del libro Color Codex; también
/// deja buscar en Registro de Colores y Clientes desde acá mismo, sin tener
/// que abrir el sistema completo. Se conecta a Firestore igual que el
/// sistema (las reglas de Firestore ya son abiertas para toda la app, no
/// hay una capa de seguridad nueva que romper acá) pero no pasa por el
/// AuthGate ni pide código/clave.
class FormulasKioskScreen extends StatefulWidget {
  const FormulasKioskScreen({super.key});

  @override
  State<FormulasKioskScreen> createState() => _FormulasKioskScreenState();
}

class _FormulasKioskScreenState extends State<FormulasKioskScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFC62828),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset('assets/images/logo_redondo.png', width: 34, height: 34, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Text('Fórmulas', style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Fórmulas'),
                      Tab(text: 'Colores'),
                      Tab(text: 'Clientes'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  BuscarFormulaScreen(esDialogo: false),
                  _BuscarColoresKiosk(),
                  _BuscarClientesKiosk(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuscarColoresKiosk extends ConsumerStatefulWidget {
  const _BuscarColoresKiosk();

  @override
  ConsumerState<_BuscarColoresKiosk> createState() => _BuscarColoresKioskState();
}

class _BuscarColoresKioskState extends ConsumerState<_BuscarColoresKiosk> {
  final _ctrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coloresAsync = ref.watch(coloresStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _campoBusqueda(_ctrl, 'Código, cliente, descripción o ubicación...', (v) => setState(() => _busqueda = v.trim())),
          const SizedBox(height: 12),
          Expanded(
            child: coloresAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
              error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
              data: (colores) {
                if (_busqueda.isEmpty) return _estadoVacio('Escribí para buscar en Registro de Colores');
                final resultados = colores.where((c) => coincideFuzzy(c.textoBusqueda, _busqueda)).toList();
                if (resultados.isEmpty) return _estadoVacio('Sin resultados para "$_busqueda"');
                return ListView.separated(
                  itemCount: resultados.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _tarjetaColor(resultados[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaColor(ColorModel c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.codigo, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
          if (c.descripcion.isNotEmpty) Text(c.descripcion, style: GoogleFonts.poppins(fontSize: 13)),
          if (c.cliente.isNotEmpty) Text('Cliente: ${c.cliente}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          if (c.ubicacionFisica.isNotEmpty) Text('Ubicación: ${c.ubicacionFisica}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          if (c.pagina.isNotEmpty) Text('Página: ${c.pagina}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _BuscarClientesKiosk extends ConsumerStatefulWidget {
  const _BuscarClientesKiosk();

  @override
  ConsumerState<_BuscarClientesKiosk> createState() => _BuscarClientesKioskState();
}

class _BuscarClientesKioskState extends ConsumerState<_BuscarClientesKiosk> {
  final _ctrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientesAsync = ref.watch(clientesStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _campoBusqueda(_ctrl, 'Nombre, DNI o teléfono...', (v) => setState(() => _busqueda = v.trim())),
          const SizedBox(height: 12),
          Expanded(
            child: clientesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
              error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
              data: (clientes) {
                if (_busqueda.isEmpty) return _estadoVacio('Escribí para buscar en Clientes');
                final resultados = clientes.where((c) => coincideFuzzy(c.textoBusqueda, _busqueda)).toList();
                if (resultados.isEmpty) return _estadoVacio('Sin resultados para "$_busqueda"');
                return ListView.separated(
                  itemCount: resultados.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _tarjetaCliente(resultados[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCliente(ClienteModel c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.nombreCompleto, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          if (c.dni.isNotEmpty) Text('DNI: ${c.dni}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          if (c.telefono.isNotEmpty) Text('Tel: ${c.telefono}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          if (c.direccion.isNotEmpty) Text(c.direccion, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

Widget _campoBusqueda(TextEditingController ctrl, String hint, void Function(String) onChanged) {
  return Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB6BCC7))),
    child: Row(
      children: [
        Icon(Icons.search, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrl,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400), border: InputBorder.none, isDense: true),
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

Widget _estadoVacio(String texto) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 10),
        Text(texto, style: GoogleFonts.poppins(color: Colors.grey.shade500)),
      ],
    ),
  );
}
