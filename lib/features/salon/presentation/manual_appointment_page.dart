import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../appointments/models/appointment.dart';
import '../../appointments/models/occupied_period.dart';
import '../data/salon_repository.dart';
import '../models/salon_client.dart';
import '../models/salon_service.dart';
import '../models/team_member.dart';

class ManualAppointmentPage extends StatefulWidget {
  const ManualAppointmentPage({
    required this.professionalId,
    required this.repository,
    this.initialTeamMemberId,
    this.initialTeamMemberName,
    this.teamMemberAccessToken,
    this.onAppointmentCreated,
    super.key,
  }) : assert(
         teamMemberAccessToken == null || initialTeamMemberId != null,
         'Team-member access requires a selected team member.',
       );

  final String professionalId;
  final SalonRepository repository;
  final String? initialTeamMemberId;
  final String? initialTeamMemberName;
  final String? teamMemberAccessToken;
  final ValueChanged<DateTime>? onAppointmentCreated;

  @override
  State<ManualAppointmentPage> createState() => _ManualAppointmentPageState();
}

class _ManualAppointmentPageState extends State<ManualAppointmentPage> {
  late Future<_ManualBookingData> _dataFuture;
  final _clientController = TextEditingController();
  final _clientFocusNode = FocusNode();
  final _phoneController = TextEditingController();
  SalonService? _service;
  SalonClient? _client;
  String? _selectedTeamMemberId;
  DateTime _day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _time;
  Map<String, dynamic>? _settings;
  List<OccupiedPeriod> _occupied = [];
  bool _loadingTimes = true;
  bool _saving = false;
  String? _availabilityError;
  int _availabilityRequestId = 0;

  @override
  void initState() {
    super.initState();
    _selectedTeamMemberId = widget.initialTeamMemberId;
    _dataFuture = _loadData();
    _loadAvailability();
  }

  @override
  void dispose() {
    _clientController.dispose();
    _clientFocusNode.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<_ManualBookingData> _loadData() async {
    final settings = await widget.repository.loadSettings(
      widget.professionalId,
    );
    final accessToken = widget.teamMemberAccessToken;
    final services = accessToken == null
        ? await widget.repository.listServices(widget.professionalId)
        : await widget.repository.listTeamMemberServices(accessToken);
    final teamMembers = accessToken == null
        ? await widget.repository.listTeamMembers(widget.professionalId)
        : [
            TeamMember(
              id: widget.initialTeamMemberId!,
              name: widget.initialTeamMemberName ?? 'Minha agenda',
            ),
          ];
    final clients = accessToken == null
        ? await widget.repository.listClients(widget.professionalId)
        : await widget.repository.listTeamMemberClients(accessToken);
    final activeTeamMemberIds = teamMembers
        .where((member) => member.isActive)
        .map((member) => member.id)
        .toSet();
    if (!activeTeamMemberIds.contains(_selectedTeamMemberId)) {
      _selectedTeamMemberId = null;
    }
    if (!mounted) {
      return _ManualBookingData(
        settings: settings,
        services: services,
        teamMembers: teamMembers,
        clients: clients,
      );
    }
    setState(() => _settings = settings);
    if (_selectedTeamMemberId != null) {
      _loadAvailability();
    }
    return _ManualBookingData(
      settings: settings,
      services: services,
      teamMembers: teamMembers,
      clients: clients,
    );
  }

  Future<void> _loadAvailability() async {
    if (!mounted) return;
    final requestId = ++_availabilityRequestId;
    final teamMemberId = _selectedTeamMemberId;
    if (teamMemberId == null) {
      setState(() {
        _loadingTimes = false;
        _availabilityError = null;
        _occupied = [];
        _time = null;
      });
      return;
    }
    final requestedDay = DateTime(_day.year, _day.month, _day.day);
    setState(() {
      _loadingTimes = true;
      _availabilityError = null;
      _time = null;
    });
    try {
      final periods = await widget.repository.listOccupiedPeriods(
        widget.professionalId,
        requestedDay,
        teamMemberId: teamMemberId,
      );
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _occupied = periods;
        _loadingTimes = false;
      });
    } catch (error) {
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _availabilityError = error.toString();
        _loadingTimes = false;
      });
    }
  }

  Future<void> _selectDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (selected == null) return;
    setState(() => _day = selected);
    await _loadAvailability();
  }

  Future<void> _save() async {
    final service = _service;
    final time = _time;
    final teamMemberId = _selectedTeamMemberId;
    if (teamMemberId == null || service == null || time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha o profissional, cliente, serviço e horário.'),
        ),
      );
      return;
    }
    var client = _client;
    final phoneLength = _phoneController.text
        .replaceAll(RegExp(r'\D'), '')
        .length;
    if (client == null &&
        (_clientController.text.trim().isEmpty ||
            phoneLength < 8 ||
            phoneLength > 15)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome e um telefone válido do cliente.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final accessToken = widget.teamMemberAccessToken;
      late final SalonClient savedClient;
      if (client != null) {
        savedClient = client;
      } else if (accessToken == null) {
        savedClient = await widget.repository.saveSalonClient(
          professionalId: widget.professionalId,
          name: _clientController.text,
          phone: _phoneController.text,
        );
      } else {
        savedClient = await widget.repository.saveTeamMemberClient(
          accessToken: accessToken,
          name: _clientController.text,
          phone: _phoneController.text,
        );
      }
      final startsAt = DateTime(
        _day.year,
        _day.month,
        _day.day,
        time.hour,
        time.minute,
      );
      if (accessToken == null) {
        await widget.repository.createAppointment(
          professionalId: widget.professionalId,
          clientId: savedClient.isSalonContact ? null : savedClient.id,
          salonClientId: savedClient.salonClientId,
          service: service,
          startsAt: startsAt,
          paymentType: PaymentType.local,
          teamMemberId: teamMemberId,
        );
      } else {
        final clientId = savedClient.salonClientId;
        if (clientId == null) {
          throw StateError('Selecione um cliente cadastrado para a equipe.');
        }
        await widget.repository.createTeamMemberAppointment(
          accessToken: accessToken,
          clientId: clientId,
          service: service,
          startsAt: startsAt,
        );
      }
      widget.onAppointmentCreated?.call(startsAt);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o agendamento: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Agendamento')),
      body: FutureBuilder<_ManualBookingData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Erro ao carregar dados: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          _settings ??= data.settings;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.initialTeamMemberName != null) ...[
                Text(
                  'Agendamento para ${widget.initialTeamMemberName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
              ],
              if (widget.teamMemberAccessToken == null)
                _teamMemberSelector(data.teamMembers)
              else
                Text(
                  'Profissional: ${widget.initialTeamMemberName ?? 'Minha agenda'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 12),
              if (data.clients.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Digite o nome e telefone para cadastrar um novo cliente.',
                  ),
                ),
              _clientAutocomplete(data.clients),
              if (_client == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_BrazilianPhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Telefone do novo cliente',
                    hintText: '(11) 99999-9999',
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _client!.phone.isEmpty
                        ? 'Telefone não informado no perfil selecionado.'
                        : 'Telefone: ${_client!.phone}',
                  ),
                ),
              const SizedBox(height: 12),
              if (data.services.isEmpty)
                const InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Serviço',
                    enabled: false,
                  ),
                  child: Text(
                    'Nenhum serviço ativo cadastrado para este salão.',
                  ),
                )
              else
                DropdownButtonFormField<SalonService>(
                  initialValue: _service,
                  decoration: const InputDecoration(labelText: 'Serviço'),
                  items: data.services
                      .map(
                        (service) => DropdownMenuItem(
                          value: service,
                          child: Text(
                            '${service.title} · ${service.durationMinutes} min',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _service = value);
                    _loadAvailability();
                  },
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _selectDay,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(DateFormat('EEEE, d MMMM', 'pt_BR').format(_day)),
              ),
              const SizedBox(height: 12),
              if (_availabilityError != null)
                Text('Erro ao carregar horários: $_availabilityError'),
              if (_loadingTimes)
                const Center(child: CircularProgressIndicator())
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableTimes.map((time) {
                    final occupied = _isTimeOccupied(time);
                    return ChoiceChip(
                      label: Text(time.format(context)),
                      selected: time == _time,
                      onSelected: occupied
                          ? null
                          : (_) => setState(() => _time = time),
                    );
                  }).toList(),
                ),
              if (_selectedTeamMemberId != null &&
                  !_loadingTimes &&
                  (_availableTimes.isEmpty ||
                      _availableTimes.every(_isTimeOccupied)))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Não há horários disponíveis neste dia.'),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving || _selectedTeamMemberId == null
                    ? null
                    : _save,
                icon: const Icon(Icons.add),
                label: Text(_saving ? 'Salvando...' : 'Criar agendamento'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _teamMemberSelector(List<TeamMember> teamMembers) {
    final members = teamMembers.where((member) => member.isActive).toList();
    TeamMember? selected;
    for (final member in members) {
      if (member.id == _selectedTeamMemberId) {
        selected = member;
        break;
      }
    }
    if (members.isEmpty) {
      return const Text(
        'Cadastre um profissional da equipe antes de criar agendamentos.',
      );
    }
    return DropdownButtonFormField<TeamMember>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Profissional',
        hintText: 'Selecione um profissional',
      ),
      items: members
          .map(
            (member) =>
                DropdownMenuItem(value: member, child: Text(member.name)),
          )
          .toList(),
      onChanged: (member) {
        setState(() {
          _selectedTeamMemberId = member?.id;
          _time = null;
        });
        _loadAvailability();
      },
    );
  }

  Widget _clientAutocomplete(List<SalonClient> clients) {
    return Autocomplete<SalonClient>(
      textEditingController: _clientController,
      focusNode: _clientFocusNode,
      displayStringForOption: (client) => client.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return clients;
        return clients.where((client) {
          return client.name.toLowerCase().contains(query) ||
              client.phone.toLowerCase().contains(query);
        });
      },
      onSelected: (client) {
        setState(() {
          _client = client;
          _phoneController.text = client.phone;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Cliente',
            hintText: 'Busque por nome/telefone ou digite um novo nome',
            suffixIcon: _client == null
                ? const Icon(Icons.person_search_outlined)
                : IconButton(
                    tooltip: 'Limpar cliente selecionado',
                    onPressed: () {
                      setState(() {
                        _client = null;
                        _clientController.clear();
                        _phoneController.clear();
                      });
                      focusNode.requestFocus();
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (value) {
            if (_client != null && value.trim() != _client!.name) {
              setState(() {
                _client = null;
                _phoneController.clear();
              });
            }
          },
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final client = options.elementAt(index);
                  return ListTile(
                    title: Text(client.name),
                    subtitle: Text(
                      client.phone.isEmpty
                          ? 'Telefone não informado'
                          : client.phone,
                    ),
                    onTap: () => onSelected(client),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  List<TimeOfDay> get _availableTimes {
    final service = _service;
    final settings = _settings;
    if (service == null ||
        _selectedTeamMemberId == null ||
        _loadingTimes ||
        _availabilityError != null) {
      return const [];
    }
    if (settings == null) return const [];
    final weekdays = _parseDays(settings['dias_abertos']);
    if (!weekdays.contains(_day.weekday)) return const [];
    final daysOff = settings['dias_folga'] as List<dynamic>? ?? const [];
    if (daysOff.any((item) {
      final date = DateTime.tryParse(item.toString());
      return date != null &&
          date.year == _day.year &&
          date.month == _day.month &&
          date.day == _day.day;
    })) {
      return const [];
    }
    final opening = _parseMinutes(settings['horario_inicio']);
    final closing = _parseMinutes(settings['horario_fim']);
    if (opening == null || closing == null || opening >= closing) {
      return const [];
    }
    final lunchStart = _parseMinutes(settings['almoco_inicio']);
    final lunchEnd = _parseMinutes(settings['almoco_fim']);
    final times = <TimeOfDay>[];
    for (
      var minute = opening;
      minute + service.durationMinutes <= closing;
      minute += 30
    ) {
      final endsAt = minute + service.durationMinutes;
      final dayStart = DateTime(_day.year, _day.month, _day.day);
      final startsAt = dayStart.add(Duration(minutes: minute));
      final lunchOverlap =
          lunchStart != null &&
          lunchEnd != null &&
          minute < lunchEnd &&
          endsAt > lunchStart;
      if (!lunchOverlap && startsAt.isAfter(DateTime.now())) {
        times.add(TimeOfDay(hour: minute ~/ 60, minute: minute % 60));
      }
    }
    return times;
  }

  bool _isTimeOccupied(TimeOfDay time) {
    final service = _service;
    if (service == null) return false;
    final startsAt = DateTime(
      _day.year,
      _day.month,
      _day.day,
      time.hour,
      time.minute,
    );
    final endsAt = startsAt.add(Duration(minutes: service.durationMinutes));
    return _occupied.any(
      (period) =>
          startsAt.isBefore(period.endsAt) && endsAt.isAfter(period.startsAt),
    );
  }

  Set<int> _parseDays(Object? value) {
    if (value is! List) return const {};
    return value
        .map((item) => num.tryParse(item.toString())?.toInt())
        .whereType<int>()
        .toSet();
  }

  int? _parseMinutes(Object? value) {
    if (value == null) return null;
    final parts = value.toString().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }
}

class _BrazilianPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;

    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = digits.substring(
      0,
      digits.length > 11 ? 11 : digits.length,
    );
    final formatted = _format(phoneDigits);
    final cursor = newValue.selection.extentOffset;
    if (cursor < 0 || cursor >= newValue.text.length) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final digitsBeforeCursor = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, phoneDigits.length);
    var formattedCursor = 0;
    var digitsCounted = 0;
    while (formattedCursor < formatted.length &&
        digitsCounted < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[formattedCursor])) {
        digitsCounted++;
      }
      formattedCursor++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formattedCursor),
    );
  }

  String _format(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return '($digits';

    final areaCode = digits.substring(0, 2);
    final subscriber = digits.substring(2);
    final subscriberLength = digits[2] == '9' ? 5 : 4;
    if (subscriber.length <= subscriberLength) {
      return '($areaCode) $subscriber';
    }
    return '($areaCode) ${subscriber.substring(0, subscriberLength)}-'
        '${subscriber.substring(subscriberLength)}';
  }
}

class _ManualBookingData {
  const _ManualBookingData({
    required this.settings,
    required this.services,
    required this.teamMembers,
    required this.clients,
  });

  final Map<String, dynamic> settings;
  final List<SalonService> services;
  final List<TeamMember> teamMembers;
  final List<SalonClient> clients;
}
