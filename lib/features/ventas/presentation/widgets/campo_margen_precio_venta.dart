import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Par de campos "Margen % <-> Precio de venta" sincronizados en ambos
/// sentidos -MISMA fórmula y MISMO mecanismo de sincronización que ya usa
/// Compras (ver RegistrarCompraScreen: _campoInlineConEtiqueta / _costoFinalItem
/// / _actualizarMargenCompra / _actualizarPrecioVentaCompra /
/// _sincronizarMargenControlador). No se reinventa la fórmula ni el
/// mecanismo acá, solo se empaqueta en un widget reusable para las otras
/// pantallas que necesitan lo mismo.
///
/// Fórmula (margen SOBRE EL COSTO, no sobre el precio):
///   porcentaje = (precioVenta - costo) / costo * 100
///   precioVenta = costo * (1 + porcentaje / 100)
///
/// Sincronización: los dos campos NO están conectados por `onChanged` -eso
/// dispararía en cada tecla y sería imposible terminar de escribir un
/// número sin que el otro campo se reescriba a mitad de camino-, sino por la
/// misma convención de "confirmar al perder el foco" que ya usa el resto de
/// la app (`FocusNode.addListener`, ver `_campoInlineNumero` en
/// registrar_compra_screen.dart): al confirmar un campo, el OTRO se
/// actualiza escribiendo directo su `TextEditingController.text` -una
/// asignación de propiedad simple, sin pasar por un método que dispare foco
/// ni reconstruya el campo- que es precisamente lo que evita el loop
/// infinito.
class CampoMargenPrecioVenta extends StatefulWidget {
  /// Costo contra el que se calcula el margen. Puede cambiar en caliente
  /// (ej. el cajero agrega otro tinte y el costo total sube): cuando eso
  /// pasa, se recalcula el margen mostrado a partir del precio de venta
  /// vigente -el precio de venta no se toca solo, igual que en Compras
  /// cuando cambia el costo unitario o el descuento de línea-.
  final double costoBase;

  /// Precio de venta inicial a mostrar/partir. Si es null, arranca en el
  /// propio [costoBase] (0% de margen).
  final double? precioVentaInicial;

  /// Se llama cada vez que se confirma un cambio en cualquiera de los dos
  /// campos (margen o precio), con el precio de venta resultante ya
  /// recalculado -así el que use este widget puede leer el precio vigente
  /// sin necesidad de un controller propio.
  final ValueChanged<double> onPrecioVentaCambiado;

  final String etiquetaMargen;
  final String etiquetaPrecio;

  const CampoMargenPrecioVenta({
    super.key,
    required this.costoBase,
    this.precioVentaInicial,
    required this.onPrecioVentaCambiado,
    this.etiquetaMargen = 'Margen %',
    this.etiquetaPrecio = 'Precio de venta',
  });

  @override
  State<CampoMargenPrecioVenta> createState() => CampoMargenPrecioVentaState();
}

class CampoMargenPrecioVentaState extends State<CampoMargenPrecioVenta> {
  late final TextEditingController _ctrlMargen;
  late final TextEditingController _ctrlPrecio;
  late final FocusNode _focusMargen;
  late final FocusNode _focusPrecio;
  late double _precioVenta;

  double get precioVentaVigente => _precioVenta;

  @override
  void initState() {
    super.initState();
    _precioVenta = redondearMoneda(widget.precioVentaInicial ?? widget.costoBase);
    _ctrlPrecio = TextEditingController(text: _precioVenta.toStringAsFixed(2));
    _ctrlMargen = TextEditingController(text: _margenDesde(_precioVenta).toStringAsFixed(1));
    _focusMargen = FocusNode()
      ..addListener(() {
        if (!_focusMargen.hasFocus) _confirmarMargen();
      });
    _focusPrecio = FocusNode()
      ..addListener(() {
        if (!_focusPrecio.hasFocus) _confirmarPrecio();
      });
  }

  @override
  void didUpdateWidget(covariant CampoMargenPrecioVenta oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El costo base cambió desde afuera (ej. se agregó/quitó un tinte de la
    // línea): se recalcula el margen mostrado contra el precio de venta
    // vigente -mismo criterio que _sincronizarMargenControlador en
    // Compras-, sin tocar el precio de venta solo y sin pisar lo que el
    // usuario esté escribiendo en ese momento.
    if (oldWidget.costoBase != widget.costoBase && !_focusMargen.hasFocus && !_focusPrecio.hasFocus) {
      setState(() => _ctrlMargen.text = _margenDesde(_precioVenta).toStringAsFixed(1));
    }
  }

  @override
  void dispose() {
    _ctrlMargen.dispose();
    _ctrlPrecio.dispose();
    _focusMargen.dispose();
    _focusPrecio.dispose();
    super.dispose();
  }

  double _margenDesde(double precio) => widget.costoBase > 0 ? ((precio - widget.costoBase) / widget.costoBase * 100) : 0.0;

  void _confirmarMargen() {
    final valor = double.tryParse(_ctrlMargen.text.replaceAll(',', '').trim());
    if (valor == null) return;
    final nuevoPrecio = redondearMoneda(widget.costoBase * (1 + valor / 100));
    setState(() {
      _precioVenta = nuevoPrecio;
      _ctrlPrecio.text = nuevoPrecio.toStringAsFixed(2);
    });
    widget.onPrecioVentaCambiado(nuevoPrecio);
  }

  void _confirmarPrecio() {
    final valor = double.tryParse(_ctrlPrecio.text.replaceAll(',', '').trim());
    if (valor == null || valor < 0) return;
    final precio = redondearMoneda(valor);
    setState(() {
      _precioVenta = precio;
      _ctrlMargen.text = _margenDesde(precio).toStringAsFixed(1);
    });
    widget.onPrecioVentaCambiado(precio);
  }

  /// Fuerza la confirmación del campo que tenga el foco en este momento -por
  /// si el usuario escribió un valor pero todavía no salió del campo (ni con
  /// Tab ni tocando afuera)- y devuelve el precio de venta ya vigente. Pensado
  /// para el botón "Agregar"/"Confirmar" de un diálogo que use este widget,
  /// para no perder un valor recién tecleado que nunca llegó a perder el foco.
  double confirmarYObtenerPrecioVenta() {
    if (_focusMargen.hasFocus) {
      _confirmarMargen();
    } else if (_focusPrecio.hasFocus) {
      _confirmarPrecio();
    }
    return _precioVenta;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _campo(_ctrlMargen, _focusMargen, widget.etiquetaMargen, sufijo: '%')),
        const SizedBox(width: 10),
        Expanded(child: _campo(_ctrlPrecio, _focusPrecio, widget.etiquetaPrecio, prefijo: 'L.')),
      ],
    );
  }

  Widget _campo(TextEditingController ctrl, FocusNode focus, String etiqueta, {String? sufijo, String? prefijo}) {
    return CampoTecladoCompacto(
      controller: ctrl,
      numerico: true,
      titulo: etiqueta,
      onSubmitted: (_) => focus.unfocus(),
      child: TextField(
        controller: ctrl,
        focusNode: focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        style: GoogleFonts.poppins(fontSize: 13),
        decoration: InputDecoration(
          labelText: etiqueta,
          labelStyle: GoogleFonts.poppins(fontSize: 11.5),
          suffixText: sufijo,
          prefixText: prefijo,
          prefixStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
          filled: true,
          fillColor: const Color(0xFFF2F3F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onSubmitted: (_) => focus.unfocus(),
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      ),
    );
  }
}
