import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_selector_button.dart';
import '../../../core/config/app_config.dart';
import '../../appointments/models/appointment.dart';
import '../../appointments/presentation/appointment_card.dart';
import '../../salon/data/salon_repository.dart';
import '../../salon/data/subscription_admin_repository.dart';
import '../../salon/models/subscription_profile.dart';
import '../../salon/presentation/clients_management_page.dart';
import '../../salon/presentation/manual_appointment_page.dart';
import '../../salon/presentation/professional_settings_page.dart';
import '../../salon/presentation/team_member_form_page.dart';
import '../../salon/presentation/services_management_page.dart';
import '../../salon/models/team_member.dart';
import '../data/report_repository.dart';
import '../models/financial_summary.dart';
import '../services/pdf_report_service.dart';

class ProfessionalDashboardPage extends StatefulWidget {
  const ProfessionalDashboardPage({
    required this.professionalId,
    required this.demoMode,
    required this.salonRepository,
    required this.reportRepository,
    required this.themeController,
    this.professionalName,
    this.isPlatformAdmin = false,
    this.publicAppBaseUrl,
    super.key,
  });

  final String professionalId;
  final String? professionalName;
  final bool demoMode;
  final SalonRepository salonRepository;
  final ReportRepository reportRepository;
  final ThemeController themeController;
  final bool isPlatformAdmin;
  final String? publicAppBaseUrl;

  @override
  State<ProfessionalDashboardPage> createState() =>
      _ProfessionalDashboardPageState();
}

class _ProfessionalDashboardPageState extends State<ProfessionalDashboardPage> {
  final _pdfService = PdfReportService();
  final _teamCardsScrollController = ScrollController();
  late Future<List<Appointment>> _appointmentsFuture;
  late Future<List<TeamMember>> _teamMembersFuture;
  late Future<FinancialSummary> _summaryFuture;
  late Future<List<SubscriptionProfile>> _subscriptionProfilesFuture;
  DateTime _selectedDay = DateTime.now();

  @override
  void dispose() {
    _teamCardsScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<List<SubscriptionProfile>> _loadSubscriptionProfiles() {
    return SubscriptionAdminRepository(client: Supabase.instance.client)
        .listProfessionalProfiles();
  }

  void _refresh() {
    if (widget.isPlatformAdmin) {
      _subscriptionProfilesFuture = _loadSubscriptionProfiles();
      return;
    }
    _loadAppointments();
    _teamMembersFuture = widget.salonRepository.listTeamMembers(
      widget.professionalId,
    );
    _summaryFuture = widget.reportRepository.load(
      widget.professionalId,
      DateTime.now(),
    );
  }

  Future<void> _setSubscriptionStatus(
    SubscriptionProfile profile,
    String status,
  ) async {
    try {
      await SubscriptionAdminRepository(client: Supabase.instance.client)
          .setAccessStatus(profileId: profile.id, status: status);
      if (!mounted) return;
      setState(() {
        _subscriptionProfilesFuture = _loadSubscriptionProfiles();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status de ${profile.name} atualizado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o status: $error')),
      );
    }
  }

  Widget _subscriptionProfilesSection() {
    return FutureBuilder<List<SubscriptionProfile>>(
      future: _subscriptionProfilesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(error: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contas profissionais',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (snapshot.data!.isEmpty)
              const Card(
                child: ListTile(title: Text('Nenhuma conta profissional.')),
              ),
            for (final profile in snapshot.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(profile.email),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(label: Text(profile.accessStatus)),
                          Text('Plano: ${profile.plan}'),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (profile.accessStatus != 'ativo')
                            TextButton.icon(
                              onPressed: () =>
                                  _setSubscriptionStatus(profile, 'ativo'),
                              icon: const Icon(Icons.payment),
                              label: const Text('Aprovar Pix'),
                            ),
                          if (profile.accessStatus != 'cortesia')
                            TextButton.icon(
                              onPressed: () =>
                                  _setSubscriptionStatus(profile, 'cortesia'),
                              icon: const Icon(Icons.card_giftcard_outlined),
                              label: const Text('Tornar Cortesia'),
                            ),
                          if (profile.accessStatus != 'recusado')
                            TextButton.icon(
                              onPressed: () =>
                                  _setSubscriptionStatus(profile, 'recusado'),
                              icon: const Icon(Icons.close_outlined),
                              label: const Text('Recusar'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _loadAppointments() {
    _appointmentsFuture = widget.salonRepository.listAppointments(
      widget.professionalId,
      _selectedDay,
    );
  }

  Future<void> _selectDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedDay = selected;
      _loadAppointments();
    });
  }

  Future<void> _addTeamMember() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TeamMemberFormPage(
          professionalId: widget.professionalId,
          repository: widget.salonRepository,
        ),
      ),
    );
    if (!mounted) return;
    if (added == true) {
      setState(_refresh);
    }
  }

  Future<void> _createManualAppointment({
    String? teamMemberId,
    String? teamMemberName,
  }) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManualAppointmentPage(
          professionalId: widget.professionalId,
          repository: widget.salonRepository,
          initialTeamMemberId: teamMemberId,
          initialTeamMemberName: teamMemberName,
          onAppointmentCreated: (startsAt) {
            setState(() {
              _selectedDay = DateTime(
                startsAt.year,
                startsAt.month,
                startsAt.day,
              );
            });
          },
        ),
      ),
    );
    if (!mounted) return;
    if (created == true) setState(_refresh);
  }

  Future<void> _export(FinancialSummary summary) async {
    try {
      await _pdfService.export(summary);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gerar o PDF: $error')),
        );
      }
    }
  }

  Future<void> _updateAppointmentStatus(
    Appointment appointment,
    String status,
  ) async {
    try {
      await widget.salonRepository.updateAppointmentStatus(
        appointment.id,
        status,
      );
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível atualizar o atendimento: $error'),
          ),
        );
      }
    }
  }

  Future<void> _showTeamMemberAccessLink(TeamMember member) async {
    final String link;
    try {
      link = AppConfig.publicAppUrl(
        '/equipe/${Uri.encodeComponent(member.id)}',
        baseUrl: widget.publicAppBaseUrl,
      ).toString();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o link: $error')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Acesso de ${member.name}'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: InkWell(
            onTap: () => _openTeamMemberAccessLink(link),
            child: SelectableText(
              link,
              maxLines: 1,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          TextButton.icon(
            onPressed: () => _openTeamMemberAccessLink(link),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir no navegador'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (!mounted || !context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Link individual copiado.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar link'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTeamMemberAccessLink(String link) async {
    try {
      final opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o link: $error')),
      );
    }
  }

  Future<void> _setTeamMemberPin(TeamMember member) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _SetTeamMemberPinDialog(memberName: member.name),
    );
    if (pin == null || !mounted) return;
    try {
      await widget.salonRepository.setTeamMemberPin(
        teamMemberId: member.id,
        pin: pin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PIN de ${member.name} atualizado. Compartilhe o link individual.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar o PIN: $error')),
      );
    }
  }

  Future<void> _removeTeamMemberPin(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover PIN de acesso?'),
        content: Text(
          'O link de ${member.name} deixará de permitir acesso até que um novo PIN seja definido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover PIN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.salonRepository.setTeamMemberPin(
        teamMemberId: member.id,
        pin: null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PIN de ${member.name} removido.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível remover o PIN: $error')),
      );
    }
  }

  Future<void> _deleteTeamMember(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir ${member.name}?'),
        content: const Text(
          'A exclusão só será permitida se não houver agendamentos vinculados. '
          'Se existirem atendimentos, reatribua-os antes de tentar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir profissional'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.salonRepository.deleteTeamMember(
        professionalId: widget.professionalId,
        teamMember: member,
      );
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível excluir o profissional: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPlatformAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Conta Master'),
          actions: [
            if (!widget.demoMode)
              IconButton(
                tooltip: 'Sair',
                onPressed: () => Supabase.instance.client.auth.signOut(),
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => setState(_refresh),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                'Gestão de licenças e planos',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Consulte o plano e o status de acesso das contas profissionais '
                'e gerencie a aprovação da licença.',
              ),
              const SizedBox(height: 24),
              _subscriptionProfilesSection(),
            ],
          ),
        ),
      );
    }

    final date = DateFormat('EEEE, d MMMM', 'pt_BR').format(_selectedDay);
    final name = widget.professionalName?.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda Pro'),
        actions: [
          ThemeSelectorButton(controller: widget.themeController),
          if (!widget.demoMode)
            IconButton(
              tooltip: 'Sair',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_refresh),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (widget.demoMode) ...[
              const _DemoNotice(),
              const SizedBox(height: 20),
            ],
            Text(
              name == null || name.isEmpty
                  ? 'Olá, seja bem-vindo(a) 👋'
                  : 'Olá, $name 👋',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text('Aqui está o resumo do seu espaço.'),
            const SizedBox(height: 24),
            FutureBuilder<FinancialSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _LoadError(error: snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final summary = snapshot.data!;
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            title: 'Esta semana',
                            amount: summary.weekTotal,
                            icon: Icons.trending_up,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            title: 'Este mês',
                            amount: summary.monthTotal,
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _export(summary),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Exportar relatório em PDF'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ServicesManagementPage(
                          professionalId: widget.professionalId,
                          demoMode: widget.demoMode,
                          repository: widget.salonRepository,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.content_cut),
                    label: const Text('Serviços'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProfessionalSettingsPage(
                          professionalId: widget.professionalId,
                          demoMode: widget.demoMode,
                          repository: widget.salonRepository,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Expediente'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ClientsManagementPage(
                      professionalId: widget.professionalId,
                      repository: widget.salonRepository,
                    ),
                  ),
                ),
                icon: const Icon(Icons.people_outline),
                label: const Text('Clientes'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Agenda do salão',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _selectDay,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(date),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: widget.demoMode ? null : _addTeamMember,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Adicionar profissional'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _createManualAppointment,
                icon: const Icon(Icons.add),
                label: const Text('+ Novo Agendamento'),
              ),
            ),
            const SizedBox(height: 12),
            _agendaSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _agendaSection() {
    return FutureBuilder<List<TeamMember>>(
      future: _teamMembersFuture,
      builder: (context, membersSnapshot) {
        if (membersSnapshot.hasError) {
          return _LoadError(error: membersSnapshot.error.toString());
        }
        if (!membersSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return FutureBuilder<List<Appointment>>(
          future: _appointmentsFuture,
          builder: (context, appointmentsSnapshot) {
            if (appointmentsSnapshot.hasError) {
              return _LoadError(error: appointmentsSnapshot.error.toString());
            }
            if (!appointmentsSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final members = membersSnapshot.data!;
            final appointments = appointmentsSnapshot.data!;
            if (members.isEmpty) {
              return const _NoTeamMembers();
            }
            return SizedBox(
              height: 390,
              child: ScrollConfiguration(
                behavior: const _TeamCardsScrollBehavior(),
                child: Scrollbar(
                  controller: _teamCardsScrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _teamCardsScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(
                      left: 4,
                      right: 16,
                      bottom: 18,
                    ),
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final memberAppointments = appointments
                          .where(
                            (appointment) =>
                                appointment.teamMemberId == member.id,
                          )
                          .toList();
                      return SizedBox(
                        width: 270,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Tooltip(
                                        message: member.name,
                                        child: Text(
                                          member.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 40,
                                            height: 40,
                                          ),
                                      tooltip:
                                          'Novo agendamento para ${member.name}',
                                      onPressed: member.isActive
                                          ? () => _createManualAppointment(
                                              teamMemberId: member.id,
                                              teamMemberName: member.name,
                                            )
                                          : null,
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                    PopupMenuButton<_TeamMemberAction>(
                                      tooltip: 'Ações de ${member.name}',
                                      constraints: const BoxConstraints(
                                        minWidth: 250,
                                        maxWidth: 320,
                                      ),
                                      onSelected: (action) {
                                        switch (action) {
                                          case _TeamMemberAction.showLink:
                                            _showTeamMemberAccessLink(member);
                                            break;
                                          case _TeamMemberAction.setPin:
                                            _setTeamMemberPin(member);
                                            break;
                                          case _TeamMemberAction.removePin:
                                            _removeTeamMemberPin(member);
                                            break;
                                          case _TeamMemberAction.delete:
                                            _deleteTeamMember(member);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: _TeamMemberAction.showLink,
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.link),
                                            title: Text(
                                              'Link de acesso individual',
                                            ),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: _TeamMemberAction.setPin,
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.lock_outline),
                                            title: Text(
                                              'Definir ou alterar PIN',
                                            ),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: _TeamMemberAction.removePin,
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.lock_open),
                                            title: Text('Remover PIN'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: _TeamMemberAction.delete,
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('Excluir profissional'),
                                          ),
                                        ),
                                      ],
                                      icon: const Icon(Icons.more_vert),
                                    ),
                                  ],
                                ),
                                const Divider(height: 1),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: memberAppointments.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'Nenhum atendimento neste dia.',
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: memberAppointments.length,
                                          padding: EdgeInsets.zero,
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 2),
                                          itemBuilder:
                                              (
                                                context,
                                                appointmentIndex,
                                              ) => _appointmentTile(
                                                memberAppointments[appointmentIndex],
                                              ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _appointmentTile(Appointment appointment) {
    return AppointmentCard(
      startsAt: appointment.startsAt,
      clientName: appointment.clientName ?? '',
      serviceTitle: appointment.serviceTitle,
      value: appointment.value,
      status: appointment.status,
      paymentLabel: '${appointment.paymentType.label} · ${appointment.status}',
      actionTooltip: 'Atualizar atendimento',
      onStatusSelected: (status) =>
          _updateAppointmentStatus(appointment, status),
    );
  }
}

enum _TeamMemberAction { showLink, setPin, removePin, delete }

class _SetTeamMemberPinDialog extends StatefulWidget {
  const _SetTeamMemberPinDialog({required this.memberName});

  final String memberName;

  @override
  State<_SetTeamMemberPinDialog> createState() =>
      _SetTeamMemberPinDialogState();
}

class _SetTeamMemberPinDialogState extends State<_SetTeamMemberPinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? pin]) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('PIN de ${widget.memberName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 12,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Novo PIN',
          helperText: 'Informe de 6 a 12 dígitos.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text('Cancelar')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: RegExp(r'^\d{6,12}$').hasMatch(value.text)
                ? () => _close(value.text)
                : null,
            child: const Text('Salvar PIN'),
          ),
        ),
      ],
    );
  }
}

class _TeamCardsScrollBehavior extends MaterialScrollBehavior {
  const _TeamCardsScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class _NoTeamMembers extends StatelessWidget {
  const _NoTeamMembers();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(22),
      child: Text(
        'Nenhum profissional cadastrado. Cadastre a equipe para visualizar a agenda.',
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.amount,
    required this.icon,
  });

  final String title;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title),
            const SizedBox(height: 4),
            Text(
              currency.format(amount),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Modo demonstração: os dados são de exemplo e não são sincronizados. '
        'Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY para usar sua conta.',
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Erro ao carregar dados: $error'),
    ),
  );
}
