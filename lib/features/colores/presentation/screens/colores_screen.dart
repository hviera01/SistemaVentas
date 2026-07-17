import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/color_model.dart';
import '../../data/color_export_service.dart';
import '../../providers/colores_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/exportador.dart';
import '../widgets/color_form_dialog.dart';

class ColoresScreen extends ConsumerStatefulWidget {
  const ColoresScreen({super.key});

  @override
  ConsumerState<ColoresScreen> createState() => _ColoresScreenState();
}

class _ColoresScreenState extends ConsumerState<ColoresScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = ColorExportService();
  List<ColorModel> _listaActual = [];
  String? _filaSeleccionada;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() {
    ref.read(coloresBusquedaProvider.notifier).actualizar(_busquedaController.text.trim());
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(coloresBusquedaProvider.notifier).actualizar('');
  }

  void _abrirFormulario([ColorModel? color]) {
    showDialog(context: context, builder: (context) => ColorFormDialog(color: color));
  }

  Future<void> _eliminar(ColorModel color) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar registro', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('¿Seguro que querés eliminar este registro de color?', style: GoogleFonts.poppins(fontSize: 13)),
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
    await ref.read(colorRepositoryProvider).eliminar(color.id);
  }

  void _manejarAccion(String valor, ColorModel color) {
    switch (valor) {
      case 'editar':
        _abrirFormulario(color);
        break;
      case 'eliminar':
        _eliminar(color);
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

  Future<void> _exportarExcel() async {
    if (_listaActual.isEmpty) return;
    final bytes = _servicioExport.generarExcel(_listaActual);
    final fecha = DateFormat('dd-MM-yyyy').format(DateTime.now());
    await guardarOCompartirArchivo(bytes, 'Registro_Colores_$fecha.xlsx');
  }

  @override
  Widget build(BuildContext context) {
    final coloresAsync = ref.watch(coloresStreamProvider);
    final busqueda = ref.watch(coloresBusquedaProvider);
    final vista = ref.watch(coloresVistaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 720;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Text(
                    'Registro de Colores',
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
                        onPressed: () => ref.invalidate(coloresStreamProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportarExcel,
                        icon: const Icon(Icons.grid_on_outlined, size: 18),
                        label: Text('Descargar Excel', style: GoogleFonts.poppins(fontSize: 13)),
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
                        label: Text('Nuevo Color', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
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
                ...coloresAsync.when(
                  data: (colores) {
                    var lista = colores;
                    if (busqueda.isNotEmpty) {
                      lista = lista.where((c) => coincideFuzzy(c.textoBusqueda, busqueda)).toList();
                    } else if (vista == 'filtrados') {
                      lista = [];
                    }
                    _listaActual = lista;

                    if (lista.isEmpty) {
                      return [
                        SliverToBoxAdapter(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.palette_outlined, size: 56, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    vista == 'filtrados' && busqueda.isEmpty ? 'Escribí algo y presioná buscar' : 'No hay colores encontrados',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ];
                    }

                    return [
                      DecoratedSliver(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
                        ),
                        sliver: esMovil ? _tarjetasSliver(lista) : _tablaSliver(lista, constraints.maxWidth),
                      ),
                    ];
                  },
                  loading: () => [
                    const SliverToBoxAdapter(
                      child: Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))),
                    ),
                  ],
                  error: (e, st) => [
                    SliverToBoxAdapter(
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 80), child: Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red)))),
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 20)),
              ],
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
            DropdownMenuItem(value: 'filtrados', child: Text('Colores filtrados')),
            DropdownMenuItem(value: 'todos', child: Text('Mostrar todos')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref.read(coloresVistaProvider.notifier).actualizar(v);
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
                hintText: 'Buscar por código, cliente o descripción...',
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

  Widget _tablaSliver(List<ColorModel> lista, double anchoDisponible) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final mostrarUbicacion = anchoDisponible >= 850;
    final mostrarDescripcion = anchoDisponible >= 1100;
    final mostrarObservaciones = anchoDisponible >= 1350;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: const Color(0xFFECEEF3), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
            child: Row(
              children: [
                _celdaHeader('CÓDIGO', 2),
                _celdaHeader('CLIENTE', 3),
                if (mostrarDescripcion) _celdaHeader('DESCRIPCIÓN', 4),
                if (mostrarUbicacion) _celdaHeader('UBICACIÓN', 2),
                _celdaHeader('FECHA', 2),
                if (mostrarObservaciones) _celdaHeader('OBSERVACIONES', 3),
                const SizedBox(width: 56),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final color = lista[index];
              final seleccionada = _filaSeleccionada == color.id;
              final ubicacion = [color.ubicacionFisica, if (color.pagina.isNotEmpty) 'Pág. ${color.pagina}'].where((s) => s.isNotEmpty).join(' · ');
              return Column(
                children: [
                  if (index > 0) Divider(height: 1, color: Colors.grey.shade200),
                  InkWell(
                    onTap: () => setState(() => _filaSeleccionada = seleccionada ? null : color.id),
                    child: Container(
                      color: seleccionada ? const Color(0xFFFBEAEA) : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          _celda(2, color.codigo.isEmpty ? '-' : color.codigo, peso: FontWeight.w600),
                          _celda(3, color.cliente.isEmpty ? '-' : color.cliente),
                          if (mostrarDescripcion) _celda(4, color.descripcion.isEmpty ? '-' : color.descripcion, gris: true),
                          if (mostrarUbicacion) _celda(2, ubicacion.isEmpty ? '-' : ubicacion, gris: true),
                          _celda(2, color.fechaRegistro != null ? formatoFecha.format(color.fechaRegistro!) : '-', gris: true),
                          if (mostrarObservaciones) _celda(3, color.observaciones.isEmpty ? '-' : color.observaciones, gris: true),
                          SizedBox(width: 56, child: _celdaAcciones(color)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            childCount: lista.length,
          ),
        ),
      ],
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

  Widget _celdaAcciones(ColorModel color) {
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFDFE1E6))), child: const Icon(Icons.more_vert, size: 19, color: Color(0xFF454950))),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      position: PopupMenuPosition.under,
      onSelected: (valor) => _manejarAccion(valor, color),
      itemBuilder: (context) => _opcionesMenu(),
    );
  }

  Widget _tarjetasSliver(List<ColorModel> lista) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return SliverPadding(
      padding: const EdgeInsets.all(14),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) return const SizedBox(height: 12);
            final color = lista[index ~/ 2];
            return _tarjetaColor(color, formatoFecha);
          },
          childCount: lista.length * 2 - 1,
        ),
      ),
    );
  }

  Widget _tarjetaColor(ColorModel color, DateFormat formatoFecha) {
    final seleccionada = _filaSeleccionada == color.id;
    final ubicacion = [color.ubicacionFisica, if (color.pagina.isNotEmpty) 'Pág. ${color.pagina}'].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _filaSeleccionada = seleccionada ? null : color.id),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: seleccionada ? const Color(0xFFFBEAEA) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: seleccionada ? const Color(0xFFC62828) : const Color(0xFFC7CBD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        color.cliente.isEmpty ? 'Sin cliente' : color.cliente,
                        style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                      ),
                    ),
                    _celdaAcciones(color),
                  ],
                ),
                if (color.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(color.descripcion, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (color.codigo.isNotEmpty) _chipInfo('Código', color.codigo),
                    if (ubicacion.isNotEmpty) _chipInfo('Ubicación', ubicacion),
                    _chipInfo('Fecha', color.fechaRegistro != null ? formatoFecha.format(color.fechaRegistro!) : '-'),
                  ],
                ),
                if (color.observaciones.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(color.observaciones, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
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
