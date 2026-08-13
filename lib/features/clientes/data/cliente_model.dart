class ClienteModel {
  final String id;
  final String dni;
  final String nombreCompleto;
  final String direccion;
  final String telefono;
  final bool estado;

  ClienteModel({
    required this.id,
    required this.dni,
    required this.nombreCompleto,
    required this.direccion,
    required this.telefono,
    required this.estado,
  });

  factory ClienteModel.fromMap(String id, Map<String, dynamic> data) {
    return ClienteModel(
      id: id,
      dni: data['dni'] ?? '',
      nombreCompleto: data['nombreCompleto'] ?? '',
      direccion: data['direccion'] ?? '',
      telefono: data['telefono'] ?? '',
      estado: data['estado'] ?? true,
    );
  }

  String get textoBusqueda => '$dni $nombreCompleto $direccion $telefono';
}
