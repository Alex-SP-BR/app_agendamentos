import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../appointments/presentation/appointment_card.dart';
import '../data/salon_repository.dart';
import '../models/salon_client.dart';
import '../models/team_member_access_session.dart';
import '../models/team_member_agenda_item.dart';
import 'manual_appointment_page.dart';

class TeamMemberAccessPage extends StatefulWidget {
  const TeamMemberAccessPage({
    required this.teamMemberId,
    required this.repository,
    this.initialDay,
    super.key,
  });

  final String teamMemberId;
  final SalonRepository repository;
  final DateTime? initialDay;

  @override
  State<TeamMemberAccessPage> createState() => _TeamMemberAccessPageState();
}

class _TeamMemberAccessPageState extends State<TeamMemberAccessPage> {
  final _pinController = TextEditingController();
  TeamMemberAccessSession? _session;
  List<TeamMemberAgendaItem> _appointments = [];
  List<SalonClient> _clients = [];
  late DateTime _selectedDay;
  bool _loading = false;
  String? _error;
  String? _clientsError;
  int _agendaRequestId = 0;

  @override
  void initState() {
    super.initState();
    final initialDay = widget.initialDay ?? DateTime.now();
    _selectedDay = DateTime(initialDay.year, initialDay.month, initialDay.day);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadAgenda() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      setState(() {
        _error = 'Informe o PIN de 6 a 12 dígitos.';
        _session = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.repository.authenticateTeamMemberAccess(
        teamMemberId: widget.teamMemberId,
        pin: pin,
      );
      if (!mounted) return;
      setState(() => _session = session);
      await _refreshTeamData(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível acessar a agenda: $error';
      });
    }
  }

  Future<void> _refreshTeamData([TeamMemberAccessSession? session]) async {
    final currentSession = session ?? _session;
    if (currentSession == null) return;
    final requestId = ++_agendaRequestId;
    final requestedDay = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    setState(() {
      _loading = true;
      _error = null;
      _clientsError = null;
    });

    final List<TeamMemberAgendaItem> appointments;
    try {
      appointments = await widget.repository.listTeamMemberAppointments(
        currentSession.accessToken,
        day: requestedDay,
      );
    } catch (error) {
      if (!mounted || requestId != _agendaRequestId) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
      return;
    }

    if (!mounted || requestId != _agendaRequestId) return;
    setState(() {
      _appointments = appointments;
      _loading = false;
    });

    try {
      final clients = await widget.repository.listTeamMemberClients(
        currentSession.accessToken,
      );
      if (!mounted || requestId != _agendaRequestId) return;
      setState(() {
        _clients = clients;
      });
    } catch (error) {
      if (!mounted || requestId != _agendaRequestId) return;
      setState(() {
        _clientsError = error.toString();
      });
    }
  }

  Future<void> _createAppointment() async {
    final session = _session;
    if (session == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManualAppointmentPage(
          professionalId: session.professionalId,
          repository: widget.repository,
          initialTeamMemberId: session.teamMemberId,
          initialTeamMemberName: session.teamMemberName,
          teamMemberAccessToken: session.accessToken,
          onAppointmentCreated: (startsAt) {
            if (!mounted) return;
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
    if (created == true && mounted) await _refreshTeamData();
  }

  Future<void> _selectDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedDay = selected);
    await _refreshTeamData();
  }

  Future<void> _updateAppointmentStatus(
    TeamMemberAgendaItem appointment,
    String status,
  ) async {
    final session = _session;
    if (session == null) return;
    try {
      await widget.repository.updateTeamMemberAppointmentStatus(
        accessToken: session.accessToken,
        appointmentId: appointment.appointmentId,
        status: status,
      );
      if (!mounted) return;
      await _refreshTeamData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $error')),
      );
    }
  }

  Future<void> _manageClients() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Meus clientes'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: _clients.isEmpty
              ? const Center(child: Text('Nenhum cliente cadastrado.'))
              : ListView.builder(
                  itemCount: _clients.length,
                  itemBuilder: (context, index) {
                    final client = _clients[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(client.name),
                      subtitle: Text(client.phone),
                      trailing: IconButton(
                        tooltip: 'Editar ${client.name}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _editClient(client);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editClient(SalonClient client) async {
    final session = _session;
    if (session == null) return;
    final nameController = TextEditingController(text: client.name);
    final phoneController = TextEditingController(text: client.phone);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]')),
              ],
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      try {
        await widget.repository.updateTeamMemberClient(
          accessToken: session.accessToken,
          clientId: client.salonClientId!,
          name: nameController.text,
          phone: phoneController.text,
        );
        if (mounted) await _refreshTeamData();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível editar o cliente: $error'),
            ),
          );
        }
      }
    }

    nameController.dispose();
    phoneController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, d MMMM', 'pt_BR').format(_selectedDay);
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          session == null ? 'Acesso do profissional' : session.teamMemberName,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        children: [
          if (session == null)
            Text(date, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (session == null) ...[
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'PIN de acesso',
                helperText: 'Use o PIN de 6 a 12 dígitos fornecido pelo salão.',
              ),
              onSubmitted: (_) => _loadAgenda(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _loadAgenda,
              child: Text(_loading ? 'Verificando...' : 'Acessar minha agenda'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _createAppointment,
                  icon: const Icon(Icons.add),
                  label: const Text('Novo Agendamento'),
                ),
                OutlinedButton.icon(
                  onPressed: _manageClients,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Meus clientes'),
                ),
                IconButton(
                  tooltip: 'Atualizar agenda',
                  onPressed: _loading ? null : _refreshTeamData,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _selectDay,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(date),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Não foi possível carregar a agenda: $_error'),
              )
            else if (_appointments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhum atendimento agendado neste dia.'),
              )
            else
              ..._appointments.map(
                (appointment) => AppointmentCard(
                  startsAt: appointment.startsAt,
                  clientName: appointment.clientName,
                  serviceTitle: appointment.serviceTitle,
                  value: appointment.value,
                  status: appointment.status,
                  paymentLabel: appointment.status,
                  actionTooltip: 'Ações do atendimento',
                  cancelActionLabel: 'Cancelar',
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  onStatusSelected: (status) =>
                      _updateAppointmentStatus(appointment, status),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Este acesso permite gerenciar apenas os atendimentos e clientes '
              'vinculados a este profissional.',
            ),
          ],
          if (session == null && _error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_clientsError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar a lista de clientes: $_clientsError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
