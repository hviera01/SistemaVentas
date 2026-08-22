import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../providers/ventas_credito_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../ventas/presentation/widgets/buscar_cliente_dialog.dart';
import '../../../../core/utils/formato_moneda.dart';

class RegistrarCreditoDialog extends ConsumerStatefulWidget {
  const RegistrarCreditoDialog({super.key});

  @override
  ConsumerState<RegistrarCreditoDialog> createState() => _RegistrarCreditoDialogState();
}

class _RegistrarCreditoDialogState extends ConsumerState<RegistrarCreditoDialog> {
  final _numeroDocumentoController = TextEditingController();
  final _clienteController = TextEditingController();
  final _rtnController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _saldoPendienteController = TextEditingController();
  DateTime _fechaVencimiento = DateTime.now().add(const Duration(days: 30));
  bool _guardando = false;
  String? _error;
  // Cliente elegido con BuscarClienteDialog (opcional): si se elige, este
  // crédito manual queda vinculado de verdad al registro de 'clientes' -ver
  // CRM de clientes-, no solo con el nombre/RTN tipeados a mano. Se limpia
  // si el cajero edita el nombre/RTN después de elegirlo (ver
  // _limpiarClienteSiEdit).
  ClienteModel? _clienteSeleccionado;
  // Saldo vencido (si hay) del cliente elegido: aviso NO bloqueante, igual
  // que en RegistrarVentaScreen -no impide seguir registrando el crédito-.
  double? _saldoVencidoCliente;

  @override
  void dispose() {
    _numeroDocumentoController.dispose();
    _clienteController.dispose();
    _rtnController.dispose();
    _montoTotalController.dispose();
    _saldoPendienteController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  Future<void> _buscarCliente() async {
    final cliente = await showDialog<ClienteModel>(context: context, builder: (context) => const BuscarClienteDialog());
    if (cliente == null) return;
    setState(() {
      _clienteController.text = cliente.nombreCompleto;
      _rtnController.text = cliente.dni;
      _clienteSeleccionado = cliente;
    });
    await _verificarCreditoVencido(cliente.id);
  }

  /// Aviso NO bloqueante -ver el mismo mecanismo en RegistrarVentaScreen-:
  /// solo informa, no impide seguir registrando el crédito manual.
  Future<void> _verificarCreditoVencido(String idCliente) async {
    try {
      final creditos = await ref.read(ventaCreditoRepositoryProvider).obtenerCreditosDeCliente(idCliente: idCliente);
      final totalVencido = creditos.where((c) => c.vencida).fold<double>(0, (s, c) => s + c.saldoPendiente);
      if (!mounted) return;
      setState(() => _saldoVencidoCliente = totalVencido > 0 ? totalVencido : null);
    } catch (_) {
      // Best-effort: sin internet u otro error transitorio, no se muestra el
      // aviso esta vez.
    }
  }

  /// El cajero editó a mano el nombre/RTN después de haber elegido un
  /// cliente con el buscador: ese vínculo ya no es confiable.
  void _limpiarClienteSiEdit() {
    if (_clienteSeleccionado == null) return;
    setState(() {
      _clienteSeleccionado = null;
      _saldoVencidoCliente = null;
    });
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaVencimiento,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() => _fechaVencimiento = fecha);
  }

  Future<void> _guardar() async {
    final cliente = _clienteController.text.trim();
    if (cliente.isEmpty) {
      setState(() => _error = 'El cliente es obligatorio');
      return;
    }
    final montoTotal = _parseDouble(_montoTotalController.text);
    if (montoTotal <= 0) {
      setState(() => _error = 'Ingresá un monto total válido');
      return;
    }
    final saldoTexto = _saldoPendienteController.text.trim();
    final saldoPendiente = saldoTexto.isEmpty ? montoTotal : _parseDouble(saldoTexto);

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(ventaCreditoRepositoryProvider).crearCreditoManual(
            documentoCliente: _rtnController.text.trim(),
            nombreCliente: cliente,
            idCliente: _clienteSeleccionado?.id,
            numeroDocumento: _numeroDocumentoController.text.trim(),
            montoTotal: montoTotal,
            saldoPendiente: saldoPendiente,
            fechaVencimiento: _fechaVencimiento,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 520;
    final anchoDialog = esMovil ? tamano.width - 48 : 460.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.credit_score_outlined, color: Color(0xFFC62828)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Registrar Crédito', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usá esto para créditos que no vienen de una venta registrada en el sistema (créditos anteriores, migraciones, etc.).',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    CampoTecladoCompacto(
                      controller: _numeroDocumentoController,
                      numerico: false,
                      child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _numeroDocumentoController,
                      autofocus: true,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('No. de factura (opcional)'),
                    ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CampoTecladoCompacto(
                            controller: _clienteController,
                            numerico: false,
                            child: TextField(
                            inputFormatters: [mayusculasInputFormatter],
                            autocorrect: false,
                            enableSuggestions: false,
                            controller: _clienteController,
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Cliente'),
                            onChanged: (_) => _limpiarClienteSiEdit(),
                          ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Buscar cliente registrado',
                          onPressed: _buscarCliente,
                          icon: const Icon(Icons.search),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EAF0), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    CampoTecladoCompacto(
                      controller: _rtnController,
                      numerico: false,
                      child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _rtnController,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: _decoracion('RTN / Documento (opcional)'),
                      onChanged: (_) => _limpiarClienteSiEdit(),
                    ),
                    ),
                    if (_saldoVencidoCliente != null) ...[
                      const SizedBox(height: 14),
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
                                'Este cliente tiene un crédito vencido de ${formatearMoneda(_saldoVencidoCliente!)} — revisá antes de continuar.',
                                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CampoTecladoCompacto(
                            controller: _montoTotalController,
                            numerico: true,
                            child: TextField(
                            inputFormatters: [mayusculasInputFormatter],
                            autocorrect: false,
                            enableSuggestions: false,
                            controller: _montoTotalController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Monto total'),
                          ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CampoTecladoCompacto(
                            controller: _saldoPendienteController,
                            numerico: true,
                            child: TextField(
                            inputFormatters: [mayusculasInputFormatter],
                            autocorrect: false,
                            enableSuggestions: false,
                            controller: _saldoPendienteController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.poppins(fontSize: 14),
                            decoration: _decoracion('Saldo pendiente'),
                          ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Fecha de vencimiento', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Flexible(child: Text(formatoFecha.format(_fechaVencimiento), overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)))),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Registrar Crédito', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
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
