import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/rendimiento_pintura_data.dart';

/// Calculadora de cuánta pintura hace falta según el área a pintar, como
/// panel flotante minimizable -pedido explícito del dueño: "pongamos esa
/// calculadora en Registrar Venta, una ventana igual que lo de Consulta de
/// Costos que se pueda minimizar". Mismo patrón EXACTO que
/// ConsultarCostoFlotanteController (ver panel_flotante_consultar_costo.dart,
/// ya corregido y verificado): Route transparente al Navigator raíz -no un
/// OverlayEntry suelto, eso fue el bug real corregido ahí y no hay que
/// repetirlo acá-, minimizar mantiene el contenido vivo
/// (Visibility.maintainState), cerrar sí lo descarta, tocar afuera minimiza.
class CalculadoraRendimientoFlotanteController {
  Route<void>? _route;
  final ValueNotifier<bool> minimizado = ValueNotifier(false);

  void abrir(BuildContext context) {
    if (_route != null) {
      minimizado.value = false;
      return;
    }
    minimizado.value = false;
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => PanelFlotanteCalculadoraRendimiento(controlador: this),
    );
    _route = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() => _route = null);
  }

  void minimizarPanel() => minimizado.value = true;

  void restaurarPanel() => minimizado.value = false;

  void cerrar() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void dispose() {
    cerrar();
    minimizado.dispose();
  }
}

class PanelFlotanteCalculadoraRendimiento extends StatelessWidget {
  final CalculadoraRendimientoFlotanteController controlador;

  const PanelFlotanteCalculadoraRendimiento({super.key, required this.controlador});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controlador.minimizado,
      builder: (context, minimizado, _) {
        return Stack(
          children: [
            // Positioned.fill tiene que ser hijo DIRECTO del Stack, y
            // ExcludeSemantics+IgnorePointer+Opacity en vez de
            // Visibility(maintainState:true) -ver la nota grande en
            // panel_flotante_consultar_costo.dart: Offstage (lo que
            // Visibility usa por dentro) deja los TextField del formulario
            // "vivos" y con foco reclamable aunque estén invisibles, que
            // era lo que dejaba el sistema entero atascado al minimizar.
            Positioned.fill(
              child: ExcludeSemantics(
                excluding: minimizado,
                child: IgnorePointer(
                  ignoring: minimizado,
                  child: Opacity(
                    opacity: minimizado ? 0 : 1,
                    // Sin Material acá el texto de adentro sale con el
                    // subrayado amarillo doble de "falta ancestro Material"
                    // -esta Route no es MaterialPageRoute, no lo trae solo.
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: controlador.minimizarPanel,
                              child: Container(color: Colors.black.withValues(alpha: 0.4)),
                            ),
                          ),
                          Center(
                            child: GestureDetector(onTap: () {}, child: _ContenidoCalculadora(controlador: controlador)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (minimizado) _chipRestaurar(context),
          ],
        );
      },
    );
  }

  Widget _chipRestaurar(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(30),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: controlador.restaurarPanel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.straighten, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Calculadora de pintura', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ModoArea { dimensiones, lineal, m2 }

class _ContenidoCalculadora extends StatefulWidget {
  final CalculadoraRendimientoFlotanteController controlador;
  const _ContenidoCalculadora({required this.controlador});

  @override
  State<_ContenidoCalculadora> createState() => _ContenidoCalculadoraState();
}

class _ContenidoCalculadoraState extends State<_ContenidoCalculadora> {
  _ModoArea _modo = _ModoArea.dimensiones;
  TipoProductoPintura _tipo = TipoProductoPintura.latex;
  final _ctrlAncho = TextEditingController();
  final _ctrlAlto = TextEditingController();
  final _ctrlLineal = TextEditingController();
  final _ctrlAlturaLineal = TextEditingController();
  final _ctrlM2 = TextEditingController();
  final _ctrlManos = TextEditingController(text: '2');
  ResultadoRendimientoPintura? _resultado;
  String? _error;

  @override
  void dispose() {
    _ctrlAncho.dispose();
    _ctrlAlto.dispose();
    _ctrlLineal.dispose();
    _ctrlAlturaLineal.dispose();
    _ctrlM2.dispose();
    _ctrlManos.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim()) ?? 0;

  void _calcular() {
    double areaM2;
    switch (_modo) {
      case _ModoArea.dimensiones:
        areaM2 = areaDesdeAnchoAlto(_num(_ctrlAncho), _num(_ctrlAlto));
        break;
      case _ModoArea.lineal:
        areaM2 = areaDesdeLineal(_num(_ctrlLineal), _num(_ctrlAlturaLineal));
        break;
      case _ModoArea.m2:
        areaM2 = _num(_ctrlM2);
        break;
    }
    if (areaM2 <= 0) {
      setState(() {
        _error = 'Ingresá un área mayor a cero para calcular.';
        _resultado = null;
      });
      return;
    }
    final manos = _num(_ctrlManos).round();
    setState(() {
      _error = null;
      _resultado = calcularPintura(areaM2, _tipo, manos);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width - 48 < 480 ? tamano.width - 48 : 480.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: ancho, maxHeight: tamano.height - 48),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(child: Text('Calculadora de pintura', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.remove), tooltip: 'Minimizar', onPressed: widget.controlador.minimizarPanel),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: widget.controlador.cerrar),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimado según el área y el tipo de producto -pedí confirmación para proyectos grandes.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _botonModo('Ancho × Alto', _ModoArea.dimensiones),
                        _botonModo('Metros lineales', _ModoArea.lineal),
                        _botonModo('Metros cuadrados', _ModoArea.m2),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_modo == _ModoArea.dimensiones)
                      Row(
                        children: [
                          Expanded(child: _campo('Ancho (m)', _ctrlAncho)),
                          const SizedBox(width: 10),
                          Expanded(child: _campo('Alto (m)', _ctrlAlto)),
                        ],
                      )
                    else if (_modo == _ModoArea.lineal)
                      Row(
                        children: [
                          Expanded(child: _campo('Metros lineales', _ctrlLineal)),
                          const SizedBox(width: 10),
                          Expanded(child: _campo('Altura (m)', _ctrlAlturaLineal)),
                        ],
                      )
                    else
                      _campo('Área (m²)', _ctrlM2),
                    const SizedBox(height: 10),
                    Text('Tipo de producto', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFB6BCC7))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<TipoProductoPintura>(
                          value: _tipo,
                          isExpanded: true,
                          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
                          items: [
                            for (final t in TipoProductoPintura.values)
                              DropdownMenuItem(value: t, child: Text(etiquetaTipoProductoPintura(t))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _tipo = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _campo('Número de manos', _ctrlManos),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _calcular,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: Text('Calcular', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFFC62828))),
                    ],
                    if (_resultado != null) ...[const SizedBox(height: 14), _resumenResultado(_resultado!)],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonModo(String texto, _ModoArea valor) {
    final activo = _modo == valor;
    return InkWell(
      onTap: () => setState(() => _modo = valor),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: activo ? const Color(0xFF1565C0) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: activo ? const Color(0xFF1565C0) : const Color(0xFFB6BCC7))),
        child: Text(texto, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: activo ? Colors.white : const Color(0xFF666A72))),
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFB6BCC7))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFB6BCC7))),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _resumenResultado(ResultadoRendimientoPintura r) {
    final partes = <String>[];
    if (r.compra.cubetas > 0) partes.add('${r.compra.cubetas} cubeta${r.compra.cubetas > 1 ? "s" : ""} (5 gal)');
    if (r.compra.galones > 0) partes.add('${r.compra.galones} galón${r.compra.galones > 1 ? "es" : ""}');
    if (r.compra.cuartos > 0) partes.add('${r.compra.cuartos} cuarto${r.compra.cuartos > 1 ? "s" : ""}');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFE8F5EC), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Área: ${r.areaM2.toStringAsFixed(2)} m²', style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF16A34A))),
          const SizedBox(height: 2),
          Text('Necesitás aprox. ${r.galonesNecesarios.toStringAsFixed(2)} galones', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
          const SizedBox(height: 6),
          Text(
            'Sugerencia de compra: ${partes.isNotEmpty ? partes.join(' + ') : 'menos de un cuarto'}',
            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF16A34A)),
          ),
        ],
      ),
    );
  }
}
