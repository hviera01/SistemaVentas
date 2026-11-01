import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PlaceholderScreen extends StatelessWidget {
  final String titulo;
  final IconData icono;

  const PlaceholderScreen({super.key, required this.titulo, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.fondo,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 64, color: AppColors.gris300),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(fontSize: 18, color: AppColors.gris500, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('Pantalla en construcción', style: TextStyle(color: AppColors.gris400)),
          ],
        ),
      ),
    );
  }
}