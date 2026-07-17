import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/compra_model.dart';
import '../../providers/compras_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Pantalla de consulta de una compra ya registrada: buscá por número de
/// documento (o abrila directo desde Compras a Crédito pasando
/// [compraIdInicial]) para ver el detalle completo o anularla.
class DetalleCompraScreen extends ConsumerStatefulWidget {
  final String? compraIdInicial;
  final String? numeroDocumentoInicial;

  /// true cuando se abre como modal (push encima de otra pantalla, ej. desde
  /// un botón en Compras a Crédito): muestra su propio Scaffold y flecha de
  /// volver. false cuando se abre como pestaña del menú principal (ej.
  /// Compras > Ver Detalle): se embebe como las demás pantallas.
  final bool esDialogo;

  const DetalleCompraScreen({super.key, this.compraIdInicial, this.numeroDocumentoInicial, this.esDialogo = true});

  @override
  ConsumerState<DetalleCompraScreen> createState() => _DetalleCompraScreenState();
}

class _DetalleCompraScreenState extends ConsumerState<DetalleCompraScreen> {
  final _busquedaController = TextEditingController();
  CompraModel? _compra;
  bool _cargando = false;
  bool _anulando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.compraIdInicial != null) {
      _buscarPorId(widget.compraIdInicial!);
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
      final compra = await ref.read(compraRepositoryProvider).obtenerCompraPorId(id);
      if (!mounted) return;
      if (compra == null) {
        setState(() => _error = 'No se encontró la compra');
      } else {
        _busquedaController.text = compra.numeroDocumento;
        setState(() => _compra = compra);
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
      _compra = null;
    });
    try {
      final compra = await ref.read(compraRepositoryProvider).obtenerCompraPorNumeroDocumento(texto);
      if (!mounted) return;
      if (compra == null) {
        setState(() => _error = 'No se encontró ninguna compra con ese número de documento');
      } else {
        setState(() => _compra = compra);
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
      _compra = null;
      _error = null;
    });
  }

  Future<void> _anular() async {
    final compra = _compra;
    if (compra == null) return;

    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Anular compra ${compra.numeroDocumento}', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción descuenta del inventario el stock que esta compra había sumado y no se puede deshacer.',
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
      await ref.read(compraRepositoryProvider).anularCompra(id: compra.id, usuario: usuario, motivo: motivoController.text.trim());
      if (!mounted) return;
      await _buscarPorId(compra.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compra anulada correctamente')));
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
                    Text('Detalle de Compra', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                  ],
                )
              : Text('Detalle de Compra', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
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
                    autofocus: widget.compraIdInicial == null,
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
                    : _compra == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('Buscá una compra por su número de documento', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                              ],
                            ),
                          )
                        : SingleChildScrollView(child: _detalle(_compra!, esMovil)),
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

  Widget _detalle(CompraModel compra, bool esMovil) {
    final formatoDia = DateFormat('dd/MM/yyyy');
    final esCredito = compra.condicion == 'Credito';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compra.estaAnulada) ...[
          _bannerAnulada(compra, formatoDia),
          const SizedBox(height: 14),
        ],
        _tarjeta(
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _campoInfo('No. Factura', compra.noFactura.isEmpty ? '-' : compra.noFactura),
              _campoInfo('No. Documento', compra.numeroDocumento),
              _campoInfo('Fecha', compra.fechaRegistro != null ? formatoDia.format(compra.fechaRegistro!) : '-'),
              _campoInfo('Registrado por', compra.usuarioRegistro),
              _campoInfo('Proveedor', compra.razonSocial.isEmpty ? 'N/A' : compra.razonSocial),
              _campoInfo('RTN Proveedor', compra.documentoProveedor.isEmpty ? 'N/A' : compra.documentoProveedor),
              _campoInfo('Condición', esCredito ? 'Crédito' : 'Contado'),
              if (esCredito && compra.fechaVencimiento != null) _campoInfo('Vence', formatoDia.format(compra.fechaVencimiento!)),
              if (!esCredito) _campoInfo('Método de pago', compra.metodoPago),
              _campoInfo('Estado', compra.estado),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Productos', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _tarjeta(child: esMovil ? _tarjetasItems(compra) : _tablaItems(compra)),
        const SizedBox(height: 16),
        _tarjetaTotales(compra),
        const SizedBox(height: 20),
        if (!compra.estaAnulada)
          FilledButton.icon(
            onPressed: _anulando ? null : _anular,
            icon: _anulando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.block_outlined, size: 18),
            label: Text(_anulando ? 'Anulando...' : 'Anular Compra', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
      ],
    );
  }

  Widget _bannerAnulada(CompraModel compra, DateFormat formatoDia) {
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
                Text('Esta compra está anulada', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                if (compra.motivoAnulacion.isNotEmpty) Text('Motivo: ${compra.motivoAnulacion}', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF7A1F1F))),
                if (compra.usuarioAnulacion.isNotEmpty || compra.fechaAnulacion != null)
                  Text(
                    [
                      if (compra.usuarioAnulacion.isNotEmpty) 'Por ${compra.usuarioAnulacion}',
                      if (compra.fechaAnulacion != null) 'el ${formatoDia.format(compra.fechaAnulacion!)}',
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

  double _descuentoLineaMonto(dynamic item) {
    final sinDescuento = (item.precioCompra as double) * (item.cantidad as double);
    return sinDescuento - (item.subtotal as double);
  }

  Widget _tablaItems(CompraModel compra) {
    final estiloEncabezado = GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: Text('Cant.', textAlign: TextAlign.center, style: estiloEncabezado)),
            Expanded(flex: 5, child: Text('Producto', style: estiloEncabezado)),
            Expanded(flex: 2, child: Text('Costo unitario', textAlign: TextAlign.right, style: estiloEncabezado)),
            Expanded(flex: 2, child: Text('Descuento', textAlign: TextAlign.right, style: estiloEncabezado)),
            Expanded(flex: 2, child: Text('Importe', textAlign: TextAlign.right, style: estiloEncabezado)),
          ],
        ),
        Divider(height: 18, color: Colors.grey.shade300),
        for (final item in compra.detalle) ...[
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
                      if (item.descuentoPorcentaje > 0) Text('Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%', style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: Text(formatearMoneda(item.precioCompra), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13))),
                Expanded(flex: 2, child: Text(formatearMoneda(_descuentoLineaMonto(item)), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text(formatearMoneda(item.subtotal), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          if (item != compra.detalle.last) Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    );
  }

  Widget _tarjetasItems(CompraModel compra) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in compra.detalle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (item.descuentoPorcentaje > 0)
                  Text('Descuento ${_formatoCantidad(item.descuentoPorcentaje)}%', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text(
                  '${_formatoCantidad(item.cantidad)} x ${formatearMoneda(item.precioCompra)} = ${formatearMoneda(item.subtotal)}',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF3F434A)),
                ),
              ],
            ),
          ),
          if (item != compra.detalle.last) Divider(height: 1, color: Colors.grey.shade200),
        ],
      ],
    );
  }

  Widget _tarjetaTotales(CompraModel compra) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _filaTotalTexto('Subtotal', compra.subtotal),
              if (compra.descuentoTotalMonto > 0) _filaTotalTexto('Descuento total', compra.descuentoTotalMonto),
              _filaTotalTexto('ISV (${_formatoCantidad(compra.isvPorcentaje)}%)', compra.impuesto),
              if (compra.ajusteManual != 0) _filaTotalTexto('Ajuste', compra.ajusteManual),
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
                Text(formatearMoneda(compra.totalAPagar), style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
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

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }
}
