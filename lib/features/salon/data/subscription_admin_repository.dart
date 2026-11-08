import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription_profile.dart';

class SubscriptionAdminRepository {
  const SubscriptionAdminRepository({required this.client});

  final SupabaseClient client;

  Future<List<SubscriptionProfile>> listProfessionalProfiles() async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw StateError('É necessário iniciar sessão como administrador.');
    }
    final rows = await client
        .from('perfis')
        .select('id, nome, email, status_acesso, plano_assinatura')
        .eq('tipo', 'profissional')
        .neq('id', currentUser.id)
        .order('nome');
    return rows.map(SubscriptionProfile.fromMap).toList();
  }

  Future<void> setAccessStatus({
    required String profileId,
    required String status,
  }) async {
    await client.rpc(
      'admin_set_access_status',
      params: {'p_profile_id': profileId, 'p_status': status},
    );
  }
}
