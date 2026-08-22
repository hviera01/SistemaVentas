import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../clientes/providers/clientes_provider.dart';
import '../../../clientes/presentation/widgets/cliente_form_dialog.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

class BuscarClienteDialog extends ConsumerStatefulWidget {
  const BuscarClienteDialog({super.key});

  @override
  ConsumerState<BuscarClienteDialog> createState() => _BuscarClienteDialogState();
}

class _BuscarClienteDialogState extends ConsumerState<BuscarClienteDialog> {
  final _busquedaController = TextEditingController();
  final _focusBusqueda = FocusNode();
  // A diferencia de la versión anterior (filtraba en vivo mostrando TODA la
  // lista con la caja vacía), esto ahora funciona igual que Buscar Producto
  // -pedido explícito del dueño: con una lista de clientes que va a seguir
  // creciendo, mostrar todo de entrada no sirve-. La búsqueda solo corre al
  // presionar Enter o tocar el botón, no en cada tecla; con la caja vacía
  // no se muestra ningún cliente todavía.
  String? _busquedaAplicada;

  @override
  void initState() {
    super.initState();
    // Sin `autofocus` por el mismo motivo que en BuscarProductoDialog: en
    // Windows compite con la animación de apertura del diálogo y se pierde
    // la primera tecla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusBusqueda.requestFocus();
    });
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _focusBusqueda.dispose();
    super.dispose();
  }

  void _buscar() {
    setState(() => _busquedaAplicada = _busquedaController.text.trim());
  }

  /// "Crear cliente nuevo" -pedido explícito del dueño (item 5, y ajustado
  /// en una vuelta posterior porque el dueño no la encontraba escondida
  /// detrás de una búsqueda fallida): visible siempre, apenas se abre el
  /// diálogo, no solo cuando la búsqueda no encuentra a nadie. En vez de
  /// depender solo de la creación silenciosa al confirmar la venta (ver
  /// VentaRepository._resolverIdCliente), el cajero puede crearlo acá mismo,
  /// con el nombre ya tipeado precargado, y queda vinculado a la venta al
  /// instante -mismo contrato que elegir uno ya existente:
  /// Navigator.pop(context, cliente).
  Future<void> _crearClienteNuevo() async {
    final nuevo = await showDialog<ClienteModel>(
      context: context,
      builder: (context) => ClienteFormDialog(nombreInicial: _busquedaController.text),
    );
    if (nuevo == null || !mounted) return;
    Navigator.pop(context, nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final clientesAsync = ref.watch(clientesStreamProvider);
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 560;
    final anchoDialog = esMovil ? tamano.width - 24 : 500.0;
    final altoDialog = tamano.height < 640 ? tamano.height - 40 : 560.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: anchoDialog,
        height: altoDialog,
        padding: EdgeInsets.all(esMovil ? 16 : 22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Buscar Cliente', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Escribí y presioná Enter para buscar por DNI o nombre.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CampoTecladoCompacto(
                            controller: _busquedaController,
                            numerico: false,
                            onSubmitted: (_) => _buscar(),
                            titulo: 'Buscar por DNI o nombre...',
                            child: TextField(
                              inputFormatters: [mayusculasInputFormatter],
                              autocorrect: false,
                              enableSuggestions: false,
                              controller: _busquedaController,
                              focusNode: _focusBusqueda,
                              style: GoogleFonts.poppins(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Buscar por DNI o nombre...',
                                hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _buscar(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Buscar',
                  onPressed: _buscar,
                  icon: const Icon(Icons.arrow_forward),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8EAF0), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _crearClienteNuevo,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: Text('Crear cliente nuevo', style: GoogleFonts.poppins(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC62828),
                  side: const BorderSide(color: Color(0xFFC62828)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: clientesAsync.when(
                data: (clientes) {
                  final aplicada = _busquedaAplicada;
                  if (aplicada == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Escribí algo y presioná Enter para buscar', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }
                  final lista = aplicada.isEmpty
                      ? const <ClienteModel>[]
                      : clientes.where((c) => c.estado && coincideFuzzy(c.textoBusqueda, aplicada)).toList();
                  if (lista.isEmpty) {
                    // El botón "Crear cliente nuevo" ya vive siempre visible
                    // arriba del buscador (ver Align más arriba); acá ya no
                    // hace falta repetirlo.
                    return Center(
                      child: Text('No se encontraron clientes', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                    );
                  }
                  return ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) {
                      final c = lista[i];
                      return InkWell(
                        onTap: () => Navigator.pop(context, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.nombreCompleto, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              if (c.dni.isNotEmpty) Text('DNI: ${c.dni}', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
                error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
