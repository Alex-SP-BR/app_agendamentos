class TeamMemberAccessSession {
  const TeamMemberAccessSession({
    required this.accessToken,
    required this.teamMemberId,
    required this.teamMemberName,
    required this.professionalId,
  });

  final String accessToken;
  final String teamMemberId;
  final String teamMemberName;
  final String professionalId;

  factory TeamMemberAccessSession.fromMap(Map<String, dynamic> map) {
    return TeamMemberAccessSession(
      accessToken: _requiredString(map, 'access_token'),
      teamMemberId: _requiredString(map, 'team_member_id'),
      teamMemberName: _requiredString(map, 'team_member_name'),
      professionalId: _requiredString(map, 'professional_id'),
    );
  }
}

String _requiredString(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Campo obrigatório "$field" ausente na resposta de autenticação PIN.',
    );
  }
  return value;
}
