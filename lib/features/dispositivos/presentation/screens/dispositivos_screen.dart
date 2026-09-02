import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/dispositivo_model.dart';
import '../../providers/dispositivos_provider.dart';
import '../../../../core/services/actualizacion_service.dart';
import '../../../negocio/providers/negocio_provider.dart';

class DispositivosScreen extends ConsumerStatefulWidget {
  const DispositivosScreen({super.key});

  @override
  ConsumerState<DispositivosScreen> createState() => _DispositivosScreenState();
}

class _DispositivosScreenState extends ConsumerState<DispositivosScreen> {
  int? _ultimaVersionPublicada;

  @override
  void initState() {
    super.initState();
    ActualizacionService.obtenerUltimaVersionPublicada().then((v) {
      if (mounted) setState(() => _ultimaVersionPublicada = v);
    });
  }

  Future<void> _alternarPcPrincipal(String hostname, bool marcada) async {
    await ref
        .read(negocioRepositoryProvider)
        .establecerPcPrincipalHostname(marcada ? '' : hostname);
  }

  @override
  Widget build(BuildContext context) {
    final dispositivosAsync = ref.watch(dispositivosStreamProvider);
    final negocioAsync = ref.watch(negocioStreamProvider);
    final pcPrincipalHostname = negocioAsync.value?.pcPrincipalHostname ?? '';
    final formatoFecha = DateFormat('dd/MM/yyyy hh:mm a');

    return Container(
      color: const Color(0xFFF2F3F7),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Text(
                  'Dispositivos',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                if (_ultimaVersionPublicada != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Última versión publicada: v$_ultimaVersionPublicada',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Cada equipo actualiza este registro solo al iniciar sesión: si alguien no ha abierto la app en un tiempo, su fila va a quedar vieja.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Marcá con la estrella la PC que tiene la impresora conectada de verdad. Sin ninguna marcada (como hasta ahora), cualquier PC/laptop con la app abierta se comporta como si lo fuera -si tenés más de un equipo de escritorio, marcá el correcto para que los demás, al no poder imprimir local, le pidan a este que imprima en su lugar en vez de intentar imprimir ellos mismos-.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
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
                child: dispositivosAsync.when(
                  data: (dispositivos) {
                    if (dispositivos.isEmpty) {
                      return Center(
                        child: Text(
                          'Todavía no hay dispositivos registrados',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      );
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final esMovil = constraints.maxWidth < 700;
                        return esMovil
                            ? _tarjetas(dispositivos, pcPrincipalHostname)
                            : _tabla(
                                dispositivos,
                                pcPrincipalHostname,
                                formatoFecha,
                              );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0F1B3D)),
                  ),
                  error: (e, st) => Center(
                    child: Text(
                      'Error: $e',
                      style: GoogleFonts.poppins(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipVersion(DispositivoModel d) {
    final desactualizado =
        _ultimaVersionPublicada != null &&
        d.versionApp < _ultimaVersionPublicada!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: desactualizado
            ? const Color(0xFFFCE4E4)
            : const Color(0xFFE8F8EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v${d.versionApp}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: desactualizado
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF16A34A),
            ),
          ),
          if (desactualizado) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.warning_amber_rounded,
              size: 13,
              color: Color(0xFFB91C1C),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonEstrella(DispositivoModel d, bool esPrincipal) {
    return IconButton(
      tooltip: esPrincipal
          ? 'Es la PC principal (tocá para quitarla)'
          : 'Marcar como PC principal',
      onPressed: () => _alternarPcPrincipal(d.id, esPrincipal),
      icon: Icon(
        esPrincipal ? Icons.star : Icons.star_border,
        color: esPrincipal ? const Color(0xFFE0A63C) : Colors.grey.shade400,
        size: 22,
      ),
    );
  }

  // Vista de escritorio (tabla de columnas fijas): sin cambios de fondo,
  // solo separada de build() para poder elegir entre esta y _tarjetas según
  // el ancho disponible (ver LayoutBuilder en build()).
  Widget _tabla(
    List<DispositivoModel> dispositivos,
    String pcPrincipalHostname,
    DateFormat formatoFecha,
  ) {
    return ListView.builder(
      itemCount: dispositivos.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFECEEF3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _celdaHeader('DISPOSITIVO', 3),
                _celdaHeader('PLATAFORMA', 2),
                _celdaHeader('VERSIÓN', 2),
                _celdaHeader('ÚLTIMO USUARIO', 2),
                _celdaHeader('ÚLTIMA CONEXIÓN', 3),
                // Ancho fijo, sin Expanded -a diferencia de _celdaHeader,
                // que solo sirve como hijo directo de un Row/Column-: antes
                // esto envolvía un _celdaHeader (que YA es un Expanded)
                // dentro de un SizedBox, un árbol de widgets inválido que
                // tiraba la pantalla entera con un error de layout (bug
                // real reportado por el dueño, se veía sobre todo en
                // celular).
                SizedBox(
                  width: 48,
                  child: Text(
                    'PPAL',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF666A72),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final d = dispositivos[index - 1];
        final esPrincipal =
            pcPrincipalHostname.isNotEmpty && pcPrincipalHostname == d.id;
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _celda(3, d.id, peso: FontWeight.w600),
              _celda(2, d.plataforma),
              Expanded(flex: 2, child: _chipVersion(d)),
              _celda(2, d.usuario.isEmpty ? '-' : d.usuario),
              _celda(
                3,
                d.ultimaConexion != null
                    ? formatoFecha.format(d.ultimaConexion!)
                    : '-',
                gris: true,
              ),
              SizedBox(width: 48, child: _botonEstrella(d, esPrincipal)),
            ],
          ),
        );
      },
    );
  }

  // Vista de celular/tablet angosta: una tarjeta por equipo con todo
  // apilado, sin truncar ningún dato -pedido explícito del dueño: "hacer
  // responsivo eso, tiene overflow"-.
  Widget _tarjetas(
    List<DispositivoModel> dispositivos,
    String pcPrincipalHostname,
  ) {
    final formatoFecha = DateFormat('dd/MM/yyyy hh:mm a');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: dispositivos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final d = dispositivos[index];
        final esPrincipal =
            pcPrincipalHostname.isNotEmpty && pcPrincipalHostname == d.id;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: esPrincipal
                ? const Color(0xFFFFF8E8)
                : const Color(0xFFF8F9FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: esPrincipal
                  ? const Color(0xFFE0A63C)
                  : const Color(0xFFC7CBD3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      d.id,
                      style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  _botonEstrella(d, esPrincipal),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chipInfo(d.plataforma),
                  _chipVersion(d),
                  _chipInfo(d.usuario.isEmpty ? 'Sin usuario' : d.usuario),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Última conexión: ${d.ultimaConexion != null ? formatoFecha.format(d.ultimaConexion!) : '-'}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipInfo(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: const Color(0xFF3F434A),
        ),
      ),
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF666A72),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _celda(
    int flex,
    String texto, {
    bool gris = false,
    FontWeight peso = FontWeight.w400,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: peso,
            color: gris ? Colors.grey.shade600 : const Color(0xFF1A1A1A),
          ),
        ),
      ),
    );
  }
}
