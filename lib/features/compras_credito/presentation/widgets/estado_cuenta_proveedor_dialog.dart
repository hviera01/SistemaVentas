import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/abono_compra_model.dart';
import '../../data/compra_credito_model.dart';
import '../../data/compra_credito_export_service.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../negocio/providers/negocio_provider.dart';

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

  const EstadoCuentaProveedorDialog({
    super.key,
    required this.idProveedor,
    required this.nombreProveedor,
  });

  @override
  ConsumerState<EstadoCuentaProveedorDialog> createState() =>
      _EstadoCuentaProveedorDialogState();
}

class _EstadoCuentaProveedorDialogState
    extends ConsumerState<EstadoCuentaProveedorDialog> {
  final _servicioExport = CompraCreditoExportService();
  bool _cargando = true;
  String? _error;
  List<_MovimientoCuenta> _movimientos = [];
  // Saldo corriendo después de cada movimiento, precalculado una sola vez
  // acá (mismo índice que _movimientos) — NUNCA calcularlo dentro de un
  // itemBuilder de una lista con scroll: Flutter arma esas filas de forma
  // perezosa y no garantiza orden ni una sola pasada (menos aún al rotar la
  // pantalla, que reconstruye todo desde cero), así que una variable mutable
  // compartida ahí daba saldos distintos según cómo se scrolleaba -reportado
  // por el dueño: en el PDF (una sola pasada synchronous) siempre salía bien,
  // pero en la lista de la pantalla el último monto cambiaba solo-.
  List<double> _saldosCorrientes = [];
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
      final resultados = await Future.wait([
        repo.obtenerComprasPorProveedor(widget.idProveedor),
        repo.obtenerAbonosPorProveedor(widget.idProveedor),
      ]);
      final compras = resultados[0] as List<CompraCreditoModel>;
      final abonos = resultados[1] as List<AbonoCompraModel>;
      final comprasPorId = {for (final c in compras) c.id: c};

      // El "cargo" de cada factura al estado de cuenta no siempre es su
      // montoTotal: algunas facturas se registraron con un saldoPendiente ya
      // menor al total (un pago hecho antes de digitalizar el crédito, sin
      // abono registrado para esa diferencia -caso real: Ventura, facturas
      // 00052894 y 00052953-). El saldoAnterior del primer abono (si hay
      // abonos) es la deuda real que entró al sistema; si nunca hubo abonos,
      // es el saldoPendiente actual. Usar montoTotal a ciegas acá hacía que
      // el saldo corriendo del estado de cuenta no cuadrara con el saldo
      // pendiente real (reportado por el dueño: quedaba una diferencia igual
      // a esos pagos previos no registrados).
      final abonosPorCompra = <String, List<AbonoCompraModel>>{};
      for (final a in abonos) {
        abonosPorCompra.putIfAbsent(a.idCompra, () => []).add(a);
      }

      final movimientos = <_MovimientoCuenta>[];
      for (final c in compras) {
        if (c.fechaRegistro == null) continue;
        final abonosDeEsta = abonosPorCompra[c.id] ?? [];
        abonosDeEsta.sort(
          (x, y) => (x.fecha ?? DateTime(0)).compareTo(y.fecha ?? DateTime(0)),
        );
        final saldoInicial = abonosDeEsta.isNotEmpty
            ? abonosDeEsta.first.saldoAnterior
            : c.saldoPendiente;
        final huboPagoPrevio = c.montoTotal - saldoInicial > 0.01;
        movimientos.add(
          _MovimientoCuenta(
            fecha: c.fechaRegistro!,
            esCargo: true,
            titulo:
                'Factura ${c.noFactura.isEmpty ? c.numeroDocumento : c.noFactura} registrada',
            subtitulo: huboPagoPrevio
                ? 'Documento ${c.numeroDocumento} · Factura original ${formatearMoneda(c.montoTotal)}, ya traía ${formatearMoneda(c.montoTotal - saldoInicial)} abonado antes de registrarse'
                : 'Documento ${c.numeroDocumento}',
            monto: saldoInicial,
          ),
        );
      }

      final porDia = <DateTime, List<AbonoCompraModel>>{};
      for (final a in abonos) {
        if (a.fecha == null) continue;
        final dia = DateTime(a.fecha!.year, a.fecha!.month, a.fecha!.day);
        porDia.putIfAbsent(dia, () => []).add(a);
      }
      final formatoHora = DateFormat('HH:mm');
      for (final entry in porDia.entries) {
        final lista = entry.value
          ..sort(
            (x, y) =>
                (x.fecha ?? DateTime(0)).compareTo(y.fecha ?? DateTime(0)),
          );
        final montoPorUsuario = <String, double>{};
        final detalle = <String>[];
        final facturas = <String>{};
        var total = 0.0;
        for (final a in lista) {
          total += a.montoAbonado;
          final usuario = a.usuario.isEmpty ? 'Sin usuario' : a.usuario;
          montoPorUsuario[usuario] =
              (montoPorUsuario[usuario] ?? 0) + a.montoAbonado;
          final factura = comprasPorId[a.idCompra]?.noFactura ?? a.idCompra;
          facturas.add(factura);
          final hora = a.fecha != null ? formatoHora.format(a.fecha!) : '--:--';
          detalle.add(
            '$hora · Factura $factura · ${formatearMoneda(a.montoAbonado)} · $usuario',
          );
        }
        movimientos.add(
          _MovimientoCuenta(
            fecha: entry.key,
            esCargo: false,
            titulo: 'Abono',
            subtitulo: facturas.length == 1
                ? 'Factura ${facturas.first}'
                : 'Facturas: ${facturas.join(', ')}',
            monto: total,
            montoPorUsuario: montoPorUsuario,
            detalle: detalle,
          ),
        );
      }

      movimientos.sort((a, b) => a.fecha.compareTo(b.fecha));

      // Mismo criterio que arriba: sumar el cargo real que entró a la cuenta
      // (no el montoTotal de la factura), para que Total Facturado - Total
      // Abonado dé siempre exactamente el Saldo Pendiente Actual.
      final totalFacturado = movimientos
          .where((m) => m.esCargo)
          .fold<double>(0, (s, m) => s + m.monto);
      final totalAbonado = abonos.fold<double>(0, (s, a) => s + a.montoAbonado);
      final saldoActual = compras.fold<double>(
        0,
        (s, c) => s + c.saldoPendiente,
      );

      final saldosCorrientes = <double>[];
      var acumulado = 0.0;
      for (final m in movimientos) {
        acumulado = m.esCargo ? acumulado + m.monto : acumulado - m.monto;
        saldosCorrientes.add(acumulado);
      }

      if (mounted) {
        setState(() {
          _movimientos = movimientos;
          _saldosCorrientes = saldosCorrientes;
          _totalFacturado = totalFacturado;
          _totalAbonado = totalAbonado;
          _saldoActual = saldoActual;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = 'No se pudo cargar el estado de cuenta');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<FilaEstadoCuenta> _filasParaPdf() {
    return [
      for (var i = 0; i < _movimientos.length; i++)
        FilaEstadoCuenta(
          fecha: _movimientos[i].fecha,
          esCargo: _movimientos[i].esCargo,
          titulo: _movimientos[i].titulo,
          subtitulo: _movimientos[i].subtitulo,
          monto: _movimientos[i].monto,
          usuarios: _movimientos[i].montoPorUsuario.keys.isEmpty
              ? '-'
              : _movimientos[i].montoPorUsuario.keys.join(', '),
          saldoDespues: _saldosCorrientes[i],
        ),
    ];
  }

  Future<void> _exportarPdf() async {
    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;
    final filas = _filasParaPdf();
    await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Estado de Cuenta',
        nombreArchivo:
            'estado_cuenta_${widget.nombreProveedor.replaceAll(' ', '_')}.pdf',
        generarPdf: () => _servicioExport.generarPdfEstadoCuenta(
          nombreProveedor: widget.nombreProveedor,
          filas: filas,
          totalFacturado: _totalFacturado,
          totalAbonado: _totalAbonado,
          saldoActual: _saldoActual,
          negocio: negocio,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 760;
    final anchoDialog = esMovil
        ? tamano.width - 16
        : (tamano.width - 60).clamp(0, 1300).toDouble();
    final altoDialog = tamano.height < 700
        ? tamano.height - 24
        : (tamano.height - 60).clamp(0, 860).toDouble();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 14 : 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado de Cuenta',
                        style: GoogleFonts.poppins(
                          fontSize: esMovil ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        widget.nombreProveedor,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!_cargando && _error == null && _movimientos.isNotEmpty)
                  IconButton(
                    tooltip: 'Descargar PDF',
                    icon: const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 22,
                      color: Color(0xFFC62828),
                    ),
                    onPressed: _exportarPdf,
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_cargando && _error == null) _resumenTotales(esMovil),
            const SizedBox(height: 14),
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFC62828),
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    )
                  : _movimientos.isEmpty
                  ? Center(
                      child: Text(
                        'No hay movimientos para este proveedor',
                        style: GoogleFonts.poppins(color: Colors.grey.shade500),
                      ),
                    )
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
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenTotales(bool esMovil) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statChip(
          'TOTAL FACTURADO (HISTÓRICO)',
          formatearMoneda(_totalFacturado),
          const Color(0xFF3B4252),
        ),
        _statChip(
          'TOTAL ABONADO (HISTÓRICO)',
          formatearMoneda(_totalAbonado),
          const Color(0xFF16A34A),
        ),
        _statChip(
          'SALDO PENDIENTE ACTUAL',
          formatearMoneda(_saldoActual),
          const Color(0xFFC62828),
        ),
      ],
    );
  }

  Widget _celdaUsuarios(Map<String, double> montoPorUsuario) {
    if (montoPorUsuario.isEmpty)
      return Text('-', style: GoogleFonts.poppins(fontSize: 12));
    if (montoPorUsuario.length == 1) {
      return Text(
        montoPorUsuario.keys.first,
        style: GoogleFonts.poppins(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      );
    }
    final entradas = montoPorUsuario.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final desglose = entradas
        .map((e) => '${e.key}: ${formatearMoneda(e.value)}')
        .join('\n');
    return Tooltip(
      message: desglose,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2B6CB0).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.group_outlined,
              size: 13,
              color: Color(0xFF2B6CB0),
            ),
            const SizedBox(width: 4),
            Text(
              '${entradas.length} usuarios',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B6CB0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celdaDetalle(_MovimientoCuenta m) {
    final texto = Text(
      m.subtitulo,
      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
    if (m.detalle.isEmpty) return texto;
    return Tooltip(message: m.detalle.join('\n'), child: texto);
  }

  Widget _tabla() {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB6BCC7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFECEEF3),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'FECHA',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'MOVIMIENTO',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'USUARIO(S)',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'CARGO',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ABONO',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'SALDO',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _movimientos.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final m = _movimientos[index];
                final saldo = _saldosCorrientes[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          formatoFecha.format(m.fecha),
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.titulo,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _celdaDetalle(m),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _celdaUsuarios(m.montoPorUsuario),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          m.esCargo ? formatearMoneda(m.monto) : '-',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          !m.esCargo ? formatearMoneda(m.monto) : '-',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          formatearMoneda(saldo),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
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
    return ListView.separated(
      itemCount: _movimientos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final m = _movimientos[index];
        final saldo = _saldosCorrientes[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC7CBD3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.titulo,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    formatoFecha.format(m.fecha),
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _celdaDetalle(m),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    m.esCargo
                        ? 'Cargo: ${formatearMoneda(m.monto)}'
                        : 'Abono: ${formatearMoneda(m.monto)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: m.esCargo
                          ? const Color(0xFFC62828)
                          : const Color(0xFF16A34A),
                    ),
                  ),
                  const Spacer(),
                  _celdaUsuarios(m.montoPorUsuario),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Saldo después de este movimiento: ${formatearMoneda(saldo)}',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
