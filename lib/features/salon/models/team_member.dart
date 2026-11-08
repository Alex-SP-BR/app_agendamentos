class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String name;
  final bool isActive;

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      id: map['id'] as String,
      name: map['nome'] as String,
      isActive: map['ativo'] as bool? ?? true,
    );
  }
}
