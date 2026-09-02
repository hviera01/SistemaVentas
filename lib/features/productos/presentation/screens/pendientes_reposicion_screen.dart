import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/pendiente_reposicion_model.dart';
import '../../providers/productos_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Lista las "ventas anticipadas" que siguen esperando la compra que las
/// repone (ver ItemVentaModel.pendienteCompra, VentaRepository.registrarVenta
/// y CompraRepository.registrarCompra). Es de solo consulta -el emparejamiento
/// pasa solo, automático, al registrar la compra correspondiente-; la única
/// acción disponible acá es cancelar a mano una que ya no va a esperar
/// ninguna compra (se resolvió de otra forma, o se marcó por error).
class PendientesReposicionScreen extends ConsumerWidget {
  const PendientesReposicionScreen({super.key});

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble())
      return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  String _formatoFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Future<void> _cancelar(
    BuildContext context,
    WidgetRef ref,
    PendienteReposicionModel pendiente,
  ) async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancelar pendiente de reposición',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Esto deja de esperar una compra para "${pendiente.nombreProducto}" (factura ${pendiente.numeroDocumentoVenta}). '
          'Usalo solo si ya se resolvió de otra forma, o si se marcó por error -no cambia nada del inventario ni de la venta original-.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Volver', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancelar pendiente', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;
    await ref
        .read(pendienteReposicionRepositoryProvider)
        .cancelar(pendiente.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pendiente cancelado'),
          showCloseIcon: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientesAsync = ref.watch(pendientesReposicionStreamProvider);

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 720;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _encabezado(esMovil),
                const SizedBox(height: 18),
                Expanded(
                  child: pendientesAsync.when(
                    data: (pendientes) => pendientes.isEmpty
                        ? _estadoVacio()
                        : Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFAEB4C0),
                                width: 1.3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.14),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: esMovil
                                ? _tarjetas(context, ref, pendientes)
                                : _tabla(context, ref, pendientes),
                          ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFC62828),
                      ),
                    ),
                    error: (e, st) => Center(
                      child: Text(
                        'Error: $e',
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.hourglass_bottom,
            color: Color(0xFFF59E0B),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pendientes de Reposición',
                style: GoogleFonts.poppins(
                  fontSize: esMovil ? 19 : 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              Text(
                'Ventas anticipadas esperando la compra que las repone. Se completan solas al registrar esa compra.',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _estadoVacio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 14),
          Text(
            'No hay ninguna venta esperando reposición ahora mismo.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Tabla de escritorio ----------

  Widget _tabla(
    BuildContext context,
    WidgetRef ref,
    List<PendienteReposicionModel> lista,
  ) {
    return Column(
      children: [
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFECEEF3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              _celdaHeader('FECHA VENTA', 2),
              _celdaHeader('FACTURA', 2),
              _celdaHeader('PRODUCTO', 3),
              _celdaHeader('PENDIENTE / ORIGINAL', 2),
              _celdaHeader('COSTO PROVISIONAL', 2),
              _celdaHeader('', 1),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: lista.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) =>
                _filaTabla(context, ref, lista[index]),
          ),
        ),
      ],
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          texto,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _chipParcial() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'parcial',
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFF59E0B),
        ),
      ),
    );
  }

  Widget _filaTabla(
    BuildContext context,
    WidgetRef ref,
    PendienteReposicionModel p,
  ) {
    final esParcial = p.cantidadPendiente != p.cantidadOriginal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _formatoFecha(p.fechaRegistro),
                style: GoogleFonts.poppins(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                p.numeroDocumentoVenta,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                p.nombreProducto,
                style: GoogleFonts.poppins(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    '${_formatoCantidad(p.cantidadPendiente)} / ${_formatoCantidad(p.cantidadOriginal)}',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  if (esParcial) _chipParcial(),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                formatearMoneda(p.costoRegistrado),
                style: GoogleFonts.poppins(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: IconButton(
              tooltip: 'Cancelar pendiente',
              icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
              onPressed: () => _cancelar(context, ref, p),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Tarjetas móvil ----------

  Widget _tarjetas(
    BuildContext context,
    WidgetRef ref,
    List<PendienteReposicionModel> lista,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _tarjetaPendiente(context, ref, lista[index]),
    );
  }

  Widget _tarjetaPendiente(
    BuildContext context,
    WidgetRef ref,
    PendienteReposicionModel p,
  ) {
    final esParcial = p.cantidadPendiente != p.cantidadOriginal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.nombreProducto,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Cancelar pendiente',
                icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
                onPressed: () => _cancelar(context, ref, p),
              ),
            ],
          ),
          Text(
            'Factura ${p.numeroDocumentoVenta} · ${_formatoFecha(p.fechaRegistro)}',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PENDIENTE / ORIGINAL',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '${_formatoCantidad(p.cantidadPendiente)} / ${_formatoCantidad(p.cantidadOriginal)}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (esParcial) _chipParcial(),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COSTO PROVISIONAL',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    formatearMoneda(p.costoRegistrado),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
