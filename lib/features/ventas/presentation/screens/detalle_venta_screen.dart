import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../data/venta_model.dart';
import '../../data/venta_export_service.dart';
import '../../providers/ventas_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../ventas_credito/data/abono_model.dart';
import '../../../ventas_credito/data/venta_credito_export_service.dart';
import '../../../ventas_credito/providers/ventas_credito_provider.dart';
import '../../../ventas_credito/presentation/widgets/registrar_abono_dialog.dart';

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

  const DetalleVentaScreen({super.key, this.ventaIdInicial, this.numeroDocumentoInicial, this.esDialogo = true});

  @override
  ConsumerState<DetalleVentaScreen> createState() => _DetalleVentaScreenState();
}

class _DetalleVentaScreenState extends ConsumerState<DetalleVentaScreen> {
  final _busquedaController = TextEditingController();
  final _servicioExport = VentaExportService();
  VentaModel? _venta;
  bool _cargando = false;
  bool _anulando = false;
  bool _procesandoPdf = false;
  String? _error;
  bool _precioConIsv = true;

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
      final venta = await ref.read(ventaRepositoryProvider).obtenerVentaPorId(id);
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
      final venta = await ref.read(ventaRepositoryProvider).obtenerVentaPorNumeroDocumento(texto);
      if (!mounted) return;
      if (venta == null) {
        setState(() => _error = 'No se encontró ninguna venta con ese número de documento');
      } else {
        setState(() => _venta = venta);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al buscar: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _limpiar() {
    _busquedaController.clear();
    setState(() {
      _venta = null;
      _error = null;
    });
  }

  Future<void> _reimprimir() async {
    final venta = _venta;
    if (venta == null) return;
    setState(() => _procesandoPdf = true);
    try {
      final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
      if (!mounted) return;
      final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
      await showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Vista previa · ${venta.numeroDocumento}',
          nombreArchivo: 'venta_${venta.numeroDocumento}.pdf',
          generarPdf: () => _servicioExport.generarPdfFactura(venta, negocio),
          impresora: impresora,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el ticket: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesandoPdf = false);
    }
  }

  Future<void> _descargarPdf() async {
    final venta = _venta;
    if (venta == null) return;
    setState(() => _procesandoPdf = true);
    try {
      final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Documento formal · ${venta.numeroDocumento}',
          nombreArchivo: '${venta.tipoDocumento}_${venta.numeroDocumento}.pdf',
          generarPdf: () => _servicioExport.generarPdfDetalleVenta(venta, negocio),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesandoPdf = false);
    }
  }

  Future<void> _abrirRegistrarAbono() async {
    final venta = _venta;
    if (venta == null) return;
    final credito = await ref.read(ventaCreditoRepositoryProvider).obtenerPorId(venta.id);
    if (!mounted) return;
    if (credito == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró el crédito asociado a esta venta')));
      return;
    }
    if (credito.saldoPendiente <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este crédito ya está saldado')));
      return;
    }
    final abono = await showDialog<AbonoModel>(context: context, builder: (context) => RegistrarAbonoDialog(credito: credito));
    if (abono == null || !mounted) return;
    final negocio = await ref.read(negocioRepositoryProvider).obtenerNegocioActual();
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty ? null : Printer(url: negocio.impresoraTermicaUrl, name: negocio.impresoraTermicaNombre);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Recibo de abono',
        nombreArchivo: 'recibo_${credito.numeroDocumento}.pdf',
        generarPdf: () => VentaCreditoExportService().generarPdfRecibo(credito, abono, negocio),
        impresora: impresora,
      ),
    );
  }

  Future<void> _anular() async {
    final venta = _venta;
    if (venta == null) return;

    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Anular venta ${venta.numeroDocumento}', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción repone al inventario el stock de los productos de esta venta y no se puede deshacer.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: motivoController,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Motivo (opcional)',
                labelStyle: GoogleFonts.poppins(fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
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
      await ref.read(ventaRepositoryProvider).anularVenta(id: venta.id, usuario: usuario, motivo: motivoController.text.trim());
      if (!mounted) return;
      await _buscarPorId(venta.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta anulada correctamente')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
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
                        IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                        const SizedBox(width: 6),
                        Text('Detalle de Venta', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                      ],
                    )
                  : Text('Detalle de Venta', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
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
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB6BCC7))),
                      child: TextField(
                        controller: _busquedaController,
                        autofocus: widget.ventaIdInicial == null,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Número de documento...',
                          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _buscarPorNumero(),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _cargando ? null : _buscarPorNumero,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  OutlinedButton.icon(
                    onPressed: _cargando ? null : _limpiar,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))
                    : _error != null
                        ? Center(child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red)))
                        : _venta == null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
                                    const SizedBox(height: 12),
                                    Text('Buscá una venta por su número de documento', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
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
        _tarjeta(
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _campoInfo('Tipo de documento', venta.tipoDocumento),
              _campoInfo('No. Documento', venta.numeroDocumento),
              _campoInfo('Fecha', venta.fechaRegistro != null ? formatoDia.format(venta.fechaRegistro!) : '-'),
              _campoInfo('Atendido por', venta.usuarioRegistro),
              _campoInfo('Cliente', venta.nombreCliente.isEmpty ? 'CONSUMIDOR FINAL' : venta.nombreCliente),
              _campoInfo('Documento cliente', venta.documentoCliente.isEmpty ? 'N/A' : venta.documentoCliente),
              _campoInfo('Condición', esCredito ? 'Crédito' : 'Contado'),
              if (esCredito && venta.fechaVencimiento != null) _campoInfo('Vence', formatoDia.format(venta.fechaVencimiento!)),
              if (!esCotizacion && !esCredito) _campoInfo('Método de pago', venta.metodoPago),
              _campoInfo('Estado', venta.estado),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Productos', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
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
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A1A)))
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text('Reimprimir', style: GoogleFonts.poppins(fontSize: 13)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            OutlinedButton.icon(
              onPressed: _procesandoPdf ? null : _descargarPdf,
              icon: _procesandoPdf
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A1A)))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text('Descargar PDF', style: GoogleFonts.poppins(fontSize: 13)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            if (esCredito && !venta.estaAnulada)
              OutlinedButton.icon(
                onPressed: _abrirRegistrarAbono,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Registrar Abono', style: GoogleFonts.poppins(fontSize: 13)),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF16A34A), side: const BorderSide(color: Color(0xFFBEE9CE)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            if (!esCotizacion && !venta.estaAnulada)
              FilledButton.icon(
                onPressed: _anulando ? null : _anular,
                icon: _anulando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.block_outlined, size: 18),
                label: Text(_anulando ? 'Anulando...' : 'Anular Venta', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      decoration: BoxDecoration(color: const Color(0xFFFCE4E4), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC62828))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_outlined, color: Color(0xFFC62828)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Esta venta está anulada', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                if (venta.motivoAnulacion.isNotEmpty) Text('Motivo: ${venta.motivoAnulacion}', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF7A1F1F))),
                if (venta.usuarioAnulacion.isNotEmpty || venta.fechaAnulacion != null)
                  Text(
                    [
                      if (venta.usuarioAnulacion.isNotEmpty) 'Por ${venta.usuarioAnulacion}',
                      if (venta.fechaAnulacion != null) 'el ${formatoDia.format(venta.fechaAnulacion!)}',
                    ].join(' '),
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF7A1F1F)),
                  ),
              ],
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
          Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
          const SizedBox(height: 3),
          Text(valor, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A))),
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
          decoration: BoxDecoration(color: activo ? const Color(0xFFC62828) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(texto, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opcion('Con ISV', true), opcion('Sin ISV', false)]),
    );
  }

  double _precioMostrado(dynamic item) => _precioConIsv ? redondearMoneda((item.precioVenta as double) * 1.15) : item.precioVenta as double;

  double _importeMostrado(dynamic item) {
    final precio = _precioMostrado(item);
    return redondearMoneda(precio * (item.cantidad as double) * (1 - (item.descuentoPorcentaje as double) / 100));
  }

  Widget _tablaItems(VentaModel venta) {
    final estiloEncabezado = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: Text('Cant.', textAlign: TextAlign.center, style: estiloEncabezado)),
            Expanded(flex: 5, child: Text('Producto', style: estiloEncabezado)),
            Expanded(flex: 2, child: Text(_precioConIsv ? 'Precio (c/ISV)' : 'Precio (s/ISV)', textAlign: TextAlign.right, style: estiloEncabezado)),
            Expanded(flex: 2, child: Text('Importe', textAlign: TextAlign.right, style: estiloEncabezado)),
          ],
        ),
        Divider(height: 18, color: Colors.grey.shade300),
        for (final item in venta.detalle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 2, child: Text(_formatoCantidad(item.cantidad), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13))),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      if (item.reembasado) Text('Reembasado', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                      if (item.descuentoPorcentaje > 0) Text('Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: Text(formatearMoneda(_precioMostrado(item)), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13))),
                Expanded(flex: 2, child: Text(formatearMoneda(_importeMostrado(item)), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          if (item != venta.detalle.last) Divider(height: 1, color: Colors.grey.shade200),
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
                Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (item.reembasado || item.descuentoPorcentaje > 0)
                  Text(
                    [if (item.reembasado) 'Reembasado', if (item.descuentoPorcentaje > 0) 'Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%'].join(' · '),
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(_precioMostrado(item))} = ${formatearMoneda(_importeMostrado(item))}',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF3F434A)),
                ),
              ],
            ),
          ),
          if (item != venta.detalle.last) Divider(height: 1, color: Colors.grey.shade200),
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
              _filaTotalTexto('ISV (15%)', venta.impuesto),
              if (venta.descuentoGlobal > 0) _filaTotalTextoPorcentaje('Descuento global', venta.descuentoGlobal),
              if (venta.condicion != 'Credito' && venta.metodoPago == 'Efectivo' && venta.montoPago > 0) ...[
                _filaTotalTexto('Paga con', venta.montoPago),
                _filaTotalTexto('Cambio', venta.montoCambio),
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
                Text(formatearMoneda(venta.totalAPagar), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
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

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
