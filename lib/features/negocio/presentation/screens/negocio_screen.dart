import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/impresora_red_service.dart';
import '../../data/negocio_model.dart';
import '../../providers/negocio_provider.dart';
import '../widgets/negocio_logo_picker.dart';
import '../widgets/selector_impresora.dart';

class NegocioScreen extends ConsumerWidget {
  const NegocioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negocioAsync = ref.watch(negocioStreamProvider);
    return Container(
      color: const Color(0xFFF2F3F7),
      child: negocioAsync.when(
        data: (modelo) => _NegocioForm(modelo: modelo),
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
        error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
      ),
    );
  }
}

class _NegocioForm extends ConsumerStatefulWidget {
  final NegocioModel modelo;

  const _NegocioForm({required this.modelo});

  @override
  ConsumerState<_NegocioForm> createState() => _NegocioFormState();
}

class _NegocioFormState extends ConsumerState<_NegocioForm> {
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _rtnController = TextEditingController();
  final _caiController = TextEditingController();
  final _direccionController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _esloganController = TextEditingController();
  final _rangoPrefijoController = TextEditingController();
  final _rangoDesdeController = TextEditingController();
  final _rangoHastaController = TextEditingController();
  final _claveController = TextEditingController();
  final _ipRedController = TextEditingController();
  final _puertoRedController = TextEditingController();
  final _servicioImpresoraRed = ImpresoraRedService();

  DateTime? _fechaLimite;
  late Map<String, bool> _permisos;
  bool _guardando = false;
  bool _guardandoClave = false;
  bool _guardandoRed = false;
  bool _probandoRed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.modelo;
    _nombreController.text = m.nombre;
    _correoController.text = m.correo;
    _rtnController.text = m.rtn;
    _caiController.text = m.cai;
    _direccionController.text = m.direccion;
    _telefonoController.text = m.telefono;
    _esloganController.text = m.eslogan;
    _rangoPrefijoController.text = m.rangoPrefijo;
    _rangoDesdeController.text = m.rangoDesde;
    _rangoHastaController.text = m.rangoHasta;
    _fechaLimite = m.fechaLimiteEmision;
    _permisos = Map<String, bool>.from(m.permisos);
    _ipRedController.text = m.impresoraRedIp;
    _puertoRedController.text = m.impresoraRedPuerto.toString();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _rtnController.dispose();
    _caiController.dispose();
    _direccionController.dispose();
    _telefonoController.dispose();
    _esloganController.dispose();
    _rangoPrefijoController.dispose();
    _rangoDesdeController.dispose();
    _rangoHastaController.dispose();
    _claveController.dispose();
    _ipRedController.dispose();
    _puertoRedController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre del negocio es obligatorio');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(negocioRepositoryProvider).actualizarDatosGenerales(
            nombre: nombre,
            correo: _correoController.text.trim(),
            rtn: _rtnController.text.trim(),
            cai: _caiController.text.trim(),
            direccion: _direccionController.text.trim(),
            telefono: _telefonoController.text.trim(),
            eslogan: _esloganController.text.trim(),
            rangoPrefijo: _rangoPrefijoController.text.trim(),
            rangoDesde: _rangoDesdeController.text.trim(),
            rangoHasta: _rangoHastaController.text.trim(),
            fechaLimiteEmision: _fechaLimite,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos del negocio guardados')));
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar los cambios');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaLimite ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() => _fechaLimite = fecha);
  }

  Future<void> _guardarClave() async {
    final clave = _claveController.text.trim();
    if (clave.length < 4) {
      setState(() => _error = 'La clave especial debe tener al menos 4 caracteres');
      return;
    }
    setState(() {
      _guardandoClave = true;
      _error = null;
    });
    try {
      await ref.read(negocioRepositoryProvider).establecerClave(clave);
      _claveController.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave especial actualizada')));
    } finally {
      if (mounted) setState(() => _guardandoClave = false);
    }
  }

  Future<void> _quitarClave() async {
    setState(() => _guardandoClave = true);
    try {
      await ref.read(negocioRepositoryProvider).quitarClave();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave especial eliminada')));
    } finally {
      if (mounted) setState(() => _guardandoClave = false);
    }
  }

  void _alternarPermiso(String key, bool valor) {
    setState(() => _permisos[key] = valor);
    ref.read(negocioRepositoryProvider).actualizarPermisos(_permisos);
  }

  Future<void> _guardarImpresoraRed() async {
    final ip = _ipRedController.text.trim();
    final puerto = int.tryParse(_puertoRedController.text.trim()) ?? 9100;
    setState(() => _guardandoRed = true);
    try {
      await ref.read(negocioRepositoryProvider).actualizarImpresoraRed(ip, puerto);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impresora de red guardada')));
    } finally {
      if (mounted) setState(() => _guardandoRed = false);
    }
  }

  Future<void> _probarImpresoraRed() async {
    final ip = _ipRedController.text.trim();
    final puerto = int.tryParse(_puertoRedController.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresá la IP de la impresora primero')));
      return;
    }
    setState(() => _probandoRed = true);
    try {
      // ESC @ (inicializar impresora): no imprime nada visible, solo
      // confirma que la impresora respondió en esa IP/puerto sin gastar
      // papel en cada prueba de conexión.
      final ok = await _servicioImpresoraRed.imprimir(ip: ip, puerto: puerto, bytes: const [0x1B, 0x40]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Conexión exitosa' : 'No se pudo conectar a esa IP/puerto')),
      );
    } finally {
      if (mounted) setState(() => _probandoRed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneClave = widget.modelo.tieneClaveEspecial;

    return LayoutBuilder(
      builder: (context, constraints) {
        final esMovil = constraints.maxWidth < 720;
        return Padding(
          padding: EdgeInsets.all(esMovil ? 14 : 26),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Negocio', style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(negocioStreamProvider),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A1A),
                        side: const BorderSide(color: Color(0xFFB6BCC7)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(child: const SizedBox(height: 18)),
              SliverToBoxAdapter(child: _tarjetaDatos(esMovil)),
              SliverToBoxAdapter(child: const SizedBox(height: 18)),
              SliverToBoxAdapter(child: _tarjetaPermisos(esMovil, tieneClave)),
              SliverToBoxAdapter(child: const SizedBox(height: 18)),
              SliverToBoxAdapter(child: _tarjetaImpresoras(esMovil)),
              SliverToBoxAdapter(child: const SizedBox(height: 18)),
              SliverToBoxAdapter(child: _tarjetaFactura()),
              SliverToBoxAdapter(child: const SizedBox(height: 18)),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC7CBD3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }

  Widget _tituloSeccion(String texto, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 19, color: const Color(0xFFC62828)),
        const SizedBox(width: 8),
        Text(texto, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
      ],
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _campo(TextEditingController controller, String label, double ancho) {
    return SizedBox(
      width: ancho,
      child: TextField(
        controller: controller,
        style: GoogleFonts.poppins(fontSize: 13.5),
        decoration: _decoracion(label),
      ),
    );
  }

  Widget _tarjetaDatos(bool esMovil) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Datos del negocio', Icons.store_outlined),
          const SizedBox(height: 18),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              NegocioLogoPicker(titulo: 'Logo a color', base64Actual: widget.modelo.logoColorBase64, esColor: true),
              NegocioLogoPicker(titulo: 'Logo blanco y negro', base64Actual: widget.modelo.logoBnBase64, esColor: false),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final anchoCampo = esMovil ? constraints.maxWidth : (constraints.maxWidth - 20) / 2;
              return Wrap(
                spacing: 20,
                runSpacing: 14,
                children: [
                  _campo(_nombreController, 'Nombre del negocio', anchoCampo),
                  _campo(_correoController, 'Correo electrónico', anchoCampo),
                  _campo(_rtnController, 'R.T.N.', anchoCampo),
                  _campo(_caiController, 'CAI', anchoCampo),
                  _campo(_direccionController, 'Dirección', anchoCampo),
                  _rangoAutorizado(anchoCampo),
                  _campo(_telefonoController, 'Teléfono', anchoCampo),
                  _campo(_esloganController, 'Eslogan', anchoCampo),
                  SizedBox(width: anchoCampo, child: _campoFecha()),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFFC62828))),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: esMovil ? double.infinity : 220,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_guardando ? 'Guardando...' : 'Guardar cambios', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangoAutorizado(double ancho) {
    return SizedBox(
      width: ancho,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rango autorizado', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(flex: 3, child: TextField(controller: _rangoPrefijoController, style: GoogleFonts.poppins(fontSize: 13), decoration: _decoracion('Prefijo'))),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: TextField(controller: _rangoDesdeController, keyboardType: TextInputType.number, style: GoogleFonts.poppins(fontSize: 13), decoration: _decoracion('Desde'))),
              const SizedBox(width: 8),
              Text('AL', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: TextField(controller: _rangoHastaController, keyboardType: TextInputType.number, style: GoogleFonts.poppins(fontSize: 13), decoration: _decoracion('Hasta'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _campoFecha() {
    final formato = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fecha límite de emisión', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        InkWell(
          onTap: _seleccionarFecha,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 10),
                Flexible(child: Text(_fechaLimite != null ? formato.format(_fechaLimite!) : 'Sin definir', overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF1A1A1A)))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaPermisos(bool esMovil, bool tieneClave) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Acceso de permisos especiales', Icons.lock_outline),
          const SizedBox(height: 6),
          Text(
            'Definí una clave que se pedirá antes de realizar ciertas acciones sensibles. Es opcional: activá solo lo que necesites.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: esMovil ? double.infinity : 260,
                child: TextField(
                  controller: _claveController,
                  obscureText: true,
                  style: GoogleFonts.poppins(fontSize: 13.5),
                  decoration: _decoracion(tieneClave ? 'Nueva clave especial' : 'Definir clave especial'),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : null,
                child: FilledButton(
                  onPressed: _guardandoClave ? null : _guardarClave,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Guardar clave', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
                ),
              ),
              if (tieneClave)
                SizedBox(
                  width: esMovil ? double.infinity : null,
                  child: OutlinedButton(
                    onPressed: _guardandoClave ? null : _quitarClave,
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFF3B9B9)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Quitar clave', style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(tieneClave ? Icons.check_circle : Icons.info_outline, size: 15, color: tieneClave ? const Color(0xFF16A34A) : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                tieneClave ? 'Clave especial activa' : 'No hay clave especial configurada',
                style: GoogleFonts.poppins(fontSize: 12, color: tieneClave ? const Color(0xFF16A34A) : Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Text('¿Dónde pedir la clave?', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 6),
          ...PermisosEspeciales.etiquetas.entries.map(
            (entrada) => _filaPermiso(entrada.key, entrada.value, PermisosEspeciales.descripciones[entrada.key] ?? '', tieneClave),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaImpresoras(bool esMovil) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Impresoras', Icons.print_outlined),
          const SizedBox(height: 6),
          Text(
            'Elegí qué impresora usar para los recibos térmicos y para las etiquetas de productos. Se usarán en todo el sistema.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Flex(
            direction: esMovil ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: esMovil ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectorImpresora(
                  titulo: 'Impresora térmica (recibos)',
                  urlActual: widget.modelo.impresoraTermicaUrl,
                  nombreActual: widget.modelo.impresoraTermicaNombre,
                  onSeleccionar: (url, nombre) => ref.read(negocioRepositoryProvider).actualizarImpresoraTermica(url, nombre),
                ),
              ),
              SizedBox(width: esMovil ? 0 : 20, height: esMovil ? 16 : 0),
              Expanded(
                child: SelectorImpresora(
                  titulo: 'Impresora de etiquetas',
                  urlActual: widget.modelo.impresoraEtiquetasUrl,
                  nombreActual: widget.modelo.impresoraEtiquetasNombre,
                  onSeleccionar: (url, nombre) => ref.read(negocioRepositoryProvider).actualizarImpresoraEtiquetas(url, nombre),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 14),
          _filaSwitchFactura(
            titulo: 'Imprimir directo, sin preguntar',
            descripcion:
                'Al confirmar una venta facturable se imprime directo, sin mostrar el diálogo de vista previa/descargar. En el programa de escritorio sale directo de la impresora elegida arriba, sin ningún clic. En el navegador (web) salta directo al diálogo de impresión del navegador (ese cartel no se puede evitar, es del navegador, no de esta app). En el celular usa la impresora de red de abajo. Si no hay impresora configurada, la venta se guarda igual y no se bloquea nada.',
            valor: widget.modelo.modoImpresion == ModoImpresion.directo,
            onChanged: (v) => ref.read(negocioRepositoryProvider).establecerModoImpresion(v ? ModoImpresion.directo : ModoImpresion.preguntar),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 14),
          Text('Impresora térmica de red (para celular)', style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text(
            'En el celular no se pueden listar las impresoras del sistema. Si tu impresora térmica está conectada a la misma red WiFi, ingresá su IP acá: la venta se manda a imprimir directo por esa dirección.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (kIsWeb)
            Text('No disponible en la versión web (el navegador no permite esta conexión directa).', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500))
          else
            Flex(
              direction: esMovil ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: esMovil ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipRedController,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'IP de la impresora',
                      hintText: '192.168.1.50',
                      filled: true,
                      fillColor: const Color(0xFFE8EAF0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                Expanded(
                  child: TextField(
                    controller: _puertoRedController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Puerto',
                      filled: true,
                      fillColor: const Color(0xFFE8EAF0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _probandoRed ? null : _probarImpresoraRed,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _probandoRed
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Probar', style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _guardandoRed ? null : _guardarImpresoraRed,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D), padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _guardandoRed
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Guardar', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tarjetaFactura() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Factura', Icons.receipt_long_outlined),
          const SizedBox(height: 6),
          Text(
            'Configuración de lo que se imprime en el ticket de venta.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          _filaSwitchFactura(
            titulo: 'Imprimir copia además del original',
            descripcion: 'Si lo apagás, cada venta solo imprime la hoja "ORIGINAL" (se ahorra el papel de la "COPIA").',
            valor: widget.modelo.facturaImprimirCopia,
            onChanged: (v) => ref.read(negocioRepositoryProvider).establecerFacturaImprimirCopia(v),
          ),
          Divider(color: Colors.grey.shade200, height: 28),
          _filaSwitchFactura(
            titulo: 'Mostrar precios con ISV incluido',
            descripcion: 'El precio unitario y el importe de cada producto en el ticket se muestran con ISV incluido (el total y el desglose de ISV no cambian).',
            valor: widget.modelo.facturaPreciosConIsv,
            onChanged: (v) => ref.read(negocioRepositoryProvider).establecerFacturaPreciosConIsv(v),
          ),
        ],
      ),
    );
  }

  Widget _filaSwitchFactura({
    required String titulo,
    required String descripcion,
    required bool valor,
    required void Function(bool) onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 3),
              Text(descripcion, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Switch(value: valor, activeThumbColor: const Color(0xFF16A34A), onChanged: onChanged),
      ],
    );
  }

  Widget _filaPermiso(String key, String titulo, String descripcion, bool tieneClave) {
    final activo = _permisos[key] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text(descripcion, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: activo,
            onChanged: !tieneClave ? null : (v) => _alternarPermiso(key, v),
            activeThumbColor: const Color(0xFFC62828),
          ),
        ],
      ),
    );
  }
}
