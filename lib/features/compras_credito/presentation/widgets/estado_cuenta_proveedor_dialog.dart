import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/abono_compra_model.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Una fila del estado de cuenta: o una factura nueva (aumenta la deuda) o
/// el total abonado en un día (sin importar si el pago se repartió entre
/// varias facturas -pedido explícito del dueño: agrupar por día, no por
/// factura ni por operación, para poder ver "tal día se abonaron L.9,000"
/// aunque hayan sido 3 abonos a 3 facturas distintas-).
class _MovimientoCuenta {
  final DateTime fecha;
  final bool esCargo;
  final String titulo;
  final String subtitulo;
  final double monto;
  final Map<String, double> montoPorUsuario;
  final List<String> detalle;

  _MovimientoCuenta({
    required this.fecha,
    required this.esCargo,
    required this.titulo,
    required this.subtitulo,
    required this.monto,
    this.montoPorUsuario = const {},
    this.detalle = const [],
  });
}

class EstadoCuentaProveedorDialog extends ConsumerStatefulWidget {
  final String idProveedor;
  final String nombreProveedor;

  const EstadoCuentaProveedorDialog({super.key, required this.idProveedor, required this.nombreProveedor});

  @override
  ConsumerState<EstadoCuentaProveedorDialog> createState() => _EstadoCuentaProveedorDialogState();
}

class _EstadoCuentaProveedorDialogState extends ConsumerState<EstadoCuentaProveedorDialog> {
  bool _cargando = true;
  String? _error;
  List<_MovimientoCuenta> _movimientos = [];
  double _totalFacturado = 0;
  double _totalAbonado = 0;
  double _saldoActual = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = ref.read(compraCreditoRepositoryProvider);
      final compras = await repo.obtenerComprasPorProveedor(widget.idProveedor);
      final abonos = await repo.obtenerAbonosPorProveedor(widget.idProveedor);
      final comprasPorId = {for (final c in compras) c.id: c};

      final movimientos = <_MovimientoCuenta>[];
      for (final c in compras) {
        if (c.fechaRegistro == null) continue;
        movimientos.add(_MovimientoCuenta(
          fecha: c.fechaRegistro!,
          esCargo: true,
          titulo: 'Factura ${c.noFactura.isEmpty ? c.numeroDocumento : c.noFactura} registrada',
          subtitulo: 'Documento ${c.numeroDocumento}',
          monto: c.montoTotal,
        ));
      }

      final porDia = <DateTime, List<AbonoCompraModel>>{};
      for (final a in abonos) {
        if (a.fecha == null) continue;
        final dia = DateTime(a.fecha!.year, a.fecha!.month, a.fecha!.day);
        porDia.putIfAbsent(dia, () => []).add(a);
      }
      final formatoHora = DateFormat('HH:mm');
      for (final entry in porDia.entries) {
        final lista = entry.value..sort((x, y) => (x.fecha ?? DateTime(0)).compareTo(y.fecha ?? DateTime(0)));
        final montoPorUsuario = <String, double>{};
        final detalle = <String>[];
        final facturas = <String>{};
        var total = 0.0;
        for (final a in lista) {
          total += a.montoAbonado;
          final usuario = a.usuario.isEmpty ? 'Sin usuario' : a.usuario;
          montoPorUsuario[usuario] = (montoPorUsuario[usuario] ?? 0) + a.montoAbonado;
          final factura = comprasPorId[a.idCompra]?.noFactura ?? a.idCompra;
          facturas.add(factura);
          final hora = a.fecha != null ? formatoHora.format(a.fecha!) : '--:--';
          detalle.add('$hora · Factura $factura · ${formatearMoneda(a.montoAbonado)} · $usuario');
        }
        movimientos.add(_MovimientoCuenta(
          fecha: entry.key,
          esCargo: false,
          titulo: 'Abono',
          subtitulo: facturas.length == 1 ? 'Factura ${facturas.first}' : 'Facturas: ${facturas.join(', ')}',
          monto: total,
          montoPorUsuario: montoPorUsuario,
          detalle: detalle,
        ));
      }

      movimientos.sort((a, b) => a.fecha.compareTo(b.fecha));

      final totalFacturado = compras.fold<double>(0, (s, c) => s + c.montoTotal);
      final totalAbonado = abonos.fold<double>(0, (s, a) => s + a.montoAbonado);
      final saldoActual = compras.fold<double>(0, (s, c) => s + c.saldoPendiente);

      if (mounted) {
        setState(() {
          _movimientos = movimientos;
          _totalFacturado = totalFacturado;
          _totalAbonado = totalAbonado;
          _saldoActual = saldoActual;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el estado de cuenta');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 760;
    final anchoDialog = esMovil ? tamano.width - 16 : (tamano.width - 60).clamp(0, 1300).toDouble();
    final altoDialog = tamano.height < 700 ? tamano.height - 24 : (tamano.height - 60).clamp(0, 860).toDouble();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 14 : 22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estado de Cuenta', style: GoogleFonts.poppins(fontSize: esMovil ? 16 : 18, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                      Text(widget.nombreProveedor, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            if (!_cargando && _error == null) _resumenTotales(esMovil),
            const SizedBox(height: 14),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))
                  : _error != null
                      ? Center(child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red)))
                      : _movimientos.isEmpty
                          ? Center(child: Text('No hay movimientos para este proveedor', style: GoogleFonts.poppins(color: Colors.grey.shade500)))
                          : (esMovil ? _listaMovil() : _tabla()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String etiqueta, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85), letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(valor, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _resumenTotales(bool esMovil) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statChip('TOTAL FACTURADO (HISTÓRICO)', formatearMoneda(_totalFacturado), const Color(0xFF3B4252)),
        _statChip('TOTAL ABONADO (HISTÓRICO)', formatearMoneda(_totalAbonado), const Color(0xFF16A34A)),
        _statChip('SALDO PENDIENTE ACTUAL', formatearMoneda(_saldoActual), const Color(0xFFC62828)),
      ],
    );
  }

  Widget _celdaUsuarios(Map<String, double> montoPorUsuario) {
    if (montoPorUsuario.isEmpty) return Text('-', style: GoogleFonts.poppins(fontSize: 12));
    if (montoPorUsuario.length == 1) {
      return Text(montoPorUsuario.keys.first, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis);
    }
    final entradas = montoPorUsuario.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final desglose = entradas.map((e) => '${e.key}: ${formatearMoneda(e.value)}').join('\n');
    return Tooltip(
      message: desglose,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF2B6CB0).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_outlined, size: 13, color: Color(0xFF2B6CB0)),
            const SizedBox(width: 4),
            Text('${entradas.length} usuarios', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF2B6CB0))),
          ],
        ),
      ),
    );
  }

  Widget _celdaDetalle(_MovimientoCuenta m) {
    final texto = Text(m.subtitulo, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis, maxLines: 2);
    if (m.detalle.isEmpty) return texto;
    return Tooltip(message: m.detalle.join('\n'), child: texto);
  }

  Widget _tabla() {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    var saldo = 0.0;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('FECHA', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 4, child: Text('MOVIMIENTO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text('USUARIO(S)', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text('CARGO', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text('ABONO', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text('SALDO', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _movimientos.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final m = _movimientos[index];
                saldo = m.esCargo ? saldo + m.monto : saldo - m.monto;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: Text(formatoFecha.format(m.fecha), style: GoogleFonts.poppins(fontSize: 12))),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.titulo, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            _celdaDetalle(m),
                          ],
                        ),
                      ),
                      Expanded(flex: 2, child: _celdaUsuarios(m.montoPorUsuario)),
                      Expanded(flex: 2, child: Text(m.esCargo ? formatearMoneda(m.monto) : '-', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFFC62828)))),
                      Expanded(flex: 2, child: Text(!m.esCargo ? formatearMoneda(m.monto) : '-', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)))),
                      Expanded(flex: 2, child: Text(formatearMoneda(saldo), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w800))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaMovil() {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    var saldo = 0.0;
    return ListView.separated(
      itemCount: _movimientos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final m = _movimientos[index];
        saldo = m.esCargo ? saldo + m.monto : saldo - m.monto;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7CBD3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(m.titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700))),
                  Text(formatoFecha.format(m.fecha), style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 4),
              _celdaDetalle(m),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    m.esCargo ? 'Cargo: ${formatearMoneda(m.monto)}' : 'Abono: ${formatearMoneda(m.monto)}',
                    style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: m.esCargo ? const Color(0xFFC62828) : const Color(0xFF16A34A)),
                  ),
                  const Spacer(),
                  _celdaUsuarios(m.montoPorUsuario),
                ],
              ),
              const SizedBox(height: 6),
              Text('Saldo después de este movimiento: ${formatearMoneda(saldo)}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}
