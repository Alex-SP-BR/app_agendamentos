class FinancialSummary {
  const FinancialSummary({
    required this.reportMonth,
    required this.monthTotal,
    required this.appointments,
    required this.teamMemberEarnings,
  });

  final DateTime reportMonth;
  final double monthTotal;
  final List<Map<String, Object>> appointments;
  final List<TeamMemberEarning> teamMemberEarnings;
}

class TeamMemberEarning {
  const TeamMemberEarning({required this.name, required this.amount});

  final String name;
  final double amount;
}
