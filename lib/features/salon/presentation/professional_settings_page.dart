import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/salon_repository.dart';

class ProfessionalSettingsPage extends StatefulWidget {
  const ProfessionalSettingsPage({
    required this.professionalId,
    required this.demoMode,
    required this.repository,
    super.key,
  });

  final String professionalId;
  final bool demoMode;
  final SalonRepository repository;

  @override
  State<ProfessionalSettingsPage> createState() =>
      _ProfessionalSettingsPageState();
}

class _ProfessionalSettingsPageState extends State<ProfessionalSettingsPage> {
  late Future<Map<String, dynamic>> _settingsFuture;
  Map<String, dynamic>? _settings;
  TimeOfDay _opening = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closing = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay? _lunchStart;
  TimeOfDay? _lunchEnd;
  Set<int> _openDays = {1, 2, 3, 4, 5, 6};
  List<DateTime> _daysOff = [];
  bool _saving = false;

  static const _weekdays = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  @override
  void initState() {
    super.initState();
    _settingsFuture = widget.repository.loadSettings(widget.professionalId);
  }

  TimeOfDay _parseTime(Object? value, TimeOfDay fallback) {
    if (value == null) return fallback;
    final parts = value.toString().split(':');
    if (parts.length < 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _applySettings(Map<String, dynamic> settings) {
    if (_settings != null) return;
    _settings = settings;
    _opening = _parseTime(settings['horario_inicio'], _opening);
    _closing = _parseTime(settings['horario_fim'], _closing);
    _lunchStart = settings['almoco_inicio'] == null
        ? null
        : _parseTime(settings['almoco_inicio'], _opening);
    _lunchEnd = settings['almoco_fim'] == null
        ? null
        : _parseTime(settings['almoco_fim'], _closing);
    _openDays = _parseDays(settings['dias_abertos'], _openDays);
    _daysOff = (settings['dias_folga'] as List<dynamic>)
        .map((day) => DateTime.parse(day as String))
        .toList();
  }

  Set<int> _parseDays(Object? value, Set<int> fallback) {
    if (value is! List) return Set<int>.from(fallback);
    return value
        .map((day) => num.tryParse(day.toString())?.toInt())
        .whereType<int>()
        .where((day) => day >= 1 && day <= 7)
        .toSet();
  }

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final result = await showTimePicker(context: context, initialTime: initial);
    if (!mounted) return;
    if (result != null) setState(() => onPicked(result));
  }

  Future<void> _addDayOff() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (selected != null) {
      setState(
        () =>
            _daysOff.add(DateTime(selected.year, selected.month, selected.day)),
      );
    }
  }

  Future<void> _save() async {
    if (widget.demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'As alterações ficam disponíveis após conectar o Supabase.',
          ),
        ),
      );
      return;
    }
    if (_openDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um dia de expediente.'),
        ),
      );
      return;
    }
    if (_minutes(_opening) >= _minutes(_closing) ||
        (_lunchStart != null &&
            (_lunchEnd == null ||
                _minutes(_lunchStart!) >= _minutes(_lunchEnd!) ||
                _minutes(_lunchStart!) < _minutes(_opening) ||
                _minutes(_lunchEnd!) > _minutes(_closing)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confira os horários de expediente e almoço.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.saveSettings(widget.professionalId, {
        ..._settings!,
        'horario_inicio': _formatTime(_opening),
        'horario_fim': _formatTime(_closing),
        'almoco_inicio': _lunchStart == null ? null : _formatTime(_lunchStart!),
        'almoco_fim': _lunchEnd == null ? null : _formatTime(_lunchEnd!),
        'dias_abertos': _openDays.toList()..sort(),
        'dias_folga': _daysOff
            .map((day) => DateFormat('yyyy-MM-dd').format(day))
            .toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Configurações salvas.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar configurações: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

  Widget _timeButton(
    String label,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onPicked,
  ) {
    return OutlinedButton(
      onPressed: () => _pickTime(initial: time, onPicked: onPicked),
      child: Text('$label: ${time.format(context)}'),
    );
  }

  Widget _weekdaySelector(Set<int> selected, ValueChanged<int> onToggle) {
    return Wrap(
      spacing: 6,
      children: _weekdays.entries
          .map(
            (entry) => FilterChip(
              label: Text(entry.value),
              selected: selected.contains(entry.key),
              onSelected: (_) => onToggle(entry.key),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expediente e preferências')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao carregar configuração: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _applySettings(snapshot.data!);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Horários de atendimento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  _timeButton(
                    'Abertura',
                    _opening,
                    (value) => _opening = value,
                  ),
                  _timeButton(
                    'Fechamento',
                    _closing,
                    (value) => _closing = value,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Dias de expediente'),
              _weekdaySelector(
                _openDays,
                (day) => setState(() {
                  _openDays.contains(day)
                      ? _openDays.remove(day)
                      : _openDays.add(day);
                }),
              ),
              const SizedBox(height: 8),
              const Text('Pausa para almoço (opcional)'),
              Wrap(
                spacing: 10,
                children: [
                  _timeButton(
                    'Início',
                    _lunchStart ?? const TimeOfDay(hour: 12, minute: 0),
                    (value) {
                      _lunchStart = value;
                      _lunchEnd ??= const TimeOfDay(hour: 13, minute: 0);
                    },
                  ),
                  _timeButton(
                    'Fim',
                    _lunchEnd ?? const TimeOfDay(hour: 13, minute: 0),
                    (value) {
                      _lunchEnd = value;
                      _lunchStart ??= const TimeOfDay(hour: 12, minute: 0);
                    },
                  ),
                  if (_lunchStart != null || _lunchEnd != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _lunchStart = null;
                        _lunchEnd = null;
                      }),
                      child: const Text('Remover pausa'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Folgas específicas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _addDayOff,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: _daysOff
                    .map(
                      (day) => InputChip(
                        label: Text(DateFormat('dd/MM/yyyy').format(day)),
                        onDeleted: () => setState(() => _daysOff.remove(day)),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 32),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Salvando...' : 'Salvar configurações'),
              ),
            ],
          );
        },
      ),
    );
  }
}
