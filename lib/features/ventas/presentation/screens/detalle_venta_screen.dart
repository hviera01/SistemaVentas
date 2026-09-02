import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../data/venta_model.dart';
import '../../data/venta_export_service.dart';
import '../../data/venta_ticket_escpos_service.dart';
import '../../data/presencia_impresion_repository.dart';
import '../../data/tipos_documento.dart';
import '../../providers/carrito_provider.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../../core/models/tab_item.dart';
import '../../../../core/providers/tabs_provider.dart';
import '../../../../core/services/impresora_red_service.dart';
import '../../../../core/services/impresora_usb_windows_service.dart';
import '../widgets/datos_envio_dialog.dart';
import '../../../clientes/providers/clientes_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/pantalla_builder.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/ticket_escpos_preview.dart';
import '../../../ventas_credito/data/abono_model.dart';
import '../../../ventas_credito/data/venta_credito_export_service.dart';
import '../../../ventas_credito/providers/ventas_credito_provider.dart';
import '../../../ventas_credito/presentation/widgets/registrar_abono_dialog.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Pantalla de consulta de una venta ya registrada: buscá por número de
/// documento (o abrila directo desde Reportes / Ventas a Crédito pasando
/// [ventaIdInicial]) para ver el detalle completo, reimprimirla, descargar
/// un PDF formal, o anularla.
class DetalleVentaScreen extends ConsumerStatefulWidget {
  final String? ventaIdInicial;
  final String? numeroDocumentoInicial;

  /// true cuando se abre como modal (push encima de otra pantalla, ej. desde
  /// un botón en Reportes/Créditos): muestra su propio Scaffold y flecha de
  /// volver. false cuando se abre como pestaña del menú principal (ej.
  /// Ventas > Ver Detalle): se embebe como las demás pantallas, sin Scaffold
  /// propio ni flecha (la pestaña se cierra con la "x" de la barra de
  /// pestañas).
  final bool esDialogo;

  const DetalleVentaScreen({
    super.key,
    this.ventaIdInicial,
    this.numeroDocumentoInicial,
    this.esDialogo = true,
  });

  @override
  ConsumerState<DetalleVentaScreen> createState() => _DetalleVentaScreenState();
}

class _DetalleVentaScreenState extends ConsumerState<DetalleVentaScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = VentaExportService();
  final _servicioTicketEscPos = VentaTicketEscPosService();
  final _servicioImpresoraRed = ImpresoraRedService();
  final _presencia = PresenciaImpresionRepository();
  VentaModel? _venta;
  bool _cargando = false;
  bool _anulando = false;
  bool _procesandoPdf = false;
  bool _procesandoGuia = false;
  String? _error;
  bool _precioConIsv = true;
  // Opcional: acota la búsqueda a un tipo de documento en particular. Hace
  // falta porque Factura/Boleta y Cotización usan contadores separados pero
  // el mismo relleno de 8 dígitos (ver VentaRepository.
  // buscarVentasPorNumeroDocumento), así que un mismo número escrito sin
  // ceros podría coincidir con más de una venta a la vez.
  String? _tipoDocumentoFiltro;

  @override
  void initState() {
    super.initState();
    if (widget.ventaIdInicial != null) {
      _buscarPorId(widget.ventaIdInicial!);
    } else if (widget.numeroDocumentoInicial != null) {
      _busquedaController.text = widget.numeroDocumentoInicial!;
      _buscarPorNumero();
    }
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _buscarPorId(String id) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final venta = await ref
          .read(ventaRepositoryProvider)
          .obtenerVentaPorId(id);
      if (!mounted) return;
      if (venta == null) {
        setState(() => _error = 'No se encontró la venta');
      } else {
        _busquedaController.text = venta.numeroDocumento;
        setState(() => _venta = venta);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al buscar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _buscarPorNumero() async {
    final texto = _busquedaController.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Ingresá un número de documento');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _venta = null;
    });
    try {
      final resultados = await ref
          .read(ventaRepositoryProvider)
          .buscarVentasPorNumeroDocumento(
            texto,
            tipoDocumento: _tipoDocumentoFiltro,
          );
      if (!mounted) return;
      if (resultados.isEmpty) {
        setState(
          () => _error =
              'No se encontró ninguna venta con ese número de documento',
        );
      } else if (resultados.length == 1) {
        setState(() => _venta = resultados.first);
      } else {
        final elegida = await _elegirEntreVarias(resultados);
        if (!mounted) return;
        if (elegida != null) {
          setState(() => _venta = elegida);
        } else {
          setState(
            () => _error =
                'Hay más de una venta con ese número: elegí el tipo de documento para buscar más preciso',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al buscar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Cuando el número escrito (sin ceros de relleno) coincide con más de
  /// una venta -típicamente una Factura/Boleta y una Cotización con el
  /// mismo número, ver VentaRepository.buscarVentasPorNumeroDocumento- se
  /// le pide al usuario que elija cuál era.
  Future<VentaModel?> _elegirEntreVarias(List<VentaModel> ventas) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return showDialog<VentaModel>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Hay más de una venta con ese número',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        content: SizedBox(
          width: 380,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: ventas.length,
            separatorBuilder: (context, i) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = ventas[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${tiposDocumento[v.tipoDocumento] ?? v.tipoDocumento} · ${v.numeroDocumento}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${v.nombreCliente.isEmpty ? 'Sin cliente' : v.nombreCliente}${v.fechaRegistro != null ? ' · ${formatoFecha.format(v.fechaRegistro!)}' : ''}',
                  style: GoogleFonts.poppins(fontSize: 11.5),
                ),
                onTap: () => Navigator.pop(context, v),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _limpiar() {
    _busquedaController.clear();
    setState(() {
      _venta = null;
      _error = null;
    });
  }

  /// Al reimprimir se le pregunta al usuario si esa hoja va a decir
  /// "ORIGINAL" o "COPIA" (por ejemplo, si el original ya se le dio al
  /// cliente y ahora hace falta una copia para el archivo del negocio, o al
  /// revés). Devuelve true para copia, false para original, null si canceló.
  Future<bool?> _elegirOriginalOCopia() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reimprimir',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿La hoja reimpresa debe decir "ORIGINAL" o "COPIA"?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Original', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Copia', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje), showCloseIcon: true));
  }

  Future<void> _reimprimir() async {
    final venta = _venta;
    if (venta == null) return;
    final esCopia = await _elegirOriginalOCopia();
    if (esCopia == null || !mounted) return;
    setState(() => _procesandoPdf = true);
    try {
      final negocio = await ref
          .read(negocioRepositoryProvider)
          .obtenerNegocioActual();
      if (!mounted) return;

      // En Android/iOS no hay impresoras del SO para elegir (esto es
      // exclusivo de escritorio): se intenta por ESC/POS de red, y si no
      // hay impresora de red configurada o falla, se le pide a la PC
      // principal que la reimprima ella sola (ver PresenciaImpresionRepository).
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _reimprimirEscPosORemoto(venta, negocio, esCopia);
        return;
      }

      // defaultTargetPlatform (a diferencia de Platform.isAndroid, que en
      // web no sirve de nada) detecta el sistema operativo real aunque se
      // esté usando desde el navegador.
      final esMovil =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      if (kIsWeb && esMovil) {
        await _pedirImpresionEnVivo(
          venta,
          esCopia,
          mensajeSinPc:
              'No se puede reimprimir directo desde el navegador del celular',
        );
        return;
      }

      final impresora = negocio.impresoraTermicaUrl.isEmpty
          ? null
          : Printer(
              url: negocio.impresoraTermicaUrl,
              name: negocio.impresoraTermicaNombre,
            );
      await showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo:
              'Vista previa · ${venta.numeroDocumento} (${esCopia ? 'copia' : 'original'})',
          nombreArchivo: 'venta_${venta.numeroDocumento}.pdf',
          generarPdf: () => _servicioExport.generarPdfFactura(
            venta,
            negocio,
            forzarCopia: esCopia,
          ),
          generarPdfConFormato: (formato) => _servicioExport.generarPdfFactura(
            venta,
            negocio,
            forzarCopia: esCopia,
            formatoImpresora: formato,
          ),
          impresora: impresora,
          generarTicketEscPos: () => _servicioTicketEscPos.generarTicket(
            venta,
            negocio,
            forzarCopia: esCopia,
          ),
          nombreImpresoraWindows: negocio.impresoraTermicaNombre,
          vistaPreviaTicket: () => TicketEscPosPreview(
            venta: venta,
            negocio: negocio,
            esCopia: esCopia,
          ),
          // Esta PC de escritorio puede no ser la que tiene la impresora
          // física conectada (ver Dispositivos > "Marcar como PC
          // principal") -pedido explícito del dueño-: si el intento local
          // falla, se le pide a la de verdad que reimprima ella sola en
          // vez de solo avisar el error.
          alFallarImprimir: () => _pedirImpresionEnVivo(
            venta,
            esCopia,
            mensajeSinPc: 'No se pudo imprimir, quedó pendiente de impresión',
          ),
        ),
      );
    } catch (e) {
      _mostrarMensaje('No se pudo generar el ticket: $e');
    } finally {
      if (mounted) setState(() => _procesandoPdf = false);
    }
  }

  Future<void> _reimprimirEscPosORemoto(
    VentaModel venta,
    NegocioModel negocio,
    bool esCopia,
  ) async {
    if (negocio.impresoraRedIp.isNotEmpty) {
      final bytes = await _servicioTicketEscPos.generarTicket(
        venta,
        negocio,
        forzarCopia: esCopia,
      );
      final ok = await _servicioImpresoraRed.imprimir(
        ip: negocio.impresoraRedIp,
        puerto: negocio.impresoraRedPuerto,
        bytes: bytes,
      );
      if (ok) {
        _mostrarMensaje('Ticket reimpreso');
        return;
      }
    }
    await _pedirImpresionEnVivo(venta, esCopia);
  }

  /// Imprime la guía de envío de esta venta -pedido explícito del dueño:
  /// "que pueda reimprimirse en detalle venta y también en una venta ya
  /// hecha que pueda generarse siempre... e imprimirse desde ahí"-. Si la
  /// venta YA tiene datos de envío guardados (esEnvio true), imprime
  /// directo. Si no (una venta que se hizo sin marcarla como envío en su
  /// momento), abre el mismo modal que Registrar Venta -prellenado del
  /// cliente vinculado si lo hay- para completarlos, los guarda en la
  /// venta, y recién ahí imprime.
  Future<void> _imprimirGuiaEnvio() async {
    final venta = _venta;
    if (venta == null) return;
    setState(() => _procesandoGuia = true);
    try {
      await _imprimirGuiaEnvioInterno(venta);
    } finally {
      if (mounted) setState(() => _procesandoGuia = false);
    }
  }

  Future<void> _imprimirGuiaEnvioInterno(VentaModel venta) async {
    var ventaConEnvio = venta;
    // El formato (normal/grande) SIEMPRE se pregunta acá, tenga o no la
    // venta datos de envío guardados ya -pedido explícito del dueño: dejar
    // las dos opciones de impresión disponibles siempre, no solo la primera
    // vez que se genera la guía-.
    String direccionInicial = venta.envioDireccion;
    String telefonoInicial = venta.envioTelefono;
    if (direccionInicial.isEmpty &&
        telefonoInicial.isEmpty &&
        venta.idCliente != null) {
      final cliente = await ref
          .read(clienteRepositoryProvider)
          .obtenerPorId(venta.idCliente!);
      direccionInicial = cliente?.direccion ?? '';
      telefonoInicial = cliente?.telefono ?? '';
    }
    if (!mounted) return;
    final resultado = await showDialog<DatosEnvioResultado>(
      context: context,
      builder: (context) => DatosEnvioDialog(
        nombreInicial: venta.envioNombre.isNotEmpty
            ? venta.envioNombre
            : (venta.nombreCliente == 'CONSUMIDOR FINAL'
                  ? ''
                  : venta.nombreCliente),
        direccionInicial: direccionInicial,
        telefonoInicial: telefonoInicial,
        mostrarOpcionImprimir: false,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      await ref
          .read(ventaRepositoryProvider)
          .actualizarDatosEnvio(
            id: venta.id,
            envioNombre: resultado.nombre,
            envioDireccion: resultado.direccion,
            envioTelefono: resultado.telefono,
          );
    } catch (e) {
      _mostrarMensaje('No se pudieron guardar los datos de envío: $e');
      return;
    }
    ventaConEnvio = venta.copyWith(
      esEnvio: true,
      envioNombre: resultado.nombre,
      envioDireccion: resultado.direccion,
      envioTelefono: resultado.telefono,
    );
    if (mounted) setState(() => _venta = ventaConEnvio);

    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;

    // Misma filosofía que _reimprimir: en Android/iOS (donde normalmente no
    // hay impresora térmica a mano) si no se puede imprimir directo por red,
    // se le pide a la PC principal -pedido explícito del dueño: "que
    // funcione en remoto, así como toda impresión"-. En escritorio, esta PC
    // ya es la candidata a "PC principal", así que si falla se avisa
    // directo, sin pedirle a nadie más (igual que el resto de la pantalla).
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (negocio.impresoraRedIp.isNotEmpty) {
        try {
          final bytes = await _servicioTicketEscPos.generarGuiaEnvio(
            ventaConEnvio,
            negocio,
            grande: resultado.formatoGrande,
          );
          final ok = await _servicioImpresoraRed.imprimir(
            ip: negocio.impresoraRedIp,
            puerto: negocio.impresoraRedPuerto,
            bytes: bytes,
          );
          if (ok) {
            _mostrarMensaje('Guía de envío impresa');
            return;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      try {
        await ref
            .read(ventaRepositoryProvider)
            .marcarSolicitudImpresionGuiaEnvio(
              venta.id,
              true,
              grande: resultado.formatoGrande,
            );
      } catch (_) {}
      final pcConectada = await _presencia.estaConectada();
      if (!mounted) return;
      if (pcConectada) {
        _mostrarMensaje(
          'Se envió la orden de impresión de la guía a la caja principal',
        );
      } else {
        _mostrarMensaje(
          'No se pudo imprimir la guía desde este dispositivo: quedó pendiente para la caja principal',
        );
      }
      return;
    }

    try {
      final bytes = await _servicioTicketEscPos.generarGuiaEnvio(
        ventaConEnvio,
        negocio,
        grande: resultado.formatoGrande,
      );
      if (!kIsWeb && Platform.isWindows) {
        if (negocio.impresoraTermicaNombre.isEmpty) {
          _mostrarMensaje(
            'No hay impresora configurada, no se pudo imprimir la guía de envío',
          );
          return;
        }
        final ok = ImpresoraUsbWindowsService().imprimir(
          nombreImpresora: negocio.impresoraTermicaNombre,
          bytes: bytes,
        );
        if (!ok) _mostrarMensaje('No se pudo imprimir la guía de envío');
      } else if (negocio.impresoraRedIp.isNotEmpty) {
        final ok = await _servicioImpresoraRed.imprimir(
          ip: negocio.impresoraRedIp,
          puerto: negocio.impresoraRedPuerto,
          bytes: bytes,
        );
        if (!ok) _mostrarMensaje('No se pudo imprimir la guía de envío');
      } else {
        _mostrarMensaje(
          'No hay impresora configurada, no se pudo imprimir la guía de envío',
        );
      }
    } catch (_) {
      _mostrarMensaje('No se pudo imprimir la guía de envío');
    }
  }

  Future<void> _pedirImpresionEnVivo(
    VentaModel venta,
    bool esCopia, {
    String mensajeSinPc = 'No se pudo reimprimir desde este dispositivo',
  }) async {
    final pcConectada = await _presencia.estaConectada();
    if (!mounted) return;
    if (pcConectada) {
      await ref
          .read(ventaRepositoryProvider)
          .marcarSolicitudImpresionEnVivo(venta.id, true, esCopia: esCopia);
      _mostrarMensaje(
        'Se envió la orden de reimpresión (${esCopia ? 'copia' : 'original'}) a la caja principal',
      );
    } else {
      _mostrarMensaje(mensajeSinPc);
    }
  }

  Future<void> _marcarComoImpresa() async {
    final venta = _venta;
    if (venta == null) return;
    try {
      await ref
          .read(ventaRepositoryProvider)
          .marcarPendienteImpresion(venta.id, false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar: $e'),
            showCloseIcon: true,
          ),
        );
      }
      return;
    }
    if (mounted) await _buscarPorId(venta.id);
  }

  Future<void> _descargarPdf() async {
    final venta = _venta;
    if (venta == null) return;
    setState(() => _procesandoPdf = true);
    try {
      final negocio = await ref
          .read(negocioRepositoryProvider)
          .obtenerNegocioActual();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Documento formal · ${venta.numeroDocumento}',
          nombreArchivo: '${venta.tipoDocumento}_${venta.numeroDocumento}.pdf',
          generarPdf: () => _servicioExport.generarPdfDetalleVenta(
            venta,
            negocio,
            preciosConIsv: _precioConIsv,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar el PDF: $e'),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoPdf = false);
    }
  }

  Future<void> _abrirRegistrarAbono() async {
    final venta = _venta;
    if (venta == null) return;
    final credito = await ref
        .read(ventaCreditoRepositoryProvider)
        .obtenerPorId(venta.id);
    if (!mounted) return;
    if (credito == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró el crédito asociado a esta venta'),
          showCloseIcon: true,
        ),
      );
      return;
    }
    if (credito.saldoPendiente <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este crédito ya está saldado'),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final abono = await showDialog<AbonoModel>(
      context: context,
      builder: (context) => RegistrarAbonoDialog(credito: credito),
    );
    if (abono == null || !mounted) return;
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
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Recibo de abono',
        nombreArchivo: 'recibo_${credito.numeroDocumento}.pdf',
        generarPdf: () => VentaCreditoExportService().generarPdfRecibo(
          credito,
          abono,
          negocio,
        ),
        impresora: impresora,
      ),
    );
  }

  /// Abre una pestaña nueva de "Registrar Venta" con los mismos productos de
  /// esta venta ya cargados en el carrito, lista para ajustar y confirmar
  /// como una venta nueva (no toca ni modifica la original). [forzarFactura]
  /// es lo que distingue "Duplicar venta" (una cotización sigue siendo
  /// cotización) de "Convertir a venta" (pasa a Factura).
  void _duplicarVenta(VentaModel venta, {bool forzarFactura = false}) {
    ref
        .read(ventaParaCargarProvider.notifier)
        .establecer(venta, forzarFactura: forzarFactura);
    final id = 'ventas_registrar_${DateTime.now().millisecondsSinceEpoch}';
    ref
        .read(tabsProvider.notifier)
        .abrirTab(
          TabItem(
            id: id,
            titulo: 'Registrar Venta',
            icono: Icons.add_shopping_cart_outlined,
            contenido: construirPantalla(
              'ventas_registrar',
              'Registrar Venta',
              Icons.add_shopping_cart_outlined,
              id,
            ),
          ),
        );
    // `popUntil((route) => route.isFirst)` en vez de un solo `pop` -pedido
    // explícito del dueño: antes había que salir manual-: cuando se llega acá
    // desde "Ver Facturas" (Navigator.push encima de la pestaña, y ESE
    // Detalle de Venta es otro push encima de Ver Facturas), un solo `pop`
    // solo cerraba Detalle de Venta y dejaba Ver Facturas tapando la pestaña
    // nueva ya activa. Esto cierra TODO lo apilado (venga de Ver Facturas,
    // de Pendientes de Impresión, o de un solo nivel) y deja ver de una vez
    // la pestaña de Registrar Venta recién abierta con la venta duplicada.
    if (widget.esDialogo) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _anular() async {
    final venta = _venta;
    if (venta == null) return;

    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Anular venta ${venta.numeroDocumento}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción repone al inventario el stock de los productos de esta venta y no se puede deshacer.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 14),
            CampoTecladoCompacto(
              controller: motivoController,
              numerico: false,
              titulo: 'Motivo (opcional)',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: motivoController,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Motivo (opcional)',
                  labelStyle: GoogleFonts.poppins(fontSize: 12.5),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Anular', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _anulando = true);
    try {
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      await ref
          .read(ventaRepositoryProvider)
          .anularVenta(
            id: venta.id,
            usuario: usuario,
            motivo: motivoController.text.trim(),
          );
      if (!mounted) return;
      await _buscarPorId(venta.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta anulada correctamente'),
            showCloseIcon: true,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _anulando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 760;

    final contenido = Padding(
      padding: EdgeInsets.all(esMovil ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.esDialogo
              ? Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Detalle de Venta',
                      style: GoogleFonts.poppins(
                        fontSize: esMovil ? 18 : 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(
                  'Detalle de Venta',
                  style: GoogleFonts.poppins(
                    fontSize: esMovil ? 19 : 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: esMovil ? tamano.width - 28 : 320,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB6BCC7)),
                  ),
                  child: CampoTecladoCompacto(
                    controller: _busquedaController,
                    numerico: false,
                    onSubmitted: (_) => _buscarPorNumero(),
                    titulo: 'Número de documento...',
                    child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _busquedaController,
                      autofocus: widget.ventaIdInicial == null,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Número de documento...',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _buscarPorNumero(),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: esMovil ? tamano.width - 28 : 200,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB6BCC7)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _tipoDocumentoFiltro,
                      isExpanded: true,
                      hint: Text(
                        'Tipo (todos)',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF1A1A1A),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Tipo (todos)',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                        ),
                        ...tiposDocumento.entries.map(
                          (e) => DropdownMenuItem<String?>(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _tipoDocumentoFiltro = v),
                    ),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _cargando ? null : _buscarPorNumero,
                icon: const Icon(Icons.search, size: 18),
                label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13)),
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
                onPressed: _cargando ? null : _limpiar,
                icon: const Icon(Icons.close, size: 18),
                label: Text(
                  'Limpiar',
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
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFC62828)),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: GoogleFonts.poppins(color: Colors.red),
                    ),
                  )
                : _venta == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Buscá una venta por su número de documento',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(child: _detalle(_venta!, esMovil)),
          ),
        ],
      ),
    );

    if (widget.esDialogo) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F3F7),
        body: SafeArea(child: contenido),
      );
    }
    return Container(color: const Color(0xFFF2F3F7), child: contenido);
  }

  Widget _detalle(VentaModel venta, bool esMovil) {
    final formatoDia = DateFormat('dd/MM/yyyy');
    final esCotizacion = venta.tipoDocumento == 'Cotizacion';
    final esCredito = venta.condicion == 'Credito';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (venta.estaAnulada) ...[
          _bannerAnulada(venta, formatoDia),
          const SizedBox(height: 14),
        ],
        if (venta.pendienteImpresion) ...[
          _bannerPendienteImpresion(),
          const SizedBox(height: 14),
        ],
        _tarjeta(
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _campoInfo('Tipo de documento', venta.tipoDocumento),
              _campoInfo('No. Documento', venta.numeroDocumento),
              _campoInfo(
                'Fecha',
                venta.fechaRegistro != null
                    ? formatoDia.format(venta.fechaRegistro!)
                    : '-',
              ),
              _campoInfo('Atendido por', venta.usuarioRegistro),
              _campoInfo(
                'Cliente',
                venta.nombreCliente.isEmpty
                    ? 'CONSUMIDOR FINAL'
                    : venta.nombreCliente,
              ),
              _campoInfo(
                'Documento cliente',
                venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente,
              ),
              _campoInfo('Condición', esCredito ? 'Crédito' : 'Contado'),
              if (esCredito && venta.fechaVencimiento != null)
                _campoInfo('Vence', formatoDia.format(venta.fechaVencimiento!)),
              if (!esCotizacion && !esCredito)
                _campoInfo('Método de pago', venta.metodoPago),
              _campoInfo('Estado', venta.estado),
              if (venta.observaciones.isNotEmpty)
                _campoInfo('Observaciones', venta.observaciones),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Productos',
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _selectorPrecioIsv(),
          ],
        ),
        const SizedBox(height: 10),
        _tarjeta(child: esMovil ? _tarjetasItems(venta) : _tablaItems(venta)),
        const SizedBox(height: 16),
        _tarjetaTotales(venta),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _procesandoPdf ? null : _reimprimir,
              icon: _procesandoPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1A1A1A),
                      ),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(
                'Reimprimir',
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
              onPressed: _procesandoPdf ? null : _descargarPdf,
              icon: _procesandoPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1A1A1A),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(
                'Descargar PDF',
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
            if (!venta.estaAnulada)
              OutlinedButton.icon(
                onPressed: _procesandoGuia ? null : _imprimirGuiaEnvio,
                icon: _procesandoGuia
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1565C0),
                        ),
                      )
                    : const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(
                  venta.esEnvio
                      ? 'Reimprimir guía de envío'
                      : 'Generar guía de envío',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (esCredito && !venta.estaAnulada)
              OutlinedButton.icon(
                onPressed: _abrirRegistrarAbono,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(
                  'Registrar Abono',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF16A34A),
                  side: const BorderSide(color: Color(0xFFBEE9CE)),
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
              onPressed: () => _duplicarVenta(venta),
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              label: Text(
                'Duplicar venta',
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
            if (esCotizacion && !venta.estaAnulada)
              FilledButton.icon(
                onPressed: () => _duplicarVenta(venta, forzarFactura: true),
                icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                label: Text(
                  'Convertir a venta',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (!esCotizacion && !venta.estaAnulada)
              FilledButton.icon(
                onPressed: _anulando ? null : _anular,
                icon: _anulando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.block_outlined, size: 18),
                label: Text(
                  _anulando ? 'Anulando...' : 'Anular Venta',
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
      ],
    );
  }

  Widget _bannerAnulada(VentaModel venta, DateFormat formatoDia) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE4E4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC62828)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_outlined, color: Color(0xFFC62828)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Esta venta está anulada',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFC62828),
                  ),
                ),
                if (venta.motivoAnulacion.isNotEmpty)
                  Text(
                    'Motivo: ${venta.motivoAnulacion}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFF7A1F1F),
                    ),
                  ),
                if (venta.usuarioAnulacion.isNotEmpty ||
                    venta.fechaAnulacion != null)
                  Text(
                    [
                      if (venta.usuarioAnulacion.isNotEmpty)
                        'Por ${venta.usuarioAnulacion}',
                      if (venta.fechaAnulacion != null)
                        'el ${formatoDia.format(venta.fechaAnulacion!)}',
                    ].join(' '),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFF7A1F1F),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerPendienteImpresion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0A63C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.print_disabled_outlined, color: Color(0xFF9A6B0F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Esta venta se guardó sin imprimir (probablemente desde el celular, sin la impresora a mano). Usá "Reimprimir" cuando tengas la impresora disponible.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFF9A6B0F),
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _marcarComoImpresa,
            child: Text(
              'Marcar como impresa',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF9A6B0F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
      ),
      child: child,
    );
  }

  Widget _campoInfo(String etiqueta, String valor) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            valor,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorPrecioIsv() {
    Widget opcion(String texto, bool valor) {
      final activo = _precioConIsv == valor;
      return InkWell(
        onTap: () => setState(() => _precioConIsv = valor),
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
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: activo ? Colors.white : const Color(0xFF666A72),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB6BCC7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [opcion('Con ISV', true), opcion('Sin ISV', false)],
      ),
    );
  }

  double _precioMostrado(dynamic item) => _precioConIsv
      ? redondearMoneda((item.precioVenta as double) * 1.15)
      : item.precioVenta as double;

  double _importeMostrado(dynamic item) {
    final precio = _precioMostrado(item);
    return redondearMoneda(
      precio *
          (item.cantidad as double) *
          (1 - (item.descuentoPorcentaje as double) / 100),
    );
  }

  Widget _tablaItems(VentaModel venta) {
    final estiloEncabezado = GoogleFonts.poppins(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'Cant.',
                textAlign: TextAlign.center,
                style: estiloEncabezado,
              ),
            ),
            Expanded(flex: 5, child: Text('Producto', style: estiloEncabezado)),
            Expanded(
              flex: 2,
              child: Text(
                _precioConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)',
                textAlign: TextAlign.right,
                style: estiloEncabezado,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Importe',
                textAlign: TextAlign.right,
                style: estiloEncabezado,
              ),
            ),
          ],
        ),
        Divider(height: 18, color: Colors.grey.shade300),
        for (final item in venta.detalle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatoCantidad(item.cantidad),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.nombreProducto,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.codigosColor.isNotEmpty)
                        Text(
                          'Código: ${item.codigosColor.join(', ')}',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      if (item.reembasado)
                        Text(
                          'Reembasado',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      if (item.descuentoPorcentaje > 0)
                        Text(
                          'Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: Colors.grey.shade400,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatearMoneda(_precioMostrado(item)),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatearMoneda(_importeMostrado(item)),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (item != venta.detalle.last)
            Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    );
  }

  Widget _tarjetasItems(VentaModel venta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in venta.detalle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombreProducto,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.codigosColor.isNotEmpty)
                  Text(
                    'Código: ${item.codigosColor.join(', ')}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFFC62828),
                    ),
                  ),
                if (item.reembasado || item.descuentoPorcentaje > 0)
                  Text(
                    [
                      if (item.reembasado) 'Reembasado',
                      if (item.descuentoPorcentaje > 0)
                        'Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%',
                    ].join(' · '),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(_precioMostrado(item))} = ${formatearMoneda(_importeMostrado(item))}',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: const Color(0xFF3F434A),
                  ),
                ),
              ],
            ),
          ),
          if (item != venta.detalle.last)
            Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    );
  }

  Widget _tarjetaTotales(VentaModel venta) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _filaTotalTexto('Subtotal', venta.subtotal),
              if (venta.descuentosYRebajas > 0)
                _filaTotalTexto(
                  'Descuentos y rebajas',
                  venta.descuentosYRebajas,
                ),
              _filaTotalTexto('ISV (15%)', venta.impuesto),
              if (venta.descuentoGlobal > 0)
                _filaTotalTextoPorcentaje(
                  'Descuento global',
                  venta.descuentoGlobal,
                ),
              if (venta.condicion != 'Credito' &&
                  venta.metodoPago == 'Efectivo' &&
                  venta.montoPago > 0) ...[
                _filaTotalTexto('Paga con', venta.montoPago),
                _filaTotalTexto('Cambio', venta.montoCambio),
              ],
              if (venta.condicion != 'Credito' && venta.metodoPago == 'Mixto')
                for (final pago in venta.pagosMixtos)
                  _filaTotalTexto(pago.metodoPago, pago.monto),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL A PAGAR',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  formatearMoneda(venta.totalAPagar),
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
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
        Text(
          etiqueta.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          formatearMoneda(valor),
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _filaTotalTextoPorcentaje(String etiqueta, double porcentaje) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          '${_formatoCantidad(porcentaje)}%',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble())
      return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
