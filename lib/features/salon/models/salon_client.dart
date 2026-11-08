class SalonClient {
  const SalonClient({
    required this.id,
    required this.name,
    required this.phone,
    this.salonClientId,
  });

  final String id;
  final String name;
  final String phone;
  final String? salonClientId;

  bool get isSalonContact => salonClientId != null;

  factory SalonClient.fromProfileMap(Map<String, dynamic> map) {
    return SalonClient(
      id: map['id'] as String,
      name: map['nome'] as String,
      phone: map['telefone'] as String? ?? '',
    );
  }

  factory SalonClient.fromSalonMap(Map<String, dynamic> map) {
    final id = map['id'] as String;
    return SalonClient(
      id: id,
      salonClientId: id,
      name: map['nome'] as String,
      phone: map['telefone'] as String,
    );
  }
}
