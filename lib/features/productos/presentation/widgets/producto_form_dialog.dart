import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import '../../data/producto_model.dart';
import '../../providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../categorias/data/categoria_model.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';
import '../../../../core/widgets/reintentar_dialog.dart';
import '../../../../core/services/cloudinary_service.dart';
import '../../../../core/services/remove_bg_service.dart';
import '../../../../core/widgets/imagen_producto_network.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Un componente agregado a la receta de un combo mientras se está armando
/// en el formulario (antes de guardar). [cantidad] vive en un controller
/// propio para poder editarse con teclado numérico normal, línea por línea.
class _ComponenteEnConstruccion {
  final ProductoModel producto;
  final TextEditingController cantidadController;
  _ComponenteEnConstruccion({required this.producto, double cantidad = 1})
    : cantidadController = TextEditingController(
        text: cantidad == cantidad.roundToDouble()
            ? cantidad.toInt().toString()
            : cantidad.toString(),
      );
}

class ProductoFormDialog extends ConsumerStatefulWidget {
  final ProductoModel? producto;

  // Precargan código/nombre al crear un producto NUEVO (producto == null);
  // se ignoran si se está editando uno existente. Vienen de EscanearFactura
  // (ver Registrar Compra > Escanear Factura, web móvil): cuando una línea
  // leída de la factura no coincide con nada del inventario, evita que el
  // cajero tenga que volver a tipear lo que la IA ya leyó bien.
  final String? codigoInicial;
  final String? nombreInicial;

  const ProductoFormDialog({
    super.key,
    this.producto,
    this.codigoInicial,
    this.nombreInicial,
  });

  @override
  ConsumerState<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends ConsumerState<ProductoFormDialog> {
  final _codigoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _precioCompraController = TextEditingController(text: '0');
  final _precioVentaController = TextEditingController(text: '0');
  final _precioVenta2Controller = TextEditingController();
  final _precioVenta3Controller = TextEditingController();
  // Sin `autofocus`: en Windows, pedir el foco durante el primer build (que
  // es lo que hace `autofocus`) compite con la animación de apertura del
  // Dialog y se pierde la primera tecla que se escribe. Pidiéndolo a mano
  // después del primer frame (mismo mecanismo ya usado en
  // registrar_venta_screen para este problema) el foco queda firme antes de
  // que llegue cualquier tecla.
  final _focusNombre = FocusNode();

  String? _idCategoria;
  bool _activo = true;
  bool _mostrarNivelesExtra = false;
  bool _guardando = false;
  String? _error;

  // Combo/Kit: solo se puede activar al crear (no se cambia el tipo de un
  // producto ya existente). Reemplaza "Existencia inicial" + "Precio Compra"
  // por un armador de receta: cada componente es un producto individual ya
  // existente (no otro combo) con la cantidad que lleva cada unidad del
  // combo. El costo se recalcula solo, en vivo, sumando cantidad×precioCompra
  // de cada componente.
  bool _esCombo = false;
  final List<_ComponenteEnConstruccion> _componentesCombo = [];
  final _busquedaComponenteController = TextEditingController();
  // Al editar un combo ya existente, su lista de componentes (guardada como
  // solo id+cantidad) recién se puede armar en pantalla cuando el stream de
  // productos trae los datos completos (nombre, precioCompra) de cada uno;
  // esta bandera evita repetir esa carga en cada rebuild.
  bool _componentesInicializados = false;

  double get _costoSumadoCombo {
    var total = 0.0;
    for (final c in _componentesCombo) {
      total +=
          c.producto.precioCompra *
          (double.tryParse(c.cantidadController.text.trim()) ?? 0);
    }
    return total;
  }

  // Foto del producto: se sube a Cloudinary apenas se elige (no recién al
  // guardar), así el usuario ve enseguida si la subida falló en vez de
  // enterarse hasta el final. _imagenUrl es lo que se manda a crear/
  // actualizar; _imagenPreviewBytes es la vista previa local mientras sube
  // (o si la subida falló y no hay URL todavía).
  String _imagenUrl = '';
  Uint8List? _imagenPreviewBytes;
  bool _subiendoImagen = false;
  bool _quitandoFondo = false;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    if (p != null) {
      _codigoController.text = p.codigo;
      _codigoBarrasController.text = p.codigoBarras;
      _nombreController.text = p.nombre;
      _descripcionController.text = p.descripcion;
      _stockController.text = p.stock.toString();
      _precioCompraController.text = p.precioCompra.toString();
      _precioVentaController.text = p.precioVenta.toString();
      if (p.precioVenta2 > 0)
        _precioVenta2Controller.text = p.precioVenta2.toString();
      if (p.precioVenta3 > 0)
        _precioVenta3Controller.text = p.precioVenta3.toString();
      _mostrarNivelesExtra = p.precioVenta2 > 0 || p.precioVenta3 > 0;
      _idCategoria = p.idCategoria;
      _activo = p.estado;
      _imagenUrl = p.imagenUrl;
      _esCombo = p.esCombo;
    } else {
      if (widget.codigoInicial != null)
        _codigoController.text = widget.codigoInicial!;
      if (widget.nombreInicial != null)
        _nombreController.text = widget.nombreInicial!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNombre.requestFocus();
    });
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _codigoBarrasController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _stockController.dispose();
    _precioCompraController.dispose();
    _precioVentaController.dispose();
    _precioVenta2Controller.dispose();
    _precioVenta3Controller.dispose();
    _focusNombre.dispose();
    _busquedaComponenteController.dispose();
    for (final c in _componentesCombo) {
      c.cantidadController.dispose();
    }
    super.dispose();
  }

  /// Pregunta en qué formato guardar la foto elegida -pedido explícito del
  /// dueño-. null si el usuario cierra el diálogo sin elegir (se cancela la
  /// subida). PNG solo tiene sentido de verdad si después se le va a quitar
  /// el fondo (ver _quitarFondo) — sin eso, PNG de una foto común no se ve
  /// distinto a JPG, solo pesa más.
  Future<String?> _elegirFormatoImagen() {
    return showDialog<String>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '¿Guardar la foto como?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        content: Text(
          'PNG permite fondo transparente (útil si después vas a usar "Quitar fondo"); JPG pesa menos.',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: Colors.grey.shade600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'jpg'),
            child: Text(
              'JPG',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(context, 'png'),
            child: Text(
              'PNG',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _elegirImagen() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty || !mounted) return;
    final archivo = resultado.files.first;
    final bytesOriginales = archivo.bytes;
    if (bytesOriginales == null) return;

    final formato = await _elegirFormatoImagen();
    if (formato == null || !mounted) return;

    // Reencodea al formato elegido (paquete `image`, ya usado en el proyecto
    // para los logos de tickets) — si por algún motivo no se puede decodificar
    // la imagen (archivo corrupto/formato raro), se sube tal cual vino en vez
    // de fallar la subida entera.
    final decodificada = img.decodeImage(bytesOriginales);
    final bytes = decodificada == null
        ? bytesOriginales
        : Uint8List.fromList(
            formato == 'png'
                ? img.encodePng(decodificada)
                : img.encodeJpg(decodificada, quality: 90),
          );
    final nombreArchivo = '${archivo.name.split('.').first}.$formato';

    setState(() {
      _imagenPreviewBytes = bytes;
      _subiendoImagen = true;
    });
    try {
      final url = await CloudinaryService().subirImagen(bytes, nombreArchivo);
      if (!mounted) return;
      setState(() {
        _imagenUrl = url;
        _subiendoImagen = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imagenPreviewBytes = null;
        _subiendoImagen = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo subir la foto, probá de nuevo'),
        ),
      );
    }
  }

  void _quitarImagen() {
    setState(() {
      _imagenUrl = '';
      _imagenPreviewBytes = null;
    });
  }

  /// Manda la foto YA subida a remove.bg (plan gratis, 50/mes, resolución
  /// miniatura) y sube el resultado (PNG con transparencia) de vuelta a
  /// Cloudinary, reemplazando la foto del producto -pedido explícito del
  /// dueño-. Sirve tanto para una foto recién subida como para una que ya
  /// tenía el producto desde antes.
  Future<void> _quitarFondo() async {
    if (_imagenUrl.isEmpty) return;
    setState(() => _quitandoFondo = true);
    try {
      final sinFondo = await RemoveBgService().quitarFondo(_imagenUrl);
      final url = await CloudinaryService().subirImagen(
        sinFondo,
        'sin_fondo.png',
      );
      if (!mounted) return;
      setState(() {
        _imagenUrl = url;
        _imagenPreviewBytes = null;
        _quitandoFondo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _quitandoFondo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo quitar el fondo (¿se acabaron las 50 gratis de este mes?, revisá tu conexión).',
          ),
        ),
      );
    }
  }

  double _parseDouble(String texto) {
    return double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio');
      return;
    }
    if (_idCategoria == null) {
      setState(() => _error = 'Seleccioná una categoría');
      return;
    }
    if (_esCombo && _componentesCombo.isEmpty) {
      setState(() => _error = 'Agregá al menos un componente al combo');
      return;
    }
    if (_esCombo &&
        _componentesCombo.any(
          (c) => (double.tryParse(c.cantidadController.text.trim()) ?? 0) <= 0,
        )) {
      setState(
        () => _error =
            'Todas las cantidades de los componentes deben ser mayores a 0',
      );
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(productoRepositoryProvider);
    final componentes = _esCombo
        ? _componentesCombo
              .map(
                (c) => ComponenteProductoModel(
                  idProducto: c.producto.id,
                  cantidad:
                      double.tryParse(c.cantidadController.text.trim()) ?? 0,
                ),
              )
              .toList()
        : const <ComponenteProductoModel>[];
    if (widget.producto == null) {
      final creado = await ejecutarConReintento(
        context,
        () => repo
            .crear(
              codigo: _codigoController.text,
              codigoBarras: _codigoBarrasController.text,
              nombre: nombre,
              descripcion: _descripcionController.text,
              idCategoria: _idCategoria!,
              stock: _esCombo ? 0 : _parseDouble(_stockController.text),
              precioCompra: _esCombo
                  ? _costoSumadoCombo
                  : _parseDouble(_precioCompraController.text),
              precioVenta: _parseDouble(_precioVentaController.text),
              precioVenta2: _parseDouble(_precioVenta2Controller.text),
              precioVenta3: _parseDouble(_precioVenta3Controller.text),
              estado: _activo,
              imagenUrl: _imagenUrl,
              esCombo: _esCombo,
              componentes: componentes,
            )
            .timeout(const Duration(seconds: 12)),
      );
      if (!mounted) return;
      if (creado == null) {
        setState(() => _guardando = false);
        return;
      }
      Navigator.pop(context, creado);
      return;
    }

    final ok = await ejecutarConReintento<bool>(context, () async {
      await repo
          .actualizar(
            id: widget.producto!.id,
            codigo: _codigoController.text,
            codigoBarras: _codigoBarrasController.text,
            nombre: nombre,
            descripcion: _descripcionController.text,
            idCategoria: _idCategoria!,
            precioCompra: _esCombo
                ? _costoSumadoCombo
                : _parseDouble(_precioCompraController.text),
            precioVenta: _parseDouble(_precioVentaController.text),
            precioVenta2: _parseDouble(_precioVenta2Controller.text),
            precioVenta3: _parseDouble(_precioVenta3Controller.text),
            estado: _activo,
            imagenUrl: _imagenUrl,
            esCombo: _esCombo ? true : null,
            componentes: _esCombo ? componentes : null,
          )
          .timeout(const Duration(seconds: 12));
      return true;
    });
    if (!mounted) return;
    if (ok != true) {
      setState(() => _guardando = false);
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Eliminar producto',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Seguro que querés eliminar este producto?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _guardando = true);
    final ok = await ejecutarConReintento<bool>(context, () async {
      await ref
          .read(productoRepositoryProvider)
          .eliminar(widget.producto!.id)
          .timeout(const Duration(seconds: 12));
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context);
    } else {
      setState(() => _guardando = false);
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.producto != null;
    final categoriasAsync = ref.watch(categoriasStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 540;
    // En pantalla ancha (PC) el formulario se organiza en dos columnas -pedido
    // explícito del dueño: que aproveche el ancho disponible y no haya que
    // scrollear-, así que el diálogo necesita bastante más ancho que el
    // angosto de una sola columna que sigue usando el celular.
    final anchoDisponibleDesktop = tamano.width - 120;
    final anchoDialog = esMovil
        ? tamano.width - 48
        : anchoDisponibleDesktop > 920
        ? 920.0
        : (anchoDisponibleDesktop < 700 ? 700.0 : anchoDisponibleDesktop);
    final altoDisponibleDesktop = tamano.height - 80;
    final altoMaximoDialog = esMovil
        ? 640.0
        : altoDisponibleDesktop > 760
        ? 760.0
        : (altoDisponibleDesktop < 520 ? 520.0 : altoDisponibleDesktop);

    // Al editar un combo ya existente, arma _componentesCombo a partir de la
    // receta guardada (solo id+cantidad) apenas el stream de productos trae
    // los datos completos de cada componente. Una sola vez por apertura del
    // diálogo (ver _componentesInicializados).
    if (!_componentesInicializados && editando && widget.producto!.esCombo) {
      final productosDisponibles = ref.watch(productosStreamProvider).value;
      if (productosDisponibles != null) {
        final mapaProductos = {for (final p in productosDisponibles) p.id: p};
        for (final c in widget.producto!.componentes) {
          final productoComponente = mapaProductos[c.idProducto];
          if (productoComponente != null) {
            _componentesCombo.add(
              _ComponenteEnConstruccion(
                producto: productoComponente,
                cantidad: c.cantidad,
              ),
            );
          }
        }
        _componentesInicializados = true;
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: altoMaximoDialog),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFC62828),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editando ? 'Editar Producto' : 'Nuevo Producto',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _selectorImagen()),
                    const SizedBox(height: 18),
                    // En pantalla ancha (PC) se reparte en dos columnas para
                    // aprovechar el ancho del diálogo y evitar el scroll del
                    // formulario largo; en celular/tablet angosto se apilan
                    // igual que siempre (una sola columna).
                    if (esMovil)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._camposIdentidad(categoriasAsync),
                          ..._camposPrecioEstado(editando),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _camposIdentidad(categoriasAsync),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _camposPrecioEstado(editando),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
              child: Row(
                children: [
                  if (editando)
                    IconButton(
                      onPressed: _guardando ? null : _eliminar,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFC62828),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFC62828,
                        ).withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : Text(
                            'Guardar',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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

  /// Columna izquierda del formulario en pantalla ancha (o el primer tramo
  /// de la única columna en celular/tablet): identidad del producto.
  List<Widget> _camposIdentidad(
    AsyncValue<List<CategoriaModel>> categoriasAsync,
  ) {
    return [
      Row(
        children: [
          Expanded(
            child: CampoTecladoCompacto(
              controller: _codigoController,
              numerico: false,
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _codigoController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _decoracion('Código (opcional)'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CampoTecladoCompacto(
              controller: _codigoBarrasController,
              numerico: false,
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _codigoBarrasController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _decoracion('Código de barras').copyWith(
                  suffixIcon: IconButton(
                    tooltip: 'Escanear',
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    onPressed: () async {
                      final codigo = await escanearCodigoBarras(context);
                      if (codigo == null || codigo.isEmpty || !mounted) return;
                      setState(() => _codigoBarrasController.text = codigo);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      CampoTecladoCompacto(
        controller: _nombreController,
        numerico: false,
        child: TextField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _nombreController,
          focusNode: _focusNombre,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: _decoracion('Nombre'),
        ),
      ),
      const SizedBox(height: 14),
      CampoTecladoCompacto(
        controller: _descripcionController,
        numerico: false,
        child: TextField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _descripcionController,
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: _decoracion('Descripción (opcional)'),
        ),
      ),
      const SizedBox(height: 14),
      categoriasAsync.when(
        data: (categorias) {
          return DropdownButtonFormField<String>(
            value: _idCategoria,
            decoration: _decoracion('Categoría'),
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF1A1A1A),
            ),
            items: categorias.map((c) {
              return DropdownMenuItem(value: c.id, child: Text(c.descripcion));
            }).toList(),
            onChanged: (v) => setState(() => _idCategoria = v),
          );
        },
        loading: () => const LinearProgressIndicator(),
        error: (e, st) => Text(
          'Error cargando categorías',
          style: GoogleFonts.poppins(color: Colors.red, fontSize: 12),
        ),
      ),
    ];
  }

  /// Columna derecha del formulario en pantalla ancha (o el segundo tramo
  /// de la única columna en celular/tablet): combo/precios/estado.
  List<Widget> _camposPrecioEstado(bool editando) {
    return [
      if (!editando) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EAF0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Es un combo/kit',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              Switch(
                value: _esCombo,
                activeColor: const Color(0xFF16A34A),
                onChanged: (v) => setState(() => _esCombo = v),
              ),
            ],
          ),
        ),
      ],
      if (_esCombo) ...[
        const SizedBox(height: 14),
        _armadorCombo(),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EAF0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                'Costo sumado',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                'L. ${_costoSumadoCombo.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ] else ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: CampoTecladoCompacto(
                controller: _stockController,
                numerico: true,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _stockController,
                  enabled: !editando,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion(
                    editando
                        ? 'Existencia (ajustar abajo)'
                        : 'Existencia inicial',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CampoTecladoCompacto(
                controller: _precioCompraController,
                numerico: true,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _precioCompraController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Precio Compra'),
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      CampoTecladoCompacto(
        controller: _precioVentaController,
        numerico: true,
        child: TextField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: _precioVentaController,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: _decoracion('Precio Venta'),
        ),
      ),
      const SizedBox(height: 8),
      InkWell(
        onTap: () =>
            setState(() => _mostrarNivelesExtra = !_mostrarNivelesExtra),
        child: Row(
          children: [
            Icon(
              _mostrarNivelesExtra
                  ? Icons.remove_circle_outline
                  : Icons.add_circle_outline,
              size: 18,
              color: const Color(0xFFC62828),
            ),
            const SizedBox(width: 8),
            Text(
              'Niveles de precio adicionales',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFFC62828),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      if (_mostrarNivelesExtra) ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: CampoTecladoCompacto(
                controller: _precioVenta2Controller,
                numerico: true,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _precioVenta2Controller,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Precio Venta 2'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CampoTecladoCompacto(
                controller: _precioVenta3Controller,
                numerico: true,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _precioVenta3Controller,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Precio Venta 3'),
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EAF0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              'Estado',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            Text(
              _activo ? 'Activo' : 'Inactivo',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _activo ? const Color(0xFF16A34A) : Colors.grey.shade500,
              ),
            ),
            Switch(
              value: _activo,
              activeColor: const Color(0xFF16A34A),
              onChanged: (v) => setState(() => _activo = v),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(
            _error!,
            style: GoogleFonts.poppins(
              color: Colors.red.shade700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _armadorCombo() {
    final productos =
        ref.watch(productosStreamProvider).value ?? const <ProductoModel>[];
    final idsYaAgregados = _componentesCombo.map((c) => c.producto.id).toSet();
    final filtro = _busquedaComponenteController.text.trim().toLowerCase();
    final resultados = filtro.isEmpty
        ? const <ProductoModel>[]
        : productos
              .where(
                (p) =>
                    !p.esCombo &&
                    !idsYaAgregados.contains(p.id) &&
                    p.textoBusqueda.toLowerCase().contains(filtro),
              )
              .take(6)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Componentes del combo',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        CampoTecladoCompacto(
          controller: _busquedaComponenteController,
          numerico: false,
          child: TextField(
            inputFormatters: [mayusculasInputFormatter],
            autocorrect: false,
            enableSuggestions: false,
            controller: _busquedaComponenteController,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: _decoracion(
              'Buscar producto para agregar...',
            ).copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (resultados.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB6BCC7)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: resultados.map((p) {
                return ListTile(
                  dense: true,
                  title: Text(
                    p.nombre,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  subtitle: Text(
                    'Cód. ${p.codigo} · Existencia ${p.stock.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFFC62828),
                  ),
                  onTap: () {
                    setState(() {
                      _componentesCombo.add(
                        _ComponenteEnConstruccion(producto: p),
                      );
                      _busquedaComponenteController.clear();
                    });
                  },
                );
              }).toList(),
            ),
          ),
        if (_componentesCombo.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._componentesCombo.map((c) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.producto.nombre,
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: CampoTecladoCompacto(
                      controller: c.cantidadController,
                      numerico: true,
                      child: TextField(
                        inputFormatters: [mayusculasInputFormatter],
                        autocorrect: false,
                        enableSuggestions: false,
                        controller: c.cantidadController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(fontSize: 13),
                        decoration: _decoracion('Cant.'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Color(0xFFC62828),
                    ),
                    onPressed: () =>
                        setState(() => _componentesCombo.remove(c)),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _selectorImagen() {
    const lado = 96.0;
    Widget contenido;
    if (_imagenPreviewBytes != null) {
      contenido = Image.memory(
        _imagenPreviewBytes!,
        width: lado,
        height: lado,
        fit: BoxFit.cover,
      );
    } else if (_imagenUrl.isNotEmpty) {
      contenido = ImagenProductoNetwork(
        url: _imagenUrl,
        width: lado,
        height: lado,
      );
    } else {
      contenido = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            color: Colors.grey.shade400,
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            'Foto',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: (_subiendoImagen || _quitandoFondo) ? null : _elegirImagen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: lado,
            height: lado,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EAF0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFB6BCC7)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: (_subiendoImagen || _quitandoFondo)
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Color(0xFFC62828),
                        strokeWidth: 2.2,
                      ),
                    )
                  : contenido,
            ),
          ),
        ),
        if (!_subiendoImagen &&
            !_quitandoFondo &&
            (_imagenUrl.isNotEmpty || _imagenPreviewBytes != null))
          Positioned(
            top: -8,
            right: -8,
            child: InkWell(
              onTap: _quitarImagen,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFC62828),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        // "Quitar fondo" (remove.bg, plan gratis) -pedido explícito del
        // dueño-: solo tiene sentido si la foto YA está subida de verdad
        // (_imagenUrl, no una vista previa local todavía sin subir) porque
        // remove.bg necesita una URL pública para descargarla.
        if (!_subiendoImagen && !_quitandoFondo && _imagenUrl.isNotEmpty)
          Positioned(
            bottom: -8,
            right: -8,
            child: Tooltip(
              message: 'Quitar fondo (remove.bg, 50 gratis por mes)',
              child: InkWell(
                onTap: _quitarFondo,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_fix_high,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
