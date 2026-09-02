import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../data/producto_export_service.dart';
import '../../providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/exportador.dart';
import '../widgets/producto_form_dialog.dart';
import '../widgets/detalle_producto_dialog.dart';
import '../widgets/importar_inventario_dialog.dart';
import '../widgets/exportar_inventario_opciones_dialog.dart';
import '../widgets/ajuste_stock_dialog.dart';
import '../widgets/historial_stock_dialog.dart';
import '../widgets/historial_movimientos_dialog.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/ticket_opciones_dialog.dart';
import 'package:printing/printing.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';
import '../../../../core/utils/codigo_barras_utils.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../../core/widgets/imagen_zoom_dialog.dart';
import '../../../../core/widgets/imagen_producto_network.dart';

class InventarioScreen extends ConsumerStatefulWidget {
  const InventarioScreen({super.key});

  @override
  ConsumerState<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends ConsumerState<InventarioScreen> {
  final _busquedaController = TextEditingController();
  final _focusNode = FocusNode();
  // Sigue la selección con las flechas del teclado -pedido explícito del
  // dueño-: solo se usa en la tabla de escritorio (_tabla), donde cada fila
  // mide siempre lo mismo (ver _alturaFila), así que se puede calcular el
  // scroll exacto sin tener que medir nada. En la vista de tarjetas
  // (móvil, alto variable) no se usa.
  final _scrollControllerTabla = ScrollController();
  static const _alturaFila = 84.0;
  static const _alturaDivisorFila = 1.0;
  static const _alturaItemLista = _alturaFila + _alturaDivisorFila;
  final _servicioExport = ProductoExportService();
  String? _filaSeleccionada;
  String? _columnaOrden;
  bool _ordenAscendente = false;
  bool _precioConIsv = true;
  // Vista elegida en el rango "tablet" -pedido explícito del dueño-: 'tabla'
  // por defecto, 'tarjetas' si el usuario la cambia con
  // _selectorVistaTabletChico. No aplica en celular (siempre tarjetas) ni en
  // escritorio ancho (siempre tabla) -ver esTablet en build()-.
  String _vistaTablet = 'tabla';
  // Cuando la búsqueda viene de escanear un código de barras se filtra por
  // coincidencia exacta de código, no con el buscador difuso (que con
  // códigos largos puede "acercarse" a varios productos distintos).
  bool _busquedaPorCodigoBarras = false;
  List<ProductoModel> _listaActual = [];
  // Solo Activos/Inactivos (sin "Todos" -pedido explícito), Activos por
  // defecto. Mismo estilo de selector-pill que _selectorPrecioIsv.
  String _filtroEstado = 'activos';
  // Campo contra el que se compara el texto del buscador -'todo' (default)
  // usa ProductoModel.textoBusqueda (código+códigoBarras+nombre+descripción
  // combinados, como ya funcionaba), cualquier otro valor compara SOLO ese
  // campo. Pedido explícito: "inicialmente siempre buscar en todo pero
  // poder ponerlo" si hace falta acotar la búsqueda a un campo puntual.
  String _campoFiltro = 'todo';

  // --- Cache de la lista filtrada/ordenada y de los totales del título ---
  // Sin esto, cada `setState` -incluido tocar una fila solo para
  // seleccionarla- reconstruye TODO build(), y eso repetía el filtrado +
  // orden (este último con lookups de stock de combos, O(n log n)) y los
  // `fold` de valor de inventario sobre TODA la lista, aunque nada de lo
  // que de verdad afecta esos cálculos hubiera cambiado -pedido explícito
  // del dueño: esta pantalla se sentía más lenta que Ventas Crédito al
  // tocar una fila, con inventarios grandes-. Riverpod reusa la misma
  // referencia de `productos`/`categoriasLista` entre rebuilds mientras el
  // stream no emita datos nuevos, así que comparar por identidad (`==` de
  // List/Map, que en Dart es identidad de objeto salvo que se sobrecargue)
  // alcanza para saber si hace falta recalcular.
  List<dynamic>? _cacheCategoriasListaOrigen;
  Map<String, String> _cacheMapaCategorias = const {};
  List<ProductoModel>? _cacheProductosOrigen;
  Map<String, String>? _cacheMapaCategoriasOrigen;
  Map<String, ProductoModel> _cacheMapaProductos = const {};
  List<ProductoModel> _cacheListaFiltrada = const [];
  String? _cacheVista;
  String? _cacheFiltroEstadoUsado;
  String? _cacheBusquedaUsada;
  bool? _cacheBusquedaPorCodigoBarrasUsada;
  String? _cacheColumnaOrdenUsada;
  bool? _cacheOrdenAscendenteUsado;
  String? _cacheCampoFiltroUsado;

  List<ProductoModel>? _cacheValoresProductosOrigen;
  bool? _cacheValoresPrecioConIsv;
  double _cacheValorCompra = 0;
  double _cacheValorVenta = 0;

  static const _opcionesCampoFiltro = [
    ('todo', 'Todo'),
    ('codigo', 'Código'),
    ('codigoBarras', 'Código de barras'),
    ('nombre', 'Nombre'),
    ('descripcion', 'Descripción'),
    ('categoria', 'Categoría'),
  ];

  bool _coincideBusqueda(
    ProductoModel p,
    String busqueda,
    Map<String, String> mapaCategorias,
  ) {
    final texto = switch (_campoFiltro) {
      'codigo' => p.codigo,
      'codigoBarras' => p.codigoBarras,
      'nombre' => p.nombre,
      'descripcion' => p.descripcion,
      'categoria' => mapaCategorias[p.idCategoria] ?? '',
      _ => p.textoBusqueda,
    };
    return coincideFuzzy(texto, busqueda);
  }

  /// Precio de venta a mostrar según la vista elegida (con o sin ISV). El
  /// precio guardado en el producto siempre incluye ISV.
  double _precioMostrado(ProductoModel p) =>
      _precioConIsv ? p.precioVenta : redondearMoneda(p.precioVenta / 1.15);

  /// Filtra (vista/estado/búsqueda) y ordena la lista de productos, con
  /// cache -ver comentario junto a los campos `_cache*` arriba-. Devuelve
  /// también `mapaProductos` porque se calcula como parte del mismo trabajo
  /// y lo necesitan tanto el filtro "bajo stock" (combos) como `_ordenarLista`.
  ({List<ProductoModel> lista, Map<String, ProductoModel> mapaProductos})
  _filtrarYOrdenar({
    required List<ProductoModel> productos,
    required Map<String, String> mapaCategorias,
    required String vista,
    required String busqueda,
  }) {
    final sinCambios =
        identical(_cacheProductosOrigen, productos) &&
        identical(_cacheMapaCategoriasOrigen, mapaCategorias) &&
        _cacheVista == vista &&
        _cacheFiltroEstadoUsado == _filtroEstado &&
        _cacheBusquedaUsada == busqueda &&
        _cacheBusquedaPorCodigoBarrasUsada == _busquedaPorCodigoBarras &&
        _cacheColumnaOrdenUsada == _columnaOrden &&
        _cacheOrdenAscendenteUsado == _ordenAscendente &&
        _cacheCampoFiltroUsado == _campoFiltro;
    if (sinCambios) {
      return (lista: _cacheListaFiltrada, mapaProductos: _cacheMapaProductos);
    }

    final mapaProductos = {for (final p in productos) p.id: p};
    var lista = productos;
    if (vista == 'bajo') {
      lista = lista
          .where(
            (p) =>
                (p.esCombo ? p.stockDisponibleCombo(mapaProductos) : p.stock) <
                3,
          )
          .toList();
    }
    lista = lista
        .where((p) => _filtroEstado == 'activos' ? p.estado : !p.estado)
        .toList();
    if (busqueda.isNotEmpty) {
      lista = _busquedaPorCodigoBarras
          ? lista
                .where(
                  (p) =>
                      p.codigoBarras.trim() == busqueda ||
                      p.codigo.trim() == busqueda,
                )
                .toList()
          : lista
                .where((p) => _coincideBusqueda(p, busqueda, mapaCategorias))
                .toList();
    } else if (vista == 'filtrados') {
      lista = [];
    }
    lista = _ordenarLista(lista, mapaProductos);

    _cacheProductosOrigen = productos;
    _cacheMapaCategoriasOrigen = mapaCategorias;
    _cacheVista = vista;
    _cacheFiltroEstadoUsado = _filtroEstado;
    _cacheBusquedaUsada = busqueda;
    _cacheBusquedaPorCodigoBarrasUsada = _busquedaPorCodigoBarras;
    _cacheColumnaOrdenUsada = _columnaOrden;
    _cacheOrdenAscendenteUsado = _ordenAscendente;
    _cacheCampoFiltroUsado = _campoFiltro;
    _cacheMapaProductos = mapaProductos;
    _cacheListaFiltrada = lista;

    return (lista: lista, mapaProductos: mapaProductos);
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _focusNode.dispose();
    _scrollControllerTabla.dispose();
    _timerRepeticionTeclado?.cancel();
    super.dispose();
  }

  void _buscar() {
    setState(() => _busquedaPorCodigoBarras = false);
    ref
        .read(inventarioBusquedaProvider.notifier)
        .actualizar(_busquedaController.text.trim());
  }

  bool _coincideExacto(ProductoModel p, String texto) =>
      p.codigoBarras.trim() == texto || p.codigo.trim() == texto;

  Future<void> _escanear() async {
    final codigo = await escanearCodigoBarras(context);
    if (codigo == null || codigo.isEmpty || !mounted) return;
    var texto = codigo.trim();
    final productos = ref.read(productosStreamProvider).value ?? [];
    // Si el código escaneado no matchea a nada, se prueban otras variantes
    // válidas del mismo código (ver variantesCodigoBarras): corrige tanto
    // el código leído al revés (algunos celulares) como el "0" que iPhone
    // agrega al principio de los códigos UPC-A (Android no lo agrega).
    if (!productos.any((p) => _coincideExacto(p, texto))) {
      for (final variante in variantesCodigoBarras(texto)) {
        if (productos.any((p) => _coincideExacto(p, variante))) {
          texto = variante;
          break;
        }
      }
    }
    _busquedaController.text = texto;
    setState(() => _busquedaPorCodigoBarras = true);
    ref.read(inventarioBusquedaProvider.notifier).actualizar(texto);
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(inventarioBusquedaProvider.notifier).actualizar('');
    setState(() {
      _filaSeleccionada = null;
      _busquedaPorCodigoBarras = false;
    });
  }

  // Doble tap/doble clic en un producto (tabla o tarjeta): una card de solo
  // lectura con toda su info, para consultar rápido -por ejemplo, un precio
  // o el código de barras- sin tener que abrir el formulario de edición.
  void _verDetalle(
    ProductoModel producto,
    Map<String, String> mapaCategorias,
    Map<String, ProductoModel> mapaProductos,
  ) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => DetalleProductoDialog(
        producto: producto,
        categoria: mapaCategorias[producto.idCategoria] ?? '-',
        mapaProductos: mapaProductos,
      ),
    );
  }

  Future<void> _abrirFormulario([ProductoModel? producto]) async {
    if (producto != null) {
      final autorizado = await verificarAccesoEspecial(
        context,
        ref,
        PermisosEspeciales.inventarioEditarProducto,
      );
      if (!autorizado || !mounted) return;
    }
    if (!mounted) return;
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => ProductoFormDialog(producto: producto),
    );
  }

  Future<void> _abrirAjusteStock(ProductoModel producto) async {
    final autorizado = await verificarAccesoEspecial(
      context,
      ref,
      PermisosEspeciales.inventarioAjustarStock,
    );
    if (!autorizado || !mounted) return;
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => AjusteStockDialog(producto: producto),
    );
  }

  void _abrirHistorial(ProductoModel producto) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => HistorialStockDialog(producto: producto),
    );
  }

  void _abrirHistorialMovimientos(ProductoModel producto, String tipo) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) =>
          HistorialMovimientosDialog(producto: producto, tipo: tipo),
    );
  }

  void _abrirImportar() {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => const ImportarInventarioDialog(),
    );
  }

  // Antes de exportar (Excel o PDF), deja elegir qué productos de la lista
  // actual van al archivo y qué columnas incluir -pedido explícito del
  // dueño-. Null si se cancela.
  Future<ExportarInventarioOpciones?> _elegirOpcionesExport(
    Map<String, String> mapaCategorias,
    String titulo,
  ) {
    return showDialog<ExportarInventarioOpciones>(
      useRootNavigator: false,
      context: context,
      builder: (context) => ExportarInventarioOpcionesDialog(
        productos: _listaActual,
        mapaCategorias: mapaCategorias,
        titulo: titulo,
      ),
    );
  }

  Future<void> _exportarExcel(Map<String, String> mapaCategorias) async {
    if (_listaActual.isEmpty) return;
    final opciones = await _elegirOpcionesExport(
      mapaCategorias,
      'Exportar a Excel',
    );
    if (opciones == null || !mounted) return;
    final bytes = _servicioExport.generarExcel(
      opciones.productos,
      mapaCategorias,
      columnas: opciones.columnas,
    );
    await guardarOCompartirArchivo(bytes, 'inventario.xlsx');
  }

  Future<void> _exportarPdf(Map<String, String> mapaCategorias) async {
    if (_listaActual.isEmpty) return;
    final opciones = await _elegirOpcionesExport(
      mapaCategorias,
      'Exportar a PDF',
    );
    if (opciones == null || !mounted) return;
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Inventario',
        nombreArchivo: 'inventario.pdf',
        generarPdf: () => _servicioExport.generarPdfInventario(
          opciones.productos,
          mapaCategorias,
          columnas: opciones.columnas,
        ),
      ),
    );
  }

  Future<void> _imprimirTicketGrid(Map<String, String> mapaCategorias) async {
    if (_listaActual.isEmpty) return;
    final campos = await showDialog<Set<String>>(
      context: context,
      builder: (context) => const TicketOpcionesDialog(),
    );
    if (campos == null || !mounted) return;
    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty
        ? null
        : Printer(
            url: negocio.impresoraTermicaUrl,
            name: negocio.impresoraTermicaNombre,
          );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Ticket',
        nombreArchivo: 'ticket_inventario.pdf',
        generarPdf: () => _servicioExport.generarPdfTicket(
          _listaActual,
          mapaCategorias,
          campos,
        ),
        impresora: impresora,
      ),
    );
  }

  Future<void> _abrirCodigoBarras(ProductoModel producto) async {
    final cantidad = await _pedirCantidadEtiquetas(producto);
    if (cantidad == null || cantidad <= 0 || !mounted) return;
    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;
    final urlImpresora = negocio.impresoraEtiquetasUrl.isNotEmpty
        ? negocio.impresoraEtiquetasUrl
        : negocio.impresoraTermicaUrl;
    final nombreImpresora = negocio.impresoraEtiquetasUrl.isNotEmpty
        ? negocio.impresoraEtiquetasNombre
        : negocio.impresoraTermicaNombre;
    final impresora = urlImpresora.isEmpty
        ? null
        : Printer(url: urlImpresora, name: nombreImpresora);
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Etiquetas · ${producto.nombre} (x$cantidad)',
        nombreArchivo: 'etiquetas_${producto.codigo}.pdf',
        generarPdf: () => _servicioExport.generarPdfEtiquetasGrid(
          List.generate(cantidad, (_) => producto),
        ),
        impresora: impresora,
      ),
    );
  }

  // Etiquetas de código de barras en tira (2 por fila) para imprimir en la
  // térmica de 80mm que ya está configurada, mientras no haya una
  // "tiquetera" dedicada — usa impresoraEtiquetas si ya la configuraron más
  // adelante, si no cae en impresoraTermica.
  Future<void> _imprimirEtiquetasGrid() async {
    if (_listaActual.isEmpty) return;
    final soloSinCodigo = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Imprimir etiquetas',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Etiquetas de todos los productos de la lista actual, o solo de los que no tienen código de barras?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Todos', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Solo sin código', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (soloSinCodigo == null || !mounted) return;
    final productos = soloSinCodigo
        ? _listaActual.where((p) => p.codigoBarras.isEmpty).toList()
        : _listaActual;
    if (productos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay productos sin código de barras en la lista actual',
          ),
        ),
      );
      return;
    }
    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;
    final urlImpresora = negocio.impresoraEtiquetasUrl.isNotEmpty
        ? negocio.impresoraEtiquetasUrl
        : negocio.impresoraTermicaUrl;
    final nombreImpresora = negocio.impresoraEtiquetasUrl.isNotEmpty
        ? negocio.impresoraEtiquetasNombre
        : negocio.impresoraTermicaNombre;
    final impresora = urlImpresora.isEmpty
        ? null
        : Printer(url: urlImpresora, name: nombreImpresora);
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Etiquetas (${productos.length})',
        nombreArchivo: 'etiquetas_codigos_barras.pdf',
        generarPdf: () => _servicioExport.generarPdfEtiquetasGrid(productos),
        impresora: impresora,
      ),
    );
  }

  Future<int?> _pedirCantidadEtiquetas(ProductoModel producto) async {
    final controller = TextEditingController(text: '1');
    return showDialog<int>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Imprimir etiquetas',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              producto.nombre,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 14),
            CampoTecladoCompacto(
              controller: controller,
              numerico: true,
              titulo: 'Cantidad de etiquetas',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Cantidad de etiquetas',
                  labelStyle: GoogleFonts.poppins(fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFE8EAF0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(controller.text.trim()) ?? 0,
            ),
            child: Text('Imprimir', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _alternarOrden(String columna) {
    setState(() {
      if (_columnaOrden == columna) {
        _ordenAscendente = !_ordenAscendente;
      } else {
        _columnaOrden = columna;
        _ordenAscendente = false;
      }
    });
  }

  List<ProductoModel> _ordenarLista(
    List<ProductoModel> lista,
    Map<String, ProductoModel> mapaProductos,
  ) {
    if (_columnaOrden == null) return lista;
    final copia = [...lista];
    double existencia(ProductoModel p) =>
        p.esCombo ? p.stockDisponibleCombo(mapaProductos) : p.stock;
    copia.sort((a, b) {
      int comparacion;
      switch (_columnaOrden) {
        case 'codigo':
          comparacion = a.codigo.compareTo(b.codigo);
          break;
        case 'nombre':
          comparacion = a.nombre.compareTo(b.nombre);
          break;
        case 'existencia':
          comparacion = existencia(a).compareTo(existencia(b));
          break;
        case 'precioVenta':
          comparacion = a.precioVenta.compareTo(b.precioVenta);
          break;
        case 'precioCompra':
          comparacion = a.precioCompra.compareTo(b.precioCompra);
          break;
        default:
          comparacion = 0;
      }
      return _ordenAscendente ? comparacion : -comparacion;
    });
    return copia;
  }

  /// Selecciona una fila por id -pedido explícito del dueño: tocar el
  /// ícono de foto o el de acciones (⋮) de una fila mueve la iluminación a
  /// ESA fila de inmediato, en vez de dejarla en la que estaba seleccionada
  /// antes-. No hace nada si ya era la seleccionada (evita un `setState`
  /// de más).
  void _seleccionarFila(String id) {
    if (_filaSeleccionada == id) return;
    setState(() => _filaSeleccionada = id);
  }

  // --- Detección manual de doble toque en una fila ---
  // Bug real reportado por el dueño: con `onTap` Y `onDoubleTap` juntos en
  // el mismo InkWell (como estaba antes), Flutter tiene que esperar la
  // ventana de doble-tap (~300ms) antes de disparar el toque simple, para
  // poder distinguir "un toque" de "el primero de dos" -por ESO tocar una
  // fila se sentía con retraso, mientras que tocar el ícono de acciones (⋮,
  // sin doble-tap) era instantáneo, dando la falsa impresión de que el
  // problema era de rendimiento en vez de este gesto-. Acá se detecta el
  // doble toque a mano (dos toques a la MISMA fila dentro de
  // `_ventanaDobleTap`) usando solo `onTap`, así la selección siempre
  // responde al toque, sin esperar a ver si viene un segundo.
  static const _ventanaDobleTap = Duration(milliseconds: 300);
  DateTime? _ultimoTapFilaEn;
  String? _ultimoTapFilaId;

  void _tocarFila(
    ProductoModel producto,
    Map<String, String> mapaCategorias,
    Map<String, ProductoModel> mapaProductos,
  ) {
    final ahora = DateTime.now();
    final esDobleTap =
        _ultimoTapFilaId == producto.id &&
        _ultimoTapFilaEn != null &&
        ahora.difference(_ultimoTapFilaEn!) < _ventanaDobleTap;
    _ultimoTapFilaEn = ahora;
    _ultimoTapFilaId = producto.id;

    _tomarFoco();
    if (esDobleTap) {
      // El primer toque de este par ya seleccionó la fila (alternando, ver
      // abajo); el segundo NO debe volver a alternar -si no, el doble toque
      // terminaría dejándola deseleccionada justo al abrir su detalle-.
      _ultimoTapFilaEn = null; // no encadenar un tercer toque como otro "doble"
      setState(() => _filaSeleccionada = producto.id);
      _verDetalle(producto, mapaCategorias, mapaProductos);
    } else {
      // A diferencia de _seleccionarFila (que solo selecciona, usada desde
      // el ícono de foto/acciones), tocar la fila misma alterna: tocar la
      // que ya está seleccionada la deselecciona -comportamiento que ya
      // tenía esta pantalla antes de este arreglo, se mantiene igual-.
      setState(
        () => _filaSeleccionada = _filaSeleccionada == producto.id
            ? null
            : producto.id,
      );
    }
  }

  void _moverSeleccion(int delta) {
    if (_listaActual.isEmpty) return;
    final indiceActual = _filaSeleccionada == null
        ? -1
        : _listaActual.indexWhere((p) => p.id == _filaSeleccionada);
    var nuevoIndice = indiceActual + delta;
    if (nuevoIndice < 0) nuevoIndice = 0;
    if (nuevoIndice >= _listaActual.length)
      nuevoIndice = _listaActual.length - 1;
    setState(() => _filaSeleccionada = _listaActual[nuevoIndice].id);
    _asegurarFilaVisible(nuevoIndice);
  }

  /// Desplaza `_scrollControllerTabla` lo mínimo necesario para que la fila
  /// [indice] quede visible -pedido explícito del dueño: que el scroll siga
  /// a la selección al moverse con las flechas del teclado-. Cada fila mide
  /// siempre lo mismo (`_alturaItemLista`), así que no hace falta medir
  /// nada, solo calcular. No hace nada si la tabla no está montada en este
  /// momento (ej. vista de tarjetas en móvil, sin este controller).
  void _asegurarFilaVisible(int indice) {
    if (!_scrollControllerTabla.hasClients) return;
    final posicion = _scrollControllerTabla.position;
    final topeArriba = indice * _alturaItemLista;
    final topeAbajo = topeArriba + _alturaFila;
    if (topeArriba < posicion.pixels) {
      _scrollControllerTabla.jumpTo(topeArriba);
    } else if (topeAbajo > posicion.pixels + posicion.viewportDimension) {
      _scrollControllerTabla.jumpTo(topeAbajo - posicion.viewportDimension);
    }
  }

  // --- Repetición al mantener presionada una flecha ---
  // Pedido explícito del dueño: si se mantiene apretada ↑/↓, la selección
  // tiene que seguir bajando/subiendo rápido, como el tecleo normal (ej. en
  // un campo de texto). Flutter no manda repeticiones automáticas a
  // `onKeyEvent` de un `Focus` -solo UN `KeyDownEvent` por toque físico de
  // tecla, sin importar cuánto se mantenga apretada-, así que hay que
  // simular la repetición a mano con un `Timer`: un primer movimiento
  // inmediato al bajar la tecla, y si sigue apretada más de
  // `_esperaAntesDeRepetir`, un movimiento repetido cada `_intervaloRepeticion`
  // hasta soltar la tecla (`KeyUpEvent`).
  static const _esperaAntesDeRepetir = Duration(milliseconds: 350);
  static const _intervaloRepeticion = Duration(milliseconds: 45);
  Timer? _timerRepeticionTeclado;

  void _iniciarRepeticionFlecha(int delta) {
    _timerRepeticionTeclado?.cancel();
    _moverSeleccion(delta);
    _timerRepeticionTeclado = Timer(_esperaAntesDeRepetir, () {
      _timerRepeticionTeclado = Timer.periodic(
        _intervaloRepeticion,
        (_) => _moverSeleccion(delta),
      );
    });
  }

  void _detenerRepeticionFlecha() {
    _timerRepeticionTeclado?.cancel();
    _timerRepeticionTeclado = null;
  }

  KeyEventResult _manejarTeclado(FocusNode node, KeyEvent event) {
    final esFlecha =
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!esFlecha) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _iniciarRepeticionFlecha(
        event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1,
      );
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _detenerRepeticionFlecha();
      return KeyEventResult.handled;
    }
    // KeyRepeatEvent (si la plataforma llega a mandarlo): ya lo cubre
    // nuestro propio Timer, se ignora para no repetir el doble de rápido.
    return KeyEventResult.handled;
  }

  void _tomarFoco() {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productosStreamProvider);
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final busqueda = ref.watch(inventarioBusquedaProvider);
    final vista = ref.watch(inventarioVistaProvider);
    final categoriasLista = categoriasAsync.value ?? <dynamic>[];
    // Cache: OJO, esto era el bug real de por qué el cache de
    // `_filtrarYOrdenar` de abajo nunca se activaba -comparaba por identidad
    // contra este Map, pero acá se creaba uno NUEVO en cada build() aunque
    // `categoriasLista` (la fuente real) no hubiera cambiado, así que la
    // comparación de "¿cambió algo?" daba que sí siempre-. Ahora se reusa el
    // mismo Map mientras `categoriasLista` sea la misma referencia (Riverpod
    // reusa esa lista entre rebuilds mientras el stream no emita datos
    // nuevos).
    if (!identical(_cacheCategoriasListaOrigen, categoriasLista)) {
      _cacheMapaCategorias = {
        for (final c in categoriasLista)
          c.id as String: c.descripcion as String,
      };
      _cacheCategoriasListaOrigen = categoriasLista;
    }
    final mapaCategorias = _cacheMapaCategorias;

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 720;
          // Rango "tablet" -pedido explícito del dueño-: ni tan angosto como
          // para forzar tarjetas, ni tan ancho como para forzar la tabla; acá
          // se deja elegir (ver _selectorVistaTabletChico), con "Tabla" por
          // defecto.
          final esTablet = !esMovil && constraints.maxWidth < 1100;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _tituloYBadges(esMovil, productosAsync)),
                      const SizedBox(width: 10),
                      // Selectores chicos, arriba en la esquina -pedido
                      // explícito: antes ocupaban una fila entera abajo en
                      // la barra de herramientas.
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          if (esTablet) _selectorVistaTabletChico(),
                          _selectorPrecioIsvChico(),
                          _selectorEstadoChico(),
                        ],
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 220,
                        child: _selectorVista(vista),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 170,
                        child: _selectorCampoFiltro(),
                      ),
                      SizedBox(
                        width: esMovil ? constraints.maxWidth : 340,
                        child: _buscador(busqueda),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.invalidate(productosStreamProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(
                          'Refrescar',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _abrirImportar,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: Text(
                          'Importar',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportarExcel(mapaCategorias),
                        icon: const Icon(Icons.grid_on_outlined, size: 18),
                        label: Text(
                          'Excel',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportarPdf(mapaCategorias),
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 18,
                        ),
                        label: Text(
                          'PDF',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _imprimirTicketGrid(mapaCategorias),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(
                          'Ticket',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _imprimirEtiquetasGrid,
                        icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                        label: Text(
                          'Etiquetas',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _abrirFormulario(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          'Nuevo Producto',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                  border: Border.all(
                    color: const Color(0xFFAEB4C0),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: productosAsync.when(
                  data: (productos) {
                    final resultado = _filtrarYOrdenar(
                      productos: productos,
                      mapaCategorias: mapaCategorias,
                      vista: vista,
                      busqueda: busqueda,
                    );
                    final mapaProductos = resultado.mapaProductos;
                    final lista = resultado.lista;
                    _listaActual = lista;

                    if (lista.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 56,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              vista == 'filtrados' && busqueda.isEmpty
                                  ? 'Escribí algo y presioná buscar'
                                  : 'No hay productos encontrados',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final usarTarjetas =
                        esMovil || (esTablet && _vistaTablet == 'tarjetas');
                    return Focus(
                      focusNode: _focusNode,
                      onKeyEvent: _manejarTeclado,
                      child: usarTarjetas
                          ? _tarjetas(lista, mapaCategorias, mapaProductos)
                          : _tabla(lista, mapaCategorias, mapaProductos),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFFC62828)),
                  ),
                  error: (e, st) => Center(
                    child: Text(
                      'Error: $e',
                      style: GoogleFonts.poppins(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _badgeInfo(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _tabla(
    List<ProductoModel> lista,
    Map<String, String> mapaCategorias,
    Map<String, ProductoModel> mapaProductos,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final mostrarDescripcion = ancho >= 1050;
        final mostrarCategoria = ancho >= 850;

        return Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFECEEF3),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  _celdaHeader(
                    texto: 'CÓDIGO',
                    flex: 12,
                    columnaOrdenKey: 'codigo',
                  ),
                  _celdaHeader(
                    texto: 'NOMBRE',
                    flex: 24,
                    columnaOrdenKey: 'nombre',
                  ),
                  if (mostrarDescripcion)
                    _celdaHeader(texto: 'DESCRIPCIÓN', flex: 20),
                  if (mostrarCategoria)
                    _celdaHeader(texto: 'CATEGORÍA', flex: 17),
                  _celdaHeader(
                    texto: 'EXISTENCIA',
                    flex: 12,
                    columnaOrdenKey: 'existencia',
                  ),
                  _celdaHeader(
                    texto: _precioConIsv
                        ? 'P. VENTA (C/ISV)'
                        : 'P. VENTA (S/ISV)',
                    flex: 14,
                    columnaOrdenKey: 'precioVenta',
                  ),
                  _celdaHeader(
                    texto: 'P. COMPRA',
                    flex: 14,
                    columnaOrdenKey: 'precioCompra',
                  ),
                  _celdaHeader(texto: 'ESTADO', flex: 11),
                  _celdaHeaderAcciones(),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: _scrollControllerTabla,
                itemCount: lista.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final producto = lista[index];
                  final existencia = producto.esCombo
                      ? producto.stockDisponibleCombo(mapaProductos)
                      : producto.stock;
                  final bajoStock = existencia < 3;
                  final seleccionada = _filaSeleccionada == producto.id;

                  return InkWell(
                    // Un solo onTap -sin onDoubleTap acá- a propósito: ver
                    // el comentario grande junto a _tocarFila.
                    onTap: () =>
                        _tocarFila(producto, mapaCategorias, mapaProductos),
                    child: Container(
                      color: seleccionada
                          ? const Color(0xFFFBEAEA)
                          : Colors.white,
                      // Alto fijo en vez de IntrinsicHeight: con alto fijo, Flutter
                      // no necesita un segundo pase de layout por fila para saber
                      // cuánto "estirar" cada celda (lo que exigía IntrinsicHeight),
                      // así que desplazarse por listas largas queda mucho más fluido.
                      // 84px alcanza para 3 líneas de nombre (ver maxLines abajo)
                      // sin que se corte con puntos suspensivos.
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _celdaTabla(
                            flex: 12,
                            child: Text(
                              producto.codigo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: const Color(0xFF3F434A),
                              ),
                            ),
                          ),
                          _celdaTabla(
                            flex: 24,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (producto.esCombo)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 3),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEDE7F6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'COMBO',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF6A1B9A),
                                      ),
                                    ),
                                  ),
                                Text(
                                  producto.nombre,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (mostrarDescripcion)
                            _celdaTabla(
                              flex: 20,
                              child: Text(
                                producto.descripcion.isEmpty
                                    ? '-'
                                    : producto.descripcion,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          if (mostrarCategoria)
                            _celdaTabla(
                              flex: 17,
                              child: Text(
                                mapaCategorias[producto.idCategoria] ?? '-',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: const Color(0xFF3F434A),
                                ),
                              ),
                            ),
                          _celdaTabla(
                            flex: 12,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: bajoStock
                                      ? const Color(0xFFFCE4E4)
                                      : const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  existencia.toStringAsFixed(
                                    existencia == existencia.roundToDouble()
                                        ? 0
                                        : 2,
                                  ),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: bajoStock
                                        ? const Color(0xFFC62828)
                                        : const Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _celdaTabla(
                            flex: 14,
                            child: Text(
                              formatearMoneda(_precioMostrado(producto)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: const Color(0xFF3F434A),
                              ),
                            ),
                          ),
                          _celdaTabla(
                            flex: 14,
                            child: Text(
                              formatearMoneda(producto.precioCompra),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: const Color(0xFF3F434A),
                              ),
                            ),
                          ),
                          _celdaTabla(
                            flex: 11,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: producto.estado
                                      ? const Color(0xFFE8F8EE)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  producto.estado ? 'Activo' : 'Inactivo',
                                  maxLines: 1,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: producto.estado
                                        ? const Color(0xFF16A34A)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _celdaAcciones(producto),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tarjetas(
    List<ProductoModel> lista,
    Map<String, String> mapaCategorias,
    Map<String, ProductoModel> mapaProductos,
  ) {
    return Column(
      children: [
        _ordenExistenciaMovil(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemCount: lista.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _tarjetaProductoMovil(
              lista[index],
              mapaCategorias,
              mapaProductos,
            ),
          ),
        ),
      ],
    );
  }

  // Fila etiqueta/valor de la tarjeta de producto en móvil (ver
  // _tarjetaProductoMovil) -pedido explícito del dueño, con captura de
  // referencia-: etiqueta chica gris a la izquierda, valor a la derecha.
  Widget _filaDatoTarjeta(String etiqueta, Widget valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.3,
            ),
          ),
          valor,
        ],
      ),
    );
  }

  // Tarjeta de producto en móvil -pedido explícito del dueño, con captura de
  // referencia-: franja roja a la izquierda, miniatura + nombre arriba, filas
  // de dato divididas (código/categoría/stock/estado), y una franja inferior
  // con costo y precio de venta.
  Widget _tarjetaProductoMovil(
    ProductoModel p,
    Map<String, String> mapaCategorias,
    Map<String, ProductoModel> mapaProductos,
  ) {
    final existencia = p.esCombo
        ? p.stockDisponibleCombo(mapaProductos)
        : p.stock;
    final bajoStock = existencia < 3;
    final seleccionada = _filaSeleccionada == p.id;
    final categoria = mapaCategorias[p.idCategoria] ?? '-';
    final textoExistencia = existencia.toStringAsFixed(
      existencia == existencia.roundToDouble() ? 0 : 2,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      // Un solo onTap -sin onDoubleTap acá- a propósito: ver el comentario
      // grande junto a _tocarFila.
      onTap: () => _tocarFila(p, mapaCategorias, mapaProductos),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: seleccionada
                ? const Color(0xFFC62828)
                : const Color(0xFFE0E2E8),
            width: seleccionada ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // Stack (no IntrinsicHeight) para la franja roja a la izquierda: con
        // muchas tarjetas en pantalla durante un scroll rápido,
        // IntrinsicHeight le agrega una pasada de layout extra a CADA
        // tarjeta (mide el alto intrínseco antes de poder acomodar todo) —
        // un Stack no la necesita, la franja simplemente se estira al alto
        // que termine ocupando el contenido de al lado, sin ese paso de más.
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: Color(0xFFC62828)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: p.imagenUrl.isEmpty
                              ? Container(
                                  width: 52,
                                  height: 52,
                                  color: const Color(0xFFF3F4F6),
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: Colors.grey.shade400,
                                    size: 24,
                                  ),
                                )
                              : ImagenProductoNetwork(
                                  url: p.imagenUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.esCombo)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDE7F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'COMBO',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6A1B9A),
                                    ),
                                  ),
                                ),
                              Text(
                                p.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              if (p.descripcion.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  p.descripcion,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _celdaAccionesMovil(p),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _filaDatoTarjeta(
                    'CODIGO',
                    Text(
                      p.codigo,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _filaDatoTarjeta(
                    'CATEGORIA',
                    Text(
                      categoria,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _filaDatoTarjeta(
                    'EXISTENCIA',
                    Text(
                      '$textoExistencia Unidades',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: bajoStock
                            ? const Color(0xFFC62828)
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _filaDatoTarjeta(
                    'ESTADO',
                    Text(
                      p.estado ? 'Activo' : 'Inactivo',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.estado
                            ? const Color(0xFF16A34A)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Container(
                    color: const Color(0xFFF7F7F9),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COSTO',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatearMoneda(p.precioCompra),
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'PRECIO VENTA',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  formatearMoneda(_precioMostrado(p)),
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFC62828),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _precioConIsv ? 'c/ISV' : 's/ISV',
                                  style: GoogleFonts.poppins(
                                    fontSize: 9.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ordenExistenciaMovil() {
    final activo = _columnaOrden == 'existencia';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _alternarOrden('existencia'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ordenar por existencia',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: activo
                        ? const Color(0xFFC62828)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  activo
                      ? (_ordenAscendente
                            ? Icons.arrow_upward
                            : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 15,
                  color: activo
                      ? const Color(0xFFC62828)
                      : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _celdaHeader({
    required String texto,
    required int flex,
    String? columnaOrdenKey,
  }) {
    final activa = columnaOrdenKey != null && _columnaOrden == columnaOrdenKey;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: columnaOrdenKey == null
            ? null
            : () => _alternarOrden(columnaOrdenKey),
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0xFFD6D9E0), width: 1),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: activa
                        ? const Color(0xFFC62828)
                        : const Color(0xFF666A72),
                    letterSpacing: 0.35,
                  ),
                ),
              ),
              if (columnaOrdenKey != null) ...[
                const SizedBox(width: 4),
                Icon(
                  activa
                      ? (_ordenAscendente
                            ? Icons.arrow_upward
                            : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 13,
                  color: activa
                      ? const Color(0xFFC62828)
                      : Colors.grey.shade400,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _celdaHeaderAcciones() {
    return Container(
      width: 116,
      height: double.infinity,
      alignment: Alignment.center,
      child: Text(
        'ACCIONES',
        maxLines: 1,
        style: GoogleFonts.poppins(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF666A72),
          letterSpacing: 0.25,
        ),
      ),
    );
  }

  Widget _celdaTabla({required int flex, required Widget child}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC7CBD3), width: 1)),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  /// Pedido explícito del dueño: ver la foto sin tener que abrir "Editar" —
  /// mismo diálogo (ImagenZoomDialog) que ya usa Buscar Producto.
  void _verFoto(ProductoModel producto) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => ImagenZoomDialog(url: producto.imagenUrl),
    );
  }

  Widget _botonVerFoto(
    ProductoModel producto, {
    required double lado,
    required double tamanoIcono,
  }) {
    if (producto.imagenUrl.isEmpty) return SizedBox(width: lado);
    return Tooltip(
      message: 'Ver foto',
      child: InkWell(
        onTap: () => _verFoto(producto),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: lado,
          height: lado,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFDFE1E6)),
          ),
          child: Icon(
            Icons.photo_outlined,
            size: tamanoIcono,
            color: const Color(0xFFC62828),
          ),
        ),
      ),
    );
  }

  Widget _celdaAcciones(ProductoModel producto) {
    return Container(
      width: 116,
      height: double.infinity,
      alignment: Alignment.center,
      // Listener (no GestureDetector/InkWell) a propósito: solo OBSERVA que
      // se tocó acá, sin competir por el gesto con el PopupMenuButton ni
      // con el InkWell del ícono de foto -pedido explícito del dueño: tocar
      // la foto o el "⋮" de una fila distinta a la seleccionada tiene que
      // mover la iluminación a esa fila de inmediato, no dejarla en la de
      // antes-.
      child: Listener(
        onPointerDown: (_) => _seleccionarFila(producto.id),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _botonVerFoto(producto, lado: 34, tamanoIcono: 19),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              padding: EdgeInsets.zero,
              icon: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFDFE1E6)),
                ),
                child: const Icon(
                  Icons.more_vert,
                  size: 21,
                  color: Color(0xFF454950),
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              position: PopupMenuPosition.under,
              onSelected: (valor) => _manejarAccion(valor, producto),
              itemBuilder: (context) =>
                  _opcionesMenu(esCombo: producto.esCombo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celdaAccionesMovil(ProductoModel producto) {
    return Listener(
      onPointerDown: (_) => _seleccionarFila(producto.id),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonVerFoto(producto, lado: 32, tamanoIcono: 17),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'Más acciones',
            padding: EdgeInsets.zero,
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFDFE1E6)),
              ),
              child: const Icon(
                Icons.more_vert,
                size: 19,
                color: Color(0xFF454950),
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 8,
            position: PopupMenuPosition.under,
            onSelected: (valor) => _manejarAccion(valor, producto),
            itemBuilder: (context) => _opcionesMenu(esCombo: producto.esCombo),
          ),
        ],
      ),
    );
  }

  void _manejarAccion(String valor, ProductoModel producto) {
    switch (valor) {
      case 'editar':
        _abrirFormulario(producto);
        break;
      case 'ajustar':
        _abrirAjusteStock(producto);
        break;
      case 'historial_stock':
        _abrirHistorial(producto);
        break;
      case 'historial_ventas':
        _abrirHistorialMovimientos(producto, 'ventas');
        break;
      case 'historial_compras':
        _abrirHistorialMovimientos(producto, 'compras');
        break;
      case 'lotes_costo':
        _abrirHistorialMovimientos(producto, 'lotes');
        break;
      case 'codigo_barras':
        _abrirCodigoBarras(producto);
        break;
    }
  }

  List<PopupMenuEntry<String>> _opcionesMenu({bool esCombo = false}) {
    return [
      _opcionMenu(
        valor: 'editar',
        icono: Icons.edit_outlined,
        texto: 'Editar producto',
      ),
      // Un combo no tiene existencia propia real (siempre 0): un ajuste
      // manual accidental rompería la premisa de que no aporta a la
      // valorización de inventario, así que ni se ofrece la opción.
      if (!esCombo)
        _opcionMenu(
          valor: 'ajustar',
          icono: Icons.tune,
          texto: 'Ajustar existencia',
        ),
      const PopupMenuDivider(),
      _opcionMenu(
        valor: 'historial_stock',
        icono: Icons.history,
        texto: 'Historial de existencia',
      ),
      _opcionMenu(
        valor: 'historial_ventas',
        icono: Icons.point_of_sale_outlined,
        texto: 'Historial de ventas',
      ),
      _opcionMenu(
        valor: 'historial_compras',
        icono: Icons.shopping_cart_outlined,
        texto: 'Historial de compras',
      ),
      _opcionMenu(
        valor: 'lotes_costo',
        icono: Icons.layers_outlined,
        texto: 'Costos por lote (FIFO)',
      ),
      const PopupMenuDivider(),
      _opcionMenu(
        valor: 'codigo_barras',
        icono: Icons.qr_code_2_outlined,
        texto: 'Código de barras',
      ),
    ];
  }

  PopupMenuItem<String> _opcionMenu({
    required String valor,
    required IconData icono,
    required String texto,
  }) {
    return PopupMenuItem<String>(
      value: valor,
      height: 44,
      child: Row(
        children: [
          Icon(icono, size: 19, color: const Color(0xFF4B4F58)),
          const SizedBox(width: 12),
          Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: const Color(0xFF25272B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorVista(String vista) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: vista,
          isExpanded: true,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF1A1A1A),
          ),
          items: const [
            DropdownMenuItem(
              value: 'filtrados',
              child: Text('Productos filtrados'),
            ),
            DropdownMenuItem(value: 'todos', child: Text('Mostrar todos')),
            DropdownMenuItem(value: 'bajo', child: Text('Bajo existencia')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref.read(inventarioVistaProvider.notifier).actualizar(v);
          },
        ),
      ),
    );
  }

  Widget _tituloYBadges(
    bool esMovil,
    AsyncValue<List<ProductoModel>> productosAsync,
  ) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text(
          'Inventario',
          style: GoogleFonts.poppins(
            fontSize: esMovil ? 19 : 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        productosAsync.when(
          data: (productos) {
            // Cache: estos dos `fold` recorren TODA la lista (no la
            // filtrada) — sin esto se repetían en cada build(), incluida
            // una selección de fila que no cambia nada de esto (ver
            // comentario junto a los campos `_cache*`).
            if (!identical(_cacheValoresProductosOrigen, productos) ||
                _cacheValoresPrecioConIsv != _precioConIsv) {
              _cacheValorCompra = productos.fold<double>(
                0,
                (s, p) => s + (p.stock * p.precioCompra),
              );
              _cacheValorVenta = productos.fold<double>(
                0,
                (s, p) => s + (p.stock * _precioMostrado(p)),
              );
              _cacheValoresProductosOrigen = productos;
              _cacheValoresPrecioConIsv = _precioConIsv;
            }
            final valorCompra = _cacheValorCompra;
            final valorVenta = _cacheValorVenta;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badgeInfo(
                  '${productos.length} productos',
                  const Color(0xFFC62828),
                ),
                _badgeInfo(
                  'Valor compra ${formatearMoneda(valorCompra)}',
                  const Color(0xFF3B82F6),
                ),
                _badgeInfo(
                  'Valor venta (${_precioConIsv ? 'con' : 'sin'} ISV) ${formatearMoneda(valorVenta)}',
                  const Color(0xFF16A34A),
                ),
              ],
            );
          },
          loading: () => const SizedBox(),
          error: (e, st) => const SizedBox(),
        ),
      ],
    );
  }

  // Versión chica del selector-pill -pedido explícito del dueño: el
  // original (46 de alto, 14/11 de padding, 13 de letra) ocupaba demasiado
  // espacio para vivir arriba en una esquina junto al título.
  Widget _pildoraChica<T>(
    T valor,
    T valorActual,
    ValueChanged<T> onTap,
    List<(String, T)> opciones,
  ) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (texto, v) in opciones)
            InkWell(
              onTap: () => onTap(v),
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: valorActual == v
                      ? const Color(0xFFC62828)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  texto,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: valorActual == v
                        ? Colors.white
                        : const Color(0xFF666A72),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectorPrecioIsvChico() {
    return _pildoraChica<bool>(
      _precioConIsv,
      _precioConIsv,
      (v) => setState(() => _precioConIsv = v),
      const [('Con ISV', true), ('Sin ISV', false)],
    );
  }

  Widget _selectorEstadoChico() {
    return _pildoraChica<String>(
      _filtroEstado,
      _filtroEstado,
      (v) => setState(() => _filtroEstado = v),
      const [('Activos', 'activos'), ('Inactivos', 'inactivos')],
    );
  }

  Widget _selectorVistaTabletChico() {
    return _pildoraChica<String>(
      _vistaTablet,
      _vistaTablet,
      (v) => setState(() => _vistaTablet = v),
      const [('Tabla', 'tabla'), ('Tarjetas', 'tarjetas')],
    );
  }

  Widget _selectorCampoFiltro() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _campoFiltro,
          isExpanded: true,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF1A1A1A),
          ),
          items: [
            for (final (valor, etiqueta) in _opcionesCampoFiltro)
              DropdownMenuItem(
                value: valor,
                child: Text('Filtrar por: $etiqueta'),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _campoFiltro = v);
          },
        ),
      ),
    );
  }

  Widget _buscador(String busqueda) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: CampoTecladoCompacto(
              controller: _busquedaController,
              numerico: false,
              onSubmitted: (_) => _buscar(),
              titulo: 'Buscar o escanear código de barras...',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _busquedaController,
                autofocus: true,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar o escanear código de barras...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _buscar(),
              ),
            ),
          ),
          if (busqueda.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close, size: 18),
              onPressed: _limpiarBusqueda,
            ),
          IconButton(
            tooltip: 'Escanear código de barras',
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            onPressed: _escanear,
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: _buscar,
          ),
        ],
      ),
    );
  }
}
