import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/escaneo_remoto_repository.dart';
import '../../data/venta_en_espera_model.dart';
import '../../data/venta_export_service.dart';
import '../../data/venta_model.dart';
import '../../data/venta_repository.dart';
import '../../data/venta_ticket_escpos_service.dart';
import '../../providers/carrito_provider.dart';
import '../../../../core/providers/tabs_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../../core/services/impresora_red_service.dart';
import '../../../../core/utils/codigo_barras_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/buscar_producto_dialog.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/reembase_dialog.dart';
import '../widgets/cobrar_dialog.dart';
import '../widgets/ventas_en_espera_dialog.dart';
import '../widgets/ventas_pendientes_impresion_dialog.dart';
import '../widgets/teclado_numerico_dialog.dart';
import '../widgets/escanear_remoto_dialog.dart';
import '../../data/tipos_documento.dart';
import 'detalle_venta_screen.dart';

const _metodosPago = ['Efectivo', 'Tarjeta', 'Transferencia'];

class RegistrarVentaScreen extends ConsumerStatefulWidget {
  // Id de la pestaña donde vive esta pantalla (ver pantalla_builder.dart):
  // como se puede tener varias ventas abiertas en pestañas distintas al
  // mismo tiempo, y todas quedan montadas de fondo (IndexedStack), esto es
  // lo que le permite a los atajos de teclado (F10/F12) saber si esta es la
  // pestaña activa antes de responder, para no disparar en todas a la vez.
  final String? tabId;

  const RegistrarVentaScreen({super.key, this.tabId});

  @override
  ConsumerState<RegistrarVentaScreen> createState() => _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends ConsumerState<RegistrarVentaScreen> {
  final _nombreClienteController = TextEditingController();
  final _documentoClienteController = TextEditingController();
  final _ocController = TextEditingController();
  final _regExoneradoController = TextEditingController();
  final _regSagController = TextEditingController();
  final _descuentoGlobalController = TextEditingController();
  bool _datosExpandidos = false;
  bool _precioCarritoConIsv = true;

  final _servicioExport = VentaExportService();
  final _servicioTicketEscPos = VentaTicketEscPosService();
  final _servicioImpresoraRed = ImpresoraRedService();
  bool _guardando = false;

  // Campo de "escanear código de barras" directo en esta pantalla (sin
  // pasar por el modal de Buscar Producto): con autofocus permanente en
  // escritorio, para que un lector de código de barras físico (que se
  // comporta como un teclado y escribe el código + Enter) lo agregue solo
  // apenas se escanea algo, sin que el usuario tenga que tocar nada. En
  // móvil el ícono de cámara abre BarcodeScannerScreen y hace lo mismo.
  final _ctrlCodigoBarras = TextEditingController();
  final _focusCodigoBarras = FocusNode();

  // defaultTargetPlatform (a diferencia de kIsWeb solo, que no distingue
  // "celular entrando por el navegador" de "PC entrando por el navegador")
  // detecta el sistema operativo real del equipo. Se usa para decidir si
  // mostrar la barra de escanear/escribir código: en escritorio (Windows o
  // navegador de escritorio) esa vía visible no aplica -ahí el escaneo es
  // "Escanear con celular" (QR) o un lector físico, que funciona en
  // cualquier momento sin necesitar un campo visible-, así que solo se
  // muestra en el celular (APK o navegador móvil).
  bool get _esPlataformaMovil => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  // Escaneo remoto por celular (ver EscanearRemotoDialog/EscaneoRemotoScreen):
  // la sesión y su escucha viven acá, en el estado de la pantalla, no dentro
  // del diálogo del QR — así el celular puede seguir mandando códigos
  // mientras tenga la cámara abierta aunque el usuario cierre esa ventanita
  // en la PC (que solo sirve para volver a mostrar el QR cuando haga falta).
  final _escaneoRemoto = EscaneoRemotoRepository();
  String? _codigoEscaneoRemoto;
  bool _escaneoRemotoConectado = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _suscripcionEscaneoRemoto;
  StreamSubscription<bool>? _suscripcionConectadoEscaneo;

  // Controladores para la edición inline (cantidad / precio / descuento) de
  // cada fila de la tabla de productos. Se reindexan cuando cambia el total
  // de filas (agregar/quitar producto).
  final Map<int, TextEditingController> _ctrlCantidad = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};
  final Map<int, TextEditingController> _ctrlDescuento = {};
  final Map<int, TextEditingController> _ctrlDescripcion = {};
  // _focusInline y _confirmarInline respaldan a _campoInlineNumero: ver el
  // comentario junto a esa función para la explicación completa.
  final Map<String, FocusNode> _focusInline = {};
  final Map<String, VoidCallback> _confirmarInline = {};
  final Map<int, FocusNode> _focusDescripcion = {};
  final Map<int, Future<void> Function()> _confirmarDescripcion = {};
  int _conteoItemsControladores = -1;

  @override
  void initState() {
    super.initState();
    // Atajos a nivel de hardware (no de foco): así funcionan sin importar
    // qué campo de la pantalla tenga el foco en ese momento (a diferencia de
    // envolver el árbol en Focus/Shortcuts, que competiría con los
    // TextField de cantidad/precio/descripción ya presentes).
    HardwareKeyboard.instance.addHandler(_manejarAtajoTeclado);

    // En escritorio, cada vez que el foco queda en nada (el usuario tocó
    // afuera de un campo, o cerró un diálogo) se lo devuelve al campo de
    // código de barras invisible (ver _campoCodigoBarras): así un lector
    // físico funciona en cualquier momento, sin que el usuario tenga que
    // clickear nada primero. En el celular no hace falta (ahí el campo es
    // visible y el usuario lo toca a propósito).
    if (!_esPlataformaMovil) {
      FocusManager.instance.addListener(_alCambiarFocoGlobal);
    }

    // Si esta pestaña se abrió desde "Duplicar venta" o "Convertir a venta"
    // en Detalle de Venta (ver DetalleVentaScreen), acá está esperando la
    // venta de origen para precargar el carrito.
    final datosOrigen = ref.read(ventaParaCargarProvider);
    if (datosOrigen != null) {
      ref.read(ventaParaCargarProvider.notifier).limpiar();
      final ventaOrigen = datosOrigen.venta;
      ref.read(carritoVentaProvider.notifier).cargarDesdeVenta(ventaOrigen, forzarFactura: datosOrigen.forzarFactura);
      _nombreClienteController.text = ventaOrigen.nombreCliente;
      _documentoClienteController.text = ventaOrigen.documentoCliente;
      _ocController.text = ventaOrigen.oc;
      _regExoneradoController.text = ventaOrigen.regExonerado;
      _regSagController.text = ventaOrigen.regSag;
      _descuentoGlobalController.text = ventaOrigen.descuentoGlobal == 0 ? '' : _formatoCantidad(ventaOrigen.descuentoGlobal);
    }
  }

  void _alCambiarFocoGlobal() {
    if (!mounted || _esPlataformaMovil) return;
    // Con varias pestañas de Registrar Venta abiertas a la vez (quedan
    // todas montadas, ver AppShell/IndexedStack), este listener global
    // corre en cada una: sin este chequeo, todas competirían por el foco
    // cada vez que queda en nada, aunque estén en una pestaña de fondo que
    // ni se ve.
    if (!_esPestanaActiva()) return;
    if (FocusManager.instance.primaryFocus == null) {
      _focusCodigoBarras.requestFocus();
    }
  }

  bool _manejarAtajoTeclado(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted || _guardando) return false;
    if (!_esPestanaActiva()) return false;
    if (event.logicalKey == LogicalKeyboardKey.f10) {
      _agregarProductoDesdeBusqueda();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f12) {
      _confirmarVenta();
      return true;
    }
    return false;
  }

  // Sin tabId (pantalla usada fuera del sistema de pestañas) siempre
  // responde, como antes.
  bool _esPestanaActiva() {
    final tabId = widget.tabId;
    if (tabId == null) return true;
    final tabsState = ref.read(tabsProvider);
    if (tabsState.indiceActivo < 0 || tabsState.indiceActivo >= tabsState.tabs.length) return false;
    return tabsState.tabs[tabsState.indiceActivo].id == tabId;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_manejarAtajoTeclado);
    if (!_esPlataformaMovil) {
      FocusManager.instance.removeListener(_alCambiarFocoGlobal);
    }
    // Best-effort: no se espera a que termine (dispose no puede ser async),
    // pero cierra la sesión de escaneo remoto si quedó una activa al
    // abandonar esta pestaña de venta.
    _suscripcionEscaneoRemoto?.cancel();
    _suscripcionConectadoEscaneo?.cancel();
    final codigoEscaneo = _codigoEscaneoRemoto;
    if (codigoEscaneo != null) _escaneoRemoto.eliminarSesion(codigoEscaneo);
    _ctrlCodigoBarras.dispose();
    _focusCodigoBarras.dispose();
    _nombreClienteController.dispose();
    _documentoClienteController.dispose();
    _ocController.dispose();
    _regExoneradoController.dispose();
    _regSagController.dispose();
    _descuentoGlobalController.dispose();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    for (final c in _ctrlDescripcion.values) {
      c.dispose();
    }
    for (final f in _focusInline.values) {
      f.dispose();
    }
    for (final f in _focusDescripcion.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje), showCloseIcon: true));
  }

  Future<bool> _confirmarDialogo(String titulo, String mensaje) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(mensaje, style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sí', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  // ---------- Cliente ----------

  Future<void> _buscarCliente() async {
    final cliente = await showDialog(context: context, builder: (context) => const BuscarClienteDialog());
    if (cliente == null) return;
    final documento = (cliente as dynamic).dni ?? '';
    final nombre = cliente.nombreCompleto ?? '';
    // Antes solo se actualizaba el nombre visible en el campo "Cliente": el
    // RTN/documento sí quedaba guardado en el carrito (se usaba al grabar la
    // venta), pero el campo "RTN / Documento" en pantalla no se refrescaba,
    // así que parecía que elegir un cliente solo traía el nombre.
    setState(() {
      _nombreClienteController.text = nombre;
      _documentoClienteController.text = documento;
    });
    ref.read(carritoVentaProvider.notifier).establecerCliente(documento: documento, nombre: nombre);
  }

  // ---------- Producto: agregar directo desde el buscador ----------

  /// Categorías como servicios o pintura preparada pueden marcarse para no
  /// controlar existencia: en ese caso la existencia en 0 (o negativa) no
  /// debe bloquear ni pedir clave especial, ni disparar el reembasado.
  bool _categoriaControlaStock(String idCategoria) {
    final categorias = ref.read(categoriasStreamProvider).value ?? [];
    final coincidencias = categorias.where((c) => c.id == idCategoria).toList();
    return coincidencias.isEmpty ? true : coincidencias.first.controlaStock;
  }

  /// Calcula, para un tipo de reembasado y una cantidad a vender, cuánto hay
  /// que descontar del producto base y la cantidad final que queda en la
  /// línea de venta. Compartido entre "agregar producto sin existencia" y
  /// "aumentar cantidad sin existencia suficiente".
  ({double cantidadReembasar, double cantidadFinal})? _calcularReembase(String tipo, double nuevaCantidad) {
    switch (tipo) {
      case 'GalonACuarto':
        return (cantidadReembasar: 0.25 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'CubetaACuarto':
        return (cantidadReembasar: 0.05 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'CubetaAGalon':
        return (cantidadReembasar: 0.2 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      case 'GalonAMedioCuarto':
        if (nuevaCantidad == 0.5) {
          return (cantidadReembasar: 0.125, cantidadFinal: 1);
        }
        return (cantidadReembasar: 0.125 * nuevaCantidad, cantidadFinal: nuevaCantidad);
      default:
        return null;
    }
  }

  Future<void> _agregarProductoDesdeBusqueda() async {
    final resultado = await Navigator.of(context).push<ProductoConPrecio>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const BuscarProductoDialog()),
    );
    if (resultado == null || !mounted) return;
    await _procesarProductoSeleccionado(resultado);
  }

  // Confirma lo escrito/escaneado en el campo de código de barras de esta
  // pantalla (ver _campoCodigoBarras): agrega el producto directo, sin abrir
  // ningún modal. Se llama al presionar Enter (o el "submit" que manda un
  // lector de código de barras físico, que se comporta como un teclado).
  Future<void> _confirmarCodigoBarras() async {
    final codigo = _ctrlCodigoBarras.text.trim();
    _ctrlCodigoBarras.clear();
    if (codigo.isEmpty) return;
    await _procesarCodigoEscaneado(codigo);
    // Vuelve a enfocar el campo para que el próximo escaneo (de un lector
    // físico) se capture solo, sin que el usuario tenga que volver a
    // clickear el campo cada vez.
    if (mounted) _focusCodigoBarras.requestFocus();
  }

  Future<void> _escanearConCamara() async {
    final codigo = await escanearCodigoBarras(context);
    if (codigo == null || codigo.isEmpty || !mounted) return;
    await _procesarCodigoEscaneado(codigo);
  }

  // Compartido entre el buscador local (_agregarProductoDesdeBusqueda) y el
  // escáner remoto por celular (_procesarCodigoEscaneadoRemoto): decide si
  // hay que ofrecer reembasado por falta de existencia, o agregar directo.
  Future<void> _procesarProductoSeleccionado(ProductoConPrecio resultado) async {
    final producto = resultado.producto;
    final carrito = ref.read(carritoVentaProvider);
    final sinExistencia = producto.stock <= 0 && _categoriaControlaStock(producto.idCategoria);

    if (sinExistencia && carrito.esCotizacion) {
      _mostrarMensaje('Advertencia: "${producto.nombre}" no tiene existencia disponible, pero se agregará a la cotización.');
    } else if (sinExistencia) {
      final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasVenderSinStock);
      if (!mounted) return;
      if (!autorizado) return;

      final quiereReembasar = await _confirmarDialogo(
        'Reembasado',
        'El producto "${producto.nombre}" no tiene existencia disponible.\n¿Desea realizar un reembasado?',
      );
      if (!mounted) return;
      if (quiereReembasar) {
        final resultadoReembase = await showDialog<ReembaseResultado>(context: context, builder: (context) => const ReembaseDialog());
        if (resultadoReembase == null || !mounted) return;

        final calculo = _calcularReembase(resultadoReembase.tipo, 1);
        if (calculo == null) {
          _mostrarMensaje('Opción de reembasado inválida');
          return;
        }
        final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
        final ok = await ref.read(productoRepositoryProvider).descontarStock(
              id: resultadoReembase.productoBase.id,
              cantidad: calculo.cantidadReembasar,
              usuario: usuario,
              motivo: 'Reembasado para venta de "${producto.nombre}"',
            );
        if (!mounted) return;
        if (!ok) {
          _mostrarMensaje('No se pudo descontar el stock del producto base');
          return;
        }
        ref.read(carritoVentaProvider.notifier).agregarProductoDirecto(producto, precioSeleccionado: resultado.precio, reembasado: true);
        return;
      }
      // Si dice que no, se ignora la falta de existencia y se agrega igual
      // (sin marcar reembasado): al vender no baja de 0 (ver venta_repository).
    }
    if (!mounted) return;
    ref.read(carritoVentaProvider.notifier).agregarProductoDirecto(producto, precioSeleccionado: resultado.precio);
  }

  /// Busca un producto por código exacto (código de barras o código interno)
  /// y lo agrega directo al carrito, con el mismo flujo de siempre (incluido
  /// el aviso de reembasado si no hay existencia) — sin pasar por el modal
  /// de Buscar Producto. Se llama tanto cuando el celular (ver
  /// EscanearRemotoDialog) manda un código escaneado, como cuando se escanea
  /// localmente en esta misma pantalla (campo de código de barras o cámara,
  /// ver _campoCodigoBarras).
  Future<void> _procesarCodigoEscaneado(String codigo) async {
    if (!mounted) return;
    final texto = codigo.trim();
    // Por si el stream de productos todavía no trajo el primer valor (poco
    // común, pero puede pasar con internet lento): espera a que haya datos
    // antes de buscar, para no buscar contra una lista vacía y fallar en
    // silencio (el código quedaría como "no encontrado" sin serlo).
    if (ref.read(productosStreamProvider).value == null) {
      try {
        await ref.read(productosStreamProvider.future);
      } catch (_) {}
      if (!mounted) return;
    }
    final productos = ref.read(productosStreamProvider).value ?? [];
    bool coincide(ProductoModel p, String t) => p.estado && (p.codigoBarras.trim() == t || p.codigo.trim() == t);
    var coincidencias = productos.where((p) => coincide(p, texto)).toList();
    if (coincidencias.isEmpty) {
      // Ver variantesCodigoBarras: corrige tanto el código leído al revés
      // (algunos celulares) como el "0" que iPhone agrega al principio de
      // los códigos UPC-A (Android no lo agrega).
      for (final variante in variantesCodigoBarras(texto)) {
        coincidencias = productos.where((p) => coincide(p, variante)).toList();
        if (coincidencias.isNotEmpty) break;
      }
    }
    if (coincidencias.isEmpty) {
      _mostrarMensaje('Código escaneado no encontrado: $texto');
      return;
    }
    final producto = coincidencias.first;
    final precio = _primerPrecioDisponible(producto);
    if (precio == null) {
      _mostrarMensaje('"${producto.nombre}" no tiene un precio configurado');
      return;
    }
    await _procesarProductoSeleccionado(ProductoConPrecio(producto: producto, precio: precio, nivelPrecio: 1));
  }

  double? _primerPrecioDisponible(ProductoModel p) {
    for (final valor in [p.precioVenta, p.precioVenta2, p.precioVenta3]) {
      if (valor > 0) return valor;
    }
    return null;
  }

  /// Crea la sesión de escaneo remoto la primera vez que hace falta y deja
  /// la escucha corriendo en el estado de la pantalla (no en el diálogo del
  /// QR), para que el celular pueda seguir mandando códigos aunque el
  /// usuario cierre esa ventanita en la PC. Si ya había una sesión activa
  /// (el usuario vuelve a tocar el botón para ver el QR de nuevo), reusa el
  /// mismo código en vez de crear uno nuevo.
  Future<String> _asegurarSesionEscaneoRemoto() async {
    final codigoActual = _codigoEscaneoRemoto;
    if (codigoActual != null) return codigoActual;
    final codigo = _escaneoRemoto.generarCodigo();
    await _escaneoRemoto.crearSesion(codigo);
    _codigoEscaneoRemoto = codigo;
    _escaneoRemotoConectado = false;
    _suscripcionEscaneoRemoto = _escaneoRemoto.escucharEventos(codigo).listen((snap) {
      for (final cambio in snap.docChanges) {
        if (cambio.type != DocumentChangeType.added) continue;
        final codigoEscaneado = cambio.doc.data()?['codigo'] as String?;
        if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
          _procesarCodigoEscaneado(codigoEscaneado);
        }
      }
    });
    // El celular marca "conectado" apenas llega a la cámara (ver
    // EscaneoRemotoScreen): con esto la pantalla sabe en vivo si ya hay
    // alguien escaneando, para decidir qué mostrar al tocar el botón de
    // nuevo (el QR otra vez, o el menú de "escaneo activo").
    _suscripcionConectadoEscaneo = _escaneoRemoto.escucharConectado(codigo).listen((conectado) {
      if (mounted) setState(() => _escaneoRemotoConectado = conectado);
    });
    return codigo;
  }

  Future<void> _finalizarEscaneoRemoto() async {
    final codigo = _codigoEscaneoRemoto;
    if (codigo == null) return;
    await _suscripcionEscaneoRemoto?.cancel();
    await _suscripcionConectadoEscaneo?.cancel();
    _suscripcionEscaneoRemoto = null;
    _suscripcionConectadoEscaneo = null;
    _codigoEscaneoRemoto = null;
    if (mounted) setState(() => _escaneoRemotoConectado = false);
    await _escaneoRemoto.eliminarSesion(codigo);
  }

  /// Si ya hay un celular conectado y escaneando, tocar el botón de nuevo no
  /// vuelve a mostrar el QR (no hace falta, ya está emparejado): muestra un
  /// menú para terminar el escaneo o arrancar de cero con otro celular. Si
  /// todavía no se conectó nadie (o no hay sesión), muestra el QR, que se
  /// cierra solo apenas el celular se empareje.
  Future<void> _abrirEscaneoRemoto() async {
    if (_codigoEscaneoRemoto != null && _escaneoRemotoConectado) {
      final codigoActivo = _codigoEscaneoRemoto!;
      await showDialog(
        context: context,
        builder: (context) => EscaneoActivoDialog(
          eventos: _escaneoRemoto.escucharEventos(codigoActivo),
          alFinalizar: () async {
            Navigator.pop(context);
            await _finalizarEscaneoRemoto();
          },
          alEscanearOtro: () async {
            Navigator.pop(context);
            await _finalizarEscaneoRemoto();
            await _abrirEscaneoRemoto();
          },
        ),
      );
      return;
    }

    final codigo = await _asegurarSesionEscaneoRemoto();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => EscanearRemotoDialog(
        codigo: codigo,
        eventos: _escaneoRemoto.escucharEventos(codigo),
        conectado: _escaneoRemoto.escucharConectado(codigo),
      ),
    );
  }

  void _quitarItem(int index) {
    ref.read(carritoVentaProvider.notifier).quitarItem(index);
  }

  // Cuando el usuario cancela o rechaza la operación (reembasado, opción
  // inválida, etc.) hay que devolver el campo de cantidad a su valor real;
  // si no, el texto tipeado se queda en el campo y el próximo toque afuera
  // (onTapOutside) vuelve a disparar la misma confirmación una y otra vez.
  void _revertirCantidad(int index) {
    final carrito = ref.read(carritoVentaProvider);
    if (index >= carrito.items.length) return;
    _ctrlCantidad[index]?.text = _formatoCantidad(carrito.items[index].cantidad);
  }

  Future<void> _actualizarCantidad(int index, double nuevaCantidad) async {
    if (nuevaCantidad <= 0) {
      _mostrarMensaje('La cantidad debe ser mayor a 0');
      _revertirCantidad(index);
      return;
    }
    final carrito = ref.read(carritoVentaProvider);
    if (index >= carrito.items.length) return;
    final item = carrito.items[index];

    if (!_categoriaControlaStock(item.idCategoria)) {
      ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
      return;
    }

    final productos = ref.read(productosStreamProvider).value ?? [];
    final coincidencias = productos.where((p) => p.id == item.idProducto).toList();
    final stockDisponible = coincidencias.isNotEmpty ? coincidencias.first.stock : 0.0;

    if (stockDisponible < nuevaCantidad && !carrito.esCotizacion) {
      final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasVenderSinStock);
      if (!mounted) return;
      if (!autorizado) {
        _revertirCantidad(index);
        return;
      }

      final quiereReembasar = await _confirmarDialogo(
        'Reembasado',
        'El producto "${item.nombreProducto}" no tiene suficiente stock para $nuevaCantidad unidad(es).\n¿Desea realizar un reembasado?',
      );
      if (!mounted) return;
      if (!quiereReembasar) {
        // A diferencia de un valor inválido, acá el usuario decidió a
        // propósito seguir sin reembasar: se deja la cantidad tal como la
        // puso (al vender no baja de 0, ver venta_repository).
        ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
        return;
      }

      final resultado = await showDialog<ReembaseResultado>(context: context, builder: (context) => const ReembaseDialog());
      if (resultado == null) {
        _revertirCantidad(index);
        return;
      }

      final calculo = _calcularReembase(resultado.tipo, nuevaCantidad);
      if (calculo == null) {
        _mostrarMensaje('Opción de reembasado inválida');
        _revertirCantidad(index);
        return;
      }

      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      final ok = await ref.read(productoRepositoryProvider).descontarStock(
            id: resultado.productoBase.id,
            cantidad: calculo.cantidadReembasar,
            usuario: usuario,
            motivo: 'Reembasado para venta de "${item.nombreProducto}"',
          );
      if (!ok) {
        _mostrarMensaje('No se pudo descontar el stock del producto base');
        _revertirCantidad(index);
        return;
      }
      ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: calculo.cantidadFinal, reembasado: true);
      return;
    } else if (stockDisponible < nuevaCantidad && carrito.esCotizacion) {
      _mostrarMensaje('Advertencia: "${item.nombreProducto}" no tiene stock suficiente, pero se actualizará en la cotización.');
    }

    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
  }

  Future<void> _actualizarPrecio(int index, double nuevoPrecioConIsv) async {
    if (nuevoPrecioConIsv < 0) {
      _mostrarMensaje('Precio inválido');
      return;
    }
    final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasCambiarPrecio);
    if (!mounted) return;
    if (!autorizado) {
      // Revierte el campo al precio actual (en la unidad que se esté
      // mostrando): el usuario ya había escrito el nuevo valor en el
      // TextField antes de que se pidiera la clave.
      final carrito = ref.read(carritoVentaProvider);
      if (index < carrito.items.length) {
        final precioBase = carrito.items[index].precioVenta;
        final valorMostrado = _precioCarritoConIsv ? redondearMoneda(precioBase * 1.15) : precioBase;
        _ctrlPrecio[index]?.text = valorMostrado.toStringAsFixed(2);
      }
      return;
    }
    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, precioConIsv: nuevoPrecioConIsv);
  }

  Future<void> _actualizarPrecioSinIsv(int index, double nuevoPrecioSinIsv) {
    return _actualizarPrecio(index, redondearMoneda(nuevoPrecioSinIsv * 1.15));
  }

  void _alternarVistaPrecioCarrito(bool conIsv) {
    final carrito = ref.read(carritoVentaProvider);
    setState(() {
      _precioCarritoConIsv = conIsv;
      for (var i = 0; i < carrito.items.length; i++) {
        final ctrl = _ctrlPrecio[i];
        if (ctrl == null) continue;
        final base = carrito.items[i].precioVenta;
        final valor = conIsv ? redondearMoneda(base * 1.15) : base;
        ctrl.text = valor.toStringAsFixed(2);
      }
    });
  }

  void _actualizarDescuentoLinea(int index, double descuento) {
    if (descuento < 0 || descuento > 100) {
      _mostrarMensaje('El descuento debe estar entre 0 y 100');
      return;
    }
    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, descuentoPorcentaje: descuento);
  }

  double _subtotalConIsv(dynamic item) {
    final precioConIsv = redondearMoneda(item.precioVenta * 1.15);
    return redondearMoneda(precioConIsv * item.cantidad * (1 - item.descuentoPorcentaje / 100));
  }

  double _subtotalSinIsv(dynamic item) {
    return redondearMoneda((item.precioVenta as double) * item.cantidad * (1 - item.descuentoPorcentaje / 100));
  }

  double _importeMostrado(dynamic item) => _precioCarritoConIsv ? _subtotalConIsv(item) : _subtotalSinIsv(item);

  // ---------- Ventas en espera ----------

  Future<void> _guardarEnEspera() async {
    final carrito = ref.read(carritoVentaProvider);
    if (carrito.items.isEmpty) {
      _mostrarMensaje('No hay productos para guardar en espera.');
      return;
    }
    final repo = ref.read(ventaRepositoryProvider);
    final sesion = VentaEnEsperaModel(
      id: carrito.idEnEspera ?? '',
      fecha: DateTime.now(),
      tipoDocumento: carrito.tipoDocumento,
      condicion: carrito.condicion,
      metodoPago: carrito.metodoPago,
      documentoCliente: carrito.documentoCliente,
      nombreCliente: _nombreClienteController.text.trim(),
      fechaVencimiento: carrito.fechaVencimiento,
      oc: carrito.oc,
      regExonerado: carrito.regExonerado,
      regSag: carrito.regSag,
      descuentoGlobal: carrito.descuentoGlobalPorcentaje,
      items: carrito.items,
    );

    if (carrito.idEnEspera != null) {
      await repo.actualizarVentaEnEspera(carrito.idEnEspera!, sesion);
      _mostrarMensaje('Venta en espera actualizada.');
    } else {
      await repo.guardarVentaEnEspera(sesion);
      _mostrarMensaje('Venta guardada en espera.');
    }
    _limpiarTodo();
  }

  void _verPendientesImpresion() {
    showDialog(context: context, builder: (context) => const VentasPendientesImpresionDialog());
  }

  Future<void> _verEnEspera() async {
    final sesion = await showDialog<VentaEnEsperaModel>(context: context, builder: (context) => const VentasEnEsperaDialog());
    if (sesion == null || !mounted) return;
    ref.read(carritoVentaProvider.notifier).cargarSesion(sesion);
    setState(() {
      _nombreClienteController.text = sesion.nombreCliente;
      _documentoClienteController.text = sesion.documentoCliente;
      _ocController.text = sesion.oc;
      _regExoneradoController.text = sesion.regExonerado;
      _regSagController.text = sesion.regSag;
      _descuentoGlobalController.text = sesion.descuentoGlobal == 0 ? '' : _formatoCantidad(sesion.descuentoGlobal);
    });
  }

  void _limpiarTodo() {
    ref.read(carritoVentaProvider.notifier).limpiar();
    _nombreClienteController.clear();
    _documentoClienteController.clear();
    _ocController.clear();
    _regExoneradoController.clear();
    _regSagController.clear();
    _descuentoGlobalController.clear();
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    for (final c in _ctrlDescuento.values) {
      c.dispose();
    }
    _ctrlCantidad.clear();
    _ctrlPrecio.clear();
    _ctrlDescuento.clear();
    for (final c in _ctrlDescripcion.values) {
      c.dispose();
    }
    _ctrlDescripcion.clear();
    for (final f in _focusInline.values) {
      f.dispose();
    }
    _focusInline.clear();
    _confirmarInline.clear();
    for (final f in _focusDescripcion.values) {
      f.dispose();
    }
    _focusDescripcion.clear();
    _confirmarDescripcion.clear();
    _conteoItemsControladores = 0;
  }

  Future<void> _confirmarLimpiar() async {
    final carrito = ref.read(carritoVentaProvider);
    final hayAlgoQuePerder = carrito.items.isNotEmpty || _nombreClienteController.text.trim().isNotEmpty;
    if (hayAlgoQuePerder) {
      final continuar = await _confirmarDialogo('Limpiar venta', '¿Seguro que querés borrar todos los productos y datos ingresados en esta venta?');
      if (!continuar) return;
    }
    _limpiarTodo();
  }

  // ---------- Confirmar venta ----------

  String get _textoBoton {
    final tipo = ref.watch(carritoVentaProvider).tipoDocumento;
    switch (tipo) {
      case 'Cotizacion':
        return 'Crear Cotización';
      case 'VentaSinFacturar':
        return 'Registrar Venta';
      default:
        return 'Crear Venta';
    }
  }

  Future<void> _confirmarVenta() async {
    final carrito = ref.read(carritoVentaProvider);
    if (carrito.items.isEmpty) {
      _mostrarMensaje('Debe ingresar productos en la venta');
      return;
    }

    var montoPago = 0.0;
    var montoCambio = 0.0;
    final esCotizacion = carrito.esCotizacion;
    NegocioModel? negocio;
    // Se captura el repositorio ahora (con `ref` todavía válido) en vez de
    // llamar `ref.read(...)` de nuevo dentro del guardado en segundo plano:
    // si el cajero cierra esta pestaña de Ventas mientras esa venta se
    // sigue guardando sola, `ref` ya no se puede usar, pero el repositorio
    // (que no depende de esta pantalla) sigue funcionando igual.
    final ventaRepo = ref.read(ventaRepositoryProvider);

    // Esta primera parte sí se espera: son cosas que necesitan una
    // respuesta del cajero (el diálogo de cobro) o una validación previa
    // (fecha límite), no la red. Mientras tanto el botón queda bloqueado
    // para no disparar la venta dos veces.
    setState(() => _guardando = true);
    try {
      if (!esCotizacion) {
        if (carrito.condicion == 'Credito') {
          montoPago = 0;
          montoCambio = 0;
        } else if (carrito.metodoPago == 'Efectivo') {
          final resultado = await showDialog<CobrarResultado>(context: context, builder: (context) => CobrarDialog(total: carrito.totalAPagar));
          if (resultado == null) return;
          montoPago = resultado.pagoCon;
          montoCambio = resultado.cambio;
        }

        negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
        if (!mounted) return;
        if (carrito.tipoDocumento == 'Factura' || carrito.tipoDocumento == 'Boleta') {
          final continuar = await _validarFechaLimite(negocio);
          if (!continuar) return;
        }
      }
    } catch (e) {
      _mostrarMensaje('Error: $e');
      return;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }

    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
    final categorias = ref.read(categoriasStreamProvider).value ?? [];
    final categoriasSinControlStock = categorias.where((c) => !c.controlaStock).map((c) => c.id).toSet();
    final esFacturable = carrito.tipoDocumento == 'Factura' || carrito.tipoDocumento == 'Boleta';
    final negocioFinal = negocio;
    // Hay que capturar esto ANTES de _limpiarTodo(): ese método vacía el
    // controlador de texto, así que leerlo después ya daría vacío.
    final nombreCliente = _nombreClienteController.text.trim().isEmpty ? 'CONSUMIDOR FINAL' : _nombreClienteController.text.trim();

    // A partir de acá la pantalla avanza al toque -se limpia el carrito y
    // queda lista para la próxima venta- SIN esperar la confirmación real
    // de Firestore: pediste que sea así aunque haya riesgo. El guardado de
    // verdad sigue solo, en segundo plano. Si falla (sin internet, error
    // del servidor, etc.) se avisa de inmediato y bien visible, porque en
    // ese caso la venta NO quedó registrada — con opción de reintentar sin
    // tener que cargar todo de nuevo.
    _limpiarTodo();

    unawaited(_guardarVentaEnSegundoPlano(
      ventaRepo: ventaRepo,
      carrito: carrito,
      esCotizacion: esCotizacion,
      esFacturable: esFacturable,
      nombreCliente: nombreCliente,
      montoPago: montoPago,
      montoCambio: montoCambio,
      usuario: usuario,
      categoriasSinControlStock: categoriasSinControlStock,
      negocio: negocioFinal,
    ));
  }

  Future<void> _guardarVentaEnSegundoPlano({
    required VentaRepository ventaRepo,
    required CarritoVentaState carrito,
    required bool esCotizacion,
    required bool esFacturable,
    required String nombreCliente,
    required double montoPago,
    required double montoCambio,
    required String usuario,
    required Set<String> categoriasSinControlStock,
    required NegocioModel? negocio,
  }) async {
    try {
      final venta = await ventaRepo.registrarVenta(
            tipoDocumento: carrito.tipoDocumento,
            condicion: esCotizacion ? 'Contado' : carrito.condicion,
            metodoPago: esCotizacion ? 'N/A' : (carrito.condicion == 'Credito' ? 'N/A' : carrito.metodoPago),
            documentoCliente: carrito.documentoCliente.trim().isEmpty ? 'N/A' : carrito.documentoCliente.trim(),
            nombreCliente: nombreCliente,
            fechaRegistro: carrito.fecha,
            fechaVencimiento: (!esCotizacion && carrito.condicion == 'Credito') ? carrito.fechaVencimiento : null,
            oc: carrito.oc,
            regExonerado: carrito.regExonerado,
            regSag: carrito.regSag,
            descuentoGlobal: carrito.descuentoGlobalPorcentaje,
            items: carrito.items,
            montoPago: montoPago,
            montoCambio: montoCambio,
            subtotal: carrito.subtotal,
            impuesto: carrito.impuesto,
            totalAPagar: carrito.totalAPagar,
            usuario: usuario,
            categoriasSinControlStock: categoriasSinControlStock,
          );

      if (carrito.idEnEspera != null) {
        unawaited(ventaRepo.eliminarVentaEnEspera(carrito.idEnEspera!));
      }

      if (esFacturable) {
        unawaited(_imprimirEnSegundoPlano(venta));
        if (negocio != null) _avisarSiRangoSuperado(negocio, venta);
      } else {
        _mostrarMensaje('${tiposDocumento[venta.tipoDocumento]} generada: ${venta.numeroDocumento}');
      }
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is TimeoutException
          ? 'No se pudo guardar: se agotó el tiempo de espera. Revisá la conexión a internet.'
          : 'No se pudo guardar: $e';
      // Esta venta NO quedó registrada en la base de datos: aviso fuerte y
      // persistente (no se cierra solo) con la opción de reintentar sin
      // tener que volver a cargar todo.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠ $mensaje', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 12),
          showCloseIcon: true,
          closeIconColor: Colors.white,
          action: SnackBarAction(
            label: 'Reintentar',
            textColor: Colors.white,
            onPressed: () => _guardarVentaEnSegundoPlano(
              ventaRepo: ventaRepo,
              carrito: carrito,
              esCotizacion: esCotizacion,
              esFacturable: esFacturable,
              nombreCliente: nombreCliente,
              montoPago: montoPago,
              montoCambio: montoCambio,
              usuario: usuario,
              categoriasSinControlStock: categoriasSinControlStock,
              negocio: negocio,
            ),
          ),
        ),
      );
    }
  }

  // Wrapper para llamar a _manejarImpresion sin bloquear _confirmarVenta
  // (se llama con `unawaited`, ver ahí). También necesita traer la
  // configuración del negocio, que normalmente ya está en caché (se
  // precarga al iniciar sesión) y resuelve casi al instante, pero por las
  // dudas tampoco se espera desde _confirmarVenta.
  Future<void> _imprimirEnSegundoPlano(VentaModel venta) async {
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    await _manejarImpresion(venta, negocio);
  }

  // Decide cómo imprimir (o no) la venta recién registrada, según
  // negocio.modoImpresion y la plataforma:
  // - En el APK de Android: sin importar el modo configurado (que está
  //   pensado para escritorio, donde si hay "modo directo" es porque hay una
  //   impresora fija conectada), se pregunta con un diálogo simple, porque en
  //   el celular lo más probable es que no haya ninguna impresora a mano.
  // - 'preguntar' (default, resto de plataformas): diálogo de vista previa.
  // - 'directo' en desktop: imprime sin diálogo en la impresora del SO
  //   configurada (paquete `printing`).
  // - 'directo' en iOS: se manda el ticket por ESC/POS a la impresora de red
  //   configurada (no hay forma de listar impresoras del SO en móvil). En
  //   Android e iOS, si esto no funciona (ver _imprimirEscPosRed), se le
  //   pide a la PC principal que imprima ella sola antes de dejarla
  //   pendiente sin más.
  // - 'directo' en web: no se puede imprimir sin diálogo desde el
  //   navegador, así que se abre su diálogo de impresión directo (sin
  //   nuestra propia vista previa intermedia).
  // En cualquier caso, si no hay impresora configurada o falla el intento,
  // no se bloquea nada: la venta ya quedó guardada. En móvil además se
  // marca `pendienteImpresion` para poder reimprimirla después.
  Future<void> _manejarImpresion(VentaModel venta, NegocioModel negocio) async {
    if (!kIsWeb && Platform.isAndroid) {
      await _manejarImpresionAndroid(venta, negocio);
      return;
    }

    if (negocio.modoImpresion != ModoImpresion.directo) {
      final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Vista previa · ${venta.numeroDocumento}',
          nombreArchivo: 'venta_${venta.numeroDocumento}.pdf',
          generarPdf: () => _servicioExport.generarPdfFactura(venta, negocio),
          generarPdfConFormato: (formato) => _servicioExport.generarPdfFactura(venta, negocio, formatoImpresora: formato),
          impresora: impresora,
        ),
      );
      return;
    }

    // defaultTargetPlatform (a diferencia de Platform.isAndroid, que en web
    // no sirve de nada) sí detecta el sistema operativo real del equipo
    // aunque se esté usando desde el navegador: hace falta para distinguir
    // "celular entrando por el navegador" de "PC entrando por el navegador".
    final esMovil = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

    if (kIsWeb && esMovil) {
      // Desde el navegador del celular no hay forma de mandar el ticket a
      // una impresora térmica: los navegadors no dan acceso a sockets
      // crudos (lo que usa la impresora de red) ni, para una impresora
      // térmica típica, hay un diálogo de impresión del sistema operativo
      // que la alcance. Antes de resignarse a dejarla pendiente, se
      // consulta si la PC principal está conectada en ese momento (envía un
      // latido periódico, ver PresenciaImpresionRepository): si lo está, se
      // le pide que la imprima ella sola apenas la detecte (sin que nadie
      // tenga que confirmar nada ahí). Si no está conectada, o la consulta
      // falla por falta de red, se cae exactamente al comportamiento de
      // siempre: queda pendiente para reimprimir después a mano.
      await ref.read(ventaRepositoryProvider).marcarPendienteImpresion(venta.id, true);
      final pcConectada = await ref.read(presenciaImpresionRepositoryProvider).estaConectada();
      if (pcConectada) {
        await ref.read(ventaRepositoryProvider).marcarSolicitudImpresionEnVivo(venta.id, true);
        _mostrarMensaje('Se envió la orden de impresión a la caja principal');
      } else {
        _mostrarMensaje('No se puede imprimir directo desde el navegador del celular: la venta quedó pendiente de impresión');
      }
      return;
    }

    if (kIsWeb) {
      // Entre que se confirma la venta y se arma el PDF pasan unos segundos
      // en los que no aparece nada en pantalla (la ventana de impresión del
      // navegador tarda en salir), lo que da la sensación de que se quedó
      // pegado. Este aviso se cierra apenas esté listo, sea que la ventana
      // de impresión abrió bien o que falló.
      ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? preparando;
      if (mounted) {
        preparando = ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparando impresión…'), duration: Duration(seconds: 30)),
        );
      }
      try {
        await Printing.layoutPdf(onLayout: (formato) => _servicioExport.generarPdfFactura(venta, negocio), name: 'venta_${venta.numeroDocumento}.pdf');
        preparando?.close();
      } catch (_) {
        preparando?.close();
        _mostrarMensaje('No se pudo imprimir. La venta se guardó de todas formas.');
      }
      return;
    }

    if (Platform.isIOS) {
      await _imprimirEscPosRed(venta, negocio);
      return;
    }

    // Desktop (Windows/macOS/Linux).
    if (negocio.impresoraTermicaUrl.isEmpty) {
      _mostrarMensaje('No hay impresora configurada, la venta se guardó sin imprimir');
      return;
    }
    try {
      final impresora = Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
      await Printing.directPrintPdf(printer: impresora, onLayout: (formato) => _servicioExport.generarPdfFactura(venta, negocio, formatoImpresora: formato));
    } catch (_) {
      _mostrarMensaje('No se pudo imprimir en la impresora configurada');
    }
  }

  // En el APK de Android casi nunca hay una impresora térmica a mano (a
  // diferencia de escritorio, donde "modo directo" solo tiene sentido si hay
  // una impresora fija conectada). En vez de intentar imprimir a ciegas por
  // red y fallar en silencio, o abrir la vista previa completa del PDF, se
  // pregunta rápido con un diálogo simple de dos botones.
  Future<void> _manejarImpresionAndroid(VentaModel venta, NegocioModel negocio) async {
    if (!mounted) return;
    final opcion = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Venta ${venta.numeroDocumento} registrada', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text('¿Qué querés hacer con el ticket?', style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'pendiente'),
            child: Text('Dejar pendiente', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(context, 'imprimir'),
            child: Text('Imprimir', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (opcion == 'imprimir') {
      await _imprimirEscPosRed(venta, negocio);
    } else {
      await ref.read(ventaRepositoryProvider).marcarPendienteImpresion(venta.id, true);
    }
  }

  // Intenta imprimir por ESC/POS de red (Android/iOS). Si no hay impresora
  // de red configurada en este equipo, o el intento falla -lo más común: el
  // celular no está conectado a la misma red que la impresora-, antes de
  // resignarse a dejarla pendiente se prueba pedirle a la PC principal que
  // la imprima ella sola, igual que desde el navegador del celular (ver
  // _manejarImpresion, rama kIsWeb && esMovil): en el celular casi nunca se
  // va a poder llegar de verdad hasta la impresora física, así que este
  // respaldo es el camino más común, no la excepción.
  Future<void> _imprimirEscPosRed(VentaModel venta, NegocioModel negocio) async {
    if (negocio.impresoraRedIp.isNotEmpty) {
      final bytes = await _servicioTicketEscPos.generarTicket(venta, negocio);
      final ok = await _servicioImpresoraRed.imprimir(ip: negocio.impresoraRedIp, puerto: negocio.impresoraRedPuerto, bytes: bytes);
      if (ok) return;
    }
    await ref.read(ventaRepositoryProvider).marcarPendienteImpresion(venta.id, true);
    final pcConectada = await ref.read(presenciaImpresionRepositoryProvider).estaConectada();
    if (pcConectada) {
      await ref.read(ventaRepositoryProvider).marcarSolicitudImpresionEnVivo(venta.id, true);
      _mostrarMensaje('Se envió la orden de impresión a la caja principal');
    } else {
      _mostrarMensaje('No se pudo imprimir: la venta quedó pendiente de impresión');
    }
  }

  Future<bool> _validarFechaLimite(NegocioModel negocio) async {
    if (negocio.fechaLimiteEmision != null) {
      final hoy = DateTime.now();
      final limite = negocio.fechaLimiteEmision!;
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
      final limiteSinHora = DateTime(limite.year, limite.month, limite.day);
      if (!hoySinHora.isBefore(limiteSinHora)) {
        final continuar = await _confirmarDialogo(
          '¡Alerta!',
          'Se ha alcanzado la fecha límite de emisión. ¿Desea continuar con la venta?',
        );
        if (!continuar) return false;
      }
    }
    return true;
  }

  // Antes esto se preguntaba ANTES de guardar, con una lectura extra a
  // Firestore (obtenerProximoCorrelativo) solo para saber si avisar — eso
  // sumaba una vuelta de red completa a cada factura. Como de todas formas
  // nunca bloqueaba la venta (con confirmar "Sí" igual se guardaba), avisar
  // DESPUÉS de guardar, ya con el número real asignado, informa exactamente
  // lo mismo sin ninguna lectura extra ni demora.
  void _avisarSiRangoSuperado(NegocioModel negocio, VentaModel venta) {
    final rangoHasta = int.tryParse(negocio.rangoHasta) ?? 0;
    if (rangoHasta <= 0) return;
    final numero = int.tryParse(venta.numeroDocumento) ?? 0;
    if (numero > rangoHasta) {
      _mostrarMensaje('Atención: se superó el rango autorizado para facturas (No. ${venta.numeroDocumento})');
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final carrito = ref.watch(carritoVentaProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          // La tabla de productos debe dominar la pantalla, pero se le da una
          // altura fija generosa (no Expanded) para que nunca desaparezca si
          // el encabezado ocupa más espacio del previsto; si el contenido no
          // cabe completo, la pantalla se vuelve desplazable en vez de
          // recortarse en silencio.
          final altoTabla = (constraints.maxHeight * 0.58).clamp(360.0, 1000.0);
          return SingleChildScrollView(
            padding: EdgeInsets.all(esMovil ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 14),
                _tarjetaDatosVenta(carrito, esMovil),
                const SizedBox(height: 14),
                esMovil
                    ? _tarjetaCarritoGrande(carrito, esMovil)
                    : SizedBox(height: altoTabla, child: _tarjetaCarritoGrande(carrito, esMovil)),
                const SizedBox(height: 14),
                _tarjetaTotales(carrito, esMovil),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text('Registrar Venta', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        OutlinedButton.icon(
          onPressed: _confirmarLimpiar,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text('Limpiar Venta', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _guardarEnEspera,
          icon: const Icon(Icons.pause_circle_outline, size: 18),
          label: Text('Guardar en Espera', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _verEnEspera,
          icon: const Icon(Icons.list_alt_outlined, size: 18),
          label: Text('Ver en Espera', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        OutlinedButton.icon(
          onPressed: _verDetalleVenta,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text('Ver Detalle', style: GoogleFonts.poppins(fontSize: 13)),
          style: _estiloBotonSecundario(),
        ),
        Badge(
          label: Text('$_cantidadPendientesImpresion'),
          backgroundColor: const Color(0xFFE0A63C),
          isLabelVisible: _cantidadPendientesImpresion > 0,
          child: OutlinedButton.icon(
            onPressed: _verPendientesImpresion,
            icon: const Icon(Icons.print_disabled_outlined, size: 18),
            label: Text('Pendientes de Impresión', style: GoogleFonts.poppins(fontSize: 13)),
            style: _estiloBotonSecundario(),
          ),
        ),
      ],
    );
  }

  int get _cantidadPendientesImpresion => ref.watch(ventasPendientesImpresionStreamProvider).value?.length ?? 0;

  void _verDetalleVenta() {
    Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const DetalleVentaScreen()),
    );
  }

  ButtonStyle _estiloBotonSecundario() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF1A1A1A),
      side: const BorderSide(color: Color(0xFFB6BCC7)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _tarjetaDatosVenta(CarritoVentaState carrito, bool esMovil) {
    final formatoFecha = DateFormat('dd/MM/yyyy');

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: esMovil ? double.infinity : 160,
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(context: context, initialDate: carrito.fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (fecha != null) ref.read(carritoVentaProvider.notifier).establecerFecha(fecha);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Flexible(child: Text(formatoFecha.format(carrito.fecha), overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)))),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 190,
                child: DropdownButtonFormField<String>(
                  initialValue: carrito.tipoDocumento,
                  isExpanded: true,
                  decoration: _decoracion('Tipo de documento'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: tiposDocumento.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(carritoVentaProvider.notifier).establecerTipoDocumento(v);
                  },
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 220,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nombreClienteController,
                        style: GoogleFonts.poppins(fontSize: 13),
                        decoration: _decoracion('Cliente').copyWith(
                          hintText: 'Vacío = Consumidor Final',
                          hintStyle: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _buscarCliente,
                      icon: const Icon(Icons.search),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EAF0), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 180,
                child: TextField(
                  controller: _documentoClienteController,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: _decoracion('RTN / Documento'),
                  onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerDocumentoCliente(v),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 150,
                child: DropdownButtonFormField<String>(
                  initialValue: carrito.condicion,
                  isExpanded: true,
                  decoration: _decoracion('Condición'),
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                  items: const [
                    DropdownMenuItem(value: 'Contado', child: Text('Contado')),
                    DropdownMenuItem(value: 'Credito', child: Text('Crédito')),
                  ],
                  onChanged: carrito.esCotizacion
                      ? null
                      : (v) {
                          if (v == null) return;
                          ref.read(carritoVentaProvider.notifier).establecerCondicion(v);
                        },
                ),
              ),
              if (!carrito.esCotizacion && carrito.condicion != 'Credito')
                SizedBox(
                  width: esMovil ? double.infinity : 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _metodosPago.contains(carrito.metodoPago) ? carrito.metodoPago : null,
                    isExpanded: true,
                    decoration: _decoracion('Método de pago'),
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                    items: _metodosPago.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(carritoVentaProvider.notifier).establecerMetodoPago(v);
                    },
                  ),
                ),
              InkWell(
                onTap: () => setState(() => _datosExpandidos = !_datosExpandidos),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _datosExpandidos ? 'Ver menos' : 'Más datos',
                        style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFFC62828)),
                      ),
                      Icon(_datosExpandidos ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFFC62828)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: !_datosExpandidos
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 14),
                        Text('Descuento y campos fiscales de uso poco frecuente', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (carrito.esCredito && !carrito.esCotizacion)
                              SizedBox(
                                width: esMovil ? double.infinity : 160,
                                child: InkWell(
                                  onTap: () async {
                                    final fecha = await showDatePicker(
                                      context: context,
                                      initialDate: carrito.fechaVencimiento ?? DateTime.now().add(const Duration(days: 30)),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (fecha != null) ref.read(carritoVentaProvider.notifier).establecerFechaVencimiento(fecha);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event_outlined, size: 16, color: Colors.grey.shade500),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Text(
                                            'Vence: ${carrito.fechaVencimiento != null ? formatoFecha.format(carrito.fechaVencimiento!) : 'Sin definir'}',
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: esMovil ? double.infinity : 260,
                              child: TextField(
                                controller: _descuentoGlobalController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('Descuento global (%) sobre toda la venta'),
                                onChanged: (v) {
                                  final valor = double.tryParse(v.replaceAll(',', '').trim());
                                  if (valor == null || valor < 0 || valor > 100) return;
                                  ref.read(carritoVentaProvider.notifier).establecerDescuentoGlobal(valor);
                                },
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _ocController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. O/C exenta'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerOc(v),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _regExoneradoController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. exonerado'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegExonerado(v),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: TextField(
                                enabled: !carrito.esCotizacion,
                                controller: _regSagController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. SAG'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegSag(v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Campo de código de barras de esta pantalla (ver _confirmarCodigoBarras),
  // siempre invisible (el llamador, ver _tarjetaCarritoGrande, lo envuelve
  // en un Offstage): en escritorio, layout y foco siguen funcionando
  // aunque no se pinte nada, así que un lector de código de barras físico
  // (que se comporta como un teclado) agrega el producto en cualquier
  // momento sin necesitar un campo visible. En el celular no hace falta
  // (ahí se escanea con la cámara, ver _escanearConCamara y el botón
  // "Escanear" junto a "Agregar Producto").
  Widget _campoCodigoBarras() {
    return TextField(
      controller: _ctrlCodigoBarras,
      focusNode: _focusCodigoBarras,
      autofocus: true,
      onSubmitted: (_) => _confirmarCodigoBarras(),
    );
  }

  Widget _tarjetaCarritoGrande(CarritoVentaState carrito, bool esMovil) {
    final productos = ref.watch(productosStreamProvider).value ?? [];
    final mapaProductos = {for (final p in productos) p.id: p};

    if (carrito.items.length != _conteoItemsControladores) {
      for (final c in _ctrlCantidad.values) {
        c.dispose();
      }
      for (final c in _ctrlPrecio.values) {
        c.dispose();
      }
      for (final c in _ctrlDescuento.values) {
        c.dispose();
      }
      _ctrlCantidad.clear();
      _ctrlPrecio.clear();
      _ctrlDescuento.clear();
      for (final c in _ctrlDescripcion.values) {
        c.dispose();
      }
      _ctrlDescripcion.clear();
      for (final f in _focusInline.values) {
        f.dispose();
      }
      _focusInline.clear();
      _confirmarInline.clear();
      for (final f in _focusDescripcion.values) {
        f.dispose();
      }
      _focusDescripcion.clear();
      _confirmarDescripcion.clear();
      _conteoItemsControladores = carrito.items.length;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          esMovil
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _agregarProductoDesdeBusqueda,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        ),
                        if (_esPlataformaMovil) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _escanearConCamara,
                            icon: const Icon(Icons.qr_code_scanner, size: 16),
                            label: Text('Escanear', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1A1A1A),
                              side: const BorderSide(color: Color(0xFFB6BCC7)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _abrirEscaneoRemoto,
                      icon: Icon(_escaneoRemotoConectado ? Icons.wifi_tethering : Icons.qr_code_scanner, size: 18, color: _escaneoRemotoConectado ? Colors.green.shade600 : null),
                      label: Text(
                        _escaneoRemotoConectado ? 'Escaneo activo' : 'Escanear con celular',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _escaneoRemotoConectado ? Colors.green.shade700 : null),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A1A),
                        side: BorderSide(color: _escaneoRemotoConectado ? Colors.green.shade400 : const Color(0xFFB6BCC7)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _agregarProductoDesdeBusqueda,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
          Offstage(offstage: true, child: _campoCodigoBarras()),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Precio unitario:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              _selectorPrecioIsvCarrito(),
            ],
          ),
          const SizedBox(height: 14),
          if (!esMovil) ...[
            _encabezadoTablaCarrito(),
            Divider(height: 18, color: Colors.grey.shade300),
          ],
          if (carrito.items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Todavía no agregaste productos.\nUsá "Agregar Producto" para buscar del inventario.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ),
            )
          else if (esMovil)
            // En móvil no usamos una lista con scroll propio: la tabla del
            // carrito viviría dentro del SingleChildScrollView de toda la
            // pantalla, y dos scrolls verticales anidados hacen que, al
            // llegar al borde de este (el interno), ya no se pueda volver a
            // subir arrastrando "por fuera" porque no queda nada de esa
            // pantalla visible fuera de la tabla. Con una Column simple todo
            // el scroll lo maneja la pantalla completa.
            Column(
              children: [
                for (var i = 0; i < carrito.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  _filaCarritoMovil(i, carrito.items[i], mapaProductos),
                ],
              ],
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: carrito.items.length,
                separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) => _filaCarritoTabla(i, carrito.items[i], mapaProductos),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectorPrecioIsvCarrito() {
    Widget opcion(String texto, bool valor) {
      final activo = _precioCarritoConIsv == valor;
      return InkWell(
        onTap: () => _alternarVistaPrecioCarrito(valor),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activo ? const Color(0xFFC62828) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            texto,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion('Con ISV', true),
          opcion('Sin ISV', false),
        ],
      ),
    );
  }

  Widget _encabezadoTablaCarrito() {
    final estilo = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 4, child: Text('Descripción', style: estilo)),
        Expanded(flex: 2, child: Text('Cantidad', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Descuento %', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Importe (c/ISV)' : 'Importe (s/ISV)', textAlign: TextAlign.right, style: estilo)),
        const SizedBox(width: 40),
      ],
    );
  }

  // [valorActual] es el valor ya aplicado (el que tiene el item en el
  // carrito). [claveFoco] identifica el campo (p.ej. "cantidad_2") para
  // cachear su FocusNode entre reconstrucciones. Antes este campo confirmaba
  // en cada tecla (onChanged) y al tocar fuera (onTapOutside) sin
  // desenfocarse, lo que provocaba pedir la clave especial (o el diálogo de
  // reembasado) una y otra vez con cualquier botón que se tocara: como el
  // campo nunca perdía el foco, *todo* toque fuera de él se interpretaba
  // como "confirmar de nuevo". Pasar a confirmar solo en onSubmitted/
  // onTapOutside arregló eso, pero introdujo otro bug: si el usuario tocaba
  // un botón directamente (sin pasar antes por un área vacía) el valor
  // tecleado se perdía. Ahora se confirma al perder el foco por cualquier
  // motivo (FocusNode.addListener), que cubre "cualquier forma de salir del
  // campo" sin volver a onChanged. El listener se crea una sola vez
  // (putIfAbsent) pero llama indirectamente a través de
  // _confirmarInline[claveFoco], que se refresca en cada build: así siempre
  // usa el [valorActual]/[alConfirmar] vigentes en vez de quedar atado a los
  // del primer build. La guarda de "no cambió respecto al ya aplicado" evita
  // volver a llamar a alConfirmar y así el problema original no vuelve.
  Widget _campoInlineNumero(String claveFoco, TextEditingController controlador, double valorActual, void Function(double) alConfirmar, {String? sufijo, bool dosDecimales = false}) {
    // defaultTargetPlatform (a diferencia de Platform.isAndroid, que en web
    // no sirve de nada) sí detecta el sistema operativo real aunque se esté
    // usando desde el navegador.
    final esMovil = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

    final focusNode = _focusInline.putIfAbsent(claveFoco, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _confirmarInline[claveFoco]?.call();
      });
      return node;
    });

    void confirmar() {
      final texto = controlador.text.replaceAll(',', '').trim();
      final valor = double.tryParse(texto);
      if (valor == null) return;
      if ((valor - valorActual).abs() >= 0.005) alConfirmar(valor);
      // Precio: siempre se deja con dos decimales al confirmar (es un
      // monto), igual que se muestra en cualquier otro lado de la app: "35"
      // pasa a verse "35.00". No se recalcula desde el estado guardado -eso
      // sí llegó a desalinearse por el redondeo del ISV en algún caso raro,
      // ver historial- sino que se formatea directo lo que el usuario tecleó.
      if (dosDecimales) controlador.text = valor.toStringAsFixed(2);
      // Después de confirmar, el campo pierde el foco del todo (no solo se
      // deja de seleccionar el texto): que quede como si el usuario hubiera
      // tocado en cualquier otro lado en blanco, sin cursor parpadeando ni
      // texto resaltado.
      if (esMovil) {
        // En el celular alcanza con soltar el foco (ahí no existe el
        // diálogo del teclado numérico en pantalla, ver más abajo, así que
        // no hay restauración de foco de la que cuidarse).
        if (focusNode.hasFocus) focusNode.unfocus();
      } else {
        // En escritorio, simplemente "unfocus()" no alcanza: si el valor se
        // acaba de confirmar viniendo del diálogo del teclado numérico (ver
        // abrirTecladoNumerico), al cerrarse ese diálogo Flutter le
        // devuelve el foco solo al campo que lo tenía antes de abrirlo
        // -este mismo-, lo que reseleccionaba todo el texto de nuevo
        // después de "arreglarlo". Pedirle el foco a otro campo concreto
        // (el de código de barras invisible, ver _campoCodigoBarras) en vez
        // de solo soltarlo evita esa restauración: ya hay algo nuevo con el
        // foco, así que no queda nada pendiente de "recuperar".
        _focusCodigoBarras.requestFocus();
      }
    }
    _confirmarInline[claveFoco] = confirmar;

    Future<void> abrirTecladoNumerico() async {
      // Sin esto, al cerrar el diálogo Flutter le devuelve el foco a este
      // campo (el que lo tenía antes de abrirlo) y reselecciona todo el
      // texto, deshaciendo lo que confirmar() acababa de arreglar.
      focusNode.unfocus();
      final texto = await showDialog<String>(
        context: context,
        builder: (context) => TecladoNumericoDialog(
          titulo: sufijo == '%' ? 'Descuento (%)' : 'Valor',
          valorInicial: controlador.text,
        ),
      );
      if (texto == null || !mounted) return;
      controlador.text = texto;
      confirmar();
    }

    return TextField(
      controller: controlador,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        suffixText: sufijo,
        filled: true,
        fillColor: const Color(0xFFE8EAF0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      // En escritorio, un clic en el campo (no solo en el ícono) ya abre el
      // teclado numérico, para que quede claro que se está por cambiar ese
      // valor. onTap es un gesto (no se dispara al recuperar el foco
      // programáticamente cuando se cierra el diálogo), así que no hay
      // riesgo de que se vuelva a abrir solo. Escribir con el teclado físico
      // y darle Enter sigue funcionando igual, sin pasar por el diálogo.
      onTap: esMovil ? null : abrirTecladoNumerico,
      onSubmitted: (_) => confirmar(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }

  Widget _campoInlineConEtiqueta(String claveFoco, String etiqueta, TextEditingController controlador, double valorActual, void Function(double) alConfirmar, {bool dosDecimales = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        _campoInlineNumero(claveFoco, controlador, valorActual, alConfirmar, dosDecimales: dosDecimales),
      ],
    );
  }

  // Campo de descripción editable de una línea del carrito: no cambia el
  // producto real, solo cómo se muestra/imprime esa línea de esta venta. Si
  // el negocio activó el permiso ventasEditarDescripcion, pide la clave
  // especial antes de aplicar el cambio (y revierte el texto si la cancelan
  // o la clave es incorrecta).
  Widget _campoDescripcion(int index, dynamic item) {
    final ctrl = _ctrlDescripcion.putIfAbsent(index, () => TextEditingController(text: item.nombreProducto as String));

    Future<void> confirmar() async {
      final nuevoTexto = ctrl.text.trim();
      final nombreActual = item.nombreProducto as String;
      if (nuevoTexto.isEmpty) {
        ctrl.text = nombreActual;
        return;
      }
      if (nuevoTexto == nombreActual) return;
      final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
      if (negocio.tienePermiso(PermisosEspeciales.ventasEditarDescripcion)) {
        if (!mounted) return;
        final permitido = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasEditarDescripcion);
        if (!permitido) {
          ctrl.text = nombreActual;
          return;
        }
      }
      ref.read(carritoVentaProvider.notifier).actualizarDescripcion(index, nuevoTexto);
    }
    _confirmarDescripcion[index] = confirmar;

    final focusNode = _focusDescripcion.putIfAbsent(index, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _confirmarDescripcion[index]?.call();
      });
      return node;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: ctrl,
          focusNode: focusNode,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          onSubmitted: (_) => confirmar(),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        if (item.reembasado as bool) Text('Reembasado', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
      ],
    );
  }

  Widget _filaCarritoTabla(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final importe = _importeMostrado(item);

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: precioMostrado.toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 2, child: Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(flex: 4, child: _campoDescripcion(index, item)),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero('cantidad_$index', ctrlCantidad, item.cantidad as double, (v) => _actualizarCantidad(index, v)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero('precio_$index', ctrlPrecio, precioMostrado, (v) => _precioCarritoConIsv ? _actualizarPrecio(index, v) : _actualizarPrecioSinIsv(index, v), dosDecimales: true))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero('descuento_$index', ctrlDescuento, item.descuentoPorcentaje as double, (v) => _actualizarDescuentoLinea(index, v), sufijo: '%'))),
          Expanded(flex: 2, child: Text(formatearMoneda(importe), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
          ),
        ],
      ),
    );
  }

  Widget _filaCarritoMovil(int index, dynamic item, Map<String, ProductoModel> mapaProductos) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final importe = _importeMostrado(item);

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: precioMostrado.toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _campoDescripcion(index, item),
                    Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campoInlineConEtiqueta('cantidad_$index', 'Cantidad', ctrlCantidad, item.cantidad as double, (v) => _actualizarCantidad(index, v))),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('precio_$index', _precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', ctrlPrecio, precioMostrado, (v) => _precioCarritoConIsv ? _actualizarPrecio(index, v) : _actualizarPrecioSinIsv(index, v), dosDecimales: true)),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('descuento_$index', 'Desc. %', ctrlDescuento, item.descuentoPorcentaje as double, (v) => _actualizarDescuentoLinea(index, v))),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Importe (${_precioCarritoConIsv ? 'c/ISV' : 's/ISV'}): ${formatearMoneda(importe)}', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  Widget _tarjetaTotales(CarritoVentaState carrito, bool esMovil) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _filaTotalTexto('Subtotal', carrito.subtotal),
              _filaTotalTexto('ISV (15%)', carrito.impuesto),
              if (carrito.descuentoGlobalPorcentaje > 0) _filaTotalTextoPorcentaje('Descuento global', carrito.descuentoGlobalPorcentaje),
              if (!carrito.esCotizacion && carrito.condicion != 'Credito' && carrito.metodoPago == 'Efectivo' && carrito.pagoCon > 0) ...[
                _filaTotalTexto('Paga con', carrito.pagoCon),
                _filaTotalTexto('Cambio', carrito.cambio),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL A PAGAR', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(formatearMoneda(carrito.totalAPagar), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmarVenta,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                  : Text(_textoBoton, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTotalTexto(String etiqueta, double valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        Text(formatearMoneda(valor), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }

  Widget _filaTotalTextoPorcentaje(String etiqueta, double porcentaje) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
        Text('${_formatoCantidad(porcentaje)}%', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }
}
