import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/providers/tabs_provider.dart';
import '../../../../core/models/tab_item.dart';
import '../../../../core/data/modulos_menu.dart';
import '../../../../core/utils/pantalla_builder.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../providers/resumen_ventas_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _abrirSubModulo(WidgetRef ref, SubModulo sub) {
    final esVentaNueva = sub.moduleKey == 'ventas_registrar';
    final id = esVentaNueva ? 'ventas_registrar_${DateTime.now().millisecondsSinceEpoch}' : sub.moduleKey;
    ref.read(tabsProvider.notifier).abrirTab(
      TabItem(
        id: id,
        titulo: sub.titulo,
        icono: sub.icono,
        contenido: construirPantalla(sub.moduleKey, sub.titulo, sub.icono, id),
      ),
    );
  }

  void _manejarTap(BuildContext context, WidgetRef ref, ModuloMenu modulo, bool esAdmin) {
    final disponibles = modulo.subModulos.where((s) => esAdmin || !s.soloAdmin).toList();
    if (disponibles.isEmpty) return;
    if (disponibles.length == 1) {
      _abrirSubModulo(ref, disponibles.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 16),
                Text(modulo.titulo, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                const SizedBox(height: 8),
                ...disponibles.map((sub) {
                  return ListTile(
                    leading: Icon(sub.icono, color: modulo.color),
                    title: Text(sub.titulo, style: GoogleFonts.poppins(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _abrirSubModulo(ref, sub);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final usuario = authState.usuario;
    final esAdmin = usuario?.rol == 'Administrador';

    final modulosVisibles = obtenerModulos().where((m) {
      return m.subModulos.any((s) => esAdmin || !s.soloAdmin);
    }).toList();

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 16 : 28),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, ${usuario?.nombreCompleto ?? ''}',
                    style: GoogleFonts.poppins(fontSize: esMovil ? 20 : 24, fontWeight: FontWeight.w700, color: const Color(0xFFC62828)),
                  ),
                  const SizedBox(height: 4),
                  Text('Seleccioná una opción para comenzar', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 20),
                  _resumenVentas(ref, esMovil),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: modulosVisibles.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: esMovil ? 180 : 270,
                      mainAxisSpacing: esMovil ? 14 : 20,
                      crossAxisSpacing: esMovil ? 14 : 20,
                      childAspectRatio: esMovil ? 0.92 : 1.15,
                    ),
                    itemBuilder: (context, index) {
                      final modulo = modulosVisibles[index];
                      return _tarjetaModulo(context, ref, modulo, esAdmin, esMovil);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resumenVentas(WidgetRef ref, bool esMovil) {
    final resumen = ref.watch(resumenVentasHomeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final apilado = esMovil || constraints.maxWidth < 480;
        final tarjetas = [
          _tarjetaResumenVenta(
            titulo: 'Venta de hoy',
            icono: Icons.today_rounded,
            colores: const [Color(0xFFC62828), Color(0xFFE53935)],
            monto: resumen.whenOrNull(data: (r) => r.totalDia),
            subtitulo: resumen.whenOrNull(data: (r) => '${r.cantidadVentasDia} ${r.cantidadVentasDia == 1 ? 'venta' : 'ventas'}'),
            cargando: resumen.isLoading,
          ),
          _tarjetaResumenVenta(
            titulo: 'Venta del mes',
            icono: Icons.calendar_month_rounded,
            colores: const [Color(0xFF1E3A5F), Color(0xFF2C5282)],
            monto: resumen.whenOrNull(data: (r) => r.totalMes),
            subtitulo: _nombreMesActual(),
            cargando: resumen.isLoading,
          ),
        ];

        if (apilado) {
          return Column(
            children: [
              tarjetas[0],
              const SizedBox(height: 12),
              tarjetas[1],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: tarjetas[0]),
            const SizedBox(width: 16),
            Expanded(child: tarjetas[1]),
          ],
        );
      },
    );
  }

  String _nombreMesActual() {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    final ahora = DateTime.now();
    return 'de ${meses[ahora.month - 1]}';
  }

  Widget _tarjetaResumenVenta({
    required String titulo,
    required IconData icono,
    required List<Color> colores,
    required double? monto,
    required String? subtitulo,
    required bool cargando,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colores, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colores.last.withOpacity(0.30), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
            child: Icon(icono, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.85))),
                const SizedBox(height: 2),
                cargando
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : Text(
                        formatearMoneda(monto ?? 0),
                        style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                if (!cargando && subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitulo, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.white.withOpacity(0.75))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaModulo(BuildContext context, WidgetRef ref, ModuloMenu modulo, bool esAdmin, bool esMovil) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _manejarTap(context, ref, modulo, esAdmin),
        child: Container(
          padding: EdgeInsets.all(esMovil ? 14 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: esMovil ? 42 : 52,
                height: esMovil ? 42 : 52,
                decoration: BoxDecoration(color: modulo.color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(modulo.icono, color: modulo.color, size: esMovil ? 20 : 26),
              ),
              SizedBox(height: esMovil ? 10 : 16),
              Text(
                modulo.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: esMovil ? 13 : 15.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 4),
              Text(
                '${modulo.subModulos.where((s) => esAdmin || !s.soloAdmin).length} opciones',
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}