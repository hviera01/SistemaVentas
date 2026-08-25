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
import '../../data/costo_tinte_service.dart';
import '../../data/escaneo_remoto_repository.dart';
import '../../data/item_venta_model.dart';
import '../../data/venta_en_espera_model.dart';
import '../../data/venta_export_service.dart';
import '../../data/venta_model.dart';
import '../../data/venta_repository.dart';
import '../../data/venta_ticket_escpos_service.dart';
import '../../providers/carrito_provider.dart';
import '../../providers/usuario_venta_provider.dart';
import '../../../../core/providers/tabs_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../clientes/providers/clientes_provider.dart';
import '../../../clientes/presentation/widgets/cliente_form_dialog.dart';
import '../../../ventas_credito/providers/ventas_credito_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/data/tinte_lookup.dart';
import '../../../productos/providers/productos_provider.dart';
import '../../../categorias/providers/categorias_provider.dart';
import '../../../promociones/data/promocion_model.dart';
import '../../../promociones/providers/promociones_provider.dart';
import '../../../promociones/presentation/widgets/promocion_detectada_dialog.dart';
import '../../../promociones/presentation/widgets/promociones_vigentes_dialog.dart';
import '../../../../core/services/impresora_red_service.dart';
import '../../../../core/services/impresora_usb_windows_service.dart';
import '../../../../core/utils/codigo_barras_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/barcode_scanner_screen.dart';
import '../../../../core/widgets/exito_transaccion_overlay.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/buscar_producto_dialog.dart';
import '../widgets/buscar_cliente_dialog.dart';
import '../widgets/codigos_color_dialog.dart';
import '../widgets/campo_cantidad_tinte.dart';
import '../widgets/campo_margen_precio_venta.dart';
import '../../../formulas/presentation/widgets/panel_flotante_consultar_costo.dart';
import '../widgets/panel_flotante_calculadora_rendimiento.dart';
import '../widgets/cambiar_usuario_venta_dialog.dart';
import '../widgets/reembase_dialog.dart';
import '../widgets/cobrar_dialog.dart';
import '../widgets/pago_mixto_dialog.dart';
import '../../data/pago_detalle_model.dart';
import '../widgets/ventas_en_espera_dialog.dart';
import '../widgets/ventas_pendientes_impresion_dialog.dart';
import '../widgets/teclado_numerico_dialog.dart';
import '../widgets/escanear_remoto_dialog.dart';
import '../widgets/ticket_escpos_preview.dart';
import '../../data/tipos_documento.dart';
import 'detalle_venta_screen.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

const _metodosPago = ['Efectivo', 'Tarjeta', 'Transferencia', 'Mixto'];

class RegistrarVentaScreen extends ConsumerStatefulWidget {
  // Id de la pestaña donde vive esta pantalla (ver pantalla_builder.dart):
  // como se puede tener varias ventas abiertas en pestañas distintas al
  // mismo tiempo, y todas quedan montadas de fondo (IndexedStack), esto es
  // lo que le permite a los atajos de teclado (F10/F12) saber si esta es la
  // pestaña activa antes de responder, para no disparar en todas a la vez.
  final String? tabId;

  // Usado por el atajo "Buscar Producto" del inicio (ver HomeScreen, solo
  // web móvil): en vez de abrir esta pantalla con el carrito vacío y
  // esperar a que el usuario toque "Agregar Producto", la abre y dispara el
  // diálogo de búsqueda directo, como si ya lo hubiera tocado.
  final bool autoAbrirBusqueda;

  const RegistrarVentaScreen({super.key, this.tabId, this.autoAbrirBusqueda = false});

  @override
  ConsumerState<RegistrarVentaScreen> createState() => _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends ConsumerState<RegistrarVentaScreen> {
  final _nombreClienteController = TextEditingController();
  final _documentoClienteController = TextEditingController();
  final _ocController = TextEditingController();
  final _regExoneradoController = TextEditingController();
  final _regSagController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _descuentoGlobalController = TextEditingController();
  bool _datosExpandidos = false;
  bool _precioCarritoConIsv = true;
  // Cliente elegido por BuscarClienteDialog (o cargado de una venta
  // duplicada): permite abrir "Completar datos del cliente" sin tener que
  // ir a buscarlo de nuevo. Se limpia apenas el cajero edita a mano el
  // nombre/documento (ver _limpiarVinculoClienteSiHaceFalta) — si eso pasa,
  // el botón de completar datos deja de mostrarse porque carrito.idCliente
  // también se limpia (ver CarritoVentaNotifier.establecerDocumentoCliente/
  // establecerNombreClienteManual).
  ClienteModel? _clienteVinculado;
  // Sugerencias de clientes ya registrados mientras se tipea a mano en
  // "Cliente" -pedido explícito del dueño-: además del buscador aparte
  // (ícono de lupa), se muestra un mini listado debajo del campo con
  // coincidencias, para no duplicar un cliente que ya existe por error de
  // tipeo. _clienteLayerLink ancla el overlay justo debajo del campo.
  final _focusNombreCliente = FocusNode();
  final _clienteLayerLink = LayerLink();
  OverlayEntry? _overlaySugerenciasCliente;
  // Saldo vencido (si hay) del cliente actual cuando la condición es
  // Crédito: aviso NO bloqueante (ver _verificarCreditoVencido). null =
  // no hay nada vencido, o todavía no se pudo verificar.
  double? _saldoVencidoCliente;
  // Evita repetir la consulta de crédito vencido si no cambió ni el cliente
  // ni la condición desde la última vez que se verificó.
  String? _claveUltimaVerificacionCredito;
  // true mientras está abierto el diálogo de "ver la tabla más grande" (ver
  // _expandirTablaProductos): mientras tanto, la tabla de acá abajo no
  // renderiza sus filas, porque esas filas comparten los mismos
  // TextEditingController/FocusNode (_ctrlCantidad, _focusInline, etc.) que
  // las del diálogo — tenerlas montadas en los dos lados a la vez rompería
  // el foco y la edición.
  bool _tablaExpandida = false;

  // Autoguardado de "venta en espera": ver _programarAutoguardado. Distinto
  // del botón manual "Guardar en Espera" (que además limpia el carrito para
  // liberar la pestaña) — este corre solo, sin tocar el carrito, así una
  // venta en curso nunca vive SOLO en la memoria de esta pestaña.
  Timer? _debounceEnEspera;

  // true mientras hay abierto un diálogo con su propio campo de texto libre
  // (por ahora, solo Buscar Producto) que necesita recibir cada tecla tal
  // cual, sin que el lector físico ni el refoco automático del código de
  // barras invisible compitan por ellas. La tabla expandida (ver
  // _expandirTablaProductos) no la toca a propósito: ahí sí tiene que
  // seguir funcionando el escáner.
  bool _pausarLectorFisico = false;
  // Ver el comentario en _expandirTablaProductos: es la forma de pedirle a
  // ese diálogo (si está abierto) que se vuelva a pintar con los datos ya
  // leídos por el `ref` correcto de esta pantalla, cada vez que el carrito
  // cambie mientras está abierto. null cuando el diálogo no está abierto.
  void Function(void Function())? _refrescarDialogoExpandido;

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

  // Nodo "ancla" sin campo de texto detrás (ver _campoInlineNumero), usado
  // solo en web móvil para robarle el foco a un campo justo después de
  // confirmar con el teclado numérico en pantalla. En escritorio esto se
  // resuelve pidiéndole el foco a _focusCodigoBarras, pero ese es un
  // TextField de verdad: en el navegador de un celular, apenas un TextField
  // -aunque esté invisible (Offstage)- recibe foco, el sistema abre el
  // teclado nativo encima. Este nodo vive en un Focus a secas (sin
  // EditableText adentro), así que puede quedarse con el foco sin disparar
  // ningún teclado.
  final _focusAnclaMovil = FocusNode(debugLabel: 'ancla_teclado_web_movil');

  // Detección del lector de código de barras físico a nivel de hardware
  // (ver _manejarAtajoTeclado/_detectarEscaneoFisico), independiente de qué
  // campo tenga el foco en ese momento: un lector escribe cada carácter
  // muchísimo más rápido de lo humanamente posible, así que se arma un
  // "buffer" con las teclas que van llegando y se reinicia solo si alguna
  // tarda demasiado (typing humano normal). Esto es lo que garantiza que
  // escanear SIEMPRE agregue el producto a la venta abierta, se haya
  // tocado lo que se haya tocado antes.
  final _bufferEscanerFisico = StringBuffer();
  DateTime? _ultimaTeclaEscanerFisico;
  static const _intervaloMaximoEscanerFisico = Duration(milliseconds: 45);

  // defaultTargetPlatform (a diferencia de kIsWeb solo, que no distingue
  // "celular entrando por el navegador" de "PC entrando por el navegador")
  // detecta el sistema operativo real del equipo. Se usa para decidir si
  // mostrar la barra de escanear/escribir código: en escritorio (Windows o
  // navegador de escritorio) esa vía visible no aplica -ahí el escaneo es
  // "Escanear con celular" (QR) o un lector físico, que funciona en
  // cualquier momento sin necesitar un campo visible-, así que solo se
  // muestra en el celular (APK o navegador móvil).
  bool get _esPlataformaMovil => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  // Específicamente el navegador de un celular (no la app APK, no
  // escritorio): usado para el teclado numérico en pantalla de
  // cantidad/precio/descuento (ver _campoInlineNumero) y la barra flotante
  // de totales (ver _barraFlotanteTotales), que solo tienen sentido en web
  // móvil.
  bool get _esWebMovil => kIsWeb && _esPlataformaMovil;

  /// true solo para el escritorio real (ancho de PC + mouse, sin
  /// [_esPlataformaMovil]): ahí la tabla de productos crece con los
  /// productos que se van agregando hasta un techo (ver [_tarjetaCarritoGrande]
  /// y `altoMaximoTabla` en build()), y recién ahí pasa a scrollear sola con
  /// la rueda del mouse -sin reservar ese alto de entrada con el carrito
  /// casi vacío-. false en cualquier dispositivo táctil, aunque el ancho
  /// alcance para verse como tabla de escritorio (ej. una tablet en
  /// horizontal): ahí la tabla se dibuja sin scroll propio ni techo, dentro
  /// del scroll único de toda la pantalla, para que deslizar desde
  /// cualquier parte de la tabla mueva la pantalla completa en vez de
  /// quedar atrapado en una franja angosta.
  bool _tablaConScrollPropio(bool esMovil) => !esMovil && !_esPlataformaMovil;

  // Controla el scroll de toda la pantalla en web móvil, para saber cuándo
  // la tarjeta de totales real (al fondo) ya está a la vista y así ocultar
  // la barra flotante de totales (ver _barraFlotanteTotales/_alScrollearMovil):
  // sin esto quedarían las dos superpuestas.
  final _scrollControllerMovil = ScrollController();
  bool _mostrarBarraFlotante = true;

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

    if (_esWebMovil) _scrollControllerMovil.addListener(_alScrollearMovil);

    // NOTA: antes había acá un listener que ocultaba el mini listado de
    // sugerencias apenas el campo "Cliente" perdía el foco. Se sacó porque
    // era la causa de un bug real (confirmado por el dueño): tocar una
    // sugerencia le saca el foco al campo ANTES de que corra el onTap del
    // InkWell (el foco cambia en el pointer-down, el onTap recién en el
    // pointer-up) -ese listener corría primero, ocultaba el overlay
    // (removiéndolo del árbol) y el toque quedaba sin destinatario, sin
    // hacer nada. Ahora ocultar el listado depende de TapRegion (ver
    // _clienteLayerLink/_sugerenciasClienteOverlay/'sugerencias-cliente'):
    // un toque afuera del campo Y del listado lo cierra, uno adentro de
    // cualquiera de los dos (incluida la sugerencia que se está tocando) no
    // cuenta como "afuera" y no lo cierra antes de tiempo.

    // En escritorio, cada vez que el foco queda en nada (el usuario tocó
    // afuera de un campo, o cerró un diálogo) se lo devuelve al campo de
    // código de barras invisible (ver _campoCodigoBarras): así un lector
    // físico funciona en cualquier momento, sin que el usuario tenga que
    // clickear nada primero. En el celular no hace falta (ahí el campo es
    // visible y el usuario lo toca a propósito).
    if (!_esPlataformaMovil) {
      FocusManager.instance.addListener(_alCambiarFocoGlobal);
      // El primer pedido de foco de este campo NO usa `autofocus` (ver
      // _campoCodigoBarras): el timing propio de `autofocus` de Flutter es
      // distinto al de _alCambiarFocoGlobal, y esa diferencia justo la
      // primera vez es lo que hacía perder la primera tecla si se abría un
      // diálogo (Buscar Producto) muy rápido después de entrar a esta
      // pantalla. Pidiéndolo acá, después del primer frame, con el mismo
      // método que usa el resto, el comportamiento es idéntico siempre.
      WidgetsBinding.instance.addPostFrameCallback((_) => _alCambiarFocoGlobal());
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
      _observacionesController.text = ventaOrigen.observaciones;
      _descuentoGlobalController.text = ventaOrigen.descuentoGlobal == 0 ? '' : _formatoCantidad(ventaOrigen.descuentoGlobal);
    }

    if (widget.autoAbrirBusqueda) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _agregarProductoDesdeBusqueda();
      });
    }

    // Por si esta pestaña arrancó ya con condición Crédito y cliente
    // vinculado (por ejemplo, al duplicar una venta a crédito de arriba):
    // ref.listen (ver build) solo dispara con cambios posteriores, así que
    // hace falta esta verificación inicial aparte.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verificarCreditoVencido(ref.read(carritoVentaProvider));
    });
  }

  // Muestra/oculta la barra flotante de totales (ver _barraFlotanteTotales)
  // según qué tan cerca del final del scroll está el usuario: cuando la
  // tarjeta de totales real (el último elemento de la pantalla) ya está a
  // la vista, no hace falta la flotante encima. 220 es más alto que esa
  // tarjeta a propósito, para que la flotante desaparezca un poco antes de
  // que la real termine de entrar, no justo al mismo tiempo.
  void _alScrollearMovil() {
    if (!mounted || !_scrollControllerMovil.hasClients) return;
    final posicion = _scrollControllerMovil.position;
    final cercaDelFinal = posicion.maxScrollExtent <= 0 || (posicion.maxScrollExtent - posicion.pixels) < 220;
    final debeMostrarse = !cercaDelFinal;
    if (debeMostrarse != _mostrarBarraFlotante) setState(() => _mostrarBarraFlotante = debeMostrarse);
  }

  void _alCambiarFocoGlobal() {
    if (!mounted || _esPlataformaMovil) return;
    // Con varias pestañas de Registrar Venta abiertas a la vez (quedan
    // todas montadas, ver AppShell/IndexedStack), este listener global
    // corre en cada una: sin este chequeo, todas competirían por el foco
    // cada vez que queda en nada, aunque estén en una pestaña de fondo que
    // ni se ve.
    if (!_esPestanaActiva()) return;
    // Ver _pausarLectorFisico: con Buscar Producto abierto, no hay que
    // disputarle el foco a su campo de texto.
    if (_pausarLectorFisico) return;
    if (FocusManager.instance.primaryFocus == null) {
      _focusCodigoBarras.requestFocus();
    }
  }

  bool _manejarAtajoTeclado(KeyEvent event) {
    // F10 y F12 se capturan enteros -keyDown Y keyUp- antes que cualquier
    // otro chequeo de este método. Antes solo se devolvía `true` (evento
    // "manejado") para el keyDown; el keyUp (soltar la tecla) caía sin
    // dueño y Windows se lo entregaba a lo que tuviera el foco en ese
    // instante -el campo de texto de Buscar Producto que F10 recién abrió,
    // justo tomando el foco porque el usuario todavía no soltó la tecla-.
    // Esa interrupción justo al enfocar es lo que hacía perder la primera
    // tecla real que se escribía ahí (solo en Windows: en Web el teclado no
    // pasa por este mismo mecanismo y no reproducía). El beep de "modo
    // menú" que F10 puede disparar a nivel de Windows se corta aparte, en
    // el lado nativo (ver FlutterWindow::MessageHandler en
    // windows/runner/flutter_window.cpp), sin afectar en nada el manejo de
    // esta tecla acá.
    if (event.logicalKey == LogicalKeyboardKey.f10 || event.logicalKey == LogicalKeyboardKey.f12) {
      if (event is KeyDownEvent && mounted && !_guardando && _esPestanaActiva() && !_pausarLectorFisico) {
        if (event.logicalKey == LogicalKeyboardKey.f10) {
          _agregarProductoDesdeBusqueda();
        } else {
          _confirmarVenta();
        }
      }
      return true;
    }
    if (event is! KeyDownEvent) return false;
    if (!mounted || _guardando) return false;
    if (!_esPestanaActiva()) return false;
    // Ver _pausarLectorFisico: con Buscar Producto abierto (el único
    // diálogo con un campo de texto libre propio) la detección del lector
    // físico no debe competir por lo que se esté tecleando ahí. La tabla
    // expandida no pausa esto: ahí el escáner sigue funcionando a
    // propósito.
    if (_pausarLectorFisico) return false;
    return _detectarEscaneoFisico(event);
  }

  // Corre a nivel de hardware (ver initState), no de foco: así un lector de
  // código de barras físico agrega el producto a la venta abierta en esta
  // pestaña sin importar qué campo (o ninguno) tenga el foco en ese
  // momento -cambiar el tipo de documento, tocar "Crear Venta", lo que
  // sea-, en vez de depender de que el campo invisible de código de barras
  // (ver _campoCodigoBarras) logre recuperar el foco a tiempo.
  //
  // Un lector escribe cada tecla en unos pocos milisegundos (mucho más
  // rápido de lo humanamente posible) y termina con Enter. Se arma un
  // buffer con las teclas que van llegando pegadas; si en algún momento
  // pasa demasiado tiempo entre una tecla y la siguiente, se asume que es
  // typing humano normal y el buffer arranca de cero desde esa tecla.
  //
  // Que este método devuelva `true` para el Enter final NO alcanza para
  // evitar que el control que tenga el foco reaccione a la ráfaga: el
  // combobox de "Tipo de documento" o "Método de pago", por ejemplo, se
  // abre solo con recibir esas teclas, sin importar qué se haga después con
  // el Enter. Por eso, apenas se confirma que hay una ráfaga rápida en
  // curso (la segunda tecla pegada a la anterior, no hay que esperar al
  // Enter) se le quita el foco a lo que sea que lo tenga: así no queda
  // ningún control despierto para reaccionar al resto de las teclas que
  // todavía faltan por llegar.
  bool _detectarEscaneoFisico(KeyEvent event) {
    final ahora = DateTime.now();
    final ultimaTecla = _ultimaTeclaEscanerFisico;
    final llegoRapido = ultimaTecla != null && ahora.difference(ultimaTecla) < _intervaloMaximoEscanerFisico;
    _ultimaTeclaEscanerFisico = ahora;

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final codigo = _bufferEscanerFisico.toString();
      _bufferEscanerFisico.clear();
      if (llegoRapido && codigo.length >= 3) {
        _ctrlCodigoBarras.clear();
        _procesarCodigoEscaneado(codigo);
        return true;
      }
      return false;
    }

    final caracter = event.character;
    if (caracter == null || caracter.isEmpty) return false;

    if (llegoRapido) {
      _bufferEscanerFisico.write(caracter);
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      _bufferEscanerFisico
        ..clear()
        ..write(caracter);
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
    _costoFlotante.dispose();
    _calculadoraRendimiento.dispose();
    _debounceEnEspera?.cancel();
    HardwareKeyboard.instance.removeHandler(_manejarAtajoTeclado);
    if (!_esPlataformaMovil) {
      FocusManager.instance.removeListener(_alCambiarFocoGlobal);
    }
    if (_esWebMovil) _scrollControllerMovil.removeListener(_alScrollearMovil);
    _scrollControllerMovil.dispose();
    // Best-effort: no se espera a que termine (dispose no puede ser async),
    // pero cierra la sesión de escaneo remoto si quedó una activa al
    // abandonar esta pestaña de venta.
    _suscripcionEscaneoRemoto?.cancel();
    _suscripcionConectadoEscaneo?.cancel();
    final codigoEscaneo = _codigoEscaneoRemoto;
    if (codigoEscaneo != null) _escaneoRemoto.eliminarSesion(codigoEscaneo);
    _ctrlCodigoBarras.dispose();
    _focusCodigoBarras.dispose();
    _focusAnclaMovil.dispose();
    _ocultarSugerenciasCliente();
    _focusNombreCliente.dispose();
    _nombreClienteController.dispose();
    _documentoClienteController.dispose();
    _ocController.dispose();
    _regExoneradoController.dispose();
    _regSagController.dispose();
    _observacionesController.dispose();
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
    final cliente = await showDialog<ClienteModel>(context: context, builder: (context) => const BuscarClienteDialog());
    if (cliente == null) return;
    final documento = cliente.dni;
    final nombre = cliente.nombreCompleto;
    // Antes solo se actualizaba el nombre visible en el campo "Cliente": el
    // RTN/documento sí quedaba guardado en el carrito (se usaba al grabar la
    // venta), pero el campo "RTN / Documento" en pantalla no se refrescaba,
    // así que parecía que elegir un cliente solo traía el nombre.
    setState(() {
      _nombreClienteController.text = nombre;
      _documentoClienteController.text = documento;
      _clienteVinculado = cliente;
    });
    // idCliente: cliente.id es el vínculo real que antes se descartaba -ver
    // CRM de clientes-: sin esto, ninguna venta quedaba conectada de verdad
    // al registro de Clientes aunque se hubiera elegido uno con el buscador.
    ref.read(carritoVentaProvider.notifier).establecerCliente(documento: documento, nombre: nombre, idCliente: cliente.id);
  }

  /// Arma (o refresca, si ya está abierto) el mini listado de clientes
  /// registrados que coinciden con lo que se va tipeando en "Cliente".
  /// No usa un diálogo aparte para no cortar el tipeo -el cajero ve las
  /// coincidencias sin dejar de escribir, y toca una para vincularla-.
  void _actualizarSugerenciasCliente(String texto) {
    final consulta = texto.trim();
    if (consulta.length < 2 || !_focusNombreCliente.hasFocus) {
      _ocultarSugerenciasCliente();
      return;
    }
    final todos = ref.read(clientesStreamProvider).value ?? const <ClienteModel>[];
    final consultaNorm = normalizarTexto(consulta);
    final coincidencias = todos.where((c) => c.estado && coincideFuzzy(c.textoBusqueda, consulta)).toList()
      ..sort((a, b) => _rangoCoincidenciaCliente(a, consultaNorm).compareTo(_rangoCoincidenciaCliente(b, consultaNorm)));
    final top = coincidencias.take(5).toList();
    if (top.isEmpty) {
      _ocultarSugerenciasCliente();
      return;
    }
    if (_overlaySugerenciasCliente == null) {
      _overlaySugerenciasCliente = OverlayEntry(builder: (context) => _sugerenciasClienteOverlay(top));
      Overlay.of(context).insert(_overlaySugerenciasCliente!);
    } else {
      _sugerenciasClienteActuales = top;
      _overlaySugerenciasCliente!.markNeedsBuild();
    }
  }

  /// Ranking de qué tan "exacta" es la coincidencia de un cliente con lo
  /// tipeado, para las sugerencias en vivo del campo "Cliente" -pedido
  /// explícito del dueño: que la predicción sea precisa, no cualquier match
  /// suelto de coincideFuzzy (que solo dice sí/no, sin orden)-. Menor =
  /// mejor. No toca coincideFuzzy (se sigue usando tal cual para decidir SI
  /// aparece, compartido con BuscarClienteDialog); esto solo decide el ORDEN
  /// entre los que ya calzaron, priorizando que el nombre -o alguna palabra
  /// del nombre- empiece exactamente con lo tipeado por sobre que la
  /// coincidencia esté enterrada en medio del nombre, la dirección o el
  /// teléfono.
  int _rangoCoincidenciaCliente(ClienteModel c, String consultaNorm) {
    final nombreNorm = normalizarTexto(c.nombreCompleto);
    if (nombreNorm.startsWith(consultaNorm)) return 0;
    if (nombreNorm.split(RegExp(r'\s+')).any((p) => p.startsWith(consultaNorm))) return 1;
    if (nombreNorm.contains(consultaNorm)) return 2;
    return 3;
  }

  List<ClienteModel> _sugerenciasClienteActuales = const [];

  Widget _sugerenciasClienteOverlay(List<ClienteModel> coincidencias) {
    _sugerenciasClienteActuales = coincidencias;
    return Positioned(
      width: 320,
      child: CompositedTransformFollower(
        link: _clienteLayerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 58),
        // Mismo groupId que el TapRegion que envuelve el campo "Cliente"
        // (ver más abajo, en el build de la fila de datos): así un toque
        // sobre una sugerencia cuenta como "adentro" del mismo grupo y NO
        // dispara el onTapOutside que cierra el listado -es lo que arregla
        // el bug real de "tocar una sugerencia no hace nada" (ver el
        // comentario en initState).
        child: TapRegion(
          groupId: 'sugerencias-cliente',
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _sugerenciasClienteActuales.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) {
                  final c = _sugerenciasClienteActuales[i];
                  return InkWell(
                    onTap: () => _seleccionarClienteSugerido(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.nombreCompleto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (c.dni.isNotEmpty) Text('DNI: ${c.dni}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _seleccionarClienteSugerido(ClienteModel cliente) {
    _ocultarSugerenciasCliente();
    setState(() {
      _nombreClienteController.text = cliente.nombreCompleto;
      _documentoClienteController.text = cliente.dni;
      _clienteVinculado = cliente;
    });
    ref.read(carritoVentaProvider.notifier).establecerCliente(documento: cliente.dni, nombre: cliente.nombreCompleto, idCliente: cliente.id);
    _focusNombreCliente.unfocus();
  }

  void _ocultarSugerenciasCliente() {
    _overlaySugerenciasCliente?.remove();
    _overlaySugerenciasCliente = null;
  }

  /// Píldora que reemplaza al TextField de "Cliente" cuando ya hay uno
  /// vinculado a esta venta (carrito.idCliente != null) -pedido explícito
  /// del dueño-: sin cursor visible ni edición inline, para que se lea de
  /// un vistazo como "cliente YA elegido" y no como un campo de texto
  /// suelto en el que se podría seguir tipeando. Mismo lenguaje visual que
  /// el resto de chips/píldoras de esta pantalla (ver _chipUsuarioVenta).
  Widget _chipClienteVinculado() {
    final nombre = _nombreClienteController.text.trim();
    return Tooltip(
      message: 'Quitar cliente y volver a escribir',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _desvincularClienteDelCampo,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8EE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nombre.isEmpty ? 'Cliente' : nombre,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF14532D)),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.close, size: 16, color: const Color(0xFF14532D).withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }

  /// Quita el vínculo real (carrito.idCliente) sin borrar lo que ya estaba
  /// escrito: el cajero vuelve a ver el campo de texto normal, con el mismo
  /// nombre listo para corregirlo, borrarlo, o volver a buscar/tipear otro.
  void _desvincularClienteDelCampo() {
    _ocultarSugerenciasCliente();
    setState(() => _clienteVinculado = null);
    ref.read(carritoVentaProvider.notifier).establecerNombreClienteManual(_nombreClienteController.text);
    // Después del frame en que el chip se reemplaza por el TextField real
    // (recién ahí existe el FocusNode que puede pedir foco): así el cajero
    // puede seguir tipeando directo, sin tener que tocar el campo de nuevo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNombreCliente.requestFocus();
    });
  }

  /// Cliente vinculado a esta venta (carrito.idCliente), para el botón
  /// "Completar datos del cliente". Usa el que ya se tiene en memoria si
  /// coincide (elegido recién por el buscador); si no -por ejemplo, viene de
  /// duplicar una venta vieja o de una venta en espera recuperada- lo busca
  /// primero en la lista ya cargada de clientesStreamProvider y, si tampoco
  /// está ahí, lo lee directo de Firestore.
  Future<ClienteModel?> _resolverClienteVinculado(String idCliente) async {
    final actual = _clienteVinculado;
    if (actual != null && actual.id == idCliente) return actual;
    final lista = ref.read(clientesStreamProvider).value ?? const <ClienteModel>[];
    for (final c in lista) {
      if (c.id == idCliente) return c;
    }
    return ref.read(clienteRepositoryProvider).obtenerPorId(idCliente);
  }

  Future<void> _completarDatosCliente() async {
    final idCliente = ref.read(carritoVentaProvider).idCliente;
    if (idCliente == null) return;
    final cliente = await _resolverClienteVinculado(idCliente);
    if (!mounted) return;
    if (cliente == null) {
      _mostrarMensaje('No se encontró el cliente vinculado a esta venta.');
      return;
    }
    await showDialog(context: context, builder: (context) => ClienteFormDialog(cliente: cliente));
    if (!mounted) return;
    // El formulario pudo haber cambiado nombre/dni: se refresca el cliente
    // en memoria y los campos visibles de la venta para que no queden
    // desactualizados sin salir de esta pantalla.
    final actualizado = await ref.read(clienteRepositoryProvider).obtenerPorId(idCliente);
    if (!mounted || actualizado == null) return;
    setState(() {
      _clienteVinculado = actualizado;
      _nombreClienteController.text = actualizado.nombreCompleto;
      _documentoClienteController.text = actualizado.dni;
    });
    ref.read(carritoVentaProvider.notifier).establecerCliente(documento: actualizado.dni, nombre: actualizado.nombreCompleto, idCliente: actualizado.id);
  }

  /// Se llama en cada cambio del carrito (ver ref.listen en build): revisa si
  /// el cliente vinculado a esta venta tiene algún crédito vencido, para
  /// mostrar un aviso NO bloqueante (el cajero puede seguir aunque haya algo
  /// vencido). A propósito NO depende de que la condición de ESTA venta sea
  /// Crédito -el dueño quiere saber del vencido aunque esta venta sea al
  /// contado, para poder cobrarle o decidir si venderle o no-: el único
  /// gatillo es tener un cliente vinculado (o, como respaldo, un documento
  /// tipeado). Best-effort: si falla la consulta (sin internet, etc.)
  /// simplemente no se muestra el aviso, no interrumpe la venta.
  Future<void> _verificarCreditoVencido(CarritoVentaState carrito) async {
    final idCliente = carrito.idCliente;
    final documento = carrito.documentoCliente.trim();
    if ((idCliente == null || idCliente.isEmpty) && (documento.isEmpty || documento == 'N/A')) {
      _claveUltimaVerificacionCredito = null;
      if (_saldoVencidoCliente != null && mounted) setState(() => _saldoVencidoCliente = null);
      return;
    }
    final clave = idCliente ?? documento;
    if (_claveUltimaVerificacionCredito == clave) return;
    _claveUltimaVerificacionCredito = clave;
    try {
      final creditos = await ref.read(ventaCreditoRepositoryProvider).obtenerCreditosDeCliente(idCliente: idCliente, documentoCliente: documento);
      final totalVencido = creditos.where((c) => c.vencida).fold<double>(0, (s, c) => s + c.saldoPendiente);
      if (!mounted) return;
      setState(() => _saldoVencidoCliente = totalVencido > 0 ? totalVencido : null);
    } catch (_) {
      // Sin internet u otro error transitorio: no se muestra el aviso esta
      // vez, no bloquea la venta.
    }
  }

  /// Aviso NO bloqueante: se muestra aunque esta venta sea al contado (no
  /// hace falta estar fiando de nuevo para que importe saber que el cliente
  /// ya tiene algo vencido); el cajero puede seguir la venta como sea, solo
  /// se le avisa para que lo tenga en cuenta.
  Widget _avisoCreditoVencido(double saldoVencido) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este cliente tiene un crédito vencido de ${formatearMoneda(saldoVencido)} — revisá antes de continuar.',
              style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
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

  /// true si la categoría del producto es de las que se tiñen con fórmula de
  /// color (Látex, Aceite, Piscina, Pintura Preparada, Selladores/
  /// Impermeabilizantes) -pedido explícito del dueño: el botón/columna de
  /// "Código Color" no debe aparecer para categorías que no son pintura
  /// (Accesorios, Solventes, Masilla, Tintes, etc, donde no aplica un código
  /// de tinte). Se detecta por el nombre real de la categoría (ver
  /// CategoriaModel.descripcion, cargado de Firestore) en vez de una lista
  /// fija de ids, para no romperse si algún día se edita/reordena la
  /// colección de categorías. idCategoria vacío (líneas de regalo de
  /// promoción, ítems del histórico viejo) no cuenta como pintura.
  bool _esCategoriaPintura(String idCategoria) {
    if (idCategoria.isEmpty) return false;
    final categorias = ref.read(categoriasStreamProvider).value ?? const [];
    final coincidencias = categorias.where((c) => c.id == idCategoria);
    if (coincidencias.isEmpty) return false;
    final descripcion = coincidencias.first.descripcion.toUpperCase();
    return descripcion.startsWith('PINTURA') || descripcion.contains('IMPERMEABILIZANTE') || descripcion.contains('SELLADOR');
  }

  /// true si la línea es un tinte vendido SUELTO (categoría TINTES, ver
  /// tinte_lookup.dart) -pedido explícito del dueño: el cajero piensa esta
  /// cantidad en onzas, no en los cuartos en los que de verdad está guardada
  /// (ver _ofrecerConversionOnzas, donde se arma la línea la primera vez), así
  /// que tanto la cantidad como el precio unitario de estas líneas se
  /// muestran/editan en esa unidad -SOLO en pantalla, cantidad/precioVenta
  /// siguen guardados en cuartos como siempre, ver _campoCantidadTintaInline y
  /// los helpers _precioUnitarioMostrado/_precioPorCuartoDesdeMostrado-.
  bool _esLineaTinte(dynamic item) => (item.idCategoria as String) == idCategoriaTintes;

  /// Convierte un precio "por cuarto" (la unidad real en la que se guarda
  /// item.precioVenta) al que corresponde mostrar en el campo de precio de
  /// la fila -por onza si es una línea de tinte suelto, tal cual si no.
  double _precioUnitarioMostrado(dynamic item, double precioPorCuarto) {
    return _esLineaTinte(item) ? redondearMoneda(precioPorCuarto / CostoTinteService.onzasPorCuarto) : precioPorCuarto;
  }

  /// Inversa de [_precioUnitarioMostrado]: lo que el cajero escribió en el
  /// campo de precio (por onza en una línea de tinte, por cuarto si no) de
  /// vuelta a "por cuarto", la unidad real que espera _actualizarPrecio/
  /// _actualizarPrecioSinIsv.
  double _precioPorCuartoDesdeMostrado(dynamic item, double valorMostrado) {
    return _esLineaTinte(item) ? valorMostrado * CostoTinteService.onzasPorCuarto : valorMostrado;
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
    // Mientras el buscador está abierto (tiene su propio campo de texto
    // libre), se pausa la detección del lector físico y el refoco
    // automático del código de barras invisible (ver _pausarLectorFisico):
    // si no, competían por el foco justo al escribir ahí. La tabla
    // expandida (ver _expandirTablaProductos) no toca esta bandera a
    // propósito: ahí sí tiene que seguir funcionando el escáner.
    _pausarLectorFisico = true;
    try {
      final carritoActual = ref.read(carritoVentaProvider);
      final resultado = await Navigator.of(context).push<ProductoConPrecio>(
        MaterialPageRoute(fullscreenDialog: true, builder: (context) => BuscarProductoDialog(condicion: carritoActual.condicion, metodoPago: carritoActual.metodoPago)),
      );
      if (resultado == null || !mounted) return;
      await _procesarProductoSeleccionado(resultado);
    } finally {
      _pausarLectorFisico = false;
    }
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
  // [esEscaneo] distingue el origen -escáner (código de barras, físico,
  // cámara o remoto por celular) vs. el buscador manual (BuscarProductoDialog)-
  // porque la fusión de líneas repetidas del mismo producto se decide
  // distinto según de dónde vino (ver agregarOFusionarProductoDirecto y
  // _agregarProductoConPromos).
  Future<void> _procesarProductoSeleccionado(ProductoConPrecio resultado, {bool esEscaneo = false}) async {
    final producto = resultado.producto;
    // Un combo/kit siempre tiene stock == 0 por diseño (no tiene existencia
    // propia, se arma de otros productos) — sin este branch, cada venta de
    // combo entraría al flujo de "sin existencia" y ofrecería Reembasado por
    // error. Se agrega directo, con la receta de componentes ya resuelta.
    if (producto.esCombo) {
      final mapaProductos = {for (final p in ref.read(productosStreamProvider).value ?? const <ProductoModel>[]) p.id: p};
      ref.read(carritoVentaProvider.notifier).agregarComboDirecto(producto, mapaProductos: mapaProductos, precioSeleccionado: resultado.precio);
      return;
    }
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
        await _agregarProductoConPromos(producto, precioSeleccionado: resultado.precio, reembasado: true, esEscaneo: esEscaneo);
        return;
      }
      // Si dice que no, se ignora la falta de existencia y se agrega igual
      // (sin marcar reembasado): al vender no baja de 0 (ver venta_repository).
    }
    if (!mounted) return;
    await _agregarProductoConPromos(producto, precioSeleccionado: resultado.precio, esEscaneo: esEscaneo);
    if (!mounted || producto.idCategoria != idCategoriaTintes) return;
    await _ofrecerConversionOnzas(producto);
  }

  /// Convención chica al agregar un producto de tinte (categoría TINTES)
  /// directo al carrito -ej. el cliente trae su propia lata de pintura y
  /// solo se le vende tinte, sin producto base en la misma venta-: el
  /// cajero y las cajeras piensan en onzas al aplicar tinte a mano, no en
  /// cuartos (la unidad en la que de verdad está cargado el stock, ver
  /// tinte_lookup.dart). Se ofrece elegir entre dos modos (pedido explícito
  /// del dueño):
  /// - "Cantidad exacta": cuántas onzas en la notación real de la máquina
  ///   tintométrica (Y + 48avos, ver CampoCantidadTinte) → se recalcula sola
  ///   la cantidad de la línea en cuartos.
  /// - "Cuarto completo": se vende el cuarto entero a su precio normal, sin
  ///   ninguna conversión -la línea ya quedó así por defecto al agregarla
  ///   (cantidad 1), así que este modo simplemente no le hace nada-.
  /// Se busca la línea por idProducto (no "la última de la lista") porque
  /// una promoción de regalo pudo haber agregado otra línea encima mientras
  /// tanto.
  Future<void> _ofrecerConversionOnzas(ProductoModel producto) async {
    // Costo actual (FIFO) del propio tinte, convertido a "por onza" -para el
    // calculador de margen/precio de acá abajo. Se calcula ANTES de abrir el
    // diálogo (una sola consulta) en vez de en cada rebuild del diálogo.
    // onzas=onzasPorCuarto (un cuarto completo) es solo la cantidad "sonda"
    // para pedirle a CostoTinteService el costo unitario vigente por
    // cuarto -ese costo unitario no depende de la cantidad pedida, es un
    // promedio ponderado de los lotes consumidos hasta ese punto (ver
    // LoteCostoRepository.consumir)-.
    final colorante = producto.nombre.replaceFirst('COLORANTE ', '').trim();
    final costeo = await CostoTinteService().calcular([UsoTinte(colorante: colorante, onzas: CostoTinteService.onzasPorCuarto, productoConocido: producto)]);
    if (!mounted) return;
    final costoPorOnza = costeo.isNotEmpty && costeo.first.resuelto ? costeo.first.costoUnitario / CostoTinteService.onzasPorCuarto : 0.0;

    bool modoExacto = true;
    double onzas = 0;
    // Precio de venta (con ISV, por onza) que el cajero terminó viendo/
    // fijando en el calculador de margen -null si nunca lo tocó, en cuyo
    // caso NO se toca el precio de la línea (ver más abajo).
    double? precioPorOnzaElegido;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Widget opcion(String texto, bool valor) {
            final activo = modoExacto == valor;
            return InkWell(
              onTap: () => setStateDialog(() => modoExacto = valor),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: activo ? const Color(0xFFC62828) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72))),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('¿Cuánto tinte se vende?', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [Expanded(child: opcion('Cantidad exacta', true)), Expanded(child: opcion('Cuarto completo', false))]),
                  ),
                  const SizedBox(height: 14),
                  if (modoExacto) ...[
                    CampoCantidadTinte(onChanged: (v) => setStateDialog(() => onzas = v)),
                    if (onzas > 0 && costoPorOnza > 0) ...[
                      const SizedBox(height: 16),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('¿A cuánto se vende la onza?', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      CampoMargenPrecioVenta(
                        costoBase: costoPorOnza,
                        etiquetaPrecio: 'Precio/oz (c/ISV)',
                        onPrecioVentaCambiado: (v) => precioPorOnzaElegido = v,
                      ),
                    ],
                  ] else
                    Text(
                      'Se agrega el cuarto completo a su precio normal, sin conversión a onzas.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
                child: Text('Confirmar', style: GoogleFonts.poppins(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmado != true || !mounted) return;
    if (!modoExacto || onzas <= 0) return; // cuarto completo, o cantidad exacta vacía: la línea se queda como ya quedó (1 cuarto, precio normal).
    final items = ref.read(carritoVentaProvider).items;
    final idx = items.lastIndexWhere((i) => i.idProducto == producto.id);
    if (idx == -1) return;
    // onzasPorCuarto: MISMA constante que usa CostoTinteService en todo el
    // resto de la app (calibrada contra la máquina real del dueño, ver su
    // doc) -antes acá se usaba un "/ 32" suelto sin relación con esa
    // constante, lo que hacía que la cantidad real guardada en la línea no
    // coincidiera con el costo/stock que sí se calculaba con 33.
    ref.read(carritoVentaProvider.notifier).actualizarLinea(idx, cantidad: onzas / CostoTinteService.onzasPorCuarto);
    // El precio por onza solo se aplica si el cajero de verdad tocó el
    // calculador (ver CampoMargenPrecioVenta.onPrecioVentaCambiado, que
    // solo dispara al confirmar un campo) -si nunca lo tocó, la línea se
    // queda con el precio normal del producto, no con "costo + 0% margen"
    // por defecto.
    if (precioPorOnzaElegido != null) {
      final autorizado = await verificarAccesoEspecial(context, ref, PermisosEspeciales.ventasCambiarPrecio);
      if (!mounted) return;
      if (autorizado) {
        final precioPorCuartoConIsv = redondearMoneda(precioPorOnzaElegido! * CostoTinteService.onzasPorCuarto);
        ref.read(carritoVentaProvider.notifier).actualizarLinea(idx, precioConIsv: precioPorCuartoConIsv);
      }
    }
  }

  // ---------- Descuentos y Promociones ----------

  /// Agrega el producto al carrito y, si corresponde, ofrece de forma
  /// interactiva la promoción vigente aplicable (según fecha y la
  /// condición/método de pago ya elegidos en la venta): el cajero decide si
  /// la acepta o no, si rechaza se queda al precio normal. Si el producto
  /// cae en más de una promoción de porcentaje/precio fijo a la vez, se
  /// aplica solo la de mayor beneficio para el cliente (ver
  /// mejorPromoPrecio). Combo por cantidad/regalo/combo multiproducto se
  /// revisan aparte porque dependen de la cantidad o de qué otros productos
  /// hay en el carrito, no del precio unitario, y solo se ofrecen la
  /// primera vez que se cumple la condición (no en cada unidad de más). Si
  /// ya se ofreció un combo por cantidad/regalo con este agregado, no se
  /// ofrece además un combo multiproducto encima (nunca dos diálogos
  /// apilados por la misma acción).
  Future<void> _agregarProductoConPromos(ProductoModel producto, {required double precioSeleccionado, bool reembasado = false, bool esEscaneo = false}) async {
    final carritoAntes = ref.read(carritoVentaProvider);
    final condicion = carritoAntes.condicion;
    final metodoPago = carritoAntes.metodoPago;
    final cantidadAntes = carritoAntes.items.where((i) => i.idProducto == producto.id).fold<double>(0, (s, i) => s + i.cantidad);
    final promociones = ref.read(promocionesStreamProvider).value ?? const <PromocionModel>[];

    // Escanear un código de barras SIEMPRE fusiona con la línea existente
    // del mismo producto, sin importar la categoría -pedido explícito del
    // dueño-. Agregar a mano (buscador) solo fusiona si la categoría NO es
    // de pintura: una línea de pintura puede llevar su propio código/tinte
    // de color (ver CodigosColorDialog), así que el dueño quiere poder
    // vender, por ejemplo, "2 galones de la misma pintura base" como dos
    // líneas separadas, cada una teñida a un color distinto -ver
    // agregarOFusionarProductoDirecto-.
    final fusionarSiYaExiste = esEscaneo || !_esCategoriaPintura(producto.idCategoria);
    final indiceNuevo = ref.read(carritoVentaProvider.notifier).agregarOFusionarProductoDirecto(
          producto,
          precioSeleccionado: precioSeleccionado,
          reembasado: reembasado,
          fusionarSiYaExiste: fusionarSiYaExiste,
        );
    if (!mounted) return;

    final promoPrecio = mejorPromoPrecio(promociones: promociones, idProducto: producto.id, precioActual: precioSeleccionado, condicion: condicion, metodoPago: metodoPago);
    if (promoPrecio != null) {
      final aceptar = await showDialog<bool>(context: context, builder: (context) => PromocionDetectadaDialog(promocion: promoPrecio));
      if (!mounted) return;
      if (aceptar == true) {
        if (promoPrecio.tipo == TipoPromocion.porcentaje) {
          ref.read(carritoVentaProvider.notifier).actualizarLinea(indiceNuevo, descuentoPorcentaje: promoPrecio.valor);
        } else {
          ref.read(carritoVentaProvider.notifier).actualizarLinea(indiceNuevo, precioConIsv: promoPrecio.valor);
        }
        _mostrarMensaje('Promoción "${promoPrecio.nombre}" aplicada.');
        // No se ofrece combo/regalo además en la misma unidad: solo se
        // aplica una promoción por vez, la de mayor beneficio ya elegida
        // arriba. Si el cajero la hubiera rechazado, sí se revisa combo más
        // abajo (ver el "if" que sigue).
        return;
      }
    }

    final cantidadDespues = cantidadAntes + 1;
    final promoCombo = promoComboORegaloAplicable(promociones: promociones, idProducto: producto.id, cantidadEnCarrito: cantidadDespues, condicion: condicion, metodoPago: metodoPago);
    if (promoCombo != null && cantidadAntes < promoCombo.cantidadRequerida) {
      await _ofrecerComboORegalo(promoCombo, precioUnitarioBase: precioSeleccionado);
      return;
    }

    // Combo multiproducto: se arma el mapa de cantidades por producto antes
    // y después de este agregado (el producto recién agregado entra con
    // cantidad 1) y solo se ofrece si el combo queda completo recién ahora
    // (no si ya estaba completo antes, por ejemplo al agregar una segunda
    // unidad de un producto que ya completaba el combo).
    final cantidadesAntes = <String, double>{};
    for (final item in carritoAntes.items) {
      cantidadesAntes[item.idProducto] = (cantidadesAntes[item.idProducto] ?? 0) + item.cantidad;
    }
    final cantidadesDespues = Map<String, double>.from(cantidadesAntes);
    cantidadesDespues[producto.id] = (cantidadesDespues[producto.id] ?? 0) + 1;

    final promoComboMulti = promoComboMultiproductoAplicable(
      promociones: promociones,
      idProducto: producto.id,
      cantidadesEnCarrito: cantidadesDespues,
      condicion: condicion,
      metodoPago: metodoPago,
    );
    if (promoComboMulti == null) return;
    final yaEstabaCompleto = promoComboMulti.idsProductosCombo.every((id) => (cantidadesAntes[id] ?? 0) >= 1);
    if (yaEstabaCompleto) return;

    // Precio normal (con ISV) de la "canasta" del combo: 1 unidad de cada
    // producto, al precio con el que ya está esa línea en el carrito (o el
    // precio recién elegido para el producto que se acaba de agregar).
    final precioNormalCombo = promoComboMulti.idsProductosCombo.fold<double>(0, (s, id) {
      if (id == producto.id) return s + redondearMoneda(precioSeleccionado);
      final itemExistente = carritoAntes.items.where((i) => i.idProducto == id);
      if (itemExistente.isEmpty) return s;
      return s + redondearMoneda(itemExistente.first.precioVenta * 1.15);
    });
    await _ofrecerComboORegalo(promoComboMulti, precioUnitarioBase: precioNormalCombo);
  }

  Future<void> _ofrecerComboORegalo(PromocionModel promo, {required double precioUnitarioBase}) async {
    if (!mounted) return;
    final aceptar = await showDialog<bool>(context: context, builder: (context) => PromocionDetectadaDialog(promocion: promo, precioUnitarioBase: precioUnitarioBase));
    if (!mounted || aceptar != true) return;
    _aplicarComboORegalo(promo);
    _mostrarMensaje('Promoción "${promo.nombre}" aplicada.');
  }

  /// Revisa, después de cambiar la cantidad de una línea (tabla del
  /// carrito), si ese cambio hace que se alcance por primera vez la
  /// cantidad requerida de algún combo por cantidad/regalo — mismo criterio
  /// que al agregar el producto, pero comparando el total de esa línea más
  /// las demás líneas del mismo producto antes y después del cambio. El
  /// combo multiproducto no se revisa acá: se completa agregando un
  /// producto nuevo al carrito (ver _agregarProductoConPromos), cambiar la
  /// cantidad de un producto que ya estaba no suma otro producto distinto.
  Future<void> _revisarPromoComboTrasCambioCantidad(int index, double cantidadAnteriorLinea, double cantidadNuevaLinea) async {
    final carrito = ref.read(carritoVentaProvider);
    if (index >= carrito.items.length) return;
    final idProducto = carrito.items[index].idProducto;
    final totalOtrasLineas = [
      for (var i = 0; i < carrito.items.length; i++)
        if (i != index && carrito.items[i].idProducto == idProducto) carrito.items[i].cantidad,
    ].fold<double>(0, (s, c) => s + c);
    final cantidadAntes = totalOtrasLineas + cantidadAnteriorLinea;
    final cantidadDespues = totalOtrasLineas + cantidadNuevaLinea;
    if (cantidadDespues <= cantidadAntes) return;

    final promociones = ref.read(promocionesStreamProvider).value ?? const <PromocionModel>[];
    final promoCombo = promoComboORegaloAplicable(
      promociones: promociones,
      idProducto: idProducto,
      cantidadEnCarrito: cantidadDespues,
      condicion: carrito.condicion,
      metodoPago: carrito.metodoPago,
    );
    if (promoCombo == null || cantidadAntes >= promoCombo.cantidadRequerida) return;
    final precioUnit = redondearMoneda(carrito.items[index].precioVenta * 1.15);
    await _ofrecerComboORegalo(promoCombo, precioUnitarioBase: precioUnit);
  }

  /// Aplica el combo/regalo aceptado:
  /// - Combo por cantidad: reparte un descuento uniforme entre todas las
  ///   líneas del producto base para que el total de las unidades
  ///   requeridas quede en el precio del combo (si hay unidades de más en
  ///   el carrito, esas se cobran a precio normal dentro del mismo cálculo).
  /// - Combo multiproducto: mismo criterio pero repartido entre las líneas
  ///   de TODOS los productos del combo (1 unidad de cada uno es lo que
  ///   entra al precio del paquete; unidades extra de algún producto del
  ///   combo se cobran a precio normal dentro del mismo cálculo).
  /// - Regalo: agrega una línea nueva por CADA producto de
  ///   idsProductosRegalo, a precio 0 (100% de descuento), sin tocar el
  ///   precio del producto llevado.
  void _aplicarComboORegalo(PromocionModel promo) {
    final notifier = ref.read(carritoVentaProvider.notifier);
    if (promo.tipo == TipoPromocion.comboCantidad) {
      final carrito = ref.read(carritoVentaProvider);
      final indices = [for (var i = 0; i < carrito.items.length; i++) if (carrito.items[i].idProducto == promo.idProductoBase) i];
      if (indices.isEmpty) return;
      final cantidadTotal = indices.fold<double>(0, (s, i) => s + carrito.items[i].cantidad);
      final totalNormalConIsv = indices.fold<double>(0, (s, i) {
        final item = carrito.items[i];
        return s + redondearMoneda(item.precioVenta * 1.15) * item.cantidad;
      });
      if (totalNormalConIsv <= 0) return;
      final extra = (cantidadTotal - promo.cantidadRequerida).clamp(0, double.infinity);
      final precioPromedioNormal = totalNormalConIsv / cantidadTotal;
      final objetivo = promo.precioCombo + extra * precioPromedioNormal;
      final descuentoPct = ((1 - objetivo / totalNormalConIsv) * 100).clamp(0, 100).toDouble();
      for (final i in indices) {
        notifier.actualizarLinea(i, descuentoPorcentaje: descuentoPct);
      }
    } else if (promo.tipo == TipoPromocion.comboMultiproducto) {
      final carrito = ref.read(carritoVentaProvider);
      final indices = [for (var i = 0; i < carrito.items.length; i++) if (promo.idsProductosCombo.contains(carrito.items[i].idProducto)) i];
      if (indices.isEmpty) return;
      // Si falta algún producto del combo (se quitó de la tabla entre que
      // se ofreció y se aceptó), no se aplica nada: cada línea se queda a
      // precio normal.
      final idsPresentes = indices.map((i) => carrito.items[i].idProducto).toSet();
      if (!promo.idsProductosCombo.every(idsPresentes.contains)) return;

      final totalNormalConIsv = indices.fold<double>(0, (s, i) {
        final item = carrito.items[i];
        return s + redondearMoneda(item.precioVenta * 1.15) * item.cantidad;
      });
      if (totalNormalConIsv <= 0) return;

      // Unidades "extra" de cada producto del combo (más allá de la 1 que
      // exige el paquete) se dejan fuera del precio de combo, al precio
      // normal promedio de ese producto.
      var extraNormalValue = 0.0;
      for (final idProd in promo.idsProductosCombo) {
        final indicesProd = indices.where((i) => carrito.items[i].idProducto == idProd).toList();
        if (indicesProd.isEmpty) continue;
        final cantidadProd = indicesProd.fold<double>(0, (s, i) => s + carrito.items[i].cantidad);
        final normalProd = indicesProd.fold<double>(0, (s, i) {
          final item = carrito.items[i];
          return s + redondearMoneda(item.precioVenta * 1.15) * item.cantidad;
        });
        final extraCantidad = (cantidadProd - 1).clamp(0, double.infinity);
        if (cantidadProd > 0) extraNormalValue += extraCantidad * (normalProd / cantidadProd);
      }

      final objetivo = promo.precioCombo + extraNormalValue;
      final descuentoPct = ((1 - objetivo / totalNormalConIsv) * 100).clamp(0, 100).toDouble();
      for (final i in indices) {
        notifier.actualizarLinea(i, descuentoPorcentaje: descuentoPct);
      }
    } else {
      final productos = ref.read(productosStreamProvider).value ?? const <ProductoModel>[];
      for (var i = 0; i < promo.idsProductosRegalo.length; i++) {
        final idRegalo = promo.idsProductosRegalo[i];
        final nombreFallback = i < promo.nombresProductosRegalo.length ? promo.nombresProductosRegalo[i] : '';
        final coincidencias = productos.where((p) => p.id == idRegalo).toList();
        final precioRegaloConIsv = coincidencias.isNotEmpty ? coincidencias.first.precioVenta : 0.0;
        final nombreRegalo = coincidencias.isNotEmpty ? coincidencias.first.nombre : nombreFallback;
        notifier.agregarItem(ItemVentaModel(
          idProducto: idRegalo,
          idCategoria: coincidencias.isNotEmpty ? coincidencias.first.idCategoria : '',
          nombreProducto: '$nombreRegalo (regalo · ${promo.nombre})',
          precioVenta: precioRegaloConIsv > 0 ? precioRegaloConIsv / 1.15 : 0,
          cantidad: promo.cantidadRegalo.toDouble(),
          subtotal: 0,
          precioCompraUsado: coincidencias.isNotEmpty ? coincidencias.first.precioCompra : 0,
          descuentoPorcentaje: 100,
        ));
      }
    }
  }

  Future<void> _abrirPromocionesVigentes() async {
    await showDialog(context: context, builder: (context) => const PromocionesVigentesDialog());
  }

  /// Atajo a la consulta de costo de un color (hasta ahora solo alcanzable
  /// desde Colores) directo desde la venta -pedido explícito del dueño-:
  /// para que la cajera pueda chequear cuánto cuesta un color mientras
  /// atiende al cliente, sin salirse de la pantalla de venta. Es de solo
  /// lectura (no toca el carrito ni el stock).
  ///
  /// Panel flotante minimizable (ver ConsultarCostoFlotanteController), no
  /// un diálogo modal normal: "minimizarlo" deja lo que se tenía cargado
  /// tal cual (Visibility.maintainState, ver ese archivo) para poder hacer
  /// otra cosa en la venta mientras tanto y volver después, en vez de tener
  /// que empezar la consulta de cero -pedido explícito del dueño-.
  final _costoFlotante = ConsultarCostoFlotanteController();

  void _abrirConsultarCosto() => _costoFlotante.abrir(context);

  /// Calculadora de cuánta pintura hace falta según el área a pintar -pedido
  /// explícito del dueño, misma calculadora que ya está en el sitio web
  /// público, y mismo panel flotante minimizable que Consultar Costo (ver
  /// panel_flotante_calculadora_rendimiento.dart).
  final _calculadoraRendimiento = CalculadoraRendimientoFlotanteController();

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
    await _procesarProductoSeleccionado(ProductoConPrecio(producto: producto, precio: precio, nivelPrecio: 1), esEscaneo: true);
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

  void _alternarPendienteCompra(int index) {
    final item = ref.read(carritoVentaProvider).items[index];
    ref.read(carritoVentaProvider.notifier).marcarPendienteCompra(index, !item.pendienteCompra);
  }

  /// "Venta anticipada": se vendió sin saber todavía qué producto exacto la
  /// va a reponer (ej. pintura preparada, antes de comprar el insumo real).
  /// No aplica a combos -su costo depende de sus componentes, no de una
  /// compra directa del combo mismo-, así que ahí el botón sale deshabilitado.
  Widget _botonPendienteCompra(int index, ItemVentaModel item) {
    if (item.esCombo) {
      return SizedBox(
        width: 32,
        child: Tooltip(
          message: 'No aplica a combos (su existencia depende de sus componentes)',
          child: Icon(Icons.hourglass_bottom, size: 18, color: Colors.grey.shade200),
        ),
      );
    }
    final activo = item.pendienteCompra;
    return SizedBox(
      width: 32,
      child: IconButton(
        tooltip: activo
            ? 'Venta anticipada: se vendió sin saber todavía qué compra la va a reponer. La próxima compra de este producto la completa sola y corrige el costo. Tocá para desmarcar.'
            : 'Marcar como venta anticipada: se vende sin tener (o sin saber exactamente cuál) producto real en existencia. La próxima compra de este producto la empareja sola y corrige el costo.',
        icon: Icon(Icons.hourglass_bottom, size: 18, color: activo ? const Color(0xFFF59E0B) : Colors.grey.shade400),
        onPressed: () => _alternarPendienteCompra(index),
      ),
    );
  }

  void _moverItem(int index, int nuevoIndex) {
    ref.read(carritoVentaProvider.notifier).moverItem(index, nuevoIndex);
    // La cantidad de items no cambia con un reordenamiento, así que el
    // chequeo normal de _tarjetaCarritoGrande (que solo reconstruye los
    // controladores cuando cambia la cantidad de filas) no se dispara solo;
    // se fuerza acá para que cada fila muestre el texto del item que le
    // toca ahora, no el que tenía cacheado por posición.
    _conteoItemsControladores = -1;
  }

  Widget _botonOrdenIcono(IconData icono, VoidCallback? onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Icon(icono, size: 16, color: onPressed == null ? Colors.grey.shade300 : Colors.grey.shade700),
      ),
    );
  }

  Widget _botonesOrden(int index, int total) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _botonOrdenIcono(Icons.keyboard_arrow_up, index == 0 ? null : () => _moverItem(index, index - 1)),
        _botonOrdenIcono(Icons.keyboard_arrow_down, index == total - 1 ? null : () => _moverItem(index, index + 1)),
      ],
    );
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
    final cantidadAnterior = item.cantidad;

    if (!_categoriaControlaStock(item.idCategoria)) {
      ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
      await _revisarPromoComboTrasCambioCantidad(index, cantidadAnterior, nuevaCantidad);
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
        await _revisarPromoComboTrasCambioCantidad(index, cantidadAnterior, nuevaCantidad);
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
      await _revisarPromoComboTrasCambioCantidad(index, cantidadAnterior, calculo.cantidadFinal);
      return;
    } else if (stockDisponible < nuevaCantidad && carrito.esCotizacion) {
      _mostrarMensaje('Advertencia: "${item.nombreProducto}" no tiene stock suficiente, pero se actualizará en la cotización.');
    }

    ref.read(carritoVentaProvider.notifier).actualizarLinea(index, cantidad: nuevaCantidad);
    await _revisarPromoComboTrasCambioCantidad(index, cantidadAnterior, nuevaCantidad);
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
        final item = carrito.items[index];
        final precioBase = item.precioVenta;
        final precioPorCuartoMostrado = _precioCarritoConIsv ? redondearMoneda(precioBase * 1.15) : precioBase;
        _ctrlPrecio[index]?.text = _precioUnitarioMostrado(item, precioPorCuartoMostrado).toStringAsFixed(2);
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
        final item = carrito.items[i];
        final base = item.precioVenta;
        final precioPorCuarto = conIsv ? redondearMoneda(base * 1.15) : base;
        ctrl.text = _precioUnitarioMostrado(item, precioPorCuarto).toStringAsFixed(2);
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
      // Se guarda para que "en espera" no pierda el vínculo real al cliente
      // -ver VentaEnEsperaModel.idCliente-.
      idCliente: carrito.idCliente,
      fechaVencimiento: carrito.fechaVencimiento,
      oc: carrito.oc,
      regExonerado: carrito.regExonerado,
      regSag: carrito.regSag,
      observaciones: carrito.observaciones,
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

  /// Se llama en cada cambio del carrito (ver ref.listen en build): reinicia
  /// el debounce para no golpear Firestore en cada tecla, y solo guarda si
  /// ya hay algo que perder. A diferencia de _guardarEnEspera (botón manual),
  /// esto NO limpia el carrito -es un respaldo silencioso de fondo, la venta
  /// sigue en curso en esta pestaña como si nada-.
  void _programarAutoguardadoEnEspera(CarritoVentaState carrito) {
    _debounceEnEspera?.cancel();
    if (carrito.items.isEmpty) return;
    _debounceEnEspera = Timer(const Duration(seconds: 2), _guardarEnEsperaAutomatico);
  }

  Future<void> _guardarEnEsperaAutomatico() async {
    if (!mounted) return;
    final carrito = ref.read(carritoVentaProvider);
    if (carrito.items.isEmpty) return;
    final repo = ref.read(ventaRepositoryProvider);
    final sesion = VentaEnEsperaModel(
      id: carrito.idEnEspera ?? '',
      fecha: DateTime.now(),
      tipoDocumento: carrito.tipoDocumento,
      condicion: carrito.condicion,
      metodoPago: carrito.metodoPago,
      documentoCliente: carrito.documentoCliente,
      nombreCliente: _nombreClienteController.text.trim(),
      // Se guarda para que "en espera" no pierda el vínculo real al cliente
      // -ver VentaEnEsperaModel.idCliente-.
      idCliente: carrito.idCliente,
      fechaVencimiento: carrito.fechaVencimiento,
      oc: carrito.oc,
      regExonerado: carrito.regExonerado,
      regSag: carrito.regSag,
      observaciones: carrito.observaciones,
      descuentoGlobal: carrito.descuentoGlobalPorcentaje,
      items: carrito.items,
    );
    try {
      if (carrito.idEnEspera != null) {
        await repo.actualizarVentaEnEspera(carrito.idEnEspera!, sesion);
      } else {
        final id = await repo.guardarVentaEnEspera(sesion);
        if (!mounted) return;
        ref.read(carritoVentaProvider.notifier).establecerIdEnEspera(id);
      }
    } catch (_) {
      // Sin internet u otro error transitorio: no se pudo autoguardar esta
      // vez, se reintenta solo con el próximo cambio del carrito.
    }
  }

  Future<void> _verEnEspera() async {
    final sesion = await showDialog<VentaEnEsperaModel>(context: context, builder: (context) => const VentasEnEsperaDialog());
    if (sesion == null || !mounted) return;
    // OJO con el orden: setState de acá abajo ANTES de cargarSesion().
    // Asignarle .text a los controladores de nombre/documento dispara su
    // onChanged (establecerNombreClienteManual/establecerDocumentoCliente),
    // que limpia carrito.idCliente a propósito para una edición manual real
    // -ver esos métodos-. Si cargarSesion() (que sí trae el idCliente
    // correcto de la sesión) corriera primero, ese onChanged lo borraría
    // justo después sin querer. Llamándolo al final, cargarSesion() siempre
    // tiene la última palabra y el vínculo real queda restaurado tal como
    // estaba al guardar en espera.
    setState(() {
      _nombreClienteController.text = sesion.nombreCliente;
      _documentoClienteController.text = sesion.documentoCliente;
      _ocController.text = sesion.oc;
      _regExoneradoController.text = sesion.regExonerado;
      _regSagController.text = sesion.regSag;
      _observacionesController.text = sesion.observaciones;
      _descuentoGlobalController.text = sesion.descuentoGlobal == 0 ? '' : _formatoCantidad(sesion.descuentoGlobal);
      // No se tiene el ClienteModel completo acá, solo el id -se resuelve
      // on-demand si se toca "Completar datos del cliente" (ver
      // _resolverClienteVinculado)-.
      _clienteVinculado = null;
    });
    ref.read(carritoVentaProvider.notifier).cargarSesion(sesion);
  }

  void _limpiarTodo() {
    ref.read(carritoVentaProvider.notifier).limpiar();
    _nombreClienteController.clear();
    _documentoClienteController.clear();
    _ocController.clear();
    _regExoneradoController.clear();
    _regSagController.clear();
    _observacionesController.clear();
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
    _clienteVinculado = null;
    _saldoVencidoCliente = null;
    _claveUltimaVerificacionCredito = null;
  }

  Future<void> _confirmarLimpiar() async {
    final carrito = ref.read(carritoVentaProvider);
    final hayAlgoQuePerder = carrito.items.isNotEmpty || _nombreClienteController.text.trim().isNotEmpty;
    if (hayAlgoQuePerder) {
      final continuar = await _confirmarDialogo('Limpiar venta', '¿Seguro que querés borrar todos los productos y datos ingresados en esta venta?');
      if (!continuar) return;
    }
    _debounceEnEspera?.cancel();
    if (carrito.idEnEspera != null) {
      unawaited(ref.read(ventaRepositoryProvider).eliminarVentaEnEspera(carrito.idEnEspera!));
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
    var pagosMixtos = const <PagoDetalle>[];
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
        } else if (carrito.metodoPago == 'Mixto') {
          final resultado = await showDialog<List<PagoDetalle>>(context: context, builder: (context) => PagoMixtoDialog(total: carrito.totalAPagar));
          if (resultado == null) return;
          pagosMixtos = resultado;
          montoPago = resultado.fold<double>(0, (s, p) => s + p.monto);
          montoCambio = 0;
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

    // El usuario que queda registrado como responsable de la venta (el que
    // cuenta para sus metas): el elegido con "cambiar usuario" en esta
    // pestaña si lo hay, si no el de la sesión. Los reembasados de arriba y
    // la anulación (detalle_venta_screen) siguen usando el de la sesión a
    // propósito: son auditoría de quién movió el stock/anuló, no atribución
    // de venta.
    final usuario = ref.read(usuarioVentaOverrideProvider)?.nombreCompleto ?? ref.read(authProvider).usuario?.nombreCompleto ?? '';
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
    // Check verde solo para una venta real -pedido explícito del dueño-,
    // no para una cotización (no es una transacción realizada todavía, no
    // cobra ni mueve stock).
    if (!esCotizacion && mounted) mostrarExitoTransaccion(context);

    unawaited(_guardarVentaEnSegundoPlano(
      ventaRepo: ventaRepo,
      carrito: carrito,
      esCotizacion: esCotizacion,
      esFacturable: esFacturable,
      nombreCliente: nombreCliente,
      montoPago: montoPago,
      montoCambio: montoCambio,
      pagosMixtos: pagosMixtos,
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
    List<PagoDetalle> pagosMixtos = const [],
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
            idCliente: carrito.idCliente,
            fechaRegistro: carrito.fecha,
            fechaVencimiento: (!esCotizacion && carrito.condicion == 'Credito') ? carrito.fechaVencimiento : null,
            oc: carrito.oc,
            regExonerado: carrito.regExonerado,
            regSag: carrito.regSag,
            observaciones: carrito.observaciones,
            descuentoGlobal: carrito.descuentoGlobalPorcentaje,
            items: carrito.items,
            montoPago: montoPago,
            montoCambio: montoCambio,
            pagosMixtos: esCotizacion ? const [] : pagosMixtos,
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
              pagosMixtos: pagosMixtos,
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
          generarTicketEscPos: () => _servicioTicketEscPos.generarTicket(venta, negocio),
          nombreImpresoraWindows: negocio.impresoraTermicaNombre,
          vistaPreviaTicket: () => TicketEscPosPreview(venta: venta, negocio: negocio, esCopia: false),
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
      // Estas dos no dependen una de la otra, así que van juntas (no una
      // esperando a la otra) para que, si hay que pedirle a la PC que
      // imprima, esa orden salga lo antes posible.
      final ventaRepoLocal = ref.read(ventaRepositoryProvider);
      final futurePendiente = ventaRepoLocal.marcarPendienteImpresion(venta.id, true);
      final pcConectada = await ref.read(presenciaImpresionRepositoryProvider).estaConectada();
      if (pcConectada) {
        await ventaRepoLocal.marcarSolicitudImpresionEnVivo(venta.id, true);
        _mostrarMensaje('Se envió la orden de impresión a la caja principal');
      } else {
        _mostrarMensaje('No se puede imprimir directo desde el navegador del celular: la venta quedó pendiente de impresión');
      }
      await futurePendiente;
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
    // En Windows se manda el ticket como ESC/POS crudo por USB en vez de
    // como PDF: algunos drivers de impresora térmica tienen un tamaño de
    // página máximo fijo (ver comentario grande en venta_export_service.dart)
    // y recortan o reescalan cualquier factura más larga que eso sin
    // importar qué le pidamos al PDF. Mismo mecanismo que ya usa la
    // impresión por red/celular, que no tiene ese límite.
    if (!kIsWeb && Platform.isWindows) {
      try {
        final bytes = await _servicioTicketEscPos.generarTicket(venta, negocio);
        final ok = ImpresoraUsbWindowsService().imprimir(nombreImpresora: negocio.impresoraTermicaNombre, bytes: bytes);
        if (!ok) _mostrarMensaje('No se pudo imprimir en la impresora configurada');
      } catch (_) {
        _mostrarMensaje('No se pudo imprimir en la impresora configurada');
      }
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
    final ventaRepoLocal = ref.read(ventaRepositoryProvider);
    final futurePendiente = ventaRepoLocal.marcarPendienteImpresion(venta.id, true);
    final pcConectada = await ref.read(presenciaImpresionRepositoryProvider).estaConectada();
    if (pcConectada) {
      await ventaRepoLocal.marcarSolicitudImpresionEnVivo(venta.id, true);
      _mostrarMensaje('Se envió la orden de impresión a la caja principal');
    } else {
      _mostrarMensaje('No se pudo imprimir: la venta quedó pendiente de impresión');
    }
    await futurePendiente;
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
    // _esCategoriaPintura/_categoriaControlaStock leen categoriasStreamProvider
    // con ref.read() -no pueden usar ref.watch() ahí porque también se
    // llaman desde fuera de build (ej. al agregar un producto)-, así que
    // sin este watch acá arriba la pantalla nunca se enteraba de que las
    // categorías ya habían terminado de cargar si todavía no estaban listas
    // en el primer build: el botón de "Código Color" se quedaba oculto para
    // siempre en esa sesión -bug real reportado al reabrir una venta en
    // espera con líneas de pintura como la primera acción del día, antes de
    // que cualquier otra pantalla hubiera "calentado" ese provider-.
    ref.watch(categoriasStreamProvider);
    ref.listen<CarritoVentaState>(carritoVentaProvider, (previous, next) {
      _programarAutoguardadoEnEspera(next);
      _verificarCreditoVencido(next);
    });
    // Si el diálogo de "ver la tabla más grande" está abierto, le pide que
    // se vuelva a pintar con los datos ya leídos por este `ref` (el
    // correcto para esta pestaña) cada vez que el carrito cambia — ver
    // _expandirTablaProductos para el porqué no puede leerlo por su cuenta.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refrescarDialogoExpandido?.call(() {}));
    // Recalcula la visibilidad de la barra flotante de totales (ver
    // _alScrollearMovil) en cada cambio del carrito, no solo cuando el
    // usuario mueve el scroll a mano: agregar un producto sin haber
    // scrolleado corre la tarjeta de totales real más abajo, y sin esto la
    // flotante se quedaría oculta aunque la real ya no esté a la vista.
    if (_esWebMovil) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _alScrollearMovil());
    }

    // Ver _focusAnclaMovil: este Focus envuelve toda la pantalla para que
    // ese nodo (usado solo en web móvil) siempre tenga dónde vivir, sin
    // interferir con el foco de los campos de adentro.
    return Focus(
      focusNode: _focusAnclaMovil,
      canRequestFocus: true,
      skipTraversal: true,
      child: Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          // Techo para la tabla de productos en escritorio real (ver
          // _tablaConScrollPropio y _tarjetaCarritoGrande): con pocos
          // productos la tarjeta se achica a su contenido, no reserva este
          // alto de entrada -antes lo hacía siempre, aunque el carrito
          // tuviera un solo producto, ocupando espacio de pantalla de más-;
          // recién a partir de este alto la lista pasa a scrollear sola.
          final altoMaximoTabla = (constraints.maxHeight * 0.72).clamp(420.0, 1400.0);
          final contenido = SingleChildScrollView(
            controller: _esWebMovil ? _scrollControllerMovil : null,
            padding: EdgeInsets.all(esMovil ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 14),
                _tarjetaDatosVenta(carrito, esMovil),
                const SizedBox(height: 14),
                _tarjetaCarritoGrande(carrito, esMovil, altoMaximoTabla: altoMaximoTabla),
                const SizedBox(height: 14),
                _tarjetaTotales(carrito, esMovil),
              ],
            ),
          );

          if (!_esWebMovil) return contenido;

          // En web móvil, con varios productos cargados, la tarjeta de
          // totales real queda lejos abajo: esta barra flotante (ver
          // _barraFlotanteTotales) deja el total y "Crear Venta" siempre a
          // mano mientras se scrollea la tabla, sin duplicarse cuando la
          // real ya está a la vista (ver _alScrollearMovil).
          return Stack(
            children: [
              contenido,
              _barraFlotanteTotales(carrito),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _barraFlotanteTotales(CarritoVentaState carrito) {
    final visible = _mostrarBarraFlotante && carrito.items.isNotEmpty;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 12,
      right: 12,
      bottom: visible ? 12 : -100,
      child: IgnorePointer(
        ignoring: !visible,
        child: Material(
          elevation: 12,
          shadowColor: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF1A1A1A),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _guardando ? null : _confirmarVenta,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('TOTAL A PAGAR', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 0.4)),
                        Text(formatearMoneda(carrito.totalAPagar), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _guardando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(12)),
                          child: Text(_textoBoton, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                ],
              ),
            ),
          ),
        ),
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
        _chipUsuarioVenta(),
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

  // Chip con el usuario al que se le va a atribuir ESTA venta (para que
  // cuente en sus metas): por defecto el de la sesión, o el elegido con
  // "cambiar usuario" si se tocó ese botón en esta pestaña. El cambio vive
  // en usuarioVentaOverrideProvider, que está scopeado por pestaña (ver
  // pantalla_builder.dart), así que no afecta la sesión principal ni las
  // demás pestañas abiertas.
  Widget _chipUsuarioVenta() {
    final override = ref.watch(usuarioVentaOverrideProvider);
    final sesion = ref.watch(authProvider).usuario;
    final actual = override ?? sesion;
    final esOverride = override != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: esOverride ? const Color(0xFFFFF3E0) : const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(12),
        border: esOverride ? Border.all(color: const Color(0xFFE0A63C)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 18, color: esOverride ? const Color(0xFF9A6A00) : const Color(0xFF1A1A1A)),
          const SizedBox(width: 6),
          Text(
            'Vendiendo como: ${actual?.nombreCompleto ?? '-'}',
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: esOverride ? const Color(0xFF9A6A00) : const Color(0xFF1A1A1A)),
          ),
          if (esOverride) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: _quitarUsuarioVenta,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.undo, size: 16, color: Color(0xFF9A6A00)),
              ),
            ),
          ],
          const SizedBox(width: 2),
          InkWell(
            onTap: _cambiarUsuarioVenta,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.swap_horiz, size: 16, color: esOverride ? const Color(0xFF9A6A00) : const Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cambiarUsuarioVenta() async {
    final usuario = await mostrarCambiarUsuarioVentaDialog(context, ref);
    if (usuario == null || !mounted) return;
    ref.read(usuarioVentaOverrideProvider.notifier).cambiar(usuario);
  }

  void _quitarUsuarioVenta() {
    ref.read(usuarioVentaOverrideProvider.notifier).quitar();
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
                // Antes 220: "RONALD CAMAS" (nombre real, largo normal)
                // quedaba cortado en "RONALD C" -pedido explícito del
                // dueño-. 340 le da lugar de sobra al nombre incluso con los
                // dos IconButton (buscar + completar datos) compartiendo la
                // fila; el Wrap que contiene toda esta fila igual manda esta
                // caja a una línea nueva sola si no entra, así que ensanchar
                // acá no rompe pantallas angostas.
                width: esMovil ? double.infinity : 340,
                child: Row(
                  children: [
                    Expanded(
                      // Con un cliente ya vinculado (carrito.idCliente !=
                      // null) esto se ve como una píldora rellena, NO como
                      // un TextField editable -pedido explícito del dueño:
                      // antes, aunque ya hubiera un cliente elegido, seguía
                      // pareciendo un campo de texto suelto en el que el
                      // cajero podía seguir tipeando por error, sin ningún
                      // indicio visual de que ya estaba "resuelto"-. Tocar
                      // la píldora desvincula y vuelve al campo de texto
                      // normal (ver _chipClienteVinculado/
                      // _desvincularClienteCampo).
                      child: carrito.idCliente != null
                          ? _chipClienteVinculado()
                          : CompositedTransformTarget(
                              link: _clienteLayerLink,
                              // Mismo groupId que el TapRegion del listado de
                              // sugerencias (ver _sugerenciasClienteOverlay):
                              // un toque en cualquiera de los dos cuenta como
                              // "adentro" del mismo grupo, así tocar una
                              // sugerencia no dispara este onTapOutside antes
                              // de que corra su propio onTap -esto es lo que
                              // arregla el bug real de "tocar una sugerencia
                              // no hace nada" (ver el comentario en
                              // initState).
                              child: TapRegion(
                                groupId: 'sugerencias-cliente',
                                onTapOutside: (_) => _ocultarSugerenciasCliente(),
                                child: CampoTecladoCompacto(
                                  controller: _nombreClienteController,
                                  numerico: false,
                                  titulo: 'Vacío = Consumidor Final',
                                  child: TextField(
                                    inputFormatters: [mayusculasInputFormatter],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    controller: _nombreClienteController,
                                    focusNode: _focusNombreCliente,
                                    style: GoogleFonts.poppins(fontSize: 13),
                                    decoration: _decoracion('Cliente').copyWith(
                                      hintText: 'Vacío = Consumidor Final',
                                      hintStyle: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade400),
                                    ),
                                    // Si el cajero tipea acá directo (no usó
                                    // el buscador), el vínculo real a un
                                    // cliente elegido antes ya no es
                                    // confiable -ver
                                    // establecerNombreClienteManual-. Además
                                    // se refrescan las sugerencias de
                                    // clientes ya registrados que coincidan
                                    // con lo tipeado.
                                    onChanged: (v) {
                                      ref.read(carritoVentaProvider.notifier).establecerNombreClienteManual(v);
                                      if (_clienteVinculado != null) setState(() => _clienteVinculado = null);
                                      _actualizarSugerenciasCliente(v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _buscarCliente,
                      icon: const Icon(Icons.search),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EAF0), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    // Visible con un cliente vinculado a esta venta (elegido
                    // por el buscador, o cargado de una venta duplicada):
                    // abre el mismo formulario de Clientes ya precargado,
                    // para completarle teléfono/dirección sin salir de acá.
                    if (carrito.idCliente != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Completar datos del cliente',
                        onPressed: _completarDatosCliente,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EAF0), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : 180,
                child: CampoTecladoCompacto(
                  controller: _documentoClienteController,
                  numerico: false,
                  child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _documentoClienteController,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: _decoracion('RTN / Documento'),
                  onChanged: (v) {
                    ref.read(carritoVentaProvider.notifier).establecerDocumentoCliente(v);
                    if (_clienteVinculado != null) setState(() => _clienteVinculado = null);
                  },
                ),
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
          if (_saldoVencidoCliente != null) ...[
            const SizedBox(height: 10),
            _avisoCreditoVencido(_saldoVencidoCliente!),
          ],
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
                              child: CampoTecladoCompacto(
                                controller: _descuentoGlobalController,
                                numerico: true,
                                child: TextField(
                                inputFormatters: [mayusculasInputFormatter],
                                autocorrect: false,
                                enableSuggestions: false,
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
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: CampoTecladoCompacto(
                                controller: _ocController,
                                numerico: false,
                                child: TextField(
                                inputFormatters: [mayusculasInputFormatter],
                                autocorrect: false,
                                enableSuggestions: false,
                                enabled: !carrito.esCotizacion,
                                controller: _ocController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. O/C exenta'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerOc(v),
                              ),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: CampoTecladoCompacto(
                                controller: _regExoneradoController,
                                numerico: false,
                                child: TextField(
                                inputFormatters: [mayusculasInputFormatter],
                                autocorrect: false,
                                enableSuggestions: false,
                                enabled: !carrito.esCotizacion,
                                controller: _regExoneradoController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. exonerado'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegExonerado(v),
                              ),
                              ),
                            ),
                            SizedBox(
                              width: esMovil ? double.infinity : 200,
                              child: CampoTecladoCompacto(
                                controller: _regSagController,
                                numerico: false,
                                child: TextField(
                                inputFormatters: [mayusculasInputFormatter],
                                autocorrect: false,
                                enableSuggestions: false,
                                enabled: !carrito.esCotizacion,
                                controller: _regSagController,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('No. Reg. SAG'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerRegSag(v),
                              ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: CampoTecladoCompacto(
                                controller: _observacionesController,
                                numerico: false,
                                child: TextField(
                                inputFormatters: [mayusculasInputFormatter],
                                autocorrect: false,
                                enableSuggestions: false,
                                controller: _observacionesController,
                                maxLines: 2,
                                style: GoogleFonts.poppins(fontSize: 13),
                                decoration: _decoracion('Observaciones (se imprimen en la factura)'),
                                onChanged: (v) => ref.read(carritoVentaProvider.notifier).establecerObservaciones(v),
                              ),
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
    // Sin autofocus: en escritorio el primer pedido de foco lo hace
    // _alCambiarFocoGlobal desde un postFrameCallback en initState (mismo
    // mecanismo, mismo timing, que los pedidos de foco posteriores). En
    // celular no hace falta que este campo tenga foco nunca.
    return CampoTecladoCompacto(
      controller: _ctrlCodigoBarras,
      numerico: false,
      onSubmitted: (_) => _confirmarCodigoBarras(),
      child: TextField(
      inputFormatters: [mayusculasInputFormatter],
      autocorrect: false,
      enableSuggestions: false,
      controller: _ctrlCodigoBarras,
      focusNode: _focusCodigoBarras,
      onSubmitted: (_) => _confirmarCodigoBarras(),
    ),
    );
  }

  Widget _tarjetaCarritoGrande(CarritoVentaState carrito, bool esMovil, {double? altoMaximoTabla}) {
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
                            // En móvil este botón comparte fila con
                            // "Escanear" (ver más abajo) y "Agregar Producto"
                            // no entraba en el ancho disponible -se cortaba
                            // "Product" y "o" en líneas separadas, reportado
                            // por el dueño-. El ícono "+" ya da el contexto,
                            // así que en móvil alcanza con "Agregar" solo; en
                            // escritorio (más ancho, sin "Escanear" al lado)
                            // se deja el texto completo.
                            label: Text(
                              _esPlataformaMovil ? 'Agregar' : 'Agregar Producto',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
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
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Ver promociones vigentes',
                          onPressed: _abrirPromocionesVigentes,
                          icon: const Icon(Icons.local_offer_outlined, size: 20),
                          color: Colors.grey.shade600,
                        ),
                        IconButton(
                          tooltip: 'Consultar costo de un color',
                          onPressed: _abrirConsultarCosto,
                          icon: const Icon(Icons.calculate_outlined, size: 20),
                          color: Colors.grey.shade600,
                        ),
                        IconButton(
                          tooltip: 'Calculadora de pintura',
                          onPressed: () => _calculadoraRendimiento.abrir(context),
                          icon: const Icon(Icons.straighten, size: 20),
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 14),
                    // En escritorio va acá, chico, en vez de en su propia
                    // fila abajo: con varios productos en la venta, esa
                    // fila de más le sacaba espacio vertical a la tabla,
                    // que es lo que más se necesita ver.
                    _selectorPrecioIsvCarrito(compacto: true),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Ver la tabla más grande',
                      onPressed: _expandirTablaProductos,
                      icon: const Icon(Icons.open_in_full, size: 18),
                      color: Colors.grey.shade600,
                    ),
                    IconButton(
                      tooltip: 'Ver promociones vigentes',
                      onPressed: _abrirPromocionesVigentes,
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      color: Colors.grey.shade600,
                    ),
                    IconButton(
                      tooltip: 'Consultar costo de un color',
                      onPressed: _abrirConsultarCosto,
                      icon: const Icon(Icons.calculate_outlined, size: 18),
                      color: Colors.grey.shade600,
                    ),
                    IconButton(
                      tooltip: 'Calculadora de pintura',
                      onPressed: () => _calculadoraRendimiento.abrir(context),
                      icon: const Icon(Icons.straighten, size: 18),
                      color: Colors.grey.shade600,
                    ),
                    const Spacer(),
                    // Escanear con la cámara de este mismo equipo: solo tiene
                    // sentido en un dispositivo táctil (tablet/celular) que
                    // tenga cámara -en la vista de escritorio normal no
                    // aparecía porque acá arriba siempre entra la rama ancha
                    // (esMovil=false), pero una tablet en horizontal también
                    // cae en esa rama y hasta ahora se quedaba sin forma de
                    // escanear directo, solo con "Escanear con celular"
                    // (remoto, para cuando el celular es un equipo aparte).
                    if (_esPlataformaMovil) ...[
                      OutlinedButton.icon(
                        onPressed: _escanearConCamara,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text('Escanear', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
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
          // En escritorio el selector de Con/Sin ISV ya va arriba, junto al
          // título (ver más arriba): acá solo hace falta en móvil, donde no
          // hay tanta presión de espacio vertical por la tabla.
          if (esMovil) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Precio unitario:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(width: 10),
                _selectorPrecioIsvCarrito(),
              ],
            ),
          ],
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
                  _filaCarritoMovil(i, carrito.items[i], mapaProductos, carrito.items.length),
                ],
              ],
            )
          else if (_tablaExpandida)
            // Ver el comentario de _tablaExpandida: mientras el diálogo de
            // "ver más grande" está abierto, esta tabla no monta sus filas
            // (esas mismas filas ya están montadas allá, usando los mismos
            // controladores).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Viendo la tabla ampliada…', style: GoogleFonts.poppins(color: Colors.grey.shade400)),
              ),
            )
          else if (_tablaConScrollPropio(esMovil))
            // Escritorio real (mouse, sin dispositivo táctil): la tabla
            // crece con los productos que se van agregando -no reserva un
            // alto fijo desde el principio, para no ocupar espacio de más
            // con el carrito casi vacío- pero no más allá de
            // [altoMaximoTabla] (un techo generoso, pensado para no empujar
            // los totales lejos de la vista con muchos productos cargados);
            // pasado ese punto, `shrinkWrap` + el `ConstrainedBox` de abajo
            // hacen que sea esta lista, y no la pantalla completa, la que
            // se scrollea con la rueda del mouse.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: altoMaximoTabla ?? 600),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: carrito.items.length,
                separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) => _filaCarritoTabla(i, carrito.items[i], mapaProductos, carrito.items.length),
              ),
            )
          else
            // Tablet en horizontal: el ancho ya alcanza para verse como la
            // tabla de escritorio (esMovil decidió que sí), pero es un
            // dispositivo táctil -mismo motivo que el bloque esMovil de
            // arriba: nada de ListView/Expanded con scroll propio, para que
            // deslizar desde cualquier parte de la tabla mueva el scroll de
            // toda la pantalla en vez de quedar atrapado adentro de una
            // franja angosta. Solo pasa a necesitar scroll de verdad -el de
            // la pantalla completa- si de verdad hay muchos productos
            // cargados.
            Column(
              children: [
                for (var i = 0; i < carrito.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  _filaCarritoTabla(i, carrito.items[i], mapaProductos, carrito.items.length),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // [alCambiarExtra] es para cuando este selector se muestra dentro de un
  // diálogo aparte (ver _expandirTablaProductos): _alternarVistaPrecioCarrito
  // ya actualiza el estado real con su propio setState, pero eso no alcanza
  // para refrescar lo que ese diálogo ya dibujó, al ser una ruta aparte.
  Widget _selectorPrecioIsvCarrito({bool compacto = false, VoidCallback? alCambiarExtra}) {
    Widget opcion(String texto, bool valor) {
      final activo = _precioCarritoConIsv == valor;
      return InkWell(
        onTap: () {
          _alternarVistaPrecioCarrito(valor);
          alCambiarExtra?.call();
        },
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 12, vertical: compacto ? 5 : 8),
          decoration: BoxDecoration(
            color: activo ? const Color(0xFFC62828) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            texto,
            style: GoogleFonts.poppins(fontSize: compacto ? 10.5 : 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opcion('Con ISV', true),
          opcion('Sin ISV', false),
        ],
      ),
    );
  }

  // Muestra la tabla de productos sola, casi a pantalla completa, para
  // cuando hay varios items y la vista normal se queda chica.
  //
  // Cada pestaña de Registrar Venta tiene su propio carrito aislado (ver
  // pantalla_builder.dart: ProviderScope con carritoVentaProvider
  // sobreescrito por pestaña), pero showDialog inserta el diálogo por
  // fuera de ese aislamiento (usa el Navigator raíz, por encima de todas
  // las pestañas): un `ref.watch` armado DENTRO del diálogo (por ejemplo
  // con un Consumer propio) terminaría leyendo el carrito por defecto de
  // afuera, vacío, en vez del de esta pestaña -por eso el diálogo decía
  // "Todavía no agregaste productos" aunque sí había-. La solución es leer
  // siempre con el `ref` de esta pantalla (que sí está adentro del
  // ProviderScope correcto) y solo usar el StatefulBuilder del diálogo
  // para volver a pintar con esos datos ya leídos correctamente.
  void _expandirTablaProductos() {
    setState(() => _tablaExpandida = true);
    showDialog(
      context: context,
      builder: (dialogContext) {
        final tamano = MediaQuery.of(dialogContext).size;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(8),
          child: Container(
            width: tamano.width - 16,
            height: tamano.height - 16,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                // Se guarda para que el build() de esta pantalla (que sí
                // escucha carritoVentaProvider con el ref correcto) pueda
                // pedirle a este diálogo que se vuelva a pintar cada vez
                // que el carrito cambie mientras está abierto.
                _refrescarDialogoExpandido = setDialogState;
                final carrito = ref.read(carritoVentaProvider);
                final productos = ref.read(productosStreamProvider).value ?? [];
                final mapaProductos = {for (final p in productos) p.id: p};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Productos en la venta', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 14),
                        _selectorPrecioIsvCarrito(compacto: true, alCambiarExtra: () => setDialogState(() {})),
                        const SizedBox(width: 10),
                        // Sigue funcionando igual que en la pantalla normal:
                        // abre el mismo buscador, y lo que se elija ahí se
                        // agrega al mismo carrito (se ve reflejado acá al
                        // toque). El lector físico de código de barras
                        // también sigue andando mientras este diálogo está
                        // abierto (a diferencia de mientras Buscar Producto
                        // está abierto, ver _pausarLectorFisico).
                        OutlinedButton.icon(
                          onPressed: _agregarProductoDesdeBusqueda,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('Agregar Producto', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1A1A1A),
                            side: const BorderSide(color: Color(0xFFB6BCC7)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const Spacer(),
                        IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(dialogContext)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _encabezadoTablaCarrito(),
                    Divider(height: 18, color: Colors.grey.shade300),
                    Expanded(
                      child: carrito.items.isEmpty
                          ? Center(
                              child: Text('Todavía no agregaste productos.', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                            )
                          : ListView.separated(
                              itemCount: carrito.items.length,
                              separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                              itemBuilder: (context, i) => _filaCarritoTabla(i, carrito.items[i], mapaProductos, carrito.items.length),
                            ),
                    ),
                    const SizedBox(height: 10),
                    // Chico y discreto a propósito: el objetivo de este
                    // diálogo es ver la tabla grande, no repetir la tarjeta
                    // de totales completa (esa ya está en la pantalla
                    // normal). Confirmar la venta desde acá funciona igual
                    // que siempre (valida, cobra si hace falta, guarda, y
                    // limpia el carrito al terminar).
                    _barraTotalesCompacta(carrito),
                  ],
                );
              },
            ),
          ),
        );
      },
    ).then((_) {
      _refrescarDialogoExpandido = null;
      if (mounted) setState(() => _tablaExpandida = false);
    });
  }

  // Versión chica de los totales + botón de crear venta, solo para la tabla
  // expandida (ver _expandirTablaProductos): una sola fila delgada, para
  // que la tabla se quede con casi todo el espacio, que es para lo que se
  // abrió este diálogo.
  Widget _barraTotalesCompacta(CarritoVentaState carrito) {
    Widget total(String etiqueta, double valor, {bool destacado = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.3)),
          Text(
            formatearMoneda(valor),
            style: GoogleFonts.poppins(fontSize: destacado ? 15 : 12.5, fontWeight: FontWeight.w800, color: destacado ? const Color(0xFFC62828) : const Color(0xFF1A1A1A)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          total('Subtotal', carrito.subtotal),
          const SizedBox(width: 20),
          total('ISV', carrito.impuesto),
          const SizedBox(width: 20),
          total('Total a pagar', carrito.totalAPagar, destacado: true),
          const Spacer(),
          SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmarVenta,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _guardando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_textoBoton, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoTablaCarrito() {
    final estilo = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Row(
      children: [
        const SizedBox(width: 28),
        Expanded(flex: 2, child: Text('Código', style: estilo)),
        Expanded(flex: 4, child: Text('Descripción', style: estilo)),
        Expanded(flex: 2, child: Text('Código Color', style: estilo)),
        Expanded(flex: 2, child: Text('Cantidad', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text('Descuento %', textAlign: TextAlign.center, style: estilo)),
        Expanded(flex: 2, child: Text(_precioCarritoConIsv ? 'Importe (c/ISV)' : 'Importe (s/ISV)', textAlign: TextAlign.right, style: estilo)),
        const SizedBox(width: 32),
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
  Widget _campoInlineNumero(String claveFoco, TextEditingController controlador, double valorActual, void Function(double) alConfirmar, {String? sufijo, String? prefijo, bool dosDecimales = false}) {
    // Antes esto agrupaba "Android/iOS" sin importar si era la app (APK) o
    // el navegador del celular, y ambos se quedaban con el teclado nativo
    // del sistema. Ahora solo la app nativa lo conserva: el navegador del
    // celular (ver _esWebMovil) pasa a abrir el mismo teclado numérico en
    // pantalla que ya usa escritorio, para no depender del teclado nativo
    // del navegador (que tapa media pantalla y deja ver el cursor).
    final esMovilNativo = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

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
      if (esMovilNativo) {
        // En la app nativa alcanza con soltar el foco (ahí no existe el
        // diálogo del teclado numérico en pantalla, ver más abajo, así que
        // no hay restauración de foco de la que cuidarse).
        if (focusNode.hasFocus) focusNode.unfocus();
      } else if (_esWebMovil) {
        // En web móvil, igual que en escritorio, un "unfocus()" solo no
        // alcanza (mismo motivo que el bloque de escritorio, abajo), así
        // que también hay que robarle el foco a otro nodo. Pero acá NO
        // puede ser _focusCodigoBarras: ese es un TextField de verdad, y
        // aunque esté invisible (Offstage), el navegador del celular abre
        // su teclado nativo apenas ese campo recibe foco. _focusAnclaMovil
        // es un nodo sin campo de texto detrás, así que resuelve lo mismo
        // sin disparar ningún teclado.
        _focusAnclaMovil.requestFocus();
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

    final campo = CampoTecladoCompacto(
      controller: controlador,
      numerico: true,
      onSubmitted: (_) => confirmar(),
      child: TextField(
      inputFormatters: [mayusculasInputFormatter],
      autocorrect: false,
      enableSuggestions: false,
      controller: controlador,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        suffixText: sufijo,
        prefixText: prefijo,
        prefixStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
        filled: true,
        fillColor: const Color(0xFFE8EAF0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onSubmitted: (_) => confirmar(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    ),
    );

    if (esMovilNativo) return campo;

    // En escritorio y en web móvil, un toque en el campo debe abrir el
    // teclado numérico de una vez, sin que primero se vea el cursor de
    // texto parpadeando ni se abra el teclado nativo (lo que pasaba porque
    // el propio TextField toma el foco apenas se presiona, antes de que
    // onTap llegue a dispararse: con un toque rápido incluso alcanzaba a
    // dejar escribir directo ahí). El GestureDetector de afuera es quien
    // recibe el toque; AbsorbPointer evita que ese mismo toque le llegue al
    // TextField, así que nunca se enfoca ni parpadea el cursor, sea con
    // mouse o con el dedo. El foco por teclado físico (Tab) no pasa por
    // gestos de puntero, así que seguir tipeando y dándole Enter sin abrir
    // el diálogo sigue funcionando igual que antes.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: abrirTecladoNumerico,
      child: AbsorbPointer(child: campo),
    );
  }

  Widget _campoInlineConEtiqueta(String claveFoco, String etiqueta, TextEditingController controlador, double valorActual, void Function(double) alConfirmar, {bool dosDecimales = false, String? prefijo, String? sufijo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        _campoInlineNumero(claveFoco, controlador, valorActual, alConfirmar, prefijo: prefijo, sufijo: sufijo, dosDecimales: dosDecimales),
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
        CampoTecladoCompacto(
          controller: ctrl,
          numerico: false,
          child: TextField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: ctrl,
          focusNode: focusNode,
          // Sin límite de líneas: un nombre largo pasa a una segunda línea
          // en vez de desplazarse fuera de vista dentro de un campo de una
          // sola línea. Como contrapartida, Enter ya no confirma el cambio
          // (inserta un salto de línea, como en cualquier campo multilínea);
          // tocar fuera del campo lo sigue confirmando igual.
          maxLines: null,
          minLines: 1,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        ),
        if (item.reembasado as bool) Text('Reembasado', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
        // Para una línea de tinte suelto, se aclara acá "X onzas × L Y.YY/oz"
        // -pedido explícito del dueño: que la línea se lea en la unidad en
        // la que el cajero de verdad piensa (onzas), no en cuartos-. Es
        // puramente de lectura: cantidad/precioVenta reales de la línea
        // siguen en cuartos, no cambia nada de lo que se guarda.
        if (_esLineaTinte(item))
          Builder(builder: (context) {
            final onzas = (item.cantidad as double) * CostoTinteService.onzasPorCuarto;
            final precioPorCuarto = _precioCarritoConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : (item.precioVenta as double);
            final precioPorOnza = _precioUnitarioMostrado(item, precioPorCuarto);
            return Text('${_formatoCantidad(onzas)} oz × ${formatearMoneda(precioPorOnza)}/oz', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500));
          }),
      ],
    );
  }

  /// Botón/badge de código(s) de color de una línea del carrito: abre
  /// CodigosColorDialog (lista chica de códigos, no un campo de texto suelto
  /// -una línea puede llevar más de un código, ej. una mezcla con dos
  /// tintes-). Sin código cargado se ve como un botón vacío ("+ Color"); con
  /// alguno cargado, se ve el primero + cuántos más hay, para que el cajero
  /// vea de un vistazo que ya se cargó algo sin tener que reabrir el diálogo.
  Widget _botonCodigoColor(int index, dynamic item) {
    final List<String> codigos = item.codigosColor;
    final List<TinteConsumidoSnapshot> tintes = item.tintesConsumidos;

    Future<void> abrir() async {
      final resultado = await showDialog<CodigosColorResultado>(
        context: context,
        builder: (context) => CodigosColorDialog(
          codigosIniciales: codigos,
          tintesIniciales: tintes,
          nombreProducto: item.nombreProducto as String,
          cantidadLinea: item.cantidad as double,
          // Costo actual del producto base de esta línea -para que el
          // diálogo pueda mostrar el costo TOTAL (tinte + producto base) y
          // no solo el de tinte, ver CodigosColorDialog.costoProductoBase.
          costoProductoBase: item.precioCompraUsado as double,
          // Precio de venta YA registrado en la línea (antes de sumarle el
          // tinte) -pedido explícito: el calculador de margen/precio tiene
          // que arrancar mostrando ESE precio, no costo+0% de margen, para
          // que el cajero vea de una si con el precio que ya tenía pensado
          // alcanza para cubrir también el tinte. Con ISV -"el precio
          // final", pedido explícito del dueño: item.precioVenta se
          // guarda sin ISV puertas adentro del carrito (ver
          // CodigosColorDialog.precioVentaProductoBase/precioConIsv).
          precioVentaProductoBase: redondearMoneda((item.precioVenta as double) * 1.15),
        ),
      );
      if (resultado == null) return;
      ref.read(carritoVentaProvider.notifier).actualizarCodigosColor(index, resultado.codigos);
      ref.read(carritoVentaProvider.notifier).actualizarTintesConsumidos(index, resultado.tintes);
    }

    // El costo del tinte -antes se agregaba acá como "· L 45.00" pegado al
    // código- se saca de esta insignia de la tabla del carrito por pedido
    // explícito del dueño: se queda solo el identificador de código, que es
    // lo que sí quiere ver de un vistazo en la tabla. El desglose de costo
    // sigue viéndose igual que siempre en el paso de SELECCIÓN, dentro de
    // CodigosColorDialog/SeleccionarFormulaDialog, antes de confirmar la
    // línea -eso no se tocó-.
    final texto = codigos.isEmpty ? 'Color' : (codigos.length == 1 ? codigos.first : '${codigos.first} +${codigos.length - 1}');
    final tieneAlgo = codigos.isNotEmpty || tintes.isNotEmpty;

    return InkWell(
      onTap: abrir,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: tieneAlgo ? const Color(0xFFFBEAEA) : const Color(0xFFE8EAF0),
          borderRadius: BorderRadius.circular(8),
          border: tieneAlgo ? Border.all(color: const Color(0xFFC62828).withOpacity(0.35)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette_outlined, size: 14, color: tieneAlgo ? const Color(0xFFC62828) : Colors.grey.shade500),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                texto,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: tieneAlgo ? const Color(0xFFC62828) : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reedición de la cantidad de una línea de tinte vendido SUELTO (ver
  /// _esLineaTinte): en vez del campo numérico genérico en cuartos (que el
  /// dueño reportó como confuso -"no es como pienso la cantidad"-), abre el
  /// mismo diálogo Y/48avos que ya usa _ofrecerConversionOnzas al agregar el
  /// producto por primera vez, más el mismo calculador de margen/precio por
  /// onza (cost basis: costo FIFO actual del propio tinte, igual que en
  /// _ofrecerConversionOnzas).
  Widget _campoCantidadTintaInline(int index, dynamic item, ProductoModel? producto) {
    final onzasActuales = (item.cantidad as double) * CostoTinteService.onzasPorCuarto;

    Future<void> editar() async {
      var costoPorOnza = 0.0;
      if (producto != null) {
        final colorante = producto.nombre.replaceFirst('COLORANTE ', '').trim();
        final costeo = await CostoTinteService().calcular([UsoTinte(colorante: colorante, onzas: CostoTinteService.onzasPorCuarto, productoConocido: producto)]);
        if (!mounted) return;
        if (costeo.isNotEmpty && costeo.first.resuelto) costoPorOnza = costeo.first.costoUnitario / CostoTinteService.onzasPorCuarto;
      }
      if (!mounted) return;

      var nuevasOnzas = onzasActuales;
      double? precioPorOnzaElegido;
      // Siempre con ISV acá (sin importar cómo esté la columna de precio
      // del carrito en este momento): lo que confirma el calculador se
      // aplica más abajo como precioConIsv directo (ver
      // "precioPorCuartoConIsv" tras cerrar el diálogo), así que tiene que
      // estar en esa misma unidad de punta a punta.
      final precioActualPorCuartoConIsv = redondearMoneda((item.precioVenta as double) * 1.15);
      final precioPorOnzaActual = _precioUnitarioMostrado(item, precioActualPorCuartoConIsv);

      final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('¿Cuántas onzas?', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CampoCantidadTinte(valorInicial: onzasActuales, onChanged: (v) => setStateDialog(() => nuevasOnzas = v)),
                    if (costoPorOnza > 0) ...[
                      const SizedBox(height: 16),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('¿A cuánto se vende la onza?', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      CampoMargenPrecioVenta(
                        costoBase: costoPorOnza,
                        precioVentaInicial: precioPorOnzaActual,
                        etiquetaPrecio: 'Precio/oz (c/ISV)',
                        onPrecioVentaCambiado: (v) => precioPorOnzaElegido = v,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
                  child: Text('Confirmar', style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        ),
      );
      if (confirmado != true || !mounted) return;
      if (nuevasOnzas <= 0) {
        _mostrarMensaje('La cantidad debe ser mayor a 0');
        return;
      }
      await _actualizarCantidad(index, nuevasOnzas / CostoTinteService.onzasPorCuarto);
      if (!mounted || precioPorOnzaElegido == null) return;
      // Optimista: si el permiso especial se niega, _actualizarPrecio ya
      // revierte este mismo campo al valor real (ver su comentario) -mismo
      // criterio que el campo de precio normal de cualquier otra línea. El
      // calculador siempre trabaja en precio CON ISV (ver etiquetaPrecio
      // arriba); si en este momento la columna de precio está mostrando
      // SIN ISV, hay que convertir antes de escribirlo en el campo.
      final precioPorOnzaMostrado = _precioCarritoConIsv ? precioPorOnzaElegido! : redondearMoneda(precioPorOnzaElegido! / 1.15);
      _ctrlPrecio[index]?.text = precioPorOnzaMostrado.toStringAsFixed(2);
      final precioPorCuartoConIsv = redondearMoneda(precioPorOnzaElegido! * CostoTinteService.onzasPorCuarto);
      await _actualizarPrecio(index, precioPorCuartoConIsv);
    }

    return InkWell(
      onTap: editar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(10)),
        child: Text('${_formatoCantidad(onzasActuales)} oz', style: GoogleFonts.poppins(fontSize: 13)),
      ),
    );
  }

  Widget _campoCantidadTintaInlineConEtiqueta(int index, dynamic item, ProductoModel? producto) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Onzas', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        _campoCantidadTintaInline(index, item, producto),
      ],
    );
  }

  Widget _filaCarritoTabla(int index, dynamic item, Map<String, ProductoModel> mapaProductos, int totalItems) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioPorCuartoMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final esTinte = _esLineaTinte(item);
    final precioMostrado = _precioUnitarioMostrado(item, precioPorCuartoMostrado);
    final importe = _importeMostrado(item);

    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad as double)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: precioMostrado.toStringAsFixed(2)));
    final ctrlDescuento = _ctrlDescuento.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.descuentoPorcentaje as double)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: _botonesOrden(index, totalItems)),
          Expanded(flex: 2, child: Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
          Expanded(flex: 4, child: _campoDescripcion(index, item)),
          Expanded(
            flex: 2,
            child: _esCategoriaPintura(item.idCategoria as String)
                ? Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Align(alignment: Alignment.centerLeft, child: _botonCodigoColor(index, item)))
                : const SizedBox.shrink(),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: esTinte ? _campoCantidadTintaInline(index, item, producto) : _campoInlineNumero('cantidad_$index', ctrlCantidad, item.cantidad as double, (v) => _actualizarCantidad(index, v)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _campoInlineNumero(
                'precio_$index',
                ctrlPrecio,
                precioMostrado,
                (v) {
                  final vPorCuarto = _precioPorCuartoDesdeMostrado(item, v);
                  if (_precioCarritoConIsv) {
                    _actualizarPrecio(index, vPorCuarto);
                  } else {
                    _actualizarPrecioSinIsv(index, vPorCuarto);
                  }
                },
                prefijo: 'L.',
                sufijo: esTinte ? '/oz' : null,
                dosDecimales: true,
              ),
            ),
          ),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _campoInlineNumero('descuento_$index', ctrlDescuento, item.descuentoPorcentaje as double, (v) => _actualizarDescuentoLinea(index, v), sufijo: '%'))),
          Expanded(flex: 2, child: Text(formatearMoneda(importe), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
          _botonPendienteCompra(index, item as ItemVentaModel),
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
          ),
        ],
      ),
    );
  }

  Widget _filaCarritoMovil(int index, dynamic item, Map<String, ProductoModel> mapaProductos, int totalItems) {
    final producto = mapaProductos[item.idProducto as String];
    final precioSinIsv = item.precioVenta as double;
    final precioPorCuartoMostrado = _precioCarritoConIsv ? redondearMoneda(precioSinIsv * 1.15) : precioSinIsv;
    final esTinte = _esLineaTinte(item);
    final precioMostrado = _precioUnitarioMostrado(item, precioPorCuartoMostrado);
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
              _botonesOrden(index, totalItems),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _campoDescripcion(index, item),
                    Text(producto?.codigo ?? '-', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    if (_esCategoriaPintura(item.idCategoria as String)) ...[
                      const SizedBox(height: 6),
                      _botonCodigoColor(index, item),
                    ],
                  ],
                ),
              ),
              _botonPendienteCompra(index, item as ItemVentaModel),
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC62828)), onPressed: () => _quitarItem(index)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: esTinte
                    ? _campoCantidadTintaInlineConEtiqueta(index, item, producto)
                    : _campoInlineConEtiqueta('cantidad_$index', 'Cantidad', ctrlCantidad, item.cantidad, (v) => _actualizarCantidad(index, v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _campoInlineConEtiqueta(
                  'precio_$index',
                  (_precioCarritoConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)') + (esTinte ? ' /oz' : ''),
                  ctrlPrecio,
                  precioMostrado,
                  (v) {
                    final vPorCuarto = _precioPorCuartoDesdeMostrado(item, v);
                    if (_precioCarritoConIsv) {
                      _actualizarPrecio(index, vPorCuarto);
                    } else {
                      _actualizarPrecioSinIsv(index, vPorCuarto);
                    }
                  },
                  prefijo: 'L.',
                  dosDecimales: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _campoInlineConEtiqueta('descuento_$index', 'Desc. %', ctrlDescuento, item.descuentoPorcentaje, (v) => _actualizarDescuentoLinea(index, v))),
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
