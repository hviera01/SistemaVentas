import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/escaneo_remoto_repository.dart';

/// URL fija del sitio publicado en GitHub Pages: el QR siempre tiene que
/// apuntar ahí (la página que sabe leer el parámetro `?escanear=` y mostrar
/// el escáner sin pedir inicio de sesión), sin importar si quien abre este
/// diálogo está usando la versión web o el .exe de escritorio.
const _urlSitioWeb = 'https://hviera01.github.io/SistemaVentas/';

/// Diálogo que se queda abierto mientras el celular escanea: muestra un QR
/// para emparejar y, apenas el celular manda un código, lo entrega vía
/// [alRecibirCodigo] sin cerrarse, para poder escanear varios productos
/// seguidos.
class EscanearRemotoDialog extends StatefulWidget {
  final void Function(String codigoEscaneado) alRecibirCodigo;

  const EscanearRemotoDialog({super.key, required this.alRecibirCodigo});

  @override
  State<EscanearRemotoDialog> createState() => _EscanearRemotoDialogState();
}

class _EscanearRemotoDialogState extends State<EscanearRemotoDialog> {
  final _repo = EscaneoRemotoRepository();
  late final String _codigo;
  Stream<dynamic>? _eventos;
  int _totalRecibidos = 0;

  @override
  void initState() {
    super.initState();
    _codigo = _repo.generarCodigo();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _repo.crearSesion(_codigo);
    if (!mounted) return;
    setState(() {
      _eventos = _repo.escucharEventos(_codigo);
    });
  }

  @override
  void dispose() {
    // Best-effort: no hace falta esperar a que termine para cerrar el
    // diálogo, y si falla (sin internet en ese instante) no importa, es solo
    // limpieza de una sesión de todas formas efímera.
    _repo.eliminarSesion(_codigo);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = '$_urlSitioWeb?escanear=$_codigo';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('Escanear con el celular', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Apuntá la cámara del celular a este código QR (no hace falta ninguna app, se abre directo en el navegador).',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: url, size: 200, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 14),
            Text('Código: $_codigo', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            const SizedBox(height: 18),
            StreamBuilder(
              stream: _eventos,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final docs = (snapshot.data as dynamic).docs as List;
                  if (docs.length > _totalRecibidos) {
                    final nuevos = docs.sublist(_totalRecibidos);
                    _totalRecibidos = docs.length;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      for (final doc in nuevos) {
                        final codigo = (doc.data() as Map)['codigo'] as String?;
                        if (codigo != null && codigo.isNotEmpty) widget.alRecibirCodigo(codigo);
                      }
                    });
                  }
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_tethering, size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text('$_totalRecibidos código(s) recibido(s)', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
