import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/factura_scanner_service.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/presentation/widgets/producto_form_dialog.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../proveedores/data/proveedor_model.dart';
import '../../../proveedores/providers/proveedores_provider.dart';
import '../../../ventas/presentation/widgets/teclado_numerico_dialog.dart';
import 'buscar_producto_compra_dialog.dart';

/// Un producto de la factura ya emparejado con el inventario, listo para
/// agregarse al carrito de compra tal cual lo devuelve este diálogo.
class ItemCompraConfirmado {
  final ProductoModel producto;
  final double cantidad;
  final double precioCompra;
  final double descuentoPorcentaje;
  ItemCompraConfirmado({required this.producto, required this.cantidad, required this.precioCompra, required this.descuentoPorcentaje});
}

/// Lo que EscanearFacturaDialog devuelve al cerrarse (ver el comentario en
/// _confirmarTodo sobre por qué no modifica el carrito directamente): datos
/// de encabezado ya revisados/corregidos por el cajero + las líneas a
/// agregar. RegistrarCompraScreen es quien los aplica al carrito de esa
/// pestaña específica.
class DatosFacturaConfirmados {
  final String? idProveedor;
  final String? documentoProveedor;
  final String? razonSocialProveedor;
  final String noFactura;
  final DateTime fecha;
  final String condicion;
  final DateTime? fechaVencimiento;
  final List<ItemCompraConfirmado> items;

  DatosFacturaConfirmados({
    required this.idProveedor,
    required this.documentoProveedor,
    required this.razonSocialProveedor,
    required this.noFactura,
    required this.fecha,
    required this.condicion,
    required this.fechaVencimiento,
    required this.items,
  });
}

/// Escanea 1+ fotos de una misma factura de compra (con IA, ver
/// FacturaScannerService) y precarga sus líneas -emparejadas con el
/// inventario por código- para que el cajero las revise y confirme antes de
/// agregarlas a la compra en curso. Nunca guarda la compra sola: eso lo
/// sigue haciendo el botón "Registrar Compra" de siempre, con el cajero
/// mirando la tabla ya llena.
///
/// Solo tiene sentido en web móvil (se abre desde ahí en
/// RegistrarCompraScreen), así que el teclado numérico en pantalla de
/// cantidad/precio/descuento va siempre, sin ninguna rama para escritorio.
class EscanearFacturaDialog extends ConsumerStatefulWidget {
  const EscanearFacturaDialog({super.key});

  @override
  ConsumerState<EscanearFacturaDialog> createState() => _EscanearFacturaDialogState();
}

class _FilaEscaneada {
  final LineaFacturaEscaneada original;
  ProductoModel? producto;
  bool incluida;
  double cantidad;
  double precioUnitario;
  double descuentoPorcentaje;
  final TextEditingController ctrlCantidad;
  final TextEditingController ctrlPrecio;
  final TextEditingController ctrlDescuento;

  _FilaEscaneada(this.original, this.producto)
      : incluida = true,
        cantidad = original.cantidad,
        precioUnitario = original.precioUnitario,
        descuentoPorcentaje = original.descuentoPorcentaje,
        ctrlCantidad = TextEditingController(text: _formatoCantidadEstatico(original.cantidad)),
        ctrlPrecio = TextEditingController(text: original.precioUnitario.toStringAsFixed(2)),
        ctrlDescuento = TextEditingController(text: _formatoCantidadEstatico(original.descuentoPorcentaje));

  static String _formatoCantidadEstatico(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void dispose() {
    ctrlCantidad.dispose();
    ctrlPrecio.dispose();
    ctrlDescuento.dispose();
  }
}

class _EscanearFacturaDialogState extends ConsumerState<EscanearFacturaDialog> {
  final List<({Uint8List bytes, String mimeType})> _fotos = [];
  bool _procesando = false;
  String? _errorProceso;
  bool _extraccionHecha = false;

  List<_FilaEscaneada> _filas = [];
  String? _proveedorIdMatch;
  final _ctrlNoFactura = TextEditingController();
  DateTime _fecha = DateTime.now();
  String _condicion = 'Contado';
  DateTime? _fechaVencimiento;

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    _ctrlNoFactura.dispose();
    super.dispose();
  }

  Future<void> _agregarFoto() async {
    final resultado = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.first;
    final bytes = archivo.bytes;
    if (bytes == null) return;
    final mimeType = (archivo.extension?.toLowerCase() == 'png') ? 'image/png' : 'image/jpeg';
    setState(() => _fotos.add((bytes: bytes, mimeType: mimeType)));
  }

  void _quitarFoto(int index) => setState(() => _fotos.removeAt(index));

  Future<void> _procesarFactura() async {
    if (_fotos.isEmpty) return;
    setState(() {
      _procesando = true;
      _errorProceso = null;
    });
    try {
      final servicio = FacturaScannerService();
      final resultado = await servicio.escanear(_fotos.map((f) => FotoParaEscanear(bytes: f.bytes, mimeType: f.mimeType)).toList());
      if (!mounted) return;

      final productos = ref.read(productosStreamProvider).value ?? [];
      final proveedores = ref.read(proveedoresStreamProvider).value ?? [];

      final filas = resultado.items.map((item) => _FilaEscaneada(item, _buscarProductoCoincidente(item, productos))).toList();
      final proveedorMatch = _buscarProveedorCoincidente(resultado.proveedorNombre, resultado.proveedorRtn, proveedores);

      setState(() {
        _filas = filas;
        _proveedorIdMatch = proveedorMatch?.id;
        _ctrlNoFactura.text = resultado.numeroFactura ?? '';
        _fecha = resultado.fecha ?? DateTime.now();
        _condicion = resultado.condicionVenta == 'Credito' ? 'Credito' : 'Contado';
        _fechaVencimiento = resultado.fechaVencimiento;
        _extraccionHecha = true;
      });
    } on EscaneoFacturaException catch (e) {
      if (mounted) setState(() => _errorProceso = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _errorProceso = 'No se pudo leer la factura: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // Por código exacto primero (según el negocio, casi siempre coincide con
  // el interno). Si no hay código o no coincide con nada, se prueba una
  // coincidencia por nombre (+ unidad, ver el prompt del Worker: a veces la
  // unidad de la factura -"GLN"- va pegada al nombre acá adentro, como
  // "SUPRA SATIN ACCENT") solo si hay UN único candidato razonable: con más
  // de uno, mejor dejarlo sin emparejar que arriesgar a elegir el
  // incorrecto -el cajero lo resuelve a mano con "Buscar"-.
  // Un combo nunca se compra directo (solo sus componentes, por separado),
  // así que una línea leída de una factura nunca debería emparejar con uno.
  ProductoModel? _buscarProductoCoincidente(LineaFacturaEscaneada item, List<ProductoModel> productosConCombos) {
    final productos = productosConCombos.where((p) => !p.esCombo).toList();
    final codigo = item.codigo?.trim();
    if (codigo != null && codigo.isNotEmpty) {
      final porCodigo = productos.where((p) => p.codigo.trim().toLowerCase() == codigo.toLowerCase()).toList();
      if (porCodigo.length == 1) return porCodigo.first;
    }
    final consulta = '${item.nombre} ${item.unidad ?? ''}'.trim();
    final porNombre = productos.where((p) => p.estado && coincideFuzzy(p.textoBusqueda, consulta)).toList();
    if (porNombre.length == 1) return porNombre.first;
    return null;
  }

  ProveedorModel? _buscarProveedorCoincidente(String? nombre, String? rtn, List<ProveedorModel> proveedores) {
    if (rtn != null && rtn.trim().isNotEmpty) {
      final porRtn = proveedores.where((p) => p.rtn.trim() == rtn.trim()).toList();
      if (porRtn.isNotEmpty) return porRtn.first;
    }
    if (nombre != null && nombre.trim().isNotEmpty) {
      final porNombre = proveedores.where((p) => coincideFuzzy(p.razonSocial, nombre)).toList();
      if (porNombre.length == 1) return porNombre.first;
    }
    return null;
  }

  Future<void> _buscarManual(_FilaEscaneada fila) async {
    final producto = await Navigator.of(context).push<ProductoModel>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoCompraDialog()),
    );
    if (producto == null || !mounted) return;
    setState(() => fila.producto = producto);
  }

  // Para cuando la línea leída es de verdad un producto que todavía no
  // existe en el inventario (no es que la búsqueda por código/nombre haya
  // fallado, sino que el proveedor mandó algo nuevo): crea el producto de
  // una vez, con el código y nombre ya precargados con lo que leyó la IA,
  // en vez de mandar al cajero a Mantenedor > Inventario a mitad de cargar
  // una factura.
  Future<void> _crearProductoNuevo(_FilaEscaneada fila) async {
    final producto = await showDialog<ProductoModel>(
      context: context,
      builder: (context) => ProductoFormDialog(
        codigoInicial: fila.original.codigo,
        nombreInicial: fila.original.nombre,
      ),
    );
    if (producto == null || !mounted) return;
    setState(() => fila.producto = producto);
  }

  void _confirmarTodo() {
    final incluidas = _filas.where((f) => f.incluida).toList();
    if (incluidas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay ninguna línea para agregar')));
      return;
    }
    final sinEmparejar = incluidas.where((f) => f.producto == null).toList();
    if (sinEmparejar.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Faltan ${sinEmparejar.length} producto(s) por emparejar (tocá "Buscar" en esas filas, o destildalas)')),
      );
      return;
    }

    String? documentoProveedor;
    String? razonSocialProveedor;
    if (_proveedorIdMatch != null) {
      final proveedores = ref.read(proveedoresStreamProvider).value ?? [];
      final proveedor = proveedores.where((p) => p.id == _proveedorIdMatch).toList();
      if (proveedor.isNotEmpty) {
        documentoProveedor = proveedor.first.rtn;
        razonSocialProveedor = proveedor.first.razonSocial;
      }
    }

    // Esta pantalla se abre con un Navigator.push normal, así que su
    // subárbol queda FUERA del ProviderScope con el que pantalla_builder.dart
    // aísla el carrito de cada pestaña de Registrar Compra (ver
    // carritoCompraProvider.overrideWith ahí). Si acá adentro se llamara a
    // ref.read(carritoCompraProvider.notifier)..., terminaría escribiendo en
    // una instancia global distinta a la que la pestaña de verdad está
    // mirando -la tabla se quedaba vacía después de "Agregar a la compra",
    // aunque la lectura de la factura hubiera salido bien-. Por eso acá
    // solo se arman los datos y se devuelven con Navigator.pop: quien los
    // aplica al carrito es RegistrarCompraScreen, con su propio `ref` (ese
    // sí, correctamente scopeado), mismo patrón que ya usa "Agregar
    // Producto" con BuscarProductoCompraDialog.
    Navigator.of(context).pop(
      DatosFacturaConfirmados(
        idProveedor: _proveedorIdMatch,
        documentoProveedor: documentoProveedor,
        razonSocialProveedor: razonSocialProveedor,
        noFactura: _ctrlNoFactura.text.trim(),
        fecha: _fecha,
        condicion: _condicion,
        fechaVencimiento: _condicion == 'Credito' ? _fechaVencimiento : null,
        items: incluidas
            .map((f) => ItemCompraConfirmado(producto: f.producto!, cantidad: f.cantidad, precioCompra: f.precioUnitario, descuentoPorcentaje: f.descuentoPorcentaje))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text('Escanear Factura', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _extraccionHecha ? _vistaRevision() : _vistaCaptura(),
      ),
    );
  }

  // ---------- Captura de fotos ----------

  Widget _vistaCaptura() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tomá una foto por cada página de la factura, en orden. Cuando termines, tocá "Procesar factura".',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (_fotos.isNotEmpty)
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: _fotos.length,
                itemBuilder: (context, i) => _miniaturaFoto(i),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Todavía no agregaste ninguna foto', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          if (_errorProceso != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Text(_errorProceso!, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.red.shade700)),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _procesando ? null : _agregarFoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_fotos.isEmpty ? 'Tomar foto' : 'Agregar otra página', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A1A1A),
                side: const BorderSide(color: Color(0xFFB6BCC7)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_fotos.isEmpty || _procesando) ? null : _procesarFactura,
              icon: _procesando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _procesando ? 'Leyendo factura, puede tardar hasta 1 minuto...' : 'Procesar factura (${_fotos.length} foto${_fotos.length == 1 ? '' : 's'})',
                style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniaturaFoto(int index) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_fotos[index].bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withOpacity(0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _procesando ? null : () => _quitarFoto(index),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 16, color: Colors.white)),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(6)),
            child: Text('${index + 1}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ---------- Revisión de lo extraído ----------

  Widget _vistaRevision() {
    final productos = ref.watch(productosStreamProvider).value ?? [];
    final mapaProductos = {for (final p in productos) p.id: p};
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _tarjetaEncabezado(),
              const SizedBox(height: 14),
              Text('Productos leídos (${_filas.length})', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._filas.asMap().entries.map((e) => _tarjetaFila(e.key, e.value, mapaProductos)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -4))]),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirmarTodo,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: Text('Agregar a la compra', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaEncabezado() {
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Datos de la factura', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Revisá y corregí lo que haga falta.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          proveedoresAsync.when(
            data: (proveedores) {
              final actual = proveedores.where((p) => p.id == _proveedorIdMatch).toList();
              return DropdownButtonFormField<ProveedorModel>(
                initialValue: actual.isNotEmpty ? actual.first : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Proveedor${_proveedorIdMatch == null ? ' (no se encontró, elegí uno)' : ''}',
                  labelStyle: GoogleFonts.poppins(fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFFE8EAF0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: proveedores.map((p) => DropdownMenuItem(value: p, child: Text(p.razonSocial, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _proveedorIdMatch = v?.id),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => Text('Error cargando proveedores', style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrlNoFactura,
            style: GoogleFonts.poppins(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'No. Factura',
              labelStyle: GoogleFonts.poppins(fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFE8EAF0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(context: context, initialDate: _fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (fecha != null) setState(() => _fecha = fecha);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Text(formatoFecha.format(_fecha), style: GoogleFonts.poppins(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _condicion,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Condición',
                    labelStyle: GoogleFonts.poppins(fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFFE8EAF0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Contado', child: Text('Contado')),
                    DropdownMenuItem(value: 'Credito', child: Text('Crédito')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _condicion = v;
                      if (v == 'Credito') _fechaVencimiento ??= _fecha.add(const Duration(days: 30));
                    });
                  },
                ),
              ),
            ],
          ),
          if (_condicion == 'Credito') ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final fecha = await showDatePicker(context: context, initialDate: _fechaVencimiento ?? _fecha.add(const Duration(days: 30)), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (fecha != null) setState(() => _fechaVencimiento = fecha);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text('Vence: ${_fechaVencimiento != null ? formatoFecha.format(_fechaVencimiento!) : 'Sin definir'}', style: GoogleFonts.poppins(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaFila(int index, _FilaEscaneada fila, Map<String, ProductoModel> mapaProductos) {
    final emparejado = fila.producto != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fila.incluida ? const Color(0xFFC7CBD3) : Colors.grey.shade200),
      ),
      child: Opacity(
        opacity: fila.incluida ? 1 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: fila.incluida, onChanged: (v) => setState(() => fila.incluida = v ?? true), visualDensity: VisualDensity.compact),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fila.original.nombre + (fila.original.unidad != null ? ' (${fila.original.unidad})' : ''),
                        style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      if (fila.original.codigo != null)
                        Text('Código leído: ${fila.original.codigo}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (emparejado)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF1E9E5A)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(fila.producto!.nombre, style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF1E9E5A), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () => _buscarManual(fila),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                      child: Text('Cambiar', style: GoogleFonts.poppins(fontSize: 11.5)),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFFCE4E4), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline, size: 14, color: Color(0xFFC62828)),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Sin coincidencia en el inventario', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828)))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _buscarManual(fila),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFC62828),
                              side: const BorderSide(color: Color(0xFFC62828)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              minimumSize: const Size(0, 0),
                            ),
                            child: Text('Buscar existente', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _crearProductoNuevo(fila),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFC62828),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              minimumSize: const Size(0, 0),
                            ),
                            child: Text('Crear nuevo', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _campoConEtiqueta('Cantidad', fila.ctrlCantidad, fila.cantidad, (v) => setState(() => fila.cantidad = v)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _campoConEtiqueta('Precio unit.', fila.ctrlPrecio, fila.precioUnitario, (v) => setState(() => fila.precioUnitario = v), prefijo: 'L.', dosDecimales: true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _campoConEtiqueta('Desc. %', fila.ctrlDescuento, fila.descuentoPorcentaje, (v) => setState(() => fila.descuentoPorcentaje = v), sufijo: '%'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoConEtiqueta(String etiqueta, TextEditingController ctrl, double valorActual, void Function(double) alConfirmar, {String? sufijo, String? prefijo, bool dosDecimales = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.grey.shade500)),
        const SizedBox(height: 3),
        _campoNumerico(ctrl, alConfirmar, sufijo: sufijo, prefijo: prefijo, dosDecimales: dosDecimales),
      ],
    );
  }

  // Siempre abre el teclado numérico en pantalla (esta pantalla solo existe
  // en web móvil): sin cursor ni teclado nativo del navegador, igual que en
  // Registrar Venta/Compra. `readOnly` alcanza acá -sin necesitar el truco
  // de AbsorbPointer que usan esas otras pantallas- porque este campo nunca
  // tiene que servir para tipear con teclado físico, solo para abrir el
  // diálogo.
  Widget _campoNumerico(TextEditingController ctrl, void Function(double) alConfirmar, {String? sufijo, String? prefijo, bool dosDecimales = false}) {
    Future<void> abrir() async {
      final texto = await showDialog<String>(
        context: context,
        builder: (context) => TecladoNumericoDialog(titulo: sufijo == '%' ? 'Descuento (%)' : 'Valor', valorInicial: ctrl.text),
      );
      if (texto == null || !mounted) return;
      final valor = double.tryParse(texto);
      if (valor == null) return;
      setState(() {
        ctrl.text = dosDecimales ? valor.toStringAsFixed(2) : (valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toStringAsFixed(2));
        alConfirmar(valor);
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: abrir,
      child: TextField(
        controller: ctrl,
        readOnly: true,
        showCursor: false,
        enableInteractiveSelection: false,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 12.5),
        decoration: InputDecoration(
          suffixText: sufijo,
          prefixText: prefijo,
          prefixStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
          filled: true,
          fillColor: const Color(0xFFE8EAF0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
      ),
    );
  }
}
