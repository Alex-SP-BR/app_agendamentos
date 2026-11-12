import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/financial_summary.dart';

class ReportRepository {
  ReportRepository({required this.client, required this.demoMode});

  final SupabaseClient? client;
  final bool demoMode;

  Future<FinancialSummary> load(
    String professionalId,
    DateTime reportMonth,
  ) async {
    final monthStart = DateTime(reportMonth.year, reportMonth.month);
    final monthEnd = DateTime(reportMonth.year, reportMonth.month + 1);
    if (demoMode) {
      return FinancialSummary(
        reportMonth: monthStart,
        monthTotal: 2140,
        appointments: const [
          {'servico': 'Corte clássico', 'valor': 45, 'status': 'concluido'},
          {'servico': 'Corte + barba', 'valor': 65, 'status': 'concluido'},
        ],
        teamMemberEarnings: const [
          TeamMemberEarning(name: 'Tati', amount: 65),
          TeamMemberEarning(name: 'Edna', amount: 0),
          TeamMemberEarning(name: 'Daiane', amount: 0),
          TeamMemberEarning(name: 'Camila', amount: 0),
        ],
      );
    }
    final memberRows = await client!
        .from('profissionais_equipe')
        .select('id, nome')
        .eq('profissional_id', professionalId)
        .order('nome');
    final memberNames = <String, String>{
      for (final row in memberRows) row['id'] as String: row['nome'] as String,
    };
    final memberTotals = <String, double>{
      for (final memberId in memberNames.keys) memberId: 0,
    };
    final rows = await client!
        .from('agendamentos')
        .select(
          'valor, status, data_hora_inicio, team_member_id, servicos(titulo)',
        )
        .eq('profissional_id', professionalId)
        .eq('status', 'concluido')
        .gte('data_hora_inicio', monthStart.toUtc().toIso8601String())
        .lt(
          'data_hora_inicio',
          monthEnd.toUtc().toIso8601String(),
        )
        .order('data_hora_inicio');
    var monthTotal = 0.0;
    final reportRows = <Map<String, Object>>[];
    for (final row in rows) {
      final value = (row['valor'] as num).toDouble();
      monthTotal += value;
      final service = row['servicos'] as Map<String, dynamic>?;
      final teamMemberId = row['team_member_id'] as String?;
      if (teamMemberId != null && memberTotals.containsKey(teamMemberId)) {
        memberTotals[teamMemberId] = memberTotals[teamMemberId]! + value;
      }
      reportRows.add({
        'servico': service?['titulo'] as String? ?? 'Serviço',
        'profissional':
            memberNames[teamMemberId] ?? 'Profissional não identificado',
        'valor': value,
        'status': row['status'] as String,
      });
    }
    return FinancialSummary(
      reportMonth: monthStart,
      monthTotal: monthTotal,
      appointments: reportRows,
      teamMemberEarnings: memberNames.entries
          .map(
            (member) => TeamMemberEarning(
              name: member.value,
              amount: memberTotals[member.key]!,
            ),
          )
          .toList(),
    );
  }
}
