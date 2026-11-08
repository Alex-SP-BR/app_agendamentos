class TeamMemberAgendaItem {
  const TeamMemberAgendaItem({
    required this.appointmentId,
    required this.startsAt,
    required this.clientName,
    required this.serviceTitle,
    required this.value,
    required this.status,
  });

  final String appointmentId;
  final DateTime startsAt;
  final String clientName;
  final String serviceTitle;
  final double value;
  final String status;

  static List<TeamMemberAgendaItem> listFromRpcResponse(Object? response) {
    if (response == null) return [];

    final rows = switch (response) {
      List<dynamic> values => values,
      Map<dynamic, dynamic> value => [value],
      _ => throw const FormatException(
        'Formato inesperado na resposta da agenda da equipe.',
      ),
    };

    return rows.map((row) {
      if (row is! Map) {
        throw const FormatException(
          'Registro inválido na resposta da agenda da equipe.',
        );
      }
      if (row.keys.any((key) => key is! String)) {
        throw const FormatException(
          'Chave inválida na resposta da agenda da equipe.',
        );
      }
      return TeamMemberAgendaItem.fromMap(Map<String, dynamic>.from(row));
    }).toList();
  }

  factory TeamMemberAgendaItem.fromMap(Map<String, dynamic> map) {
    final rawValue = map['appointment_value'];
    final parsedValue = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '');
    if (parsedValue == null || !parsedValue.isFinite) {
      throw const FormatException('Valor inválido na agenda da equipe.');
    }
    final appointmentId = _requiredString(map, 'appointment_id');
    final startsAtValue = map['appointment_starts_at'];
    if (startsAtValue is! String) {
      throw const FormatException(
        'Data inválida na resposta da agenda da equipe.',
      );
    }
    final clientName = _requiredString(map, 'client_name');
    final serviceTitle = _requiredString(map, 'service_title');
    final status = _requiredString(map, 'appointment_status');
    return TeamMemberAgendaItem(
      appointmentId: appointmentId,
      startsAt: DateTime.parse(startsAtValue).toLocal(),
      clientName: clientName,
      serviceTitle: serviceTitle,
      value: parsedValue,
      status: status,
    );
  }
}

String _requiredString(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Campo obrigatório "$field" ausente ou inválido na agenda da equipe.',
    );
  }
  return value;
}
