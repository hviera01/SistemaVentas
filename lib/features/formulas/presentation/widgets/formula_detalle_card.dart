import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/formula_colortrend_model.dart';

/// Muestra el detalle completo de una fórmula del Color Codex: código,
/// nombre, base, página del libro físico, y las cantidades agrupadas por
/// UNIDAD -Cuarto, Galón, Cubeta 5 Gal.- en vez de por tinte (pedido
/// explícito: así se lee de un vistazo "todo lo que necesito para preparar
/// un Galón", sin ir saltando de tarjeta en tarjeta por cada tinte). En
/// escritorio ancho las 3 unidades van una al lado de la otra, sin scroll;
/// en pantalla angosta (o si no entran las 3 de lado a lado) se apilan.
/// Tocar una unidad la muestra grande, centrada en pantalla (pedido
/// explícito: "si toco la card de Galón se pone en grande en el centro").
///
/// Las cantidades se muestran TAL CUAL las imprime el libro físico (texto
/// crudo del PDF, ej. "6", "0.5" o "1Y42" -pedido explícito: no
/// recalcularlas, para no arriesgar un error de conversión en un dato tan
/// delicado-. La única cantidad que SÍ se calcula es el estimado de Cuarto
/// cuando el libro no trae esa presentación (dice literal "No Quart
/// Formula"): se aproxima como Galón ÷ 4 y se formatea igual que el libro
/// -"enteroY48avos" (ej. "1Y46") si el entero es 1 o más, el número de
/// 48avos tal cual (ej. "6", "4.5") si el entero es 0-, marcado bien claro
/// como estimado, no como dato real del libro.
class FormulaDetalleCard extends StatelessWidget {
  final FormulaColortrendModel formula;

  const FormulaDetalleCard({super.key, required this.formula});

  static String _numeroSinCerosDeMas(double n) {
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  static String formatoEstimado(double? oz) {
    if (oz == null) return '—';
    var entero = oz.abs().floor();
    // Precisión de medio 48avo -misma que usa el libro en sus propios
    // valores impresos, ej. "4.5" o "1Y20.5"-.
    var avos = (((oz.abs() - entero) * 48) * 2).round() / 2;
    if (avos >= 48) {
      entero += 1;
      avos -= 48;
    }
    if (entero == 0) return _numeroSinCerosDeMas(avos);
    return '${entero}Y${_numeroSinCerosDeMas(avos)}';
  }

  void _abrirUnidadGrande(BuildContext context, String etiqueta, List<(String tinte, String valor, bool esEstimado)> filas) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(formula.codigo, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFFC62828))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(formula.nombre, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(etiqueta, style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: const Color(0xFF0F1B3D))),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final (tinte, valor, esEstimado) in filas)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Text(tinte, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800)),
                                  const Spacer(),
                                  Text(
                                    valor,
                                    style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: esEstimado ? const Color(0xFFB45309) : const Color(0xFFC62828)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = formula;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.codigo, style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w800, color: const Color(0xFFC62828))),
                    Text(f.nombre, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF0F1B3D), borderRadius: BorderRadius.circular(8)),
                child: Text(f.base.toUpperCase(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Libro físico: página ${f.pagina}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          if (!f.cuartoDisponible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El libro no trae fórmula de Cuarto para este color. El Cuarto de abajo es un estimado (Galón ÷ 4), no un valor impreso.',
                      style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final tresEnFila = constraints.maxWidth >= 620;
              final tarjetas = [
                _tarjetaUnidad(context, 'CUARTO', (c) => f.cuartoDisponible ? c.cuarto : null, estimado: !f.cuartoDisponible, estimadoValor: (c) => c.galonOz != null ? '≈ ${formatoEstimado(c.galonOz! / 4)}' : '—'),
                _tarjetaUnidad(context, 'GALÓN', (c) => c.galon),
                _tarjetaUnidad(context, 'CUBETA 5 GAL.', (c) => c.cubeta5gal),
              ];
              if (tresEnFila) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tarjetas.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: tarjetas[i]),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < tarjetas.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    tarjetas[i],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tarjetaUnidad(
    BuildContext context,
    String etiqueta,
    String? Function(ColoranteFormula) valorDe, {
    bool estimado = false,
    String Function(ColoranteFormula)? estimadoValor,
  }) {
    final filas = [
      for (final c in formula.colorantes)
        (
          c.colorante,
          (estimado && valorDe(c) == null) ? (estimadoValor?.call(c) ?? '—') : (valorDe(c) ?? '—'),
          estimado && valorDe(c) == null,
        ),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _abrirUnidadGrande(context, etiqueta, filas),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E2E8))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F1B3D), letterSpacing: 0.3)),
                ),
                Icon(Icons.open_in_full, size: 14, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 8),
            for (final (tinte, valor, esEstimado) in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 40, child: Text(tinte, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700))),
                    Expanded(
                      child: Text(
                        valor,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: esEstimado ? const Color(0xFFB45309) : const Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
