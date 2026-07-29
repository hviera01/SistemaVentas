import 'package:cloud_firestore/cloud_firestore.dart';

class DispositivoModel {
  final String id;
  final String plataforma;
  final int versionApp;
  final String usuario;
  final DateTime? ultimaConexion;

  DispositivoModel({
    required this.id,
    required this.plataforma,
    required this.versionApp,
    required this.usuario,
    required this.ultimaConexion,
  });

  factory DispositivoModel.fromMap(String id, Map<String, dynamic> data) {
    return DispositivoModel(
      id: id,
      plataforma: data['plataforma'] ?? '',
      versionApp: (data['versionApp'] as num?)?.toInt() ?? 0,
      usuario: data['usuario'] ?? '',
      ultimaConexion: (data['ultimaConexion'] as Timestamp?)?.toDate(),
    );
  }
}
