enum PaymentType {
  pix('pix_antecipado', 'PIX antecipado'),
  local('local', 'Pagar no local');

  const PaymentType(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}

class Appointment {
  const Appointment({
    required this.id,
    required this.professionalId,
    this.clientId,
    this.salonClientId,
    required this.serviceId,
    required this.serviceTitle,
    required this.startsAt,
    required this.paymentType,
    required this.value,
    required this.status,
    this.teamMemberId,
    this.clientName,
  });

  final String id;
  final String professionalId;
  final String? clientId;
  final String? salonClientId;
  final String serviceId;
  final String serviceTitle;
  final DateTime startsAt;
  final PaymentType paymentType;
  final double value;
  final String status;
  final String? teamMemberId;
  final String? clientName;

  factory Appointment.fromMap(Map<String, dynamic> map) {
    final service = map['servicos'] as Map<String, dynamic>?;
    final client = map['cliente'] as Map<String, dynamic>?;
    final salonClient = map['cliente_salao'] as Map<String, dynamic>?;
    final rawValue = map['valor'];
    final value = rawValue is num
        ? rawValue
        : num.tryParse(rawValue?.toString() ?? '');
    if (value == null || !value.isFinite) {
      throw const FormatException('Valor numérico inválido para valor.');
    }
    return Appointment(
      id: map['id'] as String,
      professionalId: map['profissional_id'] as String,
      clientId: map['cliente_id'] as String?,
      salonClientId: map['cliente_salao_id'] as String?,
      serviceId: map['servico_id'] as String,
      serviceTitle: service?['titulo'] as String? ?? 'Serviço',
      startsAt: DateTime.parse(map['data_hora_inicio'] as String).toLocal(),
      paymentType: _parsePaymentType(map['tipo_pagamento']),
      value: value.toDouble(),
      status: map['status'] as String,
      teamMemberId: map['team_member_id'] as String?,
      clientName:
          (client?['nome'] as String?) ?? (salonClient?['nome'] as String?),
    );
  }

  factory Appointment.fromTeamAgendaMap(Map<String, dynamic> map) {
    final rawValue = map['appointment_value'];
    final value = rawValue is num
        ? rawValue
        : num.tryParse(rawValue?.toString() ?? '');
    final rawStartsAt = map['appointment_starts_at'];
    if (value == null || !value.isFinite) {
      throw const FormatException(
        'Valor numérico inválido para agenda do profissional.',
      );
    }
    if (rawStartsAt is! String || rawStartsAt.isEmpty) {
      throw const FormatException(
        'Data inválida para agenda do profissional.',
      );
    }
    return Appointment(
      id: _requiredString(map, 'appointment_id'),
      professionalId: _requiredString(map, 'professional_id'),
      clientId: map['client_id'] as String?,
      salonClientId: map['salon_client_id'] as String?,
      serviceId: _requiredString(map, 'service_id'),
      serviceTitle: _requiredString(map, 'service_title'),
      startsAt: DateTime.parse(rawStartsAt).toLocal(),
      paymentType: _parsePaymentType(map['payment_type']),
      value: value.toDouble(),
      status: _requiredString(map, 'appointment_status'),
      teamMemberId: map['team_member_id'] as String?,
      clientName: _requiredString(map, 'client_name'),
    );
  }
}

PaymentType _parsePaymentType(Object? value) {
  return PaymentType.values.firstWhere(
    (type) => type.databaseValue == value,
    orElse: () => throw FormatException(
      'Tipo de pagamento inválido: $value.',
    ),
  );
}

String _requiredString(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Campo obrigatório "$field" ausente na agenda do profissional.',
    );
  }
  return value;
}
