import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/formula_colortrend_model.dart';

/// Muestra el detalle completo de una fórmula del Color Codex: código,
/// nombre, base (bien visible, es lo primero que se lee), página del libro
/// físico, y una tarjeta por cada TINTE que lleva la fórmula -pedido
/// explícito: cada unidad (Cuarto/Galón/Cubeta) separada y grande, no
/// amontonada en una sola fila chiquita, para que no se preste a confusión
/// ni en escritorio ni en celular/tablet. Cuando el libro no trae fórmula
/// de Cuarto (dice literal "No Quart Formula"), en vez de dejarlo en blanco
/// se muestra un estimado (Galón ÷ 4) marcado bien claro como estimado -no
/// es un valor impreso en el libro-.
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
          // La base va primero y grande -es lo primero que un mezclador
          // necesita confirmar antes de tocar cualquier bote-.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF0F1B3D), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.local_drink_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'BASE: ${formula.base.toUpperCase()}',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(formula.codigo, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFFC62828))),
          const SizedBox(height: 2),
          Text(formula.nombre, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text('Libro físico: página ${formula.pagina}', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500)),
          const SizedBox(height: 18),
          if (!formula.cuartoDisponible) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCD9A8))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El libro no trae fórmula de Cuarto para este tinte. El "Cuarto (estimado)" de abajo es el Galón dividido entre 4 -no es un valor impreso en el libro-.',
                      style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final c in formula.colorantes) ...[
            _tarjetaTinte(c),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaTinte(ColoranteFormula c) {
    final cuartoEstimado = !formula.cuartoDisponible;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0E2E8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TINTE', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              Text(c.colorante, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _bloqueCantidad('CUARTO${cuartoEstimado ? ' (estimado)' : ''}', c.cuartoOz != null ? _formatoOz(c.cuartoOz) : (cuartoEstimado && c.galonOz != null ? '≈ ${_formatoOz(c.galonOz! / 4)}' : '—'), destacado: !cuartoEstimado, advertencia: cuartoEstimado),
              _bloqueCantidad('GALÓN', _formatoOz(c.galonOz), destacado: true),
              _bloqueCantidad('CUBETA 5 GAL.', _formatoOz(c.cubeta5galOz)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bloqueCantidad(String etiqueta, String valor, {bool destacado = false, bool advertencia = false}) {
    final colorTexto = advertencia ? const Color(0xFFB45309) : (destacado ? const Color(0xFFC62828) : const Color(0xFF1A1A1A));
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: advertencia ? const Color(0xFFFCD9A8) : const Color(0xFFDDE0E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.4)),
          const SizedBox(height: 3),
          Text(valor, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: colorTexto)),
        ],
      ),
    );
  }
}
