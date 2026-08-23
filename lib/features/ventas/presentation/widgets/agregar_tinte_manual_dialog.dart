import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/producto_model.dart';
import '../../../productos/data/tinte_lookup.dart';
import '../../data/costo_tinte_service.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Diálogo para cargar un tinte "a ojo" (Escenario B, sin código de fórmula
/// conectado, ver CodigosColorDialog): el cajero elige el producto de tinte
/// real (categoría TINTES) y cuántas onzas le echó -mismas unidades que ya
/// usa la pantalla de Fórmulas, para razonar igual en los dos casos-. Calcula
/// el costo (FIFO, solo lectura) antes de confirmar, para que el cajero vea
/// cuánto va a sumar esa línea antes de agregarla. Devuelve el
/// [ResultadoCostoTinte] elegido, o null si se cancela.
class AgregarTinteManualDialog extends StatefulWidget {
  const AgregarTinteManualDialog({super.key});

  @override
  State<AgregarTinteManualDialog> createState() => _AgregarTinteManualDialogState();
}

class _AgregarTinteManualDialogState extends State<AgregarTinteManualDialog> {
  final _onzasController = TextEditingController();
  final _servicio = CostoTinteService();
  Future<List<ProductoModel>>? _futureTintes;
  ProductoModel? _tinteElegido;
  ResultadoCostoTinte? _calculado;
  bool _calculando = false;

  @override
  void initState() {
    super.initState();
    _futureTintes = listarProductosTinte();
  }

  @override
  void dispose() {
    _onzasController.dispose();
    super.dispose();
  }

  Future<void> _calcular() async {
    final tinte = _tinteElegido;
    final onzas = double.tryParse(_onzasController.text.replaceAll(',', '.'));
    if (tinte == null || onzas == null || onzas <= 0) {
      setState(() => _calculado = null);
      return;
    }
    setState(() => _calculando = true);
    // Se colorante desde el nombre del producto ("COLORANTE B" -> "B") en
    // vez de pedirle al cajero que lo escriba de nuevo: ya lo eligió de la
    // lista. El servicio vuelve a resolver el producto por ese código -mismo
    // camino que Escenario A- para no duplicar la lógica de costeo FIFO.
    final colorante = tinte.nombre.replaceFirst('COLORANTE ', '').trim();
    final resultados = await _servicio.calcular([UsoTinte(colorante: colorante, onzas: onzas)]);
    if (!mounted) return;
    setState(() {
      _calculado = resultados.first;
      _calculando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final ancho = tamano.width < 400 ? tamano.width - 48 : 340.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: ancho,
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
                Expanded(child: Text('Agregar tinte manual', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Elegí el tinte real y cuántas onzas le echaste.', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(height: 14),
            FutureBuilder<List<ProductoModel>>(
              future: _futureTintes,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: Color(0xFFC62828))));
                }
                final tintes = snap.data!;
                if (tintes.isEmpty) {
                  return Text('No hay productos de tinte cargados en el inventario (categoría TINTES).', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828)));
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ProductoModel>(
                      isExpanded: true,
                      hint: Text('Elegí un tinte...', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
                      value: _tinteElegido,
                      items: [
                        for (final t in tintes)
                          DropdownMenuItem(value: t, child: Text('${t.nombre}${t.descripcion.isNotEmpty ? " (${t.descripcion})" : ""}', style: GoogleFonts.poppins(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _tinteElegido = v;
                          _calculado = null;
                        });
                        _calcular();
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _onzasController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Onzas',
                labelStyle: GoogleFonts.poppins(fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFFF2F3F7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => _calcular(),
              onSubmitted: (_) => _calcular(),
            ),
            const SizedBox(height: 14),
            if (_calculando) const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CircularProgressIndicator(color: Color(0xFFC62828)))),
            if (!_calculando && _calculado != null) _resumenCalculo(_calculado!),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _calculado == null ? null : () => Navigator.pop(context, _calculado),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Agregar tinte', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenCalculo(ResultadoCostoTinte r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E2E8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.cuartos.toStringAsFixed(3)} cuartos de tinte', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            r.resuelto ? 'Costo estimado: ${formatearMoneda(r.costoTotal)}' : 'No se puede calcular el costo -sin producto en inventario.',
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: r.resuelto ? const Color(0xFF1E9E5A) : const Color(0xFFC62828)),
          ),
          if (r.advertencia != null) ...[
            const SizedBox(height: 6),
            Text(r.advertencia!, style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFFB45309))),
          ],
        ],
      ),
    );
  }
}
