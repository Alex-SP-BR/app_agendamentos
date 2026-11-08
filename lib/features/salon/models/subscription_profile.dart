class SubscriptionProfile {
  const SubscriptionProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.accessStatus,
    required this.plan,
  });

  final String id;
  final String name;
  final String email;
  final String accessStatus;
  final String plan;

  factory SubscriptionProfile.fromMap(Map<String, dynamic> map) {
    return SubscriptionProfile(
      id: map['id'] as String,
      name: map['nome'] as String,
      email: map['email'] as String,
      accessStatus: map['status_acesso'] as String,
      plan: map['plano_assinatura'] as String,
    );
  }
}
