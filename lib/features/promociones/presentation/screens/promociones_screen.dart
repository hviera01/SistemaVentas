import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/promocion_model.dart';
import '../../providers/promociones_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../widgets/promocion_form_dialog.dart';

/// Mantenedor de "Descuentos y Promociones": alta, edición, activar/
/// desactivar y baja. También sirve para "consultar todas las promociones
/// vigentes" (filtro Vigentes / Todas) sin tener que ir producto por
/// producto — ver también PromocionesVigentesDialog, la versión resumida
/// que se abre desde Registrar Venta para el cajero.
class PromocionesScreen extends ConsumerStatefulWidget {
  const PromocionesScreen({super.key});

  @override
  ConsumerState<PromocionesScreen> createState() => _PromocionesScreenState();
}

class _PromocionesScreenState extends ConsumerState<PromocionesScreen> {
  final _busquedaController = TextEditingController();
  String _vista = 'vigentes';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() {
    ref.read(promocionesBusquedaProvider.notifier).actualizar(_busquedaController.text.trim());
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(promocionesBusquedaProvider.notifier).actualizar('');
  }

  void _abrirFormulario([PromocionModel? promocion]) {
    showDialog(context: context, builder: (context) => PromocionFormDialog(promocion: promocion));
  }

  Future<void> _alternarActivo(PromocionModel p) async {
    await ref.read(promocionRepositoryProvider).alternarActivo(p.id, !p.activo);
  }

  Future<void> _eliminar(PromocionModel p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar promoción', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar "${p.nombre}"? Esta acción no se puede deshacer.', style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ref.read(promocionRepositoryProvider).eliminar(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final promocionesAsync = ref.watch(promocionesStreamProvider);
    final busqueda = ref.watch(promocionesBusquedaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 720;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Descuentos y Promociones', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                Text(
                  'Armá descuentos por porcentaje, precio especial, combos por cantidad o regalos. Se ofrecen solos al vender un producto con promoción vigente.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(width: esMovil ? constraints.maxWidth : 220, child: _selectorVista()),
                    SizedBox(width: esMovil ? constraints.maxWidth : 320, child: _buscador(busqueda)),
                    FilledButton.icon(
                      onPressed: () => _abrirFormulario(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Nueva Promoción', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: promocionesAsync.when(
                    data: (todas) {
                      var lista = todas;
                      if (busqueda.isNotEmpty) {
                        lista = lista.where((p) => coincideFuzzy(p.textoBusqueda, busqueda)).toList();
                      } else if (_vista == 'vigentes') {
                        lista = promocionesVigentes(lista);
                      }
                      if (lista.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_offer_outlined, size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                _vista == 'vigentes' ? 'No hay promociones vigentes ahora mismo' : 'No hay promociones registradas',
                                style: GoogleFonts.poppins(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        );
                      }
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, mainAxisExtent: 210, crossAxisSpacing: 12, mainAxisSpacing: 12),
                        itemCount: lista.length,
                        itemBuilder: (context, i) => _tarjetaPromocion(lista[i]),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                    error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _selectorVista() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _vista,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: const [
            DropdownMenuItem(value: 'vigentes', child: Text('Solo vigentes')),
            DropdownMenuItem(value: 'todas', child: Text('Todas')),
          ],
          onChanged: (v) => setState(() => _vista = v ?? 'vigentes'),
        ),
      ),
    );
  }

  Widget _buscador(String busqueda) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _busquedaController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(hintText: 'Buscar por nombre o producto...', hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400), border: InputBorder.none, isDense: true),
              onSubmitted: (_) => _buscar(),
            ),
          ),
          if (busqueda.isNotEmpty) IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.close, size: 18), onPressed: _limpiarBusqueda),
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _buscar),
        ],
      ),
    );
  }

  Widget _tarjetaPromocion(PromocionModel p) {
    final vigente = p.vigente(DateTime.now());
    final formatoFecha = DateFormat('dd/MM/yy');
    final colorEstado = !p.activo ? Colors.grey.shade400 : (vigente ? const Color(0xFF16A34A) : const Color(0xFFF59E0B));
    final textoEstado = !p.activo ? 'Inactiva' : (vigente ? 'Vigente' : 'Fuera de fecha');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 19, color: Color(0xFF454950)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'editar') _abrirFormulario(p);
                  if (v == 'alternar') _alternarActivo(p);
                  if (v == 'eliminar') _eliminar(p);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'editar', child: Text('Editar', style: GoogleFonts.poppins(fontSize: 12.5))),
                  PopupMenuItem(value: 'alternar', child: Text(p.activo ? 'Desactivar' : 'Activar', style: GoogleFonts.poppins(fontSize: 12.5))),
                  PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFFC62828)))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: colorEstado.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(textoEstado, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: colorEstado)),
          ),
          const SizedBox(height: 10),
          Text(p.etiquetaCorta, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFFC62828))),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              _descripcionProductos(p),
              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  p.esIndefinida ? 'Desde ${formatoFecha.format(p.fechaInicio)} · sin fecha de fin' : 'Del ${formatoFecha.format(p.fechaInicio)} al ${formatoFecha.format(p.fechaFin!)}',
                  style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(p.alcancePago == 'Todos' ? 'Todos los métodos de pago' : 'Solo ${p.alcancePago}', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  String _descripcionProductos(PromocionModel p) {
    switch (p.tipo) {
      case TipoPromocion.porcentaje:
        return '${p.valor.toStringAsFixed(p.valor == p.valor.roundToDouble() ? 0 : 1)}% off en: ${p.nombresProductos.join(', ')}';
      case TipoPromocion.precioFijo:
        return '${formatearMoneda(p.valor)} c/u en: ${p.nombresProductos.join(', ')}';
      case TipoPromocion.comboCantidad:
        return 'Llevando ${p.cantidadRequerida} de "${p.nombreProductoBase}" se pagan ${formatearMoneda(p.precioCombo)} en total.';
      case TipoPromocion.regalo:
        return 'Llevando ${p.cantidadRequerida} de "${p.nombreProductoBase}" se regalan ${p.cantidadRegalo} de "${p.nombreProductoRegalo}".';
    }
  }
}
