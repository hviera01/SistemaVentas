import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/formula_colortrend_model.dart';

/// Muestra el detalle completo de una fórmula del Color Codex: código,
/// nombre, base, página del libro físico, y la tabla de colorantes con sus
/// cantidades en Quart/Gallon/5-Gallon. Cuando el libro no trae fórmula de
/// Quart (dice literal "No Quart Formula"), en vez de dejarlo en blanco se
/// muestra un estimado (Galón ÷ 4) marcado bien claro como estimado -pedido
/// explícito, para no dejarlo "nulo del todo" pero sin hacerlo pasar por un
/// valor real del libro.
class FormulaDetalleCard extends StatelessWidget {
  final FormulaColortrendModel formula;

  const FormulaDetalleCard({super.key, required this.formula});

  String _formatoOz(double? oz) {
    if (oz == null) return '—';
    return '${oz.abs().toStringAsFixed(2)} oz';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
                    Text(formula.codigo, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFFC62828))),
                    const SizedBox(height: 2),
                    Text(formula.nombre, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFF0F1B3D).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                    child: Text(formula.base, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F1B3D))),
                  ),
                  const SizedBox(height: 6),
                  Text('Libro: pág. ${formula.pagina}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E2E8))),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(color: Color(0xFFF2F3F7), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                  child: Row(
                    children: [
                      SizedBox(width: 56, child: Text('COLOR.', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                      Expanded(child: Text('CUARTO', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                      Expanded(child: Text('GALÓN', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                      Expanded(child: Text('CUBETA 5 GAL.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                    ],
                  ),
                ),
                for (final c in formula.colorantes) ...[
                  Divider(height: 1, color: Colors.grey.shade200),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text(c.colorante, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
                        Expanded(
                          child: formula.cuartoDisponible
                              ? Text(_formatoOz(c.cuartoOz), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13))
                              : Column(
                                  children: [
                                    Text(
                                      c.galonOz != null ? '≈ ${_formatoOz(c.galonOz! / 4)}' : '—',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFFB45309)),
                                    ),
                                    Text('estimado', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 9.5, color: const Color(0xFFB45309))),
                                  ],
                                ),
                        ),
                        Expanded(child: Text(_formatoOz(c.galonOz), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600))),
                        Expanded(child: Text(_formatoOz(c.cubeta5galOz), textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!formula.cuartoDisponible) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'El libro no trae fórmula de Cuarto para este color -el estimado es el Galón dividido entre 4, no un valor impreso.',
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB45309)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
