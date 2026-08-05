import 'package:flutter/material.dart';
import 'imagen_producto_network.dart';

/// Muestra una foto de producto grande, para verla de cerca — se abre desde
/// el ícono de foto en Buscar Producto y desde la miniatura en el detalle
/// de producto. Tocar afuera de la imagen o el botón de cerrar la cierra.
class ImagenZoomDialog extends StatelessWidget {
  final String url;

  const ImagenZoomDialog({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: ImagenProductoNetwork(
                    url: url,
                    fit: BoxFit.contain,
                    iconColor: Colors.white70,
                    textColor: Colors.white70,
                    iconSize: 48,
                    textSize: 13,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
