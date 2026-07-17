import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/proveedor_model.dart';
import '../../providers/proveedores_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../widgets/proveedor_form_dialog.dart';

class ProveedoresScreen extends ConsumerStatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  ConsumerState<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends ConsumerState<ProveedoresScreen> {
  final _busquedaController = TextEditingController();
  String? _filaSeleccionada;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() {
    ref.read(proveedoresBusquedaProvider.notifier).actualizar(_busquedaController.text.trim());
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(proveedoresBusquedaProvider.notifier).actualizar('');
  }

  void _abrirFormulario([ProveedorModel? proveedor]) {
    showDialog(context: context, builder: (context) => ProveedorFormDialog(proveedor: proveedor));
  }

  Future<void> _eliminar(ProveedorModel proveedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar proveedor', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este proveedor?', style: GoogleFonts.poppins(fontSize: 13)),
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
    await ref.read(proveedorRepositoryProvider).eliminar(proveedor.id);
  }

  void _manejarAccion(String valor, ProveedorModel proveedor) {
    switch (valor) {
      case 'editar':
        _abrirFormulario(proveedor);
        break;
      case 'eliminar':
        _eliminar(proveedor);
        break;
    }
  }

  List<PopupMenuEntry<String>> _opcionesMenu() {
    return [
      _opcionMenu(valor: 'editar', icono: Icons.edit_outlined, texto: 'Editar'),
      _opcionMenu(valor: 'eliminar', icono: Icons.delete_outline, texto: 'Eliminar'),
    ];
  }

  PopupMenuItem<String> _opcionMenu({required String valor, required IconData icono, required String texto}) {
    return PopupMenuItem<String>(
      value: valor,
      height: 42,
      child: Row(children: [Icon(icono, size: 18, color: const Color(0xFF4B4F58)), const SizedBox(width: 10), Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF25272B)))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);
    final busqueda = ref.watch(proveedoresBusquedaProvider);
    final vista = ref.watch(proveedoresVistaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 720;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Text(
                    'Proveedores',
                    style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: esMovil ? constraints.maxWidth : 210, child: _selectorVista(vista)),
                      SizedBox(width: esMovil ? constraints.maxWidth : 320, child: _buscador(busqueda)),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(proveedoresStreamProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _abrirFormulario(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Nuevo Proveedor', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
              ],
              body: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
                ),
                child: proveedoresAsync.when(
                      data: (proveedores) {
                        var lista = proveedores;
                        if (busqueda.isNotEmpty) {
                          lista = lista.where((p) => coincideFuzzy(p.textoBusqueda, busqueda)).toList();
                        } else if (vista == 'filtrados') {
                          lista = [];
                        }

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_shipping_outlined, size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  vista == 'filtrados' && busqueda.isEmpty ? 'Escribí algo y presioná buscar' : 'No hay proveedores encontrados',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          );
                        }

                        return esMovil ? _tarjetas(lista) : _tabla(lista);
                      },
                      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                      error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectorVista(String vista) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: vista,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: const [
            DropdownMenuItem(value: 'filtrados', child: Text('Proveedores filtrados')),
            DropdownMenuItem(value: 'todos', child: Text('Mostrar todos')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref.read(proveedoresVistaProvider.notifier).actualizar(v);
          },
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
              decoration: InputDecoration(
                hintText: 'Buscar por RTN, razón social, correo o teléfono...',
                hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _buscar(),
            ),
          ),
          if (busqueda.isNotEmpty) IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.close, size: 18), onPressed: _limpiarBusqueda),
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _buscar),
        ],
      ),
    );
  }

  Widget _tabla(List<ProveedorModel> lista) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mostrarCorreo = constraints.maxWidth >= 950;

        return ListView.builder(
          itemCount: lista.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFFECEEF3), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                child: Row(
                  children: [
                    _celdaHeader('RTN', 2),
                    _celdaHeader('RAZÓN SOCIAL', 3),
                    if (mostrarCorreo) _celdaHeader('CORREO', 3),
                    _celdaHeader('TELÉFONO', 2),
                    _celdaHeader('ESTADO', 1),
                    const SizedBox(width: 56),
                  ],
                ),
              );
            }
            final proveedor = lista[index - 1];
            final seleccionado = _filaSeleccionada == proveedor.id;
            return Column(
              children: [
                if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
                InkWell(
                  onTap: () => setState(() => _filaSeleccionada = seleccionado ? null : proveedor.id),
                  child: Container(
                    color: seleccionado ? const Color(0xFFFBEAEA) : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        _celda(2, proveedor.rtn.isEmpty ? '-' : proveedor.rtn, peso: FontWeight.w600),
                        _celda(3, proveedor.razonSocial.isEmpty ? '-' : proveedor.razonSocial),
                        if (mostrarCorreo) _celda(3, proveedor.correo.isEmpty ? '-' : proveedor.correo, gris: true),
                        _celda(2, proveedor.telefono.isEmpty ? '-' : proveedor.telefono, gris: true),
                        Expanded(flex: 1, child: _chipEstado(proveedor.estado)),
                        SizedBox(width: 56, child: _celdaAcciones(proveedor)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF666A72), letterSpacing: 0.35)),
    );
  }

  Widget _celda(int flex, String texto, {bool gris = false, FontWeight peso = FontWeight.w400}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: peso, color: gris ? Colors.grey.shade600 : const Color(0xFF1A1A1A)),
        ),
      ),
    );
  }

  Widget _chipEstado(bool activo) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: activo ? const Color(0xFFE8F8EE) : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
        child: Text(activo ? 'Activo' : 'Inactivo', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: activo ? const Color(0xFF16A34A) : Colors.grey.shade600)),
      ),
    );
  }

  Widget _celdaAcciones(ProveedorModel proveedor) {
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFDFE1E6))), child: const Icon(Icons.more_vert, size: 19, color: Color(0xFF454950))),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      position: PopupMenuPosition.under,
      onSelected: (valor) => _manejarAccion(valor, proveedor),
      itemBuilder: (context) => _opcionesMenu(),
    );
  }

  Widget _tarjetas(List<ProveedorModel> lista) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final proveedor = lista[index];
        final seleccionado = _filaSeleccionada == proveedor.id;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _filaSeleccionada = seleccionado ? null : proveedor.id),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: seleccionado ? const Color(0xFFFBEAEA) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: seleccionado ? const Color(0xFFC62828) : const Color(0xFFC7CBD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        proveedor.razonSocial.isEmpty ? 'Sin razón social' : proveedor.razonSocial,
                        style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                      ),
                    ),
                    _celdaAcciones(proveedor),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (proveedor.rtn.isNotEmpty) _chipInfo('RTN', proveedor.rtn),
                    if (proveedor.correo.isNotEmpty) _chipInfo('Correo', proveedor.correo),
                    if (proveedor.telefono.isNotEmpty) _chipInfo('Teléfono', proveedor.telefono),
                    _chipEstado(proveedor.estado),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chipInfo(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $valor', style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF3F434A))),
    );
  }
}
