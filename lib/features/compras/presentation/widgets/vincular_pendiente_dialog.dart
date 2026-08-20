import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../productos/data/pendiente_reposicion_model.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';

/// Sentinel que VincularPendienteDialog devuelve cuando el usuario toca
/// "Quitar vínculo" (a diferencia de cancelar, que devuelve null y no
/// cambia nada). Se compara con `identical(...)`, nunca con `==`.
const quitarVinculoPendiente = Object();

/// Deja elegir a cuál venta anticipada (ver PendienteReposicionModel) repone
/// esta línea de la compra -para cuando el producto comprado es distinto al
/// que se facturó y el emparejamiento automático por idProducto no alcanza
/// (ver ItemCompraModel.idPendienteReposicionVinculado)-.
class VincularPendienteDialog extends StatefulWidget {
  final List<PendienteReposicionModel> pendientes;
  final String? idVinculadoActual;

  const VincularPendienteDialog({super.key, required this.pendientes, this.idVinculadoActual});

  @override
  State<VincularPendienteDialog> createState() => _VincularPendienteDialogState();
}

class _VincularPendienteDialogState extends State<VincularPendienteDialog> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  String _formatoFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    final termino = _busqueda.trim().toLowerCase();
    final lista = termino.isEmpty
        ? widget.pendientes
        : widget.pendientes
            .where((p) => p.nombreProducto.toLowerCase().contains(termino) || p.numeroDocumentoVenta.toLowerCase().contains(termino))
            .toList();

    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 520;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: esMovil ? tamano.width - 40 : 480,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Vincular a venta anticipada', style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                'Elegí qué venta repone esta línea de la compra, aunque el producto vendido sea distinto al que estás comprando.',
                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        inputFormatters: [mayusculasInputFormatter],
                        autocorrect: false,
                        enableSuggestions: false,
                        controller: _busquedaController,
                        style: GoogleFonts.poppins(fontSize: 13),
                        decoration: InputDecoration(hintText: 'Buscar producto o factura...', hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400), border: InputBorder.none, isDense: true),
                        onChanged: (v) => setState(() => _busqueda = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.idVinculadoActual != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, quitarVinculoPendiente),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: Text('Quitar vínculo actual', style: GoogleFonts.poppins(fontSize: 13)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFF3B9B9)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: lista.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
                      child: Text(
                        widget.pendientes.isEmpty ? 'No hay ninguna venta esperando reposición ahora mismo.' : 'Nada coincide con esa búsqueda.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemCount: lista.length,
                      separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, i) {
                        final p = lista[i];
                        final activo = p.id == widget.idVinculadoActual;
                        return InkWell(
                          onTap: () => Navigator.pop(context, p),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(color: activo ? const Color(0xFF16A34A).withOpacity(0.08) : null, borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text(
                                        'Factura ${p.numeroDocumentoVenta} · ${_formatoFecha(p.fechaRegistro)} · Pendiente ${_formatoCantidad(p.cantidadPendiente)}',
                                        style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                if (activo) const Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
