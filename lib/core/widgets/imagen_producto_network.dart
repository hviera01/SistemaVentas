import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Reemplazo de Image.network para fotos de producto. Image.network no
/// tiene un límite de tiempo propio: si la conexión se traba a mitad de
/// camino (visto en Windows — las fotos dejaban de cargar sin mostrar ni
/// error ni "cargando", y quedaban así hasta reiniciar la app entera, que es
/// lo único que limpia el caché de imágenes de Flutter donde había quedado
/// pegado el intento fallido), el pedido se queda esperando para siempre y
/// no hay forma de reintentar sin salir de la pantalla. Acá se baja la foto
/// a mano con un timeout explícito y, si falla, queda un botón para
/// reintentar en el momento.
class ImagenProductoNetwork extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  // Colores del estado de carga/error: por defecto pensados para fondos
  // claros (formularios, miniaturas), pero el zoom a pantalla completa vive
  // sobre un fondo oscuro y necesita los suyos propios.
  final Color loadingColor;
  final Color iconColor;
  final Color textColor;
  final double iconSize;
  final double textSize;

  const ImagenProductoNetwork({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.loadingColor = const Color(0xFFC62828),
    this.iconColor = const Color(0xFF9CA3AF),
    this.textColor = const Color(0xFF9CA3AF),
    this.iconSize = 20,
    this.textSize = 9,
  });

  @override
  State<ImagenProductoNetwork> createState() => _ImagenProductoNetworkState();
}

class _ImagenProductoNetworkState extends State<ImagenProductoNetwork> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  @override
  void didUpdateWidget(covariant ImagenProductoNetwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _reintentar();
  }

  Future<Uint8List> _cargar() {
    return http.get(Uri.parse(widget.url)).timeout(const Duration(seconds: 15)).then((res) {
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return res.bodyBytes;
    });
  }

  void _reintentar() => setState(() => _future = _cargar());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.loadingColor))),
          );
        }
        if (snapshot.hasError) {
          return InkWell(
            onTap: _reintentar,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, color: widget.iconColor, size: widget.iconSize),
                  const SizedBox(height: 2),
                  Text('Reintentar', style: TextStyle(fontSize: widget.textSize, color: widget.textColor)),
                ],
              ),
            ),
          );
        }
        return Image.memory(snapshot.data!, width: widget.width, height: widget.height, fit: widget.fit);
      },
    );
  }
}
