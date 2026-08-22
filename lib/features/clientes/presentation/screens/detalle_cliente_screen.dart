import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/cliente_model.dart';
import '../../data/cliente_historial_model.dart';
import '../../providers/clientes_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../ventas_credito/data/venta_credito_model.dart';

/// Historial completo de un cliente en una sola pantalla: seguimiento de
/// crédito, resumen de compras, compras recientes, qué compra más, historial
/// de códigos de color y método de pago preferido. Se llega acá desde el
/// menú de cada fila en ClientesScreen ("Ver detalle").
class DetalleClienteScreen extends ConsumerStatefulWidget {
  final ClienteModel cliente;

  const DetalleClienteScreen({super.key, required this.cliente});

  @override
  ConsumerState<DetalleClienteScreen> createState() => _DetalleClienteScreenState();
}

class _DetalleClienteScreenState extends ConsumerState<DetalleClienteScreen> {
  late Future<ClienteHistorialData> _future;
  final _formatoFecha = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _future = ref.read(clienteHistorialRepositoryProvider).obtener(widget.cliente);
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.cliente;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A1A)),
        title: Text(
          cliente.nombreCompleto.isEmpty ? 'Detalle de Cliente' : cliente.nombreCompleto,
          style: GoogleFonts.poppins(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: FutureBuilder<ClienteHistorialData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: Colors.red)));
          }
          final datos = snapshot.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final esMovil = constraints.maxWidth < 720;
              return SingleChildScrollView(
                padding: EdgeInsets.all(esMovil ? 14 : 26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tarjetaEncabezado(cliente),
                        const SizedBox(height: 16),
                        _seccionCredito(datos),
                        const SizedBox(height: 16),
                        _seccionResumenCompras(datos, esMovil),
                        const SizedBox(height: 16),
                        _seccionVentasRecientes(datos),
                        const SizedBox(height: 16),
                        _seccionProductosTop(datos),
                        const SizedBox(height: 16),
                        _seccionColores(datos),
                        const SizedBox(height: 16),
                        _seccionReferidor(datos),
                        const SizedBox(height: 16),
                        _seccionMetodoPago(datos),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------- Helpers de UI ----------

  Widget _tarjeta({required String titulo, IconData? icono, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icono != null) ...[Icon(icono, size: 18, color: const Color(0xFFC62828)), const SizedBox(width: 8)],
              Text(titulo, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _estadisticaChica(String etiqueta, String valor) {
    return SizedBox(
      width: 165,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Text(valor, style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
        ],
      ),
    );
  }

  String _fmtFecha(DateTime? fecha) => fecha == null ? 'N/D' : _formatoFecha.format(fecha);

  // ---------- Encabezado ----------

  Widget _tarjetaEncabezado(ClienteModel cliente) {
    return _tarjeta(
      titulo: cliente.nombreCompleto.isEmpty ? 'Sin nombre' : cliente.nombreCompleto,
      icono: Icons.person_outline,
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          if (cliente.dni.isNotEmpty) _estadisticaChica('DNI', cliente.dni),
          if (cliente.telefono.isNotEmpty) _estadisticaChica('Teléfono', cliente.telefono),
          if (cliente.direccion.isNotEmpty) _estadisticaChica('Dirección', cliente.direccion),
          _estadisticaChica('Estado', cliente.estado ? 'Activo' : 'Inactivo'),
        ],
      ),
    );
  }

  // ---------- Seguimiento de crédito ----------

  Widget _seccionCredito(ClienteHistorialData datos) {
    final sinHistorialCredito = datos.creditos.isEmpty && datos.abonosATiempo == null;
    return _tarjeta(
      titulo: 'Seguimiento de crédito',
      icono: Icons.credit_score_outlined,
      child: sinHistorialCredito
          ? Text('Este cliente no tiene historial de crédito.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (datos.hayCreditoVencido) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Crédito vencido: ${formatearMoneda(datos.saldoVencidoTotal)}',
                            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Historial COMPLETO de créditos, pagados y no pagados -antes
                // solo se mostraban los abiertos y un crédito ya liquidado
                // desaparecía por completo de esta pantalla (bug reportado
                // por el dueño con un cliente real, Ronald Camas).
                if (datos.creditos.isNotEmpty) ...[
                  Text('Historial de créditos', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  for (final credito in datos.creditos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: credito.vencida ? Colors.orange.shade50 : const Color(0xFFF2F3F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Factura ${credito.numeroDocumento}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  Text(
                                    '${_fmtFecha(credito.fechaRegistro)} · Vence: ${_fmtFecha(credito.fechaVencimiento)}',
                                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _chipEstadoCredito(credito),
                                const SizedBox(height: 4),
                                Text(
                                  credito.liquidada ? formatearMoneda(credito.montoTotal) : formatearMoneda(credito.saldoPendiente),
                                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w800, color: credito.vencida ? Colors.orange.shade800 : const Color(0xFF1A1A1A)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
                if (datos.abonosATiempo != null && datos.abonosAtrasados != null) ...[
                  Text('Puntualidad histórica de pago', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chipPuntualidad('${datos.abonosATiempo} a tiempo', Colors.green),
                      const SizedBox(width: 8),
                      if (datos.abonosAtrasados! > 0) _chipPuntualidad('${datos.abonosAtrasados} atrasado(s)', Colors.orange),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _chipPuntualidad(String texto, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: color.shade800)),
    );
  }

  // Vigente / Vencida / Liquidada -mismo idioma que el resto del sistema
  // (ver VentasCreditoScreen) para no inventar un vocabulario nuevo acá.
  Widget _chipEstadoCredito(VentaCreditoModel credito) {
    final String texto;
    final MaterialColor color;
    if (credito.liquidada) {
      texto = 'Liquidada';
      color = Colors.green;
    } else if (credito.vencida) {
      texto = 'Vencida';
      color = Colors.orange;
    } else {
      texto = 'Vigente';
      color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: color.shade800)),
    );
  }

  // ---------- Resumen de compras ----------

  Widget _seccionResumenCompras(ClienteHistorialData datos, bool esMovil) {
    return _tarjeta(
      titulo: 'Resumen de compras',
      icono: Icons.shopping_bag_outlined,
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        children: [
          _estadisticaChica('Total comprado', formatearMoneda(datos.totalComprado)),
          _estadisticaChica('Cantidad de compras', '${datos.cantidadCompras}'),
          _estadisticaChica('Ticket promedio', formatearMoneda(datos.ticketPromedio)),
          _estadisticaChica('Cliente desde', _fmtFecha(datos.primeraCompra)),
          _estadisticaChica('Última compra', _fmtFecha(datos.ultimaCompra)),
        ],
      ),
    );
  }

  // ---------- Compras recientes ----------

  Widget _seccionVentasRecientes(ClienteHistorialData datos) {
    return _tarjeta(
      titulo: 'Compras recientes',
      icono: Icons.receipt_long_outlined,
      child: datos.ventasRecientes.isEmpty
          ? Text('Este cliente todavía no tiene compras registradas.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (datos.hayVentasEmparejadasPorNombre)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Algunas ventas de antes de vincular a este cliente se emparejaron solo por nombre y pueden no ser 100% exactas.',
                      style: GoogleFonts.poppins(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                    ),
                  ),
                for (final venta in datos.ventasRecientes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 80, child: Text(_fmtFecha(venta.fecha), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
                        Expanded(
                          child: Text(
                            'Factura ${venta.numeroDocumento}${venta.emparejadaPorNombre ? ' *' : ''}',
                            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            venta.condicion == 'Credito' ? 'Crédito' : venta.metodoPago,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(formatearMoneda(venta.monto), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ---------- Qué compra más ----------

  Widget _seccionProductosTop(ClienteHistorialData datos) {
    return _tarjeta(
      titulo: 'Qué compra más',
      icono: Icons.star_outline,
      child: datos.productosTop.isEmpty
          ? Text('Todavía no hay suficientes compras para saberlo.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final producto in datos.productosTop)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(producto.nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
                        Text('x${_formatoCantidad(producto.cantidad)}', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  // ---------- Historial de códigos de color ----------

  Widget _seccionColores(ClienteHistorialData datos) {
    return _tarjeta(
      titulo: 'Historial de códigos de color',
      icono: Icons.palette_outlined,
      child: datos.historialColores.isEmpty
          ? Text('Este cliente no tiene códigos de color registrados.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in datos.historialColores)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 80, child: Text(_fmtFecha(item.fecha), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              Text(item.codigosColor.join(', '), style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFC62828), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Text('Fact. ${item.numeroDocumento}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ---------- Quién lo refirió ----------
  // Un referidor es ahora un ClienteModel más con esReferidor == true (ver
  // fusión del módulo aparte 'referidores' dentro de clientes), así que
  // referidor.estado acá es el mismo campo "Activo/Inactivo" de siempre.

  Widget _seccionReferidor(ClienteHistorialData datos) {
    final referidor = datos.referidor;
    return _tarjeta(
      titulo: 'Referido por',
      icono: Icons.handshake_outlined,
      child: referidor == null
          ? Text('Este cliente no tiene un referidor registrado.', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(referidor.nombreCompleto, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                      if (referidor.telefono.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(referidor.telefono, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                        ),
                    ],
                  ),
                ),
                if (!referidor.estado)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: Text('Inactivo', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  ),
              ],
            ),
    );
  }

  // ---------- Método de pago preferido ----------

  Widget _seccionMetodoPago(ClienteHistorialData datos) {
    return _tarjeta(
      titulo: 'Método de pago preferido',
      icono: Icons.payments_outlined,
      child: Text(
        datos.metodoPagoPreferido ?? 'Sin datos suficientes',
        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
      ),
    );
  }
}
