import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../categorias/data/categoria_model.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../widgets/ajuste_stock_dialog.dart';
import '../widgets/historial_stock_dialog.dart';

/// Auditoría de Inventario: el usuario elige una categoría, va anotando el
/// conteo físico real de cada producto (sin que eso toque Firestore para
/// nada -es solo un borrador en pantalla, mientras camina el negocio con la
/// lista en mano) y acá mismo ve si cuadra contra lo que dice el sistema. Si
/// no cuadra, tiene a la mano el historial de existencia del producto (para
/// entender de dónde pudo venir el descuadre) y puede ajustar el stock ahí
/// mismo -reutilizando el mismo AjusteStockDialog de Inventario, ya
/// precargado con la cantidad/motivo del reajuste- sin salir de la pantalla.
class AuditoriaInventarioScreen extends ConsumerStatefulWidget {
  const AuditoriaInventarioScreen({super.key});

  @override
  ConsumerState<AuditoriaInventarioScreen> createState() => _AuditoriaInventarioScreenState();
}

class _AuditoriaInventarioScreenState extends ConsumerState<AuditoriaInventarioScreen> {
  String? _idCategoria;
  // Un controller por producto, vivo mientras dure la sesión de auditoría
  // (se limpia solo al cambiar de categoría o al salir de la pantalla): así
  // el conteo que el usuario va tecleando no se pierde si la lista se
  // reordena o se filtra ("Solo descuadres") mientras sigue auditando.
  final Map<String, TextEditingController> _controladores = {};
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  bool _soloDescuadres = false;

  @override
  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    _busquedaController.dispose();
    super.dispose();
  }

  TextEditingController _controladorDe(String idProducto) {
    return _controladores.putIfAbsent(idProducto, () => TextEditingController());
  }

  void _cambiarCategoria(String? id) {
    setState(() {
      _idCategoria = id;
      for (final c in _controladores.values) {
        c.dispose();
      }
      _controladores.clear();
      _busqueda = '';
      _busquedaController.clear();
      _soloDescuadres = false;
    });
  }

  void _reiniciarConteo() {
    setState(() {
      for (final c in _controladores.values) {
        c.clear();
      }
    });
  }

  double? _conteoDe(String idProducto) {
    final texto = _controladores[idProducto]?.text.replaceAll(',', '').trim();
    if (texto == null || texto.isEmpty) return null;
    return double.tryParse(texto);
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  void _marcarCoincide(ProductoModel producto) {
    setState(() => _controladorDe(producto.id).text = _formatoCantidad(producto.stock));
  }

  void _abrirHistorial(ProductoModel producto) {
    showDialog(context: context, builder: (_) => HistorialStockDialog(producto: producto));
  }

  void _abrirAjuste(ProductoModel producto, double? diferencia) {
    showDialog(
      context: context,
      builder: (_) => AjusteStockDialog(
        producto: producto,
        esIngresoInicial: diferencia == null ? null : diferencia > 0,
        cantidadInicial: diferencia?.abs(),
        motivoInicial: 'Reajuste por auditoría',
        notaSuperior: (diferencia == null || diferencia == 0) ? null : _notaDiferencia(diferencia),
      ),
    );
  }

  Widget _notaDiferencia(double diferencia) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFFCE4E4), borderRadius: BorderRadius.circular(10)),
      child: Text(
        'Detectado en auditoría: diferencia de ${diferencia > 0 ? '+' : ''}${_formatoCantidad(diferencia)} contra el conteo físico.',
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFC62828)),
      ),
    );
  }

  InputDecoration _decoracion(String label, {IconData? icono}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icono == null ? null : Icon(icono, size: 19),
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final productosAsync = ref.watch(productosStreamProvider);

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
                _encabezado(esMovil),
                const SizedBox(height: 18),
                _barraControles(categoriasAsync, esMovil, constraints),
                const SizedBox(height: 18),
                Expanded(
                  child: _idCategoria == null
                      ? _estadoVacioSinCategoria()
                      : productosAsync.when(
                          data: (productos) => _contenidoCategoria(productos, esMovil),
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

  Widget _encabezado(bool esMovil) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF0EA5A4).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.fact_check_outlined, color: Color(0xFF0EA5A4), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auditoría de Inventario', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
              Text(
                'Elegí una categoría, contá lo que hay físicamente y compará contra el sistema.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barraControles(AsyncValue<List<CategoriaModel>> categoriasAsync, bool esMovil, BoxConstraints constraints) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: esMovil ? constraints.maxWidth : 260,
          child: categoriasAsync.when(
            data: (categorias) {
              final ordenadas = [...categorias]..sort((a, b) => a.descripcion.compareTo(b.descripcion));
              return DropdownButtonFormField<String>(
                initialValue: ordenadas.any((c) => c.id == _idCategoria) ? _idCategoria : null,
                isExpanded: true,
                decoration: _decoracion('Categoría a auditar', icono: Icons.category_outlined),
                style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                hint: Text('Elegí una categoría', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                items: ordenadas.map((c) => DropdownMenuItem(value: c.id, child: Text(c.descripcion, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _cambiarCategoria,
              );
            },
            loading: () => const LinearProgressIndicator(color: Color(0xFFC62828)),
            error: (e, st) => Text('No se pudieron cargar las categorías', style: GoogleFonts.poppins(fontSize: 12, color: Colors.red)),
          ),
        ),
        if (_idCategoria != null) ...[
          SizedBox(
            width: esMovil ? constraints.maxWidth : 260,
            child: TextField(
              controller: _busquedaController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: _decoracion('Buscar en la categoría', icono: Icons.search),
              onChanged: (v) => setState(() => _busqueda = v.trim()),
            ),
          ),
          _chipFiltroDescuadres(),
          OutlinedButton.icon(
            onPressed: _reiniciarConteo,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Reiniciar conteo', style: GoogleFonts.poppins(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A1A),
              side: const BorderSide(color: Color(0xFFB6BCC7)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chipFiltroDescuadres() {
    return InkWell(
      onTap: () => setState(() => _soloDescuadres = !_soloDescuadres),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _soloDescuadres ? const Color(0xFFC62828) : const Color(0xFFE8EAF0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_outlined, size: 17, color: _soloDescuadres ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 8),
            Text('Solo descuadres', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _soloDescuadres ? Colors.white : const Color(0xFF1A1A1A))),
          ],
        ),
      ),
    );
  }

  Widget _estadoVacioSinCategoria() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text('Elegí una categoría arriba para empezar a auditar', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _contenidoCategoria(List<ProductoModel> productos, bool esMovil) {
    // Los combos no se auditan directo acá: su "existencia" es virtual
    // (depende del stock real de sus componentes, ver
    // ProductoModel.stockDisponibleCombo), así que un conteo físico del
    // combo en sí no tendría con qué compararse de forma confiable.
    var lista = productos.where((p) => p.idCategoria == _idCategoria && !p.esCombo).toList()..sort((a, b) => a.nombre.compareTo(b.nombre));
    final combosExcluidos = productos.where((p) => p.idCategoria == _idCategoria && p.esCombo).length;

    if (_busqueda.isNotEmpty) {
      final termino = _busqueda.toLowerCase();
      lista = lista.where((p) => p.nombre.toLowerCase().contains(termino) || p.codigo.toLowerCase().contains(termino)).toList();
    }

    final auditados = lista.where((p) => _conteoDe(p.id) != null).length;
    final descuadres = lista.where((p) {
      final conteo = _conteoDe(p.id);
      return conteo != null && conteo != p.stock;
    }).length;

    final listaMostrar = _soloDescuadres
        ? lista.where((p) {
            final conteo = _conteoDe(p.id);
            return conteo != null && conteo != p.stock;
          }).toList()
        : lista;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _badge('${lista.length} productos', const Color(0xFF3B82F6)),
            _badge('Auditados $auditados/${lista.length}', const Color(0xFF64748B)),
            _badge('Cuadran ${auditados - descuadres}', const Color(0xFF16A34A)),
            _badge('Descuadres $descuadres', descuadres > 0 ? const Color(0xFFC62828) : Colors.grey),
            if (combosExcluidos > 0) _badge('$combosExcluidos combo(s) no aplica (existencia depende de sus componentes)', const Color(0xFFF59E0B)),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
            ),
            child: listaMostrar.isEmpty
                ? Center(
                    child: Text(
                      lista.isEmpty ? 'Esta categoría no tiene productos para auditar' : 'Sin productos con descuadre',
                      style: GoogleFonts.poppins(color: Colors.grey.shade500),
                    ),
                  )
                : esMovil
                    ? _tarjetas(listaMostrar)
                    : _tabla(listaMostrar),
          ),
        ),
      ],
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _chip(String texto, Color color, Color fondo, {IconData? icono}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 12, color: color), const SizedBox(width: 4)],
          Text(texto, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _chipDiferencia(double? diferencia) {
    if (diferencia == null) return _chip('Sin contar', Colors.grey.shade500, Colors.grey.shade200);
    if (diferencia == 0) return _chip('Cuadra', const Color(0xFF16A34A), const Color(0xFF16A34A).withOpacity(0.12), icono: Icons.check);
    final texto = diferencia > 0 ? '+${_formatoCantidad(diferencia)}' : _formatoCantidad(diferencia);
    return _chip(texto, const Color(0xFFC62828), const Color(0xFFC62828).withOpacity(0.12), icono: diferencia > 0 ? Icons.arrow_upward : Icons.arrow_downward);
  }

  // ---------- Tabla de escritorio ----------

  Widget _tabla(List<ProductoModel> lista) {
    return Column(
      children: [
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFECEEF3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              _celdaHeader('PRODUCTO', 4),
              _celdaHeader('STOCK SISTEMA', 2),
              _celdaHeader('CONTEO FÍSICO', 2),
              _celdaHeader('DIFERENCIA', 2),
              _celdaHeader('ACCIONES', 2),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: lista.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) => _filaTabla(lista[index]),
          ),
        ),
      ],
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(texto, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
      ),
    );
  }

  Widget _filaTabla(ProductoModel p) {
    final controller = _controladorDe(p.id);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final conteo = _conteoDe(p.id);
        final diferencia = conteo == null ? null : conteo - p.stock;
        final fondo = diferencia == null
            ? Colors.transparent
            : diferencia == 0
                ? const Color(0xFF16A34A).withOpacity(0.05)
                : const Color(0xFFC62828).withOpacity(0.05);
        return Container(
          color: fondo,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                          if (!p.estado) ...[const SizedBox(width: 6), _chip('Inactivo', Colors.grey.shade600, Colors.grey.shade200)],
                        ],
                      ),
                      if (p.codigo.isNotEmpty) Text('Código: ${p.codigo}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(_formatoCantidad(p.stock), style: GoogleFonts.poppins(fontSize: 13)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '—',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFC62828))),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _chipDiferencia(diferencia),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Marcar que coincide con el sistema',
                      icon: const Icon(Icons.check_circle_outline, size: 19, color: Color(0xFF16A34A)),
                      onPressed: () => _marcarCoincide(p),
                    ),
                    IconButton(
                      tooltip: 'Historial de existencia',
                      icon: Icon(Icons.history, size: 19, color: Colors.grey.shade600),
                      onPressed: () => _abrirHistorial(p),
                    ),
                    IconButton(
                      tooltip: 'Ajustar existencia',
                      icon: Icon(Icons.tune, size: 19, color: (diferencia != null && diferencia != 0) ? const Color(0xFFC62828) : Colors.grey.shade600),
                      onPressed: () => _abrirAjuste(p, diferencia),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- Tarjetas móvil ----------

  Widget _tarjetas(List<ProductoModel> lista) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _tarjetaProducto(lista[index]),
    );
  }

  Widget _tarjetaProducto(ProductoModel p) {
    final controller = _controladorDe(p.id);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final conteo = _conteoDe(p.id);
        final diferencia = conteo == null ? null : conteo - p.stock;
        final fondo = diferencia == null
            ? const Color(0xFFF8F9FB)
            : diferencia == 0
                ? const Color(0xFF16A34A).withOpacity(0.06)
                : const Color(0xFFC62828).withOpacity(0.06);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: Text(p.nombre, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                        if (!p.estado) ...[const SizedBox(width: 6), _chip('Inactivo', Colors.grey.shade600, Colors.grey.shade200)],
                      ],
                    ),
                  ),
                  _chipDiferencia(diferencia),
                ],
              ),
              if (p.codigo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Código: ${p.codigo}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500))),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SISTEMA', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
                        const SizedBox(height: 2),
                        Text(_formatoCantidad(p.stock), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Conteo físico',
                        isDense: true,
                        labelStyle: GoogleFonts.poppins(fontSize: 11.5),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _marcarCoincide(p),
                      icon: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                      label: Text('Coincide', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF16A34A))),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _abrirHistorial(p),
                      icon: Icon(Icons.history, size: 16, color: Colors.grey.shade600),
                      label: Text('Historial', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _abrirAjuste(p, diferencia),
                      icon: const Icon(Icons.tune, size: 16, color: Color(0xFFC62828)),
                      label: Text('Ajustar', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
