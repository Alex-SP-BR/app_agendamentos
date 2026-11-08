import 'package:supabase_flutter/supabase_flutter.dart';

import '../../appointments/models/appointment.dart';
import '../../appointments/models/occupied_period.dart';
import '../models/salon_client.dart';
import '../models/salon_service.dart';
import '../models/team_member_access_session.dart';
import '../models/team_member_agenda_item.dart';
import '../models/team_member.dart';

class SalonRepository {
  SalonRepository({required this.client, required this.demoMode});

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final SupabaseClient? client;
  final bool demoMode;

  void _requireUuid(String value, String parameterName) {
    if (!_uuidPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        parameterName,
        'Informe um UUID válido antes de consultar o Supabase.',
      );
    }
  }

  Future<List<SalonService>> listServices(String professionalId) async {
    if (demoMode) {
      return _demoServices
          .where((service) => service.professionalId == professionalId)
          .toList();
    }
    final rows = await client!
        .from('servicos')
        .select(
          'id, profissional_id, titulo, categoria, preco, duracao_minutos',
        )
        .eq('profissional_id', professionalId)
        .eq('ativo', true)
        .order('titulo');
    return rows.map(SalonService.fromMap).toList();
  }

  Future<List<SalonService>> listTeamMemberServices(String accessToken) async {
    if (demoMode) {
      return List<SalonService>.unmodifiable(_demoServices);
    }
    if (accessToken.trim().isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Informe o token da sessão da equipe.',
      );
    }
    final response = await client!.rpc(
      'servicos_equipe_com_sessao',
      params: {'p_access_token': accessToken},
    );
    return _normalizeRpcRows(
      response,
      'servicos_equipe_com_sessao',
    ).map(SalonService.fromMap).toList();
  }

  Future<void> saveService({
    String? id,
    required String professionalId,
    required String title,
    required String category,
    required double price,
    required int durationMinutes,
  }) async {
    if (demoMode) {
      throw StateError(
        'O cadastro de serviços requer a configuração do Supabase.',
      );
    }
    final values = {
      'profissional_id': professionalId,
      'titulo': title,
      'categoria': category,
      'preco': price,
      'duracao_minutos': durationMinutes,
      'ativo': true,
    };
    if (id == null) {
      await client!.from('servicos').insert(values);
    } else {
      await client!.from('servicos').update(values).eq('id', id);
    }
  }

  Future<void> deactivateService(String serviceId) async {
    if (demoMode) {
      throw StateError(
        'O cadastro de serviços requer a configuração do Supabase.',
      );
    }
    await client!.from('servicos').update({'ativo': false}).eq('id', serviceId);
  }

  Future<List<Appointment>> listAppointments(
    String professionalId,
    DateTime day,
  ) async {
    if (demoMode) {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      return _demoAppointments
          .where(
            (appointment) =>
                appointment.professionalId == professionalId &&
                !appointment.startsAt.isBefore(start) &&
                appointment.startsAt.isBefore(end),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    _requireUuid(professionalId, 'professionalId');
    final response = await client!.rpc(
      'agenda_profissional_por_dia',
      params: {
        'p_professional_id': professionalId,
        'p_day':
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
      },
    );
    return _normalizeRpcRows(
      response,
      'agenda_profissional_por_dia',
    ).map(Appointment.fromTeamAgendaMap).toList();
  }

  Future<List<OccupiedPeriod>> listOccupiedPeriods(
    String professionalId,
    DateTime day, {
    String? teamMemberId,
  }) async {
    if (teamMemberId == null || teamMemberId.isEmpty) return const [];
    if (demoMode) {
      final appointments = await listAppointments(professionalId, day);
      return appointments
          .where(
            (appointment) =>
                appointment.teamMemberId == teamMemberId &&
                (appointment.status == 'pendente' ||
                    appointment.status == 'confirmado'),
          )
          .map((appointment) {
            final service = _demoServices.firstWhere(
              (item) => item.id == appointment.serviceId,
            );
            return OccupiedPeriod(
              startsAt: appointment.startsAt,
              endsAt: appointment.startsAt.add(
                Duration(minutes: service.durationMinutes),
              ),
            );
          })
          .toList();
    }
    _requireUuid(professionalId, 'professionalId');
    _requireUuid(teamMemberId, 'teamMemberId');
    final date =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final Object? response;
    try {
      response = await client!.rpc(
        'horarios_ocupados',
        params: {
          'p_profissional_id': professionalId,
          'p_data': date,
          'p_team_member_id': teamMemberId,
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingOccupiedPeriodsFunction(error)) rethrow;
      return _listOccupiedPeriodsFromAppointments(
        professionalId,
        day,
        teamMemberId,
      );
    }
    final rows = _normalizeRpcRows(response, 'horarios_ocupados');
    return rows.map((row) {
      final rawStart = row['starts_at'];
      if (rawStart is! String || rawStart.isEmpty) {
        throw const FormatException(
          'Data inválida ao carregar horários ocupados.',
        );
      }
      final start = DateTime.parse(rawStart).toLocal();
      return OccupiedPeriod(
        startsAt: start,
        endsAt: start.add(
          Duration(
            minutes: parseOccupiedDurationMinutes(row['duration_minutes']),
          ),
        ),
      );
    }).toList();
  }

  bool _isMissingOccupiedPeriodsFunction(PostgrestException error) {
    if (error.code == 'PGRST202' || error.code == '42883') return true;
    final message = error.message.toLowerCase();
    return message.contains('horarios_ocupados') &&
        (message.contains('does not exist') ||
            message.contains('could not find the function') ||
            message.contains('schema cache'));
  }

  Future<List<OccupiedPeriod>> _listOccupiedPeriodsFromAppointments(
    String professionalId,
    DateTime day,
    String teamMemberId,
  ) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    var query = client!
        .from('agendamentos')
        .select('data_hora_inicio, servicos(duracao_minutos)')
        .eq('profissional_id', professionalId)
        .eq('team_member_id', teamMemberId)
        .inFilter('status', ['pendente', 'confirmado'])
        .gte('data_hora_inicio', start.toUtc().toIso8601String())
        .lt('data_hora_inicio', end.toUtc().toIso8601String());
    final rows = await query;

    return rows.map((row) {
      final appointment = row;
      final serviceValue = appointment['servicos'];
      final service = serviceValue is Map
          ? Map<String, dynamic>.from(serviceValue)
          : null;
      final rawStart = appointment['data_hora_inicio'];
      if (rawStart is! String || rawStart.isEmpty) {
        throw const FormatException(
          'Data inválida ao calcular horários ocupados.',
        );
      }
      final appointmentStart = DateTime.parse(rawStart).toLocal();
      return OccupiedPeriod(
        startsAt: appointmentStart,
        endsAt: appointmentStart.add(
          Duration(
            minutes: parseOccupiedDurationMinutes(service?['duracao_minutos']),
          ),
        ),
      );
    }).toList();
  }

  Future<void> createAppointment({
    required String professionalId,
    String? clientId,
    String? salonClientId,
    required SalonService service,
    required DateTime startsAt,
    required PaymentType paymentType,
    required String teamMemberId,
  }) async {
    if (teamMemberId.trim().isEmpty) {
      throw ArgumentError.value(
        teamMemberId,
        'teamMemberId',
        'Selecione um profissional da equipe.',
      );
    }
    if ((clientId == null) == (salonClientId == null)) {
      throw ArgumentError(
        'Informe exatamente um cliente com conta ou um cliente do salão.',
      );
    }
    if (demoMode) {
      _demoAppointments.add(
        Appointment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          professionalId: professionalId,
          clientId: clientId,
          salonClientId: salonClientId,
          serviceId: service.id,
          serviceTitle: service.title,
          startsAt: startsAt,
          paymentType: paymentType,
          value: service.price,
          status: 'confirmado',
          teamMemberId: teamMemberId,
        ),
      );
      return;
    }
    await client!.from('agendamentos').insert({
      'profissional_id': professionalId,
      'cliente_id': clientId,
      'cliente_salao_id': salonClientId,
      'servico_id': service.id,
      'team_member_id': teamMemberId,
      'data_hora_inicio': startsAt.toUtc().toIso8601String(),
      'tipo_pagamento': paymentType.databaseValue,
      'valor': service.price,
      'status': 'pendente',
    });
  }

  Future<List<TeamMember>> listTeamMembers(String professionalId) async {
    if (demoMode) {
      return professionalId == _demoProfessionalId ? _demoTeamMembers : [];
    }
    final rows = await client!
        .from('profissionais_equipe')
        .select('id, nome, ativo')
        .eq('profissional_id', professionalId)
        .order('nome');
    return rows.map(TeamMember.fromMap).toList();
  }

  Future<void> addTeamMember(String professionalId, String name) async {
    if (demoMode) {
      throw StateError('A gestão da equipa requer uma conexão com o Supabase.');
    }
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Informe o nome do profissional.',
      );
    }
    final existingMembers = await listTeamMembers(professionalId);
    final duplicate = existingMembers.any(
      (member) =>
          member.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
          normalizedName.toLowerCase(),
    );
    if (duplicate) {
      throw StateError(
        'Já existe um profissional com esse nome. Adicione um sobrenome para diferenciar.',
      );
    }
    try {
      await client!.from('profissionais_equipe').insert({
        'profissional_id': professionalId,
        'nome': normalizedName,
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError(
          'Já existe um profissional com esse nome. Adicione um sobrenome para diferenciar.',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteTeamMember({
    required String professionalId,
    required TeamMember teamMember,
  }) async {
    if (demoMode) {
      throw StateError('A gestão da equipe requer conexão com o Supabase.');
    }
    final members = await listTeamMembers(professionalId);
    final activeMembers = members.where((member) => member.isActive);
    if (teamMember.isActive && activeMembers.length <= 1) {
      throw StateError(
        'O salão precisa manter ao menos um profissional ativo na equipe.',
      );
    }
    try {
      await client!
          .from('profissionais_equipe')
          .delete()
          .eq('id', teamMember.id)
          .eq('profissional_id', professionalId);
    } on PostgrestException catch (error) {
      if (error.code == '23503') {
        throw StateError(
          'Este profissional possui agendamentos vinculados. Reatribua-os antes de excluir.',
        );
      }
      rethrow;
    }
  }

  Future<void> setTeamMemberPin({
    required String teamMemberId,
    required String? pin,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    await client!.rpc(
      'definir_pin_profissional_equipe',
      params: {'p_team_member_id': teamMemberId, 'p_pin': pin},
    );
  }

  Future<TeamMemberAccessSession> authenticateTeamMemberAccess({
    required String teamMemberId,
    required String pin,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    _requireUuid(teamMemberId, 'teamMemberId');
    final response = await client!.rpc(
      'autenticar_equipe_com_pin',
      params: {'p_team_member_id': teamMemberId, 'p_pin': pin},
    );
    final rows = _normalizeRpcRows(response, 'autenticar_equipe_com_pin');
    if (rows.isEmpty) {
      throw StateError(
        'PIN inválido, acesso bloqueado ou equipe indisponível.',
      );
    }
    return TeamMemberAccessSession.fromMap(rows.first);
  }

  Future<List<TeamMemberAgendaItem>> listTeamMemberAppointments(
    String accessToken, {
    DateTime? day,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    if (accessToken.trim().isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Informe o token da sessão da equipe.',
      );
    }
    final response = await client!.rpc(
      'agenda_equipe_com_sessao',
      params: {
        'p_access_token': accessToken,
        'p_day': _teamMemberDateOnly(day ?? DateTime.now()),
      },
    );
    return TeamMemberAgendaItem.listFromRpcResponse(response);
  }

  String _teamMemberDateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<SalonClient>> listTeamMemberClients(String accessToken) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    final response = await client!.rpc(
      'clientes_equipe_com_sessao',
      params: {'p_access_token': accessToken},
    );
    final rows = _normalizeRpcRows(response, 'clientes_equipe_com_sessao');
    return rows.map((row) {
      final id = _requiredString(
        row,
        'client_id',
        'clientes_equipe_com_sessao',
      );
      return SalonClient(
        id: id,
        salonClientId: id,
        name: _requiredString(row, 'client_name', 'clientes_equipe_com_sessao'),
        phone: _requiredString(
          row,
          'client_phone',
          'clientes_equipe_com_sessao',
        ),
      );
    }).toList();
  }

  Future<SalonClient> saveTeamMemberClient({
    required String accessToken,
    required String name,
    required String phone,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    final response = await client!.rpc(
      'criar_cliente_equipe_com_sessao',
      params: {'p_access_token': accessToken, 'p_name': name, 'p_phone': phone},
    );
    final rows = _normalizeRpcRows(response, 'criar_cliente_equipe_com_sessao');
    if (rows.isEmpty) {
      throw StateError('Não foi possível salvar o cliente da equipe.');
    }
    final row = rows.first;
    final id = _requiredString(
      row,
      'client_id',
      'criar_cliente_equipe_com_sessao',
    );
    return SalonClient(
      id: id,
      salonClientId: id,
      name: _requiredString(
        row,
        'client_name',
        'criar_cliente_equipe_com_sessao',
      ),
      phone: _requiredString(
        row,
        'client_phone',
        'criar_cliente_equipe_com_sessao',
      ),
    );
  }

  Future<void> updateTeamMemberClient({
    required String accessToken,
    required String clientId,
    required String name,
    required String phone,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    await client!.rpc(
      'atualizar_cliente_equipe_com_sessao',
      params: {
        'p_access_token': accessToken,
        'p_client_id': clientId,
        'p_name': name,
        'p_phone': phone,
      },
    );
  }

  Future<void> createTeamMemberAppointment({
    required String accessToken,
    required String clientId,
    required SalonService service,
    required DateTime startsAt,
  }) async {
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    await client!.rpc(
      'criar_agendamento_equipe_com_sessao',
      params: {
        'p_access_token': accessToken,
        'p_client_id': clientId,
        'p_service_id': service.id,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> updateTeamMemberAppointmentStatus({
    required String accessToken,
    required String appointmentId,
    required String status,
  }) async {
    const allowedStatuses = {'confirmado', 'concluido', 'cancelado'};
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Status de agendamento inválido',
      );
    }
    if (demoMode) {
      throw StateError('O acesso externo requer conexão com o Supabase.');
    }
    await client!.rpc(
      'atualizar_status_agendamento_equipe',
      params: {
        'p_access_token': accessToken,
        'p_appointment_id': appointmentId,
        'p_status': status,
      },
    );
  }

  Future<List<SalonClient>> listClients(String professionalId) async {
    if (demoMode) {
      if (professionalId != _demoProfessionalId) return [];
      return List<SalonClient>.unmodifiable(_demoSalonClients);
    }
    final profileRows = await client!
        .from('perfis')
        .select('id, nome, telefone')
        .eq('tipo', 'cliente')
        .order('nome');
    final salonRows = await client!
        .from('clientes_salao')
        .select('id, nome, telefone')
        .eq('profissional_id', professionalId)
        .order('nome');
    return [
      ...profileRows.map(SalonClient.fromProfileMap),
      ...salonRows.map(SalonClient.fromSalonMap),
    ];
  }

  List<Map<String, dynamic>> _normalizeRpcRows(
    Object? response,
    String rpcName,
  ) {
    if (response == null) return [];

    final rows = switch (response) {
      List<dynamic> values => values,
      Map<dynamic, dynamic> value => [value],
      _ => throw FormatException(
        'Formato inesperado na resposta da RPC "$rpcName".',
      ),
    };

    return rows.map((row) {
      if (row is! Map || row.keys.any((key) => key is! String)) {
        throw FormatException(
          'Registro inválido na resposta da RPC "$rpcName".',
        );
      }
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  String _requiredString(
    Map<String, dynamic> row,
    String field,
    String rpcName,
  ) {
    final value = row[field];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'Campo obrigatório "$field" ausente na resposta da RPC "$rpcName".',
      );
    }
    return value;
  }

  Future<SalonClient> saveSalonClient({
    required String professionalId,
    required String name,
    required String phone,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (name.trim().isEmpty ||
        normalizedPhone.length < 8 ||
        normalizedPhone.length > 15) {
      throw ArgumentError('Informe nome e um telefone válido para o cliente.');
    }
    if (demoMode) {
      if (professionalId != _demoProfessionalId) {
        throw StateError('Cliente não pertence ao salão de demonstração.');
      }
      final index = _demoSalonClients.indexWhere(
        (client) =>
            client.phone.replaceAll(RegExp(r'\D'), '') == normalizedPhone,
      );
      final id = index == -1
          ? 'demo-client-${DateTime.now().microsecondsSinceEpoch}'
          : _demoSalonClients[index].id;
      final saved = SalonClient(
        id: id,
        salonClientId: id,
        name: name.trim(),
        phone: phone.trim(),
      );
      if (index == -1) {
        _demoSalonClients.add(saved);
      } else {
        _demoSalonClients[index] = saved;
      }
      return saved;
    }

    final rows = await client!
        .from('clientes_salao')
        .select('id, nome, telefone')
        .eq('profissional_id', professionalId);
    Map<String, dynamic>? existing;
    for (final row in rows) {
      if ((row['telefone'] as String).replaceAll(RegExp(r'\D'), '') ==
          normalizedPhone) {
        existing = row;
        break;
      }
    }
    final values = {
      'profissional_id': professionalId,
      'nome': name.trim(),
      'telefone': phone.trim(),
    };
    final row = existing == null
        ? await client!
              .from('clientes_salao')
              .insert(values)
              .select('id, nome, telefone')
              .single()
        : await client!
              .from('clientes_salao')
              .update({'nome': name.trim(), 'telefone': phone.trim()})
              .eq('id', existing['id'] as String)
              .eq('profissional_id', professionalId)
              .select('id, nome, telefone')
              .single();
    return SalonClient.fromSalonMap(row);
  }

  Future<void> updateSalonClient({
    required String professionalId,
    required String clientId,
    required String name,
    required String phone,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (name.trim().isEmpty ||
        normalizedPhone.length < 8 ||
        normalizedPhone.length > 15) {
      throw ArgumentError('Informe nome e um telefone válido para o cliente.');
    }
    if (demoMode) {
      if (professionalId != _demoProfessionalId) {
        throw StateError('Cliente não pertence ao salão de demonstração.');
      }
      final index = _demoSalonClients.indexWhere(
        (client) => client.id == clientId,
      );
      if (index == -1) {
        throw StateError('Cliente não encontrado.');
      }
      _demoSalonClients[index] = SalonClient(
        id: clientId,
        salonClientId: clientId,
        name: name.trim(),
        phone: phone.trim(),
      );
      return;
    }

    await client!
        .from('clientes_salao')
        .update({'nome': name.trim(), 'telefone': phone.trim()})
        .eq('id', clientId)
        .eq('profissional_id', professionalId);
  }

  Future<void> deleteSalonClient({
    required String professionalId,
    required String clientId,
  }) async {
    if (demoMode) {
      if (professionalId != _demoProfessionalId) {
        throw StateError('Cliente não pertence ao salão de demonstração.');
      }
      _demoSalonClients.removeWhere((client) => client.id == clientId);
      return;
    }

    await client!
        .from('clientes_salao')
        .delete()
        .eq('id', clientId)
        .eq('profissional_id', professionalId);
  }

  Future<void> updateAppointmentStatus(
    String appointmentId,
    String status,
  ) async {
    const allowedStatuses = {'confirmado', 'concluido', 'cancelado'};
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Status de agendamento inválido',
      );
    }
    if (demoMode) {
      final index = _demoAppointments.indexWhere(
        (appointment) => appointment.id == appointmentId,
      );
      if (index == -1) {
        throw StateError('Agendamento de demonstração não encontrado.');
      }
      final appointment = _demoAppointments[index];
      _demoAppointments[index] = Appointment(
        id: appointment.id,
        professionalId: appointment.professionalId,
        clientId: appointment.clientId,
        serviceId: appointment.serviceId,
        serviceTitle: appointment.serviceTitle,
        startsAt: appointment.startsAt,
        paymentType: appointment.paymentType,
        value: appointment.value,
        status: status,
        teamMemberId: appointment.teamMemberId,
        clientName: appointment.clientName,
        salonClientId: appointment.salonClientId,
      );
      return;
    }
    await client!
        .from('agendamentos')
        .update({'status': status})
        .eq('id', appointmentId);
  }

  Future<bool> allowsLocalPayment(String professionalId) async {
    if (demoMode) return true;
    final row = await client!
        .from('profissionais_config')
        .select('permite_pagamento_local')
        .eq('profissional_id', professionalId)
        .maybeSingle();
    return row?['permite_pagamento_local'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> loadSettings(String professionalId) async {
    if (demoMode) {
      return {
        'horario_inicio': '09:00:00',
        'horario_fim': '18:00:00',
        'almoco_inicio': '12:00:00',
        'almoco_fim': '13:00:00',
        'dias_abertos': [1, 2, 3, 4, 5, 6],
        'dias_folga': <String>[],
        'aceita_pacotes': false,
        'dias_pacotes_permitidos': [1, 2, 3],
        'permite_pagamento_local': true,
      };
    }
    final settingsColumns =
        'horario_inicio, horario_fim, almoco_inicio, almoco_fim, dias_abertos, dias_folga, aceita_pacotes, dias_pacotes_permitidos, permite_pagamento_local';
    final row = await client!
        .from('profissionais_config')
        .select(settingsColumns)
        .eq('profissional_id', professionalId)
        .maybeSingle();
    return row ?? _defaultProfessionalSettings;
  }

  Future<void> saveSettings(
    String professionalId,
    Map<String, dynamic> values,
  ) async {
    if (demoMode) {
      throw StateError(
        'As configurações precisam de uma conexão com o Supabase.',
      );
    }
    await client!.from('profissionais_config').upsert({
      'profissional_id': professionalId,
      ...values,
    }, onConflict: 'profissional_id');
  }

  Future<String?> loadPixKey(String professionalId) async {
    if (demoMode) return null;
    final row = await client!
        .from('profissionais_pagamentos')
        .select('chave_pix')
        .eq('profissional_id', professionalId)
        .maybeSingle();
    return row?['chave_pix'] as String?;
  }

  Future<void> savePixKey(String professionalId, String pixKey) async {
    if (demoMode) {
      throw StateError('A chave PIX precisa de uma conexão com o Supabase.');
    }
    await client!.from('profissionais_pagamentos').upsert({
      'profissional_id': professionalId,
      'chave_pix': pixKey.isEmpty ? null : pixKey,
    });
  }

  static const _demoProfessionalId = 'demo-professional';
  static const _defaultProfessionalSettings = <String, dynamic>{
    'horario_inicio': '09:00:00',
    'horario_fim': '18:00:00',
    'almoco_inicio': null,
    'almoco_fim': null,
    'dias_abertos': [1, 2, 3, 4, 5, 6],
    'dias_folga': <String>[],
    'aceita_pacotes': false,
    'dias_pacotes_permitidos': [1, 2, 3],
    'permite_pagamento_local': false,
  };
  static final _demoSalonClients = <SalonClient>[
    const SalonClient(
      id: 'demo-client',
      name: 'Cliente de demonstração',
      phone: '',
    ),
  ];
  static const _demoTeamMembers = [
    TeamMember(id: 'demo-team-tati', name: 'Tati'),
    TeamMember(id: 'demo-team-edna', name: 'Edna'),
    TeamMember(id: 'demo-team-daiane', name: 'Daiane'),
    TeamMember(id: 'demo-team-camila', name: 'Camila'),
  ];
  static final _demoServices = <SalonService>[
    const SalonService(
      id: 'service-cut',
      professionalId: _demoProfessionalId,
      title: 'Corte clássico',
      category: 'Cabelo',
      price: 45,
      durationMinutes: 40,
    ),
    const SalonService(
      id: 'service-beard',
      professionalId: _demoProfessionalId,
      title: 'Barba + acabamento',
      category: 'Barba',
      price: 30,
      durationMinutes: 30,
    ),
    const SalonService(
      id: 'service-combo',
      professionalId: _demoProfessionalId,
      title: 'Corte + barba',
      category: 'Combo',
      price: 65,
      durationMinutes: 60,
    ),
  ];

  static final List<Appointment> _demoAppointments = [
    Appointment(
      id: 'demo-1',
      professionalId: _demoProfessionalId,
      clientId: 'demo-client',
      serviceId: 'service-cut',
      serviceTitle: 'Corte clássico',
      clientName: 'Cliente de demonstração',
      startsAt: DateTime.now().copyWith(hour: 9, minute: 0, second: 0),
      paymentType: PaymentType.local,
      value: 45,
      status: 'confirmado',
      teamMemberId: 'demo-team-tati',
    ),
    Appointment(
      id: 'demo-2',
      professionalId: _demoProfessionalId,
      clientId: 'demo-client',
      serviceId: 'service-combo',
      serviceTitle: 'Corte + barba',
      clientName: 'Cliente de demonstração',
      startsAt: DateTime.now().copyWith(hour: 11, minute: 0, second: 0),
      paymentType: PaymentType.pix,
      value: 65,
      status: 'confirmado',
      teamMemberId: 'demo-team-tati',
    ),
  ];
}
