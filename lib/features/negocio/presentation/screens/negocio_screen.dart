import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/impresora_red_service.dart';
import '../../../../core/utils/face_id_storage.dart';
import '../../../../core/utils/webauthn.dart';
import '../../../../core/widgets/face_id_icon.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../ventas/providers/ventas_provider.dart';
import '../../data/negocio_model.dart';
import '../../providers/negocio_provider.dart';
import '../widgets/negocio_logo_picker.dart';
import '../widgets/selector_impresora.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../../core/utils/tablet_utils_stub.dart'
    if (dart.library.html) '../../../../core/utils/tablet_utils_web.dart'
    as tactil;

// Específicamente el navegador de un celular/tablet (no la PC, no la app de
// escritorio): ver _tarjetaFaceId, donde vive el mismo Face ID/Touch ID que
// ya usa LoginScreen para entrar más rápido. Mismo criterio EXACTO que
// LoginScreen._esWebMovil -tiene que ser el mismo acá y ahí, si no
// "Activar Face ID" (acá) y el botón para usarlo (LoginScreen) podrían
// terminar en desacuerdo sobre si el dispositivo cuenta o no-: un iPad con
// Safari se identifica a sí mismo como macOS de escritorio, así que hace
// falta la señal aparte de tablet_utils_web.dart (navigator.maxTouchPoints)
// para no perderlo -bug real reportado por el dueño: no aparecía la opción
// de Touch ID en su iPad.
bool get _esWebMovil =>
    kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        (defaultTargetPlatform == TargetPlatform.macOS &&
            tactil.esDispositivoTactil()));

// El script que manda el reporte financiero por WhatsApp (ver
// tool/reporte_whatsapp) es un proceso de Node.js aparte que solo existe en
// esta misma PC de escritorio -no es una función en la nube-, así que el
// botón de "enviar ahora" únicamente tiene sentido corriendo la versión de
// escritorio Windows en esta máquina (no en web, ni en el celular, ni en
// otra PC que no tenga instalado ese script).
bool get _puedeEnviarReporteWhatsapp => !kIsWeb && Platform.isWindows;

const _rutaReporteWhatsapp =
    r'C:\Proyectos\sistema_ventas\tool\reporte_whatsapp';

class NegocioScreen extends ConsumerWidget {
  const NegocioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negocioAsync = ref.watch(negocioStreamProvider);
    return Container(
      color: const Color(0xFFF2F3F7),
      child: negocioAsync.when(
        data: (modelo) => _NegocioForm(modelo: modelo),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFC62828)),
        ),
        error: (e, st) => Center(
          child: Text(
            'Error: $e',
            style: GoogleFonts.poppins(color: Colors.red),
          ),
        ),
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
  final _ctrlProximoFactura = TextEditingController();
  final _servicioImpresoraRed = ImpresoraRedService();

  DateTime? _fechaLimite;
  late Map<String, bool> _permisos;
  bool _guardando = false;
  bool _guardandoClave = false;
  bool _enviandoReporteSemanal = false;
  bool _enviandoReporteMensual = false;
  bool _guardandoRed = false;
  bool _probandoRed = false;
  int? _proximoFacturaActual;
  bool _cargandoProximoFactura = true;
  bool _guardandoProximoFactura = false;
  String? _error;

  // Face ID en este celular (ver _tarjetaFaceId): id (base64url) del
  // credencial ya activado acá, o null si todavía no se activó. Se carga
  // async porque SharedPreferences no es síncrono la primera vez.
  String? _credencialFaceId;
  bool _cargandoFaceId = true;
  // El propio diálogo de _activarFaceId ya se bloquea solo mientras
  // procesa (ver "procesando" ahí adentro); esto solo evita un segundo
  // toque en el botón de la tarjeta mientras ese diálogo está abierto.
  final _procesandoFaceId = false;

  @override
  void initState() {
    super.initState();
    if (_esWebMovil) {
      _cargarEstadoFaceId();
    } else {
      _cargandoFaceId = false;
    }
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
    _cargarProximoFactura();
  }

  Future<void> _cargarEstadoFaceId() async {
    final credencial = await credencialFaceIdGuardada();
    if (mounted)
      setState(() {
        _credencialFaceId = credencial;
        _cargandoFaceId = false;
      });
  }

  // A diferencia del intento original en LoginScreen (donde se ofrecía
  // activar Face ID justo después de loguearse, y a veces "no pasaba nada"
  // porque AuthGate ya había reemplazado esa pantalla por AppShell antes de
  // llegar a mostrar el diálogo), esta pantalla no se cierra sola: se puede
  // activar acá con confianza en cualquier momento. Como Negocio no tiene a
  // mano la clave en texto plano del usuario (nunca se guarda en ningún
  // provider, por seguridad), este diálogo la vuelve a pedir y la valida de
  // verdad contra Firestore (mismo AuthRepository.login que usa el login
  // normal, con sus mismos bloqueos por intentos fallidos) antes de
  // activar Face ID con esas credenciales.
  Future<void> _activarFaceId() async {
    final disponible = await webAuthnDisponible();
    if (!mounted) return;
    if (!disponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face ID no está disponible en este modo/navegador'),
        ),
      );
      return;
    }

    final ctrlCodigo = TextEditingController();
    final ctrlClave = TextEditingController();
    // Declarado afuera del builder de StatefulBuilder a propósito: si
    // viviera adentro, cada setDialogState() -que vuelve a correr todo el
    // cuerpo del builder- lo reiniciaría a false, perdiendo el estado
    // "procesando" justo cuando más importa (mientras se valida y se pide
    // Face ID).
    var procesando = false;
    final credencialId = await showDialog<String>(
      useRootNavigator: false,
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(
              'Activar Face ID',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Confirmá el código de acceso y la contraseña que Face ID va a recordar en este celular.',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                const SizedBox(height: 16),
                CampoTecladoCompacto(
                  controller: ctrlCodigo,
                  numerico: false,
                  titulo: 'Código de acceso',
                  child: TextField(
                    inputFormatters: [mayusculasInputFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: ctrlCodigo,
                    autofocus: true,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Código de acceso',
                      filled: true,
                      fillColor: const Color(0xFFE8EAF0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrlClave,
                  obscureText: true,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    filled: true,
                    fillColor: const Color(0xFFE8EAF0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: procesando
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: procesando
                    ? null
                    : () async {
                        final codigo = ctrlCodigo.text.trim();
                        final clave = ctrlClave.text.trim();
                        if (codigo.isEmpty || clave.isEmpty) return;
                        setDialogState(() => procesando = true);
                        try {
                          await ref
                              .read(authRepositoryProvider)
                              .login(codigo, clave);
                          // El pedido de Face ID se dispara DIRECTO acá,
                          // sin ningún await de más antes: Safari en
                          // iPhone exige que WebAuthn se pida dentro del
                          // mismo gesto del usuario (activación
                          // transitoria), y ya se gastó parte de esa
                          // ventana en la validación de arriba.
                          final id = await webAuthnRegistrar(
                            usuarioId: codigo,
                            usuarioNombre: codigo,
                          );
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext, id);
                        } catch (e) {
                          setDialogState(() => procesando = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo activar: $e')),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F1B3D),
                ),
                child: procesando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Activar'),
              ),
            ],
          );
        },
      ),
    );

    final codigo = ctrlCodigo.text.trim();
    final clave = ctrlClave.text.trim();
    ctrlCodigo.dispose();
    ctrlClave.dispose();
    if (credencialId == null || !mounted) return;

    await guardarCredencialesFaceId(
      credencialId: credencialId,
      codigo: codigo,
      clave: clave,
    );
    if (!mounted) return;
    setState(() => _credencialFaceId = credencialId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Face ID activado en este celular')),
    );
  }

  Future<void> _olvidarFaceId() async {
    await olvidarCredencialesFaceId();
    if (mounted) setState(() => _credencialFaceId = null);
  }

  Future<void> _cargarProximoFactura() async {
    final proximo = await ref
        .read(ventaRepositoryProvider)
        .obtenerProximoNumeroFactura();
    if (!mounted) return;
    setState(() {
      _proximoFacturaActual = proximo;
      _cargandoProximoFactura = false;
      _ctrlProximoFactura.text = proximo.toString();
    });
  }

  Future<void> _guardarProximoFactura() async {
    final valor = int.tryParse(_ctrlProximoFactura.text.trim());
    if (valor == null || valor < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un número válido (mayor a 0)')),
      );
      return;
    }
    setState(() => _guardandoProximoFactura = true);
    try {
      await ref
          .read(ventaRepositoryProvider)
          .establecerProximoNumeroFactura(valor);
      if (!mounted) return;
      setState(() {
        _proximoFacturaActual = valor;
        _guardandoProximoFactura = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La próxima factura va a salir con el número ${_formatoFactura(valor)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoProximoFactura = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  String _formatoFactura(int numero) => numero.toString().padLeft(8, '0');

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
    _ctrlProximoFactura.dispose();
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
      await ref
          .read(negocioRepositoryProvider)
          .actualizarDatosGenerales(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos del negocio guardados')),
        );
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
      setState(
        () => _error = 'La clave especial debe tener al menos 4 caracteres',
      );
      return;
    }
    setState(() {
      _guardandoClave = true;
      _error = null;
    });
    try {
      await ref.read(negocioRepositoryProvider).establecerClave(clave);
      _claveController.clear();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clave especial actualizada')),
        );
    } finally {
      if (mounted) setState(() => _guardandoClave = false);
    }
  }

  Future<void> _quitarClave() async {
    setState(() => _guardandoClave = true);
    try {
      await ref.read(negocioRepositoryProvider).quitarClave();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clave especial eliminada')),
        );
    } finally {
      if (mounted) setState(() => _guardandoClave = false);
    }
  }

  /// Corre a mano el mismo script de Node que usa la tarea programada (ver
  /// tool/reporte_whatsapp/README.md), en vez de esperar al próximo sábado/
  /// fin de mes. Solo tiene sentido en la versión de escritorio Windows de
  /// esta misma PC -es la única que tiene Node.js instalado y la sesión de
  /// WhatsApp ya vinculada-.
  Future<void> _enviarReporteWhatsapp(String tipo) async {
    setState(() {
      if (tipo == 'semanal') {
        _enviandoReporteSemanal = true;
      } else {
        _enviandoReporteMensual = true;
      }
    });
    try {
      final resultado = await Process.run(
        'node',
        ['index.js', tipo],
        workingDirectory: _rutaReporteWhatsapp,
        runInShell: true,
      );
      if (!mounted) return;
      if (resultado.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte $tipo enviado por WhatsApp'),
            showCloseIcon: true,
          ),
        );
      } else {
        final salida = '${resultado.stderr}'.trim().isNotEmpty
            ? '${resultado.stderr}'
            : '${resultado.stdout}';
        // Se corta a las últimas líneas: la traza completa de un error de
        // Node/Baileys puede ser larguísima y no cabe (ni hace falta) en un
        // SnackBar -el detalle completo queda igual en la consola de esa PC
        // si hace falta revisarlo a fondo-.
        final lineas = salida.trim().split('\n');
        final resumen = lineas.length > 4
            ? lineas.sublist(lineas.length - 4).join('\n')
            : salida.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar el reporte $tipo:\n$resumen'),
            showCloseIcon: true,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo ejecutar el script (¿Node.js está instalado en esta PC?): $e',
            ),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (tipo == 'semanal') {
            _enviandoReporteSemanal = false;
          } else {
            _enviandoReporteMensual = false;
          }
        });
      }
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
      await ref
          .read(negocioRepositoryProvider)
          .actualizarImpresoraRed(ip, puerto);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impresora de red guardada')),
        );
    } finally {
      if (mounted) setState(() => _guardandoRed = false);
    }
  }

  Future<void> _probarImpresoraRed() async {
    final ip = _ipRedController.text.trim();
    final puerto = int.tryParse(_puertoRedController.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá la IP de la impresora primero')),
      );
      return;
    }
    setState(() => _probandoRed = true);
    try {
      // ESC @ (inicializar impresora): no imprime nada visible, solo
      // confirma que la impresora respondió en esa IP/puerto sin gastar
      // papel en cada prueba de conexión.
      final ok = await _servicioImpresoraRed.imprimir(
        ip: ip,
        puerto: puerto,
        bytes: const [0x1B, 0x40],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Conexión exitosa' : 'No se pudo conectar a esa IP/puerto',
          ),
        ),
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
                      child: Text(
                        'Negocio',
                        style: GoogleFonts.poppins(
                          fontSize: esMovil ? 19 : 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(negocioStreamProvider),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        'Refrescar',
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A1A),
                        side: const BorderSide(color: Color(0xFFB6BCC7)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
              SliverToBoxAdapter(child: _tarjetaTecladoCompacto()),
              if (_puedeEnviarReporteWhatsapp) ...[
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
                SliverToBoxAdapter(child: _tarjetaReporteWhatsapp()),
              ],
              if (_esWebMovil) ...[
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
                SliverToBoxAdapter(child: _tarjetaFaceId()),
              ],
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _tituloSeccion(String texto, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 19, color: const Color(0xFFC62828)),
        const SizedBox(width: 8),
        Text(
          texto,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _campo(TextEditingController controller, String label, double ancho) {
    return SizedBox(
      width: ancho,
      child: CampoTecladoCompacto(
        controller: controller,
        numerico: false,
        child: TextField(
          inputFormatters: [mayusculasInputFormatter],
          autocorrect: false,
          enableSuggestions: false,
          controller: controller,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _decoracion(label),
        ),
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
              NegocioLogoPicker(
                titulo: 'Logo a color',
                base64Actual: widget.modelo.logoColorBase64,
                esColor: true,
              ),
              NegocioLogoPicker(
                titulo: 'Logo blanco y negro',
                base64Actual: widget.modelo.logoBnBase64,
                esColor: false,
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final anchoCampo = esMovil
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 20) / 2;
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
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFFC62828),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: esMovil ? double.infinity : 220,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(
                _guardando ? 'Guardando...' : 'Guardar cambios',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
          Text(
            'Rango autorizado',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: CampoTecladoCompacto(
                  controller: _rangoPrefijoController,
                  numerico: false,
                  child: TextField(
                    inputFormatters: [mayusculasInputFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: _rangoPrefijoController,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: _decoracion('Prefijo'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: CampoTecladoCompacto(
                  controller: _rangoDesdeController,
                  numerico: true,
                  child: TextField(
                    inputFormatters: [mayusculasInputFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: _rangoDesdeController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: _decoracion('Desde'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AL',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: CampoTecladoCompacto(
                  controller: _rangoHastaController,
                  numerico: true,
                  child: TextField(
                    inputFormatters: [mayusculasInputFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: _rangoHastaController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: _decoracion('Hasta'),
                  ),
                ),
              ),
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
        Text(
          'Fecha límite de emisión',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _seleccionarFecha,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EAF0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _fechaLimite != null
                        ? formato.format(_fechaLimite!)
                        : 'Sin definir',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
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
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
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
                  decoration: _decoracion(
                    tieneClave
                        ? 'Nueva clave especial'
                        : 'Definir clave especial',
                  ),
                ),
              ),
              SizedBox(
                width: esMovil ? double.infinity : null,
                child: FilledButton(
                  onPressed: _guardandoClave ? null : _guardarClave,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Guardar clave',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (tieneClave)
                SizedBox(
                  width: esMovil ? double.infinity : null,
                  child: OutlinedButton(
                    onPressed: _guardandoClave ? null : _quitarClave,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFF3B9B9)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Quitar clave',
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                tieneClave ? Icons.check_circle : Icons.info_outline,
                size: 15,
                color: tieneClave
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                tieneClave
                    ? 'Clave especial activa'
                    : 'No hay clave especial configurada',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: tieneClave
                      ? const Color(0xFF16A34A)
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Text(
            '¿Dónde pedir la clave?',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          ...PermisosEspeciales.etiquetas.entries.map(
            (entrada) => _filaPermiso(
              entrada.key,
              entrada.value,
              PermisosEspeciales.descripciones[entrada.key] ?? '',
              tieneClave,
            ),
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
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 18),
          Flex(
            direction: esMovil ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: esMovil
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectorImpresora(
                  titulo: 'Impresora térmica (recibos)',
                  urlActual: widget.modelo.impresoraTermicaUrl,
                  nombreActual: widget.modelo.impresoraTermicaNombre,
                  onSeleccionar: (url, nombre) => ref
                      .read(negocioRepositoryProvider)
                      .actualizarImpresoraTermica(url, nombre),
                ),
              ),
              SizedBox(width: esMovil ? 0 : 20, height: esMovil ? 16 : 0),
              Expanded(
                child: SelectorImpresora(
                  titulo: 'Impresora de etiquetas',
                  urlActual: widget.modelo.impresoraEtiquetasUrl,
                  nombreActual: widget.modelo.impresoraEtiquetasNombre,
                  onSeleccionar: (url, nombre) => ref
                      .read(negocioRepositoryProvider)
                      .actualizarImpresoraEtiquetas(url, nombre),
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
            onChanged: (v) => ref
                .read(negocioRepositoryProvider)
                .establecerModoImpresion(
                  v ? ModoImpresion.directo : ModoImpresion.preguntar,
                ),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 14),
          Text(
            'Impresora térmica de red (para celular)',
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'En el celular no se pueden listar las impresoras del sistema. Si tu impresora térmica está conectada a la misma red WiFi, ingresá su IP acá: la venta se manda a imprimir directo por esa dirección.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          if (kIsWeb)
            Text(
              'No disponible en la versión web (el navegador no permite esta conexión directa).',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: Colors.grey.shade500,
              ),
            )
          else
            Flex(
              direction: esMovil ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: esMovil
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: CampoTecladoCompacto(
                    controller: _ipRedController,
                    numerico: false,
                    titulo: 'IP de la impresora',
                    child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _ipRedController,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'IP de la impresora',
                        hintText: '192.168.1.50',
                        filled: true,
                        fillColor: const Color(0xFFE8EAF0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                Expanded(
                  child: CampoTecladoCompacto(
                    controller: _puertoRedController,
                    numerico: true,
                    titulo: 'Puerto',
                    child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _puertoRedController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Puerto',
                        filled: true,
                        fillColor: const Color(0xFFE8EAF0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _probandoRed ? null : _probarImpresoraRed,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _probandoRed
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Probar',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                  ),
                ),
                SizedBox(width: esMovil ? 0 : 12, height: esMovil ? 12 : 0),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _guardandoRed ? null : _guardarImpresoraRed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F1B3D),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardandoRed
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Guardar',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tarjetaReporteWhatsapp() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(
            'Reporte financiero por WhatsApp',
            Icons.picture_as_pdf_outlined,
          ),
          const SizedBox(height: 6),
          Text(
            'Normalmente se manda solo, programado los sábados (semanal) y a fin de mes (mensual) desde esta PC. '
            'Estos botones lo mandan al toque, sin esperar al horario programado -por ejemplo, si el envío automático falló-.',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _enviandoReporteSemanal
                    ? null
                    : () => _enviarReporteWhatsapp('semanal'),
                icon: _enviandoReporteSemanal
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(
                  'Enviar reporte semanal ahora',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Color(0xFFB6BCC7)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _enviandoReporteMensual
                    ? null
                    : () => _enviarReporteWhatsapp('mensual'),
                icon: _enviandoReporteMensual
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(
                  'Enviar reporte mensual ahora',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Color(0xFFB6BCC7)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          _filaSwitchFactura(
            titulo: 'Imprimir copia además del original',
            descripcion:
                'Si lo apagás, cada venta solo imprime la hoja "ORIGINAL" (se ahorra el papel de la "COPIA").',
            valor: widget.modelo.facturaImprimirCopia,
            onChanged: (v) => ref
                .read(negocioRepositoryProvider)
                .establecerFacturaImprimirCopia(v),
          ),
          Divider(color: Colors.grey.shade200, height: 28),
          _filaSwitchFactura(
            titulo: 'Mostrar precios con ISV incluido',
            descripcion:
                'El precio unitario y el importe de cada producto en el ticket se muestran con ISV incluido (el total y el desglose de ISV no cambian).',
            valor: widget.modelo.facturaPreciosConIsv,
            onChanged: (v) => ref
                .read(negocioRepositoryProvider)
                .establecerFacturaPreciosConIsv(v),
          ),
          Divider(color: Colors.grey.shade200, height: 28),
          Text(
            'Numeración de facturas',
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'El número que le va a tocar a la próxima Factura o Boleta que registrés. Sirve para continuar la numeración de un talonario físico en vez de arrancar siempre desde 1 (por ejemplo, después de vaciar los datos de prueba).',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          if (_cargandoProximoFactura)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CampoTecladoCompacto(
                    controller: _ctrlProximoFactura,
                    numerico: true,
                    titulo: 'Próximo número de factura',
                    child: TextField(
                      inputFormatters: [mayusculasInputFormatter],
                      autocorrect: false,
                      enableSuggestions: false,
                      controller: _ctrlProximoFactura,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Próximo número de factura',
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        helperText: _proximoFacturaActual != null
                            ? 'Actual: ${_formatoFactura(_proximoFacturaActual!)}'
                            : null,
                        helperStyle: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFE8EAF0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _guardandoProximoFactura
                        ? null
                        : _guardarProximoFactura,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F1B3D),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardandoProximoFactura
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Guardar',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tarjetaTecladoCompacto() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Teclado en pantalla', Icons.keyboard_alt_outlined),
          const SizedBox(height: 6),
          Text(
            'Solo afecta a tablet (no a celular ni a PC/escritorio).',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          _filaSwitchFactura(
            titulo: 'Usar teclado compacto en tablet',
            descripcion:
                'En vez de abrir el teclado nativo del sistema (que en tablet ocupa media pantalla), los campos de texto abren un teclado propio, más chico, con letras y números juntos -pensado para tocar seguido sin que la pantalla se achique tanto.',
            valor: widget.modelo.tecladoCompactoTablet,
            onChanged: (v) => ref
                .read(negocioRepositoryProvider)
                .establecerTecladoCompactoTablet(v),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaFaceId() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaceIdIcon(size: 19, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              Text(
                'Face ID en este celular',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Activá Face ID en este celular para entrar a esta cuenta sin escribir código y contraseña cada vez. Es por celular y por cuenta: si otra persona usa este mismo teléfono, tiene que activar el suyo por separado.',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          if (_cargandoFaceId)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_credencialFaceId != null)
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Face ID activo en este celular',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _olvidarFaceId,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    side: const BorderSide(color: Color(0xFFF3B9B9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Olvidar',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: _procesandoFaceId ? null : _activarFaceId,
              icon: const FaceIdIcon(size: 18, color: Colors.white),
              label: Text(
                'Activar Face ID',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F1B3D),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
              Text(
                titulo,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                descripcion,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Switch(
          value: valor,
          activeThumbColor: const Color(0xFF16A34A),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _filaPermiso(
    String key,
    String titulo,
    String descripcion,
    bool tieneClave,
  ) {
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
                Text(
                  titulo,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                  ),
                ),
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
