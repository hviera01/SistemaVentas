import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../formulas/data/formula_colortrend_model.dart';
import '../../../formulas/data/formula_tamano_utils.dart';
import '../../../formulas/presentation/widgets/seleccionar_formula_dialog.dart';
import '../../data/costo_tinte_service.dart';
import '../../data/item_venta_model.dart';
import 'agregar_tinte_manual_dialog.dart';

/// Lo que devuelve CodigosColorDialog al cerrar: la lista final de códigos
/// de texto (igual que antes) más la lista final de tintes reales
/// consumidos por esta línea (nuevo, ver TinteConsumidoSnapshot).
class CodigosColorResultado {
  final List<String> codigos;
  final List<TinteConsumidoSnapshot> tintes;
  const CodigosColorResultado({required this.codigos, required this.tintes});
}

/// Diálogo compacto para agregar/quitar los códigos de color de una línea
/// del carrito (una línea puede llevar más de un código, ej. una pintura
/// mezclada con dos tintes) Y, desde acá, cargar el tinte real que se usó
/// para prepararla -para que ese costo se sume de verdad al costo de la
/// venta y el stock de tinte se descuente-, de dos formas:
/// - "Buscar fórmula": el código conectado a una fórmula real del libro
///   Color Codex -el tamaño (Cuarto/Galón/Quinto/Cubeta) se determina solo
///   según el nombre del producto de esta línea, y las onzas de cada
///   colorante salen de la fórmula (ver formula_tamano_utils.dart).
/// - "Tinte manual": sin código, el cajero elige el producto de tinte y
///   cuántas onzas le echó a ojo (ver AgregarTinteManualDialog).
/// Mismo espíritu liviano que antes -pensado para una interacción rápida en
/// caja-. Devuelve el resultado final al cerrar con "Listo" (o al tocar
/// afuera/la X: en ambos casos se conserva lo ya agregado/quitado, no hay
/// "cancelar" que descarte todo).
class CodigosColorDialog extends StatefulWidget {
  final List<String> codigosIniciales;
  final List<TinteConsumidoSnapshot> tintesIniciales;
  // Nombre y cantidad del producto de la línea de venta: hacen falta para
  // determinar el tamaño de fórmula (ver tamanoDesdeNombreProducto) y para
  // multiplicar las onzas por colorante de la fórmula (una fórmula da la
  // cantidad para UNA unidad del tamaño, la línea puede vender más de una).
  final String nombreProducto;
  final double cantidadLinea;

  const CodigosColorDialog({
    super.key,
    required this.codigosIniciales,
    this.tintesIniciales = const [],
    required this.nombreProducto,
    required this.cantidadLinea,
  });

  @override
  State<CodigosColorDialog> createState() => _CodigosColorDialogState();
}

class _CodigosColorDialogState extends State<CodigosColorDialog> {
  late List<String> _codigos;
  late List<TinteConsumidoSnapshot> _tintes;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _cargandoFormula = false;

  @override
  void initState() {
    super.initState();
    _codigos = [...widget.codigosIniciales];
    _tintes = [...widget.tintesIniciales];
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _agregarCodigoTexto() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _codigos.add(texto);
      _controller.clear();
    });
    _focusNode.requestFocus();
  }

  void _quitarCodigo(int index) => setState(() => _codigos.removeAt(index));
  void _quitarTinte(int index) => setState(() => _tintes.removeAt(index));

  void _cerrar() => Navigator.pop(context, CodigosColorResultado(codigos: _codigos, tintes: _tintes));

  void _mostrarMensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Escenario A: buscar una fórmula real y calcular sus tintes para el
  /// tamaño de esta línea. Si no se puede determinar el tamaño del
  /// producto, se agrega igual el código elegido como texto libre (mejor
  /// eso que no dejar anotar nada), pero sin calcular costo/stock -pedido
  /// explícito: mejor no calcular que calcular mal-.
  Future<void> _buscarFormula() async {
    final formula = await showDialog<FormulaColortrendModel>(context: context, builder: (context) => const SeleccionarFormulaDialog());
    if (formula == null || !mounted) return;

    final tamano = tamanoDesdeNombreProducto(widget.nombreProducto);
    if (tamano == null) {
      setState(() => _codigos.add(formula.codigo));
      _mostrarMensaje('No se pudo determinar el tamaño de "${widget.nombreProducto}" (Cuarto/Galón/Quinto/Cubeta) -se agregó el código, pero sin calcular el costo del tinte. Podés cargarlo con "Tinte manual".');
      return;
    }

    final usos = onzasFormulaParaTamano(formula, tamano, widget.cantidadLinea);
    if (usos.isEmpty) {
      setState(() => _codigos.add(formula.codigo));
      _mostrarMensaje('Esta fórmula no tiene datos de colorante para ${etiquetaTamano(tamano)} -se agregó el código, pero sin calcular el costo del tinte.');
      return;
    }

    setState(() => _cargandoFormula = true);
    final resultados = await CostoTinteService().calcular([for (final u in usos) UsoTinte(colorante: u.colorante, onzas: u.onzas)]);
    if (!mounted) return;
    setState(() => _cargandoFormula = false);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmarTintesFormulaDialog(formula: formula, tamano: tamano, usos: usos, resultados: resultados),
    );
    if (confirmar != true || !mounted) return;
    setState(() {
      _codigos.add(formula.codigo);
      _tintes.addAll(resultados.map((r) => r.toSnapshot()));
    });
  }

  /// Escenario B: tinte cargado a mano, sin código de fórmula.
  Future<void> _agregarTinteManual() async {
    final resultado = await showDialog<ResultadoCostoTinte>(context: context, builder: (context) => const AgregarTinteManualDialog());
    if (resultado == null || !mounted) return;
    setState(() => _tintes.add(resultado.toSnapshot()));
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width < 380 ? tamano.width - 48 : 340.0;
    final costoTinteTotal = _tintes.fold<double>(0, (s, t) => s + t.costoTotal);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: ancho,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Código(s) de color', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _cerrar),
              ],
            ),
            const SizedBox(height: 4),
            Text('Esta línea puede llevar más de un código.', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_codigos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Todavía no agregaste ningún código.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      )
                    else
                      for (var i = 0; i < _codigos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                Expanded(child: Text(_codigos[i], style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600))),
                                InkWell(
                                  onTap: () => _quitarCodigo(i),
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 16, color: Color(0xFFC62828))),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: CampoTecladoCompacto(
                            controller: _controller,
                            numerico: false,
                            onSubmitted: (_) => _agregarCodigoTexto(),
                            child: TextField(
                              inputFormatters: [mayusculasInputFormatter],
                              autocorrect: false,
                              enableSuggestions: false,
                              controller: _controller,
                              focusNode: _focusNode,
                              style: GoogleFonts.poppins(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Ej. C-104',
                                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                                filled: true,
                                fillColor: const Color(0xFFF2F3F7),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onSubmitted: (_) => _agregarCodigoTexto(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _agregarCodigoTexto,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text('Agregar', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A1A),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Tinte usado en esta línea', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Esto es lo que se descuenta de verdad del inventario y se suma como costo -separado del costo del producto base.', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(height: 10),
                    if (_tintes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('Sin tinte cargado todavía.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      )
                    else ...[
                      for (var i = 0; i < _tintes.length; i++) _filaTinte(i, _tintes[i]),
                      const SizedBox(height: 4),
                      Text('Costo total de tinte: ${formatearMoneda(costoTinteTotal)}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _cargandoFormula ? null : _buscarFormula,
                            icon: _cargandoFormula
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC62828)))
                                : const Icon(Icons.menu_book_outlined, size: 16),
                            label: Text('Buscar fórmula', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFC62828),
                              side: const BorderSide(color: Color(0xFFC62828)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _agregarTinteManual,
                            icon: const Icon(Icons.colorize, size: 16),
                            label: Text('Tinte manual', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1A1A1A),
                              side: const BorderSide(color: Color(0xFFB6BCC7)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _cerrar,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Listo', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaTinte(int index, TinteConsumidoSnapshot t) {
    final sinProducto = t.idProductoTinte.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: sinProducto ? const Color(0xFFFCE9E9) : const Color(0xFFF0FBF4), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nombreProductoTinte.isEmpty ? 'COLORANTE ${t.colorante}' : t.nombreProductoTinte, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(
                    sinProducto ? '${t.cuartosConsumidos.toStringAsFixed(3)} cuartos · sin producto en inventario' : '${t.cuartosConsumidos.toStringAsFixed(3)} cuartos · ${formatearMoneda(t.costoTotal)}',
                    style: GoogleFonts.poppins(fontSize: 11, color: sinProducto ? const Color(0xFFC62828) : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => _quitarTinte(index),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 16, color: Color(0xFFC62828))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmación previa a agregar los tintes de una fórmula elegida
/// (Escenario A): muestra el desglose -colorante, onzas, cuartos, costo- y
/// avisos (colorante sin producto de inventario, estimado en vez de dato
/// real del libro) ANTES de sumarlo a la línea -pedido explícito: mostrarle
/// la transparencia del cálculo al cajero, no solo calcularlo en silencio-.
class _ConfirmarTintesFormulaDialog extends StatelessWidget {
  final FormulaColortrendModel formula;
  final TamanoFormula tamano;
  final List<({String colorante, double onzas, bool esEstimado})> usos;
  final List<ResultadoCostoTinte> resultados;

  const _ConfirmarTintesFormulaDialog({required this.formula, required this.tamano, required this.usos, required this.resultados});

  @override
  Widget build(BuildContext context) {
    final total = resultados.fold<double>(0, (s, r) => s + r.costoTotal);
    final tamano_ = MediaQuery.sizeOf(context);
    final ancho = tamano_.width < 380 ? tamano_.width - 48 : 340.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: ancho,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${formula.codigo} · ${formula.nombre}', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
            Text('Tamaño: ${etiquetaTamano(tamano)}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final r in resultados)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('COLORANTE ${r.colorante}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  const Spacer(),
                                  Text('${r.onzas.toStringAsFixed(2)} oz', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                              Text(
                                r.resuelto ? '${r.cuartos.toStringAsFixed(3)} cuartos · ${formatearMoneda(r.costoTotal)}' : 'Sin producto en inventario -no se calcula costo.',
                                style: GoogleFonts.poppins(fontSize: 11.5, color: r.resuelto ? const Color(0xFF1E9E5A) : const Color(0xFFC62828)),
                              ),
                              if (r.advertencia != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(r.advertencia!, style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFFB45309))),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Costo total estimado de tinte: ${formatearMoneda(total)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Cancelar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Agregar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
