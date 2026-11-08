class SalonService {
  const SalonService({
    required this.id,
    required this.professionalId,
    required this.title,
    required this.category,
    required this.price,
    required this.durationMinutes,
  });

  final String id;
  final String professionalId;
  final String title;
  final String category;
  final double price;
  final int durationMinutes;

  factory SalonService.fromMap(Map<String, dynamic> map) {
    final price = _parseNumber(map['preco'], 'preco');
    final duration = _parseNumber(map['duracao_minutos'], 'duracao_minutos');
    if (!duration.isFinite || duration % 1 != 0) {
      throw const FormatException('A duração do serviço deve ser um inteiro.');
    }
    return SalonService(
      id: map['id'] as String,
      professionalId: map['profissional_id'] as String,
      title: map['titulo'] as String,
      category: map['categoria'] as String,
      price: price.toDouble(),
      durationMinutes: duration.toInt(),
    );
  }
}

num _parseNumber(Object? value, String field) {
  final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('Valor numérico inválido para $field.');
  }
  return parsed;
}
