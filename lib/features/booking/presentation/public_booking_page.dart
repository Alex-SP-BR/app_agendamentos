import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_selector_button.dart';
import '../../../features/appointments/models/appointment.dart';
import '../../../features/appointments/models/occupied_period.dart';
import '../../../features/salon/data/salon_repository.dart';
import '../../../features/salon/models/salon_service.dart';
import '../../../features/salon/models/team_member.dart';

class PublicBookingPage extends StatefulWidget {
  const PublicBookingPage({
    required this.professionalId,
    required this.repository,
    required this.demoMode,
    required this.themeController,
    super.key,
  });

  final String professionalId;
  final SalonRepository repository;
  final bool demoMode;
  final ThemeController themeController;

  @override
  State<PublicBookingPage> createState() => _PublicBookingPageState();
}

class _PublicBookingPageState extends State<PublicBookingPage> {
  late Future<List<SalonService>> _servicesFuture;
  late Future<List<TeamMember>> _teamMembersFuture;
  SalonService? _selectedService;
  TeamMember? _selectedTeamMember;
  DateTime _selectedDay = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _selectedTime;
  PaymentType _paymentType = PaymentType.pix;
  bool _submitting = false;
  String? _loadError;
  Map<String, dynamic>? _professionalSettings;
  String? _pixKey;
  List<OccupiedPeriod> _occupiedPeriods = [];
  bool _loadingAvailability = false;

  @override
  void initState() {
    super.initState();
    _servicesFuture = widget.repository.listServices(widget.professionalId);
    _teamMembersFuture = widget.repository.listTeamMembers(
      widget.professionalId,
    );
    _loadPaymentSettings();
  }

  Future<void> _loadAvailability(DateTime day, {String? teamMemberId}) async {
    if (!mounted) return;
    if (teamMemberId == null) {
      setState(() {
        _occupiedPeriods = [];
        _loadingAvailability = false;
        _selectedTime = null;
      });
      return;
    }
    setState(() {
      _loadingAvailability = true;
      _loadError = null;
    });
    try {
      final periods = await widget.repository.listOccupiedPeriods(
        widget.professionalId,
        day,
        teamMemberId: teamMemberId,
      );
      if (!mounted) return;
      setState(() {
        _occupiedPeriods = periods;
        _loadingAvailability = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loadingAvailability = false;
      });
    }
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final settings = await widget.repository.loadSettings(
        widget.professionalId,
      );
      if (!mounted) return;
      final pixKey = await widget.repository.loadPixKey(widget.professionalId);
      if (!mounted) return;
      setState(() {
        _professionalSettings = settings;
        _pixKey = pixKey;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.toString());
    }
  }

  Future<void> _selectDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (!mounted) return;
    if (day != null) {
      setState(() {
        _selectedDay = day;
        _selectedTime = null;
      });
      _loadAvailability(day, teamMemberId: _selectedTeamMember?.id);
    }
  }

  Future<void> _book() async {
    final service = _selectedService;
    final time = _selectedTime;
    final teamMember = _selectedTeamMember;
    if (teamMember == null || service == null || time == null) {
      _message('Escolha um profissional, serviço e horário para continuar.');
      return;
    }
    final clientId = widget.demoMode
        ? 'demo-client'
        : Supabase.instance.client.auth.currentUser?.id;
    if (clientId == null) {
      _message(
        'Entre ou crie uma conta de cliente para confirmar o agendamento.',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final start = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        time.hour,
        time.minute,
      );
      await widget.repository.createAppointment(
        professionalId: widget.professionalId,
        clientId: clientId,
        service: service,
        startsAt: start,
        paymentType: _paymentType,
        teamMemberId: teamMember.id,
      );
      if (!mounted) return;
      if (_paymentType == PaymentType.pix) {
        final pixKey = _pixKey;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Agendamento solicitado'),
            content: SelectableText(
              pixKey == null || pixKey.isEmpty
                  ? 'Combine o pagamento por PIX diretamente com o profissional. '
                        'A confirmação do agendamento será verificada pelo profissional.'
                  : 'Faça o PIX para a chave $pixKey. '
                        'O pagamento e a confirmação devem ser verificados pelo profissional.',
            ),
            actions: [
              if (pixKey != null && pixKey.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pixKey));
                    if (!context.mounted) return;
                    if (!mounted) return;
                    Navigator.pop(context);
                    _message('Chave PIX copiada.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar chave'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Concluir'),
              ),
            ],
          ),
        );
        if (!mounted) return;
      } else {
        _message('Agendamento solicitado com sucesso!');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _message('Não foi possível criar o agendamento: $error');
    }
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agendar atendimento'),
        actions: [ThemeSelectorButton(controller: widget.themeController)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Escolha seu serviço',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text('Você verá somente os serviços deste profissional.'),
          const SizedBox(height: 20),
          FutureBuilder<List<TeamMember>>(
            future: _teamMembersFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Erro ao carregar profissionais: ${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final members = snapshot.data!
                  .where((member) => member.isActive)
                  .toList();
              if (members.isEmpty) {
                return const Text(
                  'Este salão ainda não cadastrou profissionais disponíveis.',
                );
              }
              TeamMember? selected;
              for (final member in members) {
                if (member.id == _selectedTeamMember?.id) {
                  selected = member;
                  break;
                }
              }
              return DropdownButtonFormField<TeamMember>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Profissional',
                  hintText: 'Selecione um profissional',
                ),
                items: members
                    .map(
                      (member) => DropdownMenuItem(
                        value: member,
                        child: Text(member.name),
                      ),
                    )
                    .toList(),
                onChanged: (member) {
                  setState(() {
                    _selectedTeamMember = member;
                    _selectedTime = null;
                  });
                  _loadAvailability(_selectedDay, teamMemberId: member?.id);
                },
              );
            },
          ),
          const SizedBox(height: 16),
          if (_loadError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Não foi possível carregar a disponibilidade: $_loadError',
                ),
              ),
            ),
          FutureBuilder<List<SalonService>>(
            future: _servicesFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Erro ao carregar serviços: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Text(
                  'Este profissional ainda não cadastrou serviços.',
                );
              }
              return RadioGroup<SalonService>(
                groupValue: _selectedService,
                onChanged: (value) => setState(() {
                  _selectedService = value;
                  _selectedTime = null;
                }),
                child: Column(
                  children: snapshot.data!.map((service) {
                    final selected = service.id == _selectedService?.id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: RadioListTile<SalonService>(
                        value: service,
                        title: Text(service.title),
                        subtitle: Text(
                          '${service.category} · ${service.durationMinutes} min',
                        ),
                        secondary: Text(currency.format(service.price)),
                        selected: selected,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          Text('Dia e horário', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _selectDay,
            icon: const Icon(Icons.calendar_today),
            label: Text(
              DateFormat('EEEE, d MMMM', 'pt_BR').format(_selectedDay),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingAvailability)
            const Center(child: CircularProgressIndicator())
          else if (_selectedTeamMember == null)
            const Text('Selecione um profissional para consultar os horários.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableTimes
                  .map(
                    (time) => ChoiceChip(
                      label: Text(time.format(context)),
                      selected: time == _selectedTime,
                      onSelected: (_) => setState(() => _selectedTime = time),
                    ),
                  )
                  .toList(),
            ),
          if (_selectedTeamMember != null && _availableTimes.isEmpty)
            const Text('Não há horários disponíveis para este dia.'),
          if (!widget.demoMode &&
              Supabase.instance.client.auth.currentUser == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/'),
                icon: const Icon(Icons.login),
                label: const Text('Entrar ou criar conta para agendar'),
              ),
            ),
          const SizedBox(height: 22),
          Text('Pagamento', style: Theme.of(context).textTheme.titleLarge),
          RadioGroup<PaymentType>(
            groupValue: _paymentType,
            onChanged: (value) {
              if (value != null) setState(() => _paymentType = value);
            },
            child: Column(
              children: [
                RadioListTile<PaymentType>(
                  value: PaymentType.pix,
                  title: const Text('PIX'),
                  subtitle: Text(
                    _pixKey == null || _pixKey!.isEmpty
                        ? 'A chave PIX pode ser combinada diretamente com o profissional.'
                        : 'Chave PIX: $_pixKey',
                  ),
                ),
                const RadioListTile<PaymentType>(
                  value: PaymentType.local,
                  title: Text('Pagamento Pessoalmente / Presencial'),
                  subtitle: Text('Dinheiro ou cartão no salão.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _submitting || _selectedTeamMember == null
                ? null
                : _book,
            child: Text(
              _submitting ? 'Confirmando...' : 'Confirmar agendamento',
            ),
          ),
          if (widget.demoMode)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Demonstração: este agendamento fica apenas nesta sessão.',
              ),
            ),
        ],
      ),
    );
  }

  List<TimeOfDay> get _availableTimes {
    final settings = _professionalSettings;
    final service = _selectedService;
    if (_loadingAvailability ||
        _loadError != null ||
        settings == null ||
        service == null ||
        _selectedTeamMember == null) {
      return const [];
    }
    final openDays = _parseWeekdays(settings['dias_abertos']);
    if (!openDays.contains(_selectedDay.weekday)) return const [];
    final daysOff = settings['dias_folga'];
    final isDayOff = (daysOff is List ? daysOff : const <dynamic>[])
        .map((day) => DateTime.tryParse(day.toString()))
        .whereType<DateTime>()
        .any(
          (day) =>
              day.year == _selectedDay.year &&
              day.month == _selectedDay.month &&
              day.day == _selectedDay.day,
        );
    if (isDayOff) return const [];

    final opening = _minutesFromDatabase(settings['horario_inicio']);
    final closing = _minutesFromDatabase(settings['horario_fim']);
    if (opening == null || closing == null || opening >= closing) {
      return const [];
    }
    final lunchStart = settings['almoco_inicio'] == null
        ? null
        : _minutesFromDatabase(settings['almoco_inicio']);
    final lunchEnd = settings['almoco_fim'] == null
        ? null
        : _minutesFromDatabase(settings['almoco_fim']);
    if ((settings['almoco_inicio'] != null && lunchStart == null) ||
        (settings['almoco_fim'] != null && lunchEnd == null)) {
      return const [];
    }
    final day = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final today = DateTime.now();
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final result = <TimeOfDay>[];
    for (
      var minute = opening;
      minute + service.durationMinutes <= closing;
      minute += 30
    ) {
      final end = minute + service.durationMinutes;
      final overlapsLunch =
          lunchStart != null &&
          lunchEnd != null &&
          minute < lunchEnd &&
          end > lunchStart;
      final startsAt = day.add(Duration(minutes: minute));
      final endsAt = startsAt.add(Duration(minutes: service.durationMinutes));
      final overlapsExisting = _occupiedPeriods.any(
        (period) =>
            startsAt.isBefore(period.endsAt) && endsAt.isAfter(period.startsAt),
      );
      if (!overlapsLunch &&
          !overlapsExisting &&
          (!isToday || startsAt.isAfter(today))) {
        result.add(TimeOfDay(hour: minute ~/ 60, minute: minute % 60));
      }
    }
    return result;
  }

  Set<int> _parseWeekdays(Object? value) {
    if (value is! List) return const {};
    return value
        .map((day) {
          final parsed = day is num ? day : num.tryParse(day?.toString() ?? '');
          if (parsed == null || parsed % 1 != 0) return null;
          return parsed.toInt();
        })
        .whereType<int>()
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
  }

  int? _minutesFromDatabase(Object? value) {
    if (value == null) return null;
    final parts = value.toString().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }
}
