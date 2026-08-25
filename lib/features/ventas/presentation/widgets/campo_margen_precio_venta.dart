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
/// Sincronización: en vivo, en cada tecla, escuchando directo los
/// TextEditingController (no `onChanged` del TextField ni FocusNode.
/// addListener/confirmar-al-perder-el-foco, que era el mecanismo original
/// -copiado de Compras- pero en la práctica no servía acá: el cajero
/// cambia el precio y toca un botón de una sin "salir" del campo primero
/// -no hay Tab, y tocar un botón no siempre cuenta como perder el foco
/// antes de que se lea el valor-, así que el otro campo se quedaba
/// desactualizado). Para evitar el loop infinito (A actualiza B, B
/// notifica su listener, que actualizaría A de nuevo...) hay una bandera
/// [_sincronizando] que cada listener revisa antes de hacer nada: mientras
/// un campo está escribiendo en el OTRO, ese otro no reacciona.
class CampoMargenPrecioVenta extends StatefulWidget {
  /// Costo contra el que se calcula el margen. Puede cambiar en caliente
  /// (ej. el cajero agrega otro tinte y el costo total sube): cuando eso
  /// pasa, se recalcula el margen mostrado a partir del precio de venta
  /// vigente -el precio de venta no se toca solo, igual que en Compras
  /// cuando cambia el costo unitario o el descuento de línea-.
  final double costoBase;

  /// Precio de venta inicial a mostrar/partir, con ISV incluido igual que
  /// [costoBase]. Si es null, arranca en el propio [costoBase] (0% de
  /// margen).
  final double? precioVentaInicial;

  /// Comparación DIRECTA contra [costoBase], sin convertir nada por ISV -
  /// mismo criterio EXACTO que Compras (ver _costoFinalItem/_margenActual en
  /// registrar_compra_screen.dart): el costo que usa toda esta app (lotes de
  /// compra, FIFO, `item.precioCompraUsado`, `ProductoModel.precioCompra`)
  /// YA se guarda CON ISV incluido -ver CompraRepository.registrarCompra,
  /// `precioFinalConIsv = precioCompra * (1-descuento) * (1+isv/100)`, eso
  /// es lo que se graba como costoUnitario de cada lote-, y el precio de
  /// venta que se muestra acá también es con ISV. Antes este widget SÍ
  /// intentaba convertir (asumiendo que costoBase era sin ISV), lo que
  /// mezclaba mal las unidades y mostraba un margen negativo con precios
  /// que en realidad sí dejaban ganancia -bug real reportado por el dueño-.
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
  bool _sincronizando = false;

  double get precioVentaVigente => _precioVenta;

  @override
  void initState() {
    super.initState();
    _precioVenta = redondearMoneda(widget.precioVentaInicial ?? widget.costoBase);
    _ctrlPrecio = TextEditingController(text: _precioVenta.toStringAsFixed(2));
    _ctrlMargen = TextEditingController(text: _margenDesde(_precioVenta).toStringAsFixed(1));
    _focusMargen = FocusNode();
    _focusPrecio = FocusNode();
    _ctrlMargen.addListener(_confirmarMargen);
    _ctrlPrecio.addListener(_confirmarPrecio);
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
      _sincronizando = true;
      setState(() => _ctrlMargen.text = _margenDesde(_precioVenta).toStringAsFixed(1));
      _sincronizando = false;
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

  double _margenDesde(double precio) {
    if (widget.costoBase <= 0) return 0.0;
    return (precio - widget.costoBase) / widget.costoBase * 100;
  }

  double _precioDesdeMargen(double margen) {
    return redondearMoneda(widget.costoBase * (1 + margen / 100));
  }

  // Escuchan directo los TextEditingController (dispara con cada tecla, no
  // solo al perder el foco -ver la nota grande de la clase sobre por qué se
  // cambió-). [_sincronizando] evita el loop: mientras uno de los dos está
  // escribiendo en el controller del OTRO, ese otro no vuelve a reaccionar.
  void _confirmarMargen() {
    if (_sincronizando) return;
    final valor = double.tryParse(_ctrlMargen.text.replaceAll(',', '').trim());
    if (valor == null) return;
    final nuevoPrecio = _precioDesdeMargen(valor);
    _precioVenta = nuevoPrecio;
    _sincronizando = true;
    _ctrlPrecio.text = nuevoPrecio.toStringAsFixed(2);
    _sincronizando = false;
    widget.onPrecioVentaCambiado(nuevoPrecio);
  }

  void _confirmarPrecio() {
    if (_sincronizando) return;
    final valor = double.tryParse(_ctrlPrecio.text.replaceAll(',', '').trim());
    if (valor == null || valor < 0) return;
    final precio = redondearMoneda(valor);
    _precioVenta = precio;
    _sincronizando = true;
    _ctrlMargen.text = _margenDesde(precio).toStringAsFixed(1);
    _sincronizando = false;
    widget.onPrecioVentaCambiado(precio);
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
