class ReferidorModel {
  final String id;
  final String nombreCompleto;
  final String telefono;
  final String direccion;
  final bool estado;

  ReferidorModel({
    required this.id,
    required this.nombreCompleto,
    required this.telefono,
    required this.direccion,
    required this.estado,
  });

  factory ReferidorModel.fromMap(String id, Map<String, dynamic> data) {
    return ReferidorModel(
      id: id,
      nombreCompleto: data['nombreCompleto'] ?? '',
      telefono: data['telefono'] ?? '',
      direccion: data['direccion'] ?? '',
      estado: data['estado'] ?? true,
    );
  }

  String get textoBusqueda => '$nombreCompleto $telefono $direccion';
}
