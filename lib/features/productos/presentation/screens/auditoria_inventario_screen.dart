import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../categorias/data/categoria_model.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../widgets/ajuste_stock_dialog.dart';
import '../widgets/historial_stock_dialog.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';
import '../../../../core/utils/codigo_barras_utils.dart';

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
  bool _ajustandoTodo = false;

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

  // [busquedaInicial] lo usa _escanear: cuando el código escaneado
  // pertenece a una categoría distinta a la que no había ninguna elegida
  // todavía, cambia a esa categoría y deja el código ya cargado en el
  // buscador, para no tener que escribirlo de nuevo.
  void _cambiarCategoria(String? id, {String? busquedaInicial}) {
    setState(() {
      _idCategoria = id;
      for (final c in _controladores.values) {
        c.dispose();
      }
      _controladores.clear();
      _busqueda = busquedaInicial ?? '';
      _busquedaController.text = _busqueda;
      _soloDescuadres = false;
    });
  }

  bool _coincideExacto(ProductoModel p, String texto) => p.codigoBarras.trim() == texto || p.codigo.trim() == texto;

  ProductoModel? _buscarPorCodigo(List<ProductoModel> productos, String texto) {
    for (final p in productos) {
      if (_coincideExacto(p, texto)) return p;
    }
    return null;
  }

  // Mismo patrón que Inventario (ver inventario_screen.dart _escanear):
  // prueba coincidencia exacta y, si no encuentra nada, otras variantes
  // válidas del mismo código (invertido, con/sin el "0" que agrega iPhone).
  // A diferencia de Inventario, acá SÍ importa la categoría: si el producto
  // escaneado es de otra categoría a la que ya se está auditando, no la
  // cambia sola -haría perder el conteo físico que el usuario ya lleva
  // tecleado ahí-, solo avisa. Si todavía no hay categoría elegida, no hay
  // nada que perder, así que ahí sí selecciona la categoría del producto
  // automáticamente.
  Future<void> _escanear() async {
    final codigo = await escanearCodigoBarras(context);
    if (codigo == null || codigo.isEmpty || !mounted) return;
    var texto = codigo.trim();
    final productos = ref.read(productosStreamProvider).value ?? [];
    var encontrado = _buscarPorCodigo(productos, texto);
    if (encontrado == null) {
      for (final variante in variantesCodigoBarras(texto)) {
        encontrado = _buscarPorCodigo(productos, variante);
        if (encontrado != null) {
          texto = variante;
          break;
        }
      }
    }

    if (encontrado != null && encontrado.idCategoria != _idCategoria) {
      if (_idCategoria == null) {
        _cambiarCategoria(encontrado.idCategoria, busquedaInicial: texto);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${encontrado.nombre}" está en otra categoría -cambiá de categoría para auditarlo (así no se pierde el conteo que ya llevás acá).')),
      );
      return;
    }

    setState(() {
      _busqueda = texto;
      _busquedaController.text = texto;
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

  /// Ajusta de una sola vez todos los productos de [lista] cuyo conteo
  /// físico no cuadra con el sistema, en vez de tener que abrir el diálogo
  /// de ajuste uno por uno. Usa el mismo motivo que el ajuste individual
  /// ("Reajuste por auditoría") y el precio de compra vigente como costo del
  /// ingreso -si algún producto sube existencia y ese costo no es el
  /// correcto para ese caso puntual, se puede corregir después a mano desde
  /// Inventario-.
  Future<void> _ajustarTodosLosDescuadres(List<ProductoModel> lista) async {
    final aAjustar = [
      for (final p in lista)
        if (_conteoDe(p.id) != null && _conteoDe(p.id) != p.stock) (producto: p, diferencia: _conteoDe(p.id)! - p.stock),
    ];
    if (aAjustar.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ajustar todos los descuadres', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Se van a ajustar ${aAjustar.length} producto${aAjustar.length == 1 ? '' : 's'} al conteo físico que anotaste, de una sola vez -motivo "Reajuste por auditoría"-. Esta acción no se puede deshacer.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Ajustar todos', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _ajustandoTodo = true);
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
    final repo = ref.read(productoRepositoryProvider);
    const motivo = 'Reajuste por auditoría (ajuste global)';
    var exitosos = 0;
    final fallidos = <String>[];
    await Future.wait(aAjustar.map((par) async {
      try {
        if (par.diferencia > 0) {
          await repo.registrarIngreso(id: par.producto.id, cantidad: par.diferencia, costoUnitario: par.producto.precioCompra, usuario: usuario, motivo: motivo);
        } else {
          // Sin lote específico: es un ajuste global sobre varios productos
          // a la vez, no tiene sentido pararse a elegir un lote por cada uno
          // -igual que la opción "sin lote" ya disponible en el ajuste
          // individual (ver AjusteStockDialog)-.
          await repo.registrarSalida(id: par.producto.id, cantidad: par.diferencia.abs(), usuario: usuario, motivo: motivo);
        }
        exitosos++;
      } catch (e) {
        fallidos.add(par.producto.nombre);
      }
    }));

    if (!mounted) return;
    setState(() => _ajustandoTodo = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        fallidos.isEmpty ? 'Se ajustaron $exitosos productos' : 'Se ajustaron $exitosos productos. Fallaron: ${fallidos.join(', ')}',
      ),
      showCloseIcon: true,
    ));
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
        SizedBox(
          width: esMovil ? constraints.maxWidth : 300,
          child: _buscador(),
        ),
        if (_idCategoria != null) ...[
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

  Widget _buscador() {
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
                hintText: 'Buscar o escanear código de barras...',
                hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busqueda = v.trim()),
            ),
          ),
          if (_busqueda.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _busqueda = '';
                _busquedaController.clear();
              }),
            ),
          IconButton(
            tooltip: 'Escanear código de barras',
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            onPressed: _escanear,
          ),
        ],
      ),
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
          Text(
            'Elegí una categoría arriba para empezar a auditar\n(o escaneá un producto y se elige sola)',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _contenidoCategoria(List<ProductoModel> productos, bool esMovil) {
    // Los combos no se auditan directo acá: su "existencia" es virtual
    // (depende del stock real de sus componentes, ver
    // ProductoModel.stockDisponibleCombo), así que un conteo físico del
    // combo en sí no tendría con qué compararse de forma confiable.
    // Los que sí tienen existencia según el sistema van primero -son los que
    // de verdad hay que ir a contar físicamente al estante-; los que ya
    // están en 0 quedan al final, ordenados alfabéticamente dentro de cada
    // grupo.
    var lista = productos.where((p) => p.idCategoria == _idCategoria && !p.esCombo).toList()
      ..sort((a, b) {
        final tieneStockA = a.stock > 0;
        final tieneStockB = b.stock > 0;
        if (tieneStockA != tieneStockB) return tieneStockA ? -1 : 1;
        return a.nombre.compareTo(b.nombre);
      });
    final combosExcluidos = productos.where((p) => p.idCategoria == _idCategoria && p.esCombo).length;

    if (_busqueda.isNotEmpty) {
      final termino = _busqueda.toLowerCase();
      lista = lista
          .where((p) => p.nombre.toLowerCase().contains(termino) || p.codigo.toLowerCase().contains(termino) || p.codigoBarras.toLowerCase().contains(termino))
          .toList();
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
        if (descuadres > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _ajustandoTodo ? null : () => _ajustarTodosLosDescuadres(lista),
            icon: _ajustandoTodo
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC62828)))
                : const Icon(Icons.playlist_add_check, size: 18),
            label: Text('Ajustar los $descuadres descuadres de una vez', style: GoogleFonts.poppins(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
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
