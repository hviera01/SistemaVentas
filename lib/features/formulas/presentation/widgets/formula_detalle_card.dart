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
/// Tocar una unidad la agranda un poco -sin ocultar las otras dos, solo les
/// da menos espacio- para leerla más cómodo.
///
/// Las cantidades se muestran en la MISMA notación del libro y de la
/// dispensadora física -entero + 48avos ("1Y47"), no en onzas decimales-,
/// calculada a partir del valor ya convertido y verificado (ver
/// FormulaColortrendModel: cruzado matemáticamente contra las relaciones
/// Cuarto×4=Galón y Galón×5=Cubeta de cientos de fórmulas del propio libro).
/// Cuando el libro no trae fórmula de Cuarto (dice literal "No Quart
/// Formula"), se muestra un estimado -Galón ÷ 4- marcado bien claro como
/// estimado, no como dato real del libro.
class FormulaDetalleCard extends StatefulWidget {
  final FormulaColortrendModel formula;

  const FormulaDetalleCard({super.key, required this.formula});

  @override
  State<FormulaDetalleCard> createState() => _FormulaDetalleCardState();
}

enum _Unidad { cuarto, galon, cubeta }

class _FormulaDetalleCardState extends State<FormulaDetalleCard> {
  _Unidad? _expandida;

  /// Entero + 48avos, tal cual se lee en la dispensadora física (0 a 47 por
  /// cada "Y") -pedido explícito: "entero.48avosY", no "enteroY48avos", ej.
  /// 1.979166 oz -> "1.47Y" (1 entero, 47 de 48avos).
  String _formatoY(double? oz) {
    if (oz == null) return '—';
    final abs = oz.abs();
    var entero = abs.floor();
    var avos = ((abs - entero) * 48).round();
    if (avos >= 48) {
      entero += 1;
      avos -= 48;
    }
    return '$entero.${avos.toString().padLeft(2, '0')}Y';
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.formula;
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
                _tarjetaUnidad(_Unidad.cuarto, 'CUARTO', (c) => f.cuartoDisponible ? _formatoY(c.cuartoOz) : null, estimado: !f.cuartoDisponible, estimadoValor: (c) => c.galonOz != null ? '≈ ${_formatoY(c.galonOz! / 4)}' : '—'),
                _tarjetaUnidad(_Unidad.galon, 'GALÓN', (c) => _formatoY(c.galonOz)),
                _tarjetaUnidad(_Unidad.cubeta, 'CUBETA 5 GAL.', (c) => _formatoY(c.cubeta5galOz)),
              ];
              if (tresEnFila) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tarjetas.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(flex: _flexPara(_Unidad.values[i]), child: tarjetas[i]),
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

  int _flexPara(_Unidad u) {
    if (_expandida == null) return 1;
    return _expandida == u ? 2 : 1;
  }

  Widget _tarjetaUnidad(
    _Unidad unidad,
    String etiqueta,
    String? Function(ColoranteFormula) valorDe, {
    bool estimado = false,
    String Function(ColoranteFormula)? estimadoValor,
  }) {
    final expandida = _expandida == unidad;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _expandida = expandida ? null : unidad),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: expandida ? const Color(0xFFFCE9E9) : const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: expandida ? const Color(0xFFC62828) : const Color(0xFFE0E2E8), width: expandida ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F1B3D), letterSpacing: 0.3)),
                ),
                Icon(expandida ? Icons.unfold_less : Icons.unfold_more, size: 15, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 8),
            for (final c in widget.formula.colorantes) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: expandida ? 50 : 40, child: Text(c.colorante, style: GoogleFonts.poppins(fontSize: expandida ? 14 : 12.5, fontWeight: FontWeight.w700))),
                    Expanded(
                      child: (estimado && valorDe(c) == null)
                          ? Text(
                              estimadoValor?.call(c) ?? '—',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.poppins(fontSize: expandida ? 14 : 12.5, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                            )
                          : Text(
                              valorDe(c) ?? '—',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.poppins(fontSize: expandida ? 14 : 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
