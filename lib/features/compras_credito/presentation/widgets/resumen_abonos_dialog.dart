import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/abono_compra_model.dart';
import '../../providers/compras_credito_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../proveedores/providers/proveedores_provider.dart';

class _FilaResumen {
  final DateTime? dia;
  final String proveedor;
  final double totalAbonado;
  final int numeroAbonos;

  _FilaResumen({required this.dia, required this.proveedor, required this.totalAbonado, required this.numeroAbonos});
}

class ResumenAbonosDialog extends ConsumerStatefulWidget {
  const ResumenAbonosDialog({super.key});

  @override
  ConsumerState<ResumenAbonosDialog> createState() => _ResumenAbonosDialogState();
}

class _ResumenAbonosDialogState extends ConsumerState<ResumenAbonosDialog> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String? _idProveedorFiltro;
  String _vista = 'proveedor';
  bool _cargando = false;
  String? _error;
  List<AbonoCompraModel>? _abonos;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final finInclusive = DateTime(_fechaFin.year, _fechaFin.month, _fechaFin.day, 23, 59, 59);
      final abonos = await ref.read(compraCreditoRepositoryProvider).obtenerAbonosPorRango(_fechaInicio, finInclusive);
      if (mounted) setState(() => _abonos = abonos);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el resumen');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _limpiar() {
    final ahora = DateTime.now();
    setState(() {
      _fechaInicio = DateTime(ahora.year, ahora.month, 1);
      _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
      _idProveedorFiltro = null;
      _vista = 'proveedor';
    });
    _buscar();
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : _fechaFin,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
      } else {
        _fechaFin = fecha;
      }
    });
  }

  List<_FilaResumen> get _filasAgrupadas {
    final abonos = _abonos ?? [];
    final filtrados = _idProveedorFiltro == null ? abonos : abonos.where((a) => a.idProveedor == _idProveedorFiltro).toList();

    final mapa = <String, _FilaResumen>{};
    for (final a in filtrados) {
      final dia = _vista == 'dia_proveedor' && a.fecha != null ? DateTime(a.fecha!.year, a.fecha!.month, a.fecha!.day) : null;
      final clave = _vista == 'dia_proveedor' ? '${dia?.toIso8601String()}_${a.nombreProveedor}' : a.nombreProveedor;
      final existente = mapa[clave];
      if (existente == null) {
        mapa[clave] = _FilaResumen(dia: dia, proveedor: a.nombreProveedor, totalAbonado: a.montoAbonado, numeroAbonos: 1);
      } else {
        mapa[clave] = _FilaResumen(dia: dia, proveedor: a.nombreProveedor, totalAbonado: existente.totalAbonado + a.montoAbonado, numeroAbonos: existente.numeroAbonos + 1);
      }
    }
    final lista = mapa.values.toList();
    if (_vista == 'dia_proveedor') {
      lista.sort((x, y) {
        final cmp = (y.dia ?? DateTime(0)).compareTo(x.dia ?? DateTime(0));
        return cmp != 0 ? cmp : x.proveedor.compareTo(y.proveedor);
      });
    } else {
      lista.sort((x, y) => y.totalAbonado.compareTo(x.totalAbonado));
    }
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 760;
    final anchoDialog = esMovil ? tamano.width - 16 : (tamano.width - 60).clamp(0, 1200).toDouble();
    final altoDialog = tamano.height < 700 ? tamano.height - 32 : (tamano.height - 80).clamp(0, 800).toDouble();
    final filas = _filasAgrupadas;
    final totalGeneral = filas.fold<double>(0, (s, f) => s + f.totalAbonado);
    final proveedoresAsync = ref.watch(proveedoresStreamProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 16 : 24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Resumen de Abonos a Proveedores', style: GoogleFonts.poppins(fontSize: esMovil ? 16 : 18, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                ),
                IconButton(icon: const Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _campoFecha('Desde', _fechaInicio, () => _seleccionarFecha(true), esMovil),
                _campoFecha('Hasta', _fechaFin, () => _seleccionarFecha(false), esMovil),
                SizedBox(
                  width: esMovil ? double.infinity : 240,
                  child: proveedoresAsync.when(
                    data: (proveedores) => _selectorProveedor(proveedores),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, st) => const SizedBox(),
                  ),
                ),
                SizedBox(width: esMovil ? double.infinity : 240, child: _selectorVista()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _cargando ? null : _buscar,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text('Buscar', style: GoogleFonts.poppins(fontSize: 13)),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _cargando ? null : _limpiar,
                      icon: const Icon(Icons.close, size: 18),
                      label: Text('Limpiar', style: GoogleFonts.poppins(fontSize: 13)),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Color(0xFFB6BCC7)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFFC62828).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.summarize_outlined, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL ABONADO', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85), letterSpacing: 0.6)),
                      Text(formatearMoneda(totalGeneral), style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFC62828)))
                  : _error != null
                      ? Center(child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red)))
                      : filas.isEmpty
                          ? Center(child: Text('No hay abonos en el rango seleccionado', style: GoogleFonts.poppins(color: Colors.grey.shade500)))
                          : _tabla(filas),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoFecha(String label, DateTime fecha, VoidCallback onTap, bool esMovil) {
    final formato = DateFormat('dd/MM/yyyy');
    return SizedBox(
      width: esMovil ? double.infinity : 200,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Flexible(
                child: Text('$label: ${formato.format(fecha)}', overflow: TextOverflow.ellipsis, maxLines: 1, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorProveedor(List<dynamic> proveedores) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _idProveedorFiltro,
          isExpanded: true,
          hint: Text('Todos los proveedores', style: GoogleFonts.poppins(fontSize: 13)),
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('Todos los proveedores', style: GoogleFonts.poppins(fontSize: 13))),
            ...proveedores.map((p) => DropdownMenuItem<String?>(value: p.id as String, child: Text(p.razonSocial as String, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (v) => setState(() => _idProveedorFiltro = v),
        ),
      ),
    );
  }

  Widget _selectorVista() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _vista,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: const [
            DropdownMenuItem(value: 'proveedor', child: Text('Por proveedor (total periodo)')),
            DropdownMenuItem(value: 'dia_proveedor', child: Text('Por día y proveedor')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _vista = v);
          },
        ),
      ),
    );
  }

  Widget _tabla(List<_FilaResumen> filas) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final mostrarDia = _vista == 'dia_proveedor';
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB6BCC7)), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFFECEEF3), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(
              children: [
                if (mostrarDia) Expanded(flex: 2, child: Text('FECHA', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 4, child: Text('PROVEEDOR', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 3, child: Text('TOTAL ABONADO', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                Expanded(flex: 2, child: Text('Nº ABONOS', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filas.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final f = filas[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      if (mostrarDia) Expanded(flex: 2, child: Text(f.dia != null ? formatoFecha.format(f.dia!) : '-', style: GoogleFonts.poppins(fontSize: 12.5))),
                      Expanded(flex: 4, child: Text(f.proveedor, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 3, child: Text(formatearMoneda(f.totalAbonado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)))),
                      Expanded(flex: 2, child: Text(f.numeroAbonos.toString(), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5))),
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
}
