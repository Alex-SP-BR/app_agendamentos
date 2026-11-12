import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agenda_pro/app/app.dart';
import 'package:agenda_pro/core/config/app_config.dart';
import 'package:agenda_pro/core/theme/theme_controller.dart';
import 'package:agenda_pro/features/appointments/models/appointment.dart';
import 'package:agenda_pro/features/appointments/models/occupied_period.dart';
import 'package:agenda_pro/features/appointments/presentation/appointment_card.dart';
import 'package:agenda_pro/features/booking/presentation/public_booking_page.dart';
import 'package:agenda_pro/features/salon/data/salon_repository.dart';
import 'package:agenda_pro/features/salon/models/salon_service.dart';
import 'package:agenda_pro/features/salon/models/salon_client.dart';
import 'package:agenda_pro/features/salon/models/team_member_access_session.dart';
import 'package:agenda_pro/features/salon/models/team_member_agenda_item.dart';
import 'package:agenda_pro/features/salon/presentation/clients_management_page.dart';
import 'package:agenda_pro/features/salon/presentation/manual_appointment_page.dart';
import 'package:agenda_pro/features/salon/presentation/professional_settings_page.dart';
import 'package:agenda_pro/features/salon/presentation/team_member_access_page.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
  });

  test('occupied period durations tolerate RPC value formats', () {
    expect(parseOccupiedDurationMinutes(30), 30);
    expect(parseOccupiedDurationMinutes('30'), 30);
    expect(parseOccupiedDurationMinutes('00:30:00'), 30);
    expect(parseOccupiedDurationMinutes('45 minutes'), 45);
    expect(parseOccupiedDurationMinutes(Duration(seconds: 30)), 1);
    expect(parseOccupiedDurationMinutes(null), 30);
    expect(parseOccupiedDurationMinutes(''), 30);
    expect(parseOccupiedDurationMinutes('invalid'), 30);
    expect(parseOccupiedDurationMinutes(-5), 30);
    expect(parseOccupiedDurationMinutes(30.5), 30);
  });

  testWidgets('dashboard demonstrates schedule and financial overview', (
    tester,
  ) async {
    final themeController = ThemeController();
    await themeController.load();
    await tester.pumpWidget(
      SalonApp(
        themeController: themeController,
        supabaseConfigured: false,
        publicAppBaseUrl: 'https://agenda.example.com',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agenda Pro'), findsOneWidget);
    expect(find.byTooltip('Copiar link de agendamento'), findsNothing);
    expect(
      find.text(
        'Modo demonstração: os dados são de exemplo e não são sincronizados. '
        'Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY para usar sua conta.',
      ),
      findsOneWidget,
    );
    expect(find.text('Período selecionado'), findsOneWidget);
    expect(find.text('Mês selecionado'), findsOneWidget);
    final reportPeriodDropdown = find.byType(DropdownButton<DateTime>);
    final dropdown = tester.widget<DropdownButton<DateTime>>(
      reportPeriodDropdown,
    );
    expect(dropdown.items, hasLength(4));

    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final previousMonth = DateTime(currentMonth.year, currentMonth.month - 1);
    final previousMonthLabel = intl.DateFormat(
      'MMMM yyyy',
      'pt_BR',
    ).format(previousMonth);
    await tester.tap(reportPeriodDropdown);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        '${previousMonthLabel[0].toUpperCase()}'
        '${previousMonthLabel.substring(1)}',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<DateTime>>(reportPeriodDropdown).value,
      previousMonth,
    );

    await tester.scrollUntilVisible(
      find.text('Agenda do salão'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Agenda do salão'), findsOneWidget);
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Expediente'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Clientes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente de demonstração'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Adicionar profissional'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Adicionar profissional'), findsOneWidget);
    expect(find.text('Toda equipe'), findsNothing);
    expect(find.text('Sem profissional vinculado'), findsNothing);
    expect(find.text('Tati'), findsOneWidget);
    expect(find.byTooltip('Novo agendamento para Tati'), findsOneWidget);
    await tester.tap(find.byTooltip('Ações de Tati'));
    await tester.pumpAndSettle();
    expect(find.text('Link de acesso individual'), findsOneWidget);
    expect(find.text('Definir ou alterar PIN'), findsOneWidget);
    expect(find.text('Remover PIN'), findsOneWidget);
    expect(find.text('Excluir profissional'), findsOneWidget);
    await tester.tap(find.text('Definir ou alterar PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '123456',
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar PIN'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Salvar PIN'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('PIN de Tati'), findsNothing);
    await tester.tap(find.byTooltip('Ações de Tati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Definir ou alterar PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Ações de Tati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link de acesso individual'));
    await tester.pumpAndSettle();
    expect(find.text('Acesso de Tati'), findsOneWidget);
    final linkFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data?.contains('/#/equipe/demo-team-tati') ?? false),
    );
    expect(linkFinder, findsOneWidget);
    final linkText = tester.widget<SelectableText>(linkFinder);
    final accessLink = linkText.data!;
    expect(linkText.maxLines, 1);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    expect(linkText.style?.decoration, TextDecoration.underline);
    expect(linkText.style?.color, isNotNull);
    expect(accessLink.trim(), accessLink);
    expect(accessLink, Uri.parse(accessLink).toString());
    expect(Uri.parse(accessLink).fragment, '/equipe/demo-team-tati');
    expect(find.text('Abrir no navegador'), findsOneWidget);

    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(find.text('Copiar link'));
    await tester.pumpAndSettle();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    expect(copiedText, accessLink);
    expect(copiedText!.trim(), copiedText);
    expect(copiedText, isNot(contains('\n')));
    expect(find.text('Cliente de demonstração'), findsNWidgets(2));
    final horizontalListFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalListFinder, findsOneWidget);
    final horizontalList = tester.widget<ListView>(horizontalListFinder);
    expect(horizontalList.controller, isNotNull);
    expect(
      horizontalList.padding?.resolve(TextDirection.ltr).right,
      greaterThanOrEqualTo(16),
    );
    final visibleScrollbar = tester.widget<Scrollbar>(
      find.byWidgetPredicate(
        (widget) => widget is Scrollbar && widget.thumbVisibility == true,
      ),
    );
    expect(visibleScrollbar.controller, horizontalList.controller);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ScrollConfiguration &&
            widget.behavior.dragDevices.contains(PointerDeviceKind.mouse),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Corte + barba'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Corte + barba'), findsOneWidget);
    final appointmentActions = tester.widget<PopupMenuButton<String>>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is PopupMenuButton<String> &&
                widget.tooltip == 'Atualizar atendimento',
          )
          .first,
    );
    expect(appointmentActions.constraints!.minWidth, greaterThanOrEqualTo(240));
    expect(appointmentActions.constraints!.maxWidth, greaterThanOrEqualTo(320));
    await tester.scrollUntilVisible(
      find.text('+ Novo Agendamento'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('+ Novo Agendamento'));
    await tester.pumpAndSettle();
    expect(
      find.text('Busque por nome/telefone ou digite um novo nome'),
      findsOneWidget,
    );
    expect(find.text('Profissional'), findsOneWidget);
    expect(find.text('Telefone do novo cliente'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Criar agendamento'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Criar agendamento'),
    );
    expect(createButton.onPressed, isNull);
  });

  testWidgets('professional settings hides payment and package controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfessionalSettingsPage(
          professionalId: 'demo-professional',
          demoMode: true,
          repository: SalonRepository(client: null, demoMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Horários de atendimento'), findsOneWidget);
    expect(find.text('Dias de expediente'), findsOneWidget);
    expect(find.text('Pausa para almoço (opcional)'), findsOneWidget);
    expect(find.text('Aceitar pagamento no local'), findsNothing);
    expect(find.text('Chave PIX para clientes'), findsNothing);
    expect(find.text('Ativar planos e pacotes'), findsNothing);
  });

  testWidgets('public booking requires selecting a team member', (
    tester,
  ) async {
    final repository = SalonRepository(client: null, demoMode: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PublicBookingPage(
          professionalId: 'demo-professional',
          repository: repository,
          demoMode: true,
          themeController: ThemeController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profissional'), findsOneWidget);
    expect(
      find.text('Selecione um profissional para consultar os horários.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Confirmar agendamento'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar agendamento'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('team member PIN unlocks scoped agenda and client actions', (
    tester,
  ) async {
    final repository = _TeamMemberAccessRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamMemberAccessPage(
          teamMemberId: 'team-1',
          repository: repository,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Acessar minha agenda'));
    await tester.pumpAndSettle();

    expect(find.text('Ronaldo'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.text('Cliente da equipe'), findsOneWidget);
    expect(find.text('Novo Agendamento'), findsOneWidget);
    expect(find.text('Meus clientes'), findsOneWidget);
    final appointmentCard = tester.widget<AppointmentCard>(
      find.byType(AppointmentCard).first,
    );
    expect(appointmentCard.margin, const EdgeInsets.symmetric(vertical: 4));
    await tester.tap(find.text('Novo Agendamento'));
    await tester.pumpAndSettle();
    expect(find.text('Agendamento para Ronaldo'), findsOneWidget);
    expect(find.text('Profissional: Ronaldo'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<SalonService>));
    await tester.pumpAndSettle();
    expect(find.text('Corte · 30 min'), findsOneWidget);
    expect(repository.lastLoadedServicesToken, 'session-token');
    await tester.tap(find.text('Corte · 30 min').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações do atendimento'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar como concluído'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.lastUpdatedStatus, 'cancelado');

    await tester.tap(find.text('Meus clientes'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar Cliente da equipe'), findsOneWidget);
  });

  testWidgets(
    'manual booking disables slots overlapping occupied appointments',
    (tester) async {
      final day = DateTime.now().add(const Duration(days: 1));
      final repository = _TeamMemberAccessRepository(
        occupiedPeriods: [
          OccupiedPeriod(
            startsAt: DateTime(day.year, day.month, day.day, 9),
            endsAt: DateTime(day.year, day.month, day.day, 10),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ManualAppointmentPage(
            professionalId: 'demo-professional',
            repository: repository,
            initialTeamMemberId: 'demo-team-tati',
            initialTeamMemberName: 'Tati',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<SalonService>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corte · 30 min').last);
      await tester.pumpAndSettle();

      ChoiceChip slot(String label) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(slot('9:00 AM').onSelected, isNull);
      expect(slot('9:30 AM').onSelected, isNull);
      expect(slot('10:00 AM').onSelected, isNotNull);
    },
  );

  testWidgets('team status update does not refresh after page is disposed', (
    tester,
  ) async {
    final updateCompleter = Completer<void>();
    final repository = _TeamMemberAccessRepository(
      updateStatusCompleter: updateCompleter,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeamMemberAccessPage(
          teamMemberId: 'team-1',
          repository: repository,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Acessar minha agenda'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações do atendimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como concluído'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    updateCompleter.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expired team session is sent directly without PIN reauthentication',
    (tester) async {
      final repository = _TeamMemberAccessRepository(
        expireNextAppointmentCreation: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TeamMemberAccessPage(
            teamMemberId: 'team-1',
            repository: repository,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Acessar minha agenda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo Agendamento'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cliente da equipe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<SalonService>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corte · 30 min').last);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byType(ChoiceChip).first,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.scrollUntilVisible(
        find.text('Criar agendamento'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Criar agendamento'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.authenticationPins, ['123456']);
      expect(repository.createdWithTokens, ['session-token']);
      expect(find.textContaining('Sessão expirada'), findsOneWidget);
      expect(find.text('Novo Agendamento'), findsOneWidget);
    },
  );

  testWidgets('PIN agenda remains visible if loading clients fails', (
    tester,
  ) async {
    final repository = _TeamMemberAccessRepository(failLoadingClients: true);
    await tester.pumpWidget(
      MaterialApp(
        home: TeamMemberAccessPage(
          teamMemberId: 'team-1',
          repository: repository,
          initialDay: DateTime(2026, 11, 2),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Acessar minha agenda'));
    await tester.pumpAndSettle();

    expect(repository.lastRequestedDay, DateTime(2026, 11, 2));
    expect(find.text('Cliente da equipe'), findsOneWidget);
    expect(find.text('Nenhum atendimento agendado neste dia.'), findsNothing);
    expect(
      find.textContaining('Não foi possível carregar a lista de clientes'),
      findsOneWidget,
    );
  });

  testWidgets(
    'team member access link can initialize the selected agenda day',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TeamMemberAccessPage(
            teamMemberId: 'member-1',
            repository: _TeamMemberAccessRepository(),
            initialDay: DateTime(2026, 11, 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('novembro'), findsOneWidget);
    },
  );

  test('theme options are saved by their stable enum name', () async {
    final themeController = ThemeController();
    await themeController.load();
    await themeController.select(AppThemeOption.colorfulDark);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('preferred_theme'), 'colorfulDark');
    expect(themeController.selected.mode.name, 'dark');
    expect(themeController.selected.colorful, isTrue);
  });

  test('public app links use configured base and preserve hash routes', () {
    final link = AppConfig.publicAppUrl(
      '/equipe/team-member-1',
      baseUrl: 'https://agenda.example.com/',
      currentUri: Uri.parse('http://localhost:5000/#/'),
    );
    expect(
      link.toString(),
      'https://agenda.example.com/#/equipe/team-member-1',
    );
  });

  test(
    'public app links default to the deployed web app on native platforms',
    () {
      final link = AppConfig.publicAppUrl(
        '/agendar/professional-1',
        currentUri: Uri.parse('file:///data/app/agenda'),
      );
      expect(
        link.toString(),
        'https://agenda-pro-sp.netlify.app/#/agendar/professional-1',
      );
    },
  );

  test('public app links accept a configured Flutter web root hash', () {
    final link = AppConfig.publicAppUrl(
      '/agendar/professional-1',
      baseUrl: 'https://agenda.example.com/#/',
    );
    expect(
      link.toString(),
      'https://agenda.example.com/#/agendar/professional-1',
    );
  });

  test('public app links reject non-root fragments and query strings', () {
    expect(
      () => AppConfig.publicAppUrl(
        '/agendar/professional-1',
        baseUrl: 'https://agenda.example.com/#/other',
      ),
      throwsFormatException,
    );
    expect(
      () => AppConfig.publicAppUrl(
        '/agendar/professional-1',
        baseUrl: 'https://agenda.example.com/?preview=true',
      ),
      throwsFormatException,
    );
  });

  test('public app links use local development origin without config', () {
    final link = AppConfig.publicAppUrl(
      '/equipe/team-member-1',
      baseUrl: '',
      currentUri: Uri.parse('http://localhost:62185/#/'),
    );
    expect(link.toString(), 'http://localhost:62185/#/equipe/team-member-1');
  });

  test('public app links require a configured base for native URIs', () {
    expect(
      () => AppConfig.publicAppUrl(
        '/agendar/professional-1',
        baseUrl: '',
        currentUri: Uri.parse('file:///data/app/agenda'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('deve ser configurada'),
        ),
      ),
    );
  });

  test(
    'service queries return only the requested professional catalog',
    () async {
      final repository = SalonRepository(client: null, demoMode: true);

      final professionalServices = await repository.listServices(
        'demo-professional',
      );
      final unrelatedProfessionalServices = await repository.listServices(
        'another-professional',
      );

      expect(professionalServices, isNotEmpty);
      expect(
        professionalServices.every(
          (service) => service.professionalId == 'demo-professional',
        ),
        isTrue,
      );
      expect(unrelatedProfessionalServices, isEmpty);
    },
  );

  testWidgets('manual booking services load without a selected team member', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualAppointmentPage(
          professionalId: 'demo-professional',
          repository: SalonRepository(client: null, demoMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selecione um profissional'), findsOneWidget);
    expect(find.text('Serviço'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<SalonService>));
    await tester.pumpAndSettle();
    expect(find.text('Corte clássico · 40 min'), findsOneWidget);
  });

  test('service numeric fields accept numeric strings from the database', () {
    final service = SalonService.fromMap({
      'id': 'service-1',
      'profissional_id': 'professional-1',
      'titulo': 'Corte',
      'categoria': 'Cabelo',
      'preco': '45.50',
      'duracao_minutos': '30',
    });

    expect(service.price, 45.5);
    expect(service.durationMinutes, 30);
  });

  test('salon schedule includes all team appointments', () async {
    final repository = SalonRepository(client: null, demoMode: true);

    final team = await repository.listTeamMembers('demo-professional');
    final unrelatedTeam = await repository.listTeamMembers('another-salon');
    final appointments = await repository.listAppointments(
      'demo-professional',
      DateTime.now(),
    );

    expect(team.map((member) => member.name), contains('Tati'));
    expect(unrelatedTeam, isEmpty);
    expect(appointments.map((appointment) => appointment.id), [
      'demo-1',
      'demo-2',
    ]);
  });

  test('new salon clients are saved and isolated to their salon', () async {
    final repository = SalonRepository(client: null, demoMode: true);
    final saved = await repository.saveSalonClient(
      professionalId: 'demo-professional',
      name: 'Cliente novo',
      phone: '(11) 99999-1234',
    );
    final service = (await repository.listServices('demo-professional')).first;
    final appointmentTime = DateTime.now().add(const Duration(days: 1));
    await repository.createAppointment(
      professionalId: 'demo-professional',
      salonClientId: saved.salonClientId,
      service: service,
      startsAt: appointmentTime,
      paymentType: PaymentType.local,
      teamMemberId: 'demo-team-tati',
    );

    expect(saved.name, 'Cliente novo');
    expect(saved.phone, '(11) 99999-1234');
    expect(saved.isSalonContact, isTrue);

    final salonClients = await repository.listClients('demo-professional');
    final otherSalonClients = await repository.listClients('another-salon');
    final appointments = await repository.listAppointments(
      'demo-professional',
      appointmentTime,
    );
    expect(salonClients.any((client) => client.id == saved.id), isTrue);
    expect(otherSalonClients, isEmpty);
    expect(appointments.last.salonClientId, saved.id);
    expect(appointments.last.clientId, isNull);
    expect(appointments.last.teamMemberId, 'demo-team-tati');
  });

  test('appointment creation requires a team member', () async {
    final repository = SalonRepository(client: null, demoMode: true);
    final service = (await repository.listServices('demo-professional')).first;

    expect(
      () => repository.createAppointment(
        professionalId: 'demo-professional',
        salonClientId: 'demo-client',
        service: service,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        paymentType: PaymentType.local,
        teamMemberId: ' ',
      ),
      throwsArgumentError,
    );
  });

  test(
    'availability RPC rejects malformed profile and team IDs locally',
    () async {
      final repository = SalonRepository(
        client: SupabaseClient('https://example.supabase.co', 'test-key'),
        demoMode: false,
      );

      await expectLater(
        repository.listOccupiedPeriods(
          'not-a-uuid',
          DateTime(2026, 11, 2),
          teamMemberId: '00000000-0000-4000-8000-000000000001',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.listOccupiedPeriods(
          '00000000-0000-4000-8000-000000000002',
          DateTime(2026, 11, 2),
          teamMemberId: 'not-a-uuid',
        ),
        throwsArgumentError,
      );
    },
  );

  test('team agenda RPC rejects empty session tokens locally', () async {
    final repository = SalonRepository(
      client: SupabaseClient('https://example.supabase.co', 'test-key'),
      demoMode: false,
    );

    await expectLater(
      repository.listTeamMemberAppointments('  ', day: DateTime(2026, 11, 2)),
      throwsArgumentError,
    );
  });

  testWidgets('salon clients can be edited and deleted after confirmation', (
    tester,
  ) async {
    final repository = SalonRepository(client: null, demoMode: true);
    final client = await repository.saveSalonClient(
      professionalId: 'demo-professional',
      name: 'Cliente editável',
      phone: '11912345678',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ClientsManagementPage(
          professionalId: 'demo-professional',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar cliente').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Cliente atualizado',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '11987654321');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Cliente atualizado'), findsOneWidget);
    final updatedClients = await repository.listClients('demo-professional');
    expect(
      updatedClients.any(
        (item) =>
            item.id == client.id &&
            item.name == 'Cliente atualizado' &&
            item.phone == '11987654321',
      ),
      isTrue,
    );

    await tester.tap(find.byTooltip('Excluir cliente').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Tem certeza que deseja excluir este cliente?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      (await repository.listClients('demo-professional'))
          .any((item) => item.id == client.id),
      isTrue,
    );

    await tester.tap(find.byTooltip('Excluir cliente').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(
      (await repository.listClients('demo-professional'))
          .any((item) => item.id == client.id),
      isFalse,
    );
  });

  test('appointment model reads team assignment from team_member_id', () {
    final appointment = Appointment.fromMap({
      'id': 'appointment-1',
      'profissional_id': 'professional-1',
      'cliente_id': 'client-1',
      'cliente': {'nome': 'Ana Souza'},
      'servico_id': 'service-1',
      'servicos': {'titulo': 'Corte'},
      'data_hora_inicio': '2026-10-20T12:00:00.000Z',
      'tipo_pagamento': 'local',
      'valor': '45.00',
      'status': 'confirmado',
      'team_member_id': 'member-1',
    });

    expect(appointment.teamMemberId, 'member-1');
    expect(appointment.clientName, 'Ana Souza');
  });

  test('appointment model parses the synchronized team agenda RPC shape', () {
    final appointment = Appointment.fromTeamAgendaMap({
      'appointment_id': 'appointment-1',
      'professional_id': 'professional-1',
      'client_id': null,
      'salon_client_id': 'salon-client-1',
      'service_id': 'service-1',
      'team_member_id': 'member-1',
      'appointment_starts_at': '2026-10-20T12:00:00.000Z',
      'service_title': 'Corte',
      'client_name': 'Ana Souza',
      'appointment_value': '45.00',
      'payment_type': 'local',
      'appointment_status': 'confirmado',
    });

    expect(appointment.id, 'appointment-1');
    expect(appointment.professionalId, 'professional-1');
    expect(appointment.salonClientId, 'salon-client-1');
    expect(appointment.teamMemberId, 'member-1');
    expect(appointment.serviceTitle, 'Corte');
    expect(appointment.clientName, 'Ana Souza');
    expect(appointment.value, 45);
    expect(appointment.paymentType, PaymentType.local);
  });

  test('team member agenda rows parse management fields', () {
    final row = {
      'appointment_id': 'appointment-1',
      'appointment_starts_at': '2026-10-20T12:00:00.000Z',
      'service_title': 'Corte',
      'client_name': 'Ana Souza',
      'appointment_value': '45.00',
      'appointment_status': 'confirmado',
    };
    final item = TeamMemberAgendaItem.fromMap(row);

    expect(item.serviceTitle, 'Corte');
    expect(item.appointmentId, 'appointment-1');
    expect(item.clientName, 'Ana Souza');
    expect(item.value, 45);
    expect(item.status, 'confirmado');
  });

  test(
    'team member agenda accepts list, singleton map, and empty responses',
    () {
      final row = {
        'appointment_id': 'appointment-1',
        'appointment_starts_at': '2026-10-20T12:00:00.000Z',
        'service_title': 'Corte',
        'client_name': 'Ana Souza',
        'appointment_value': 45,
        'appointment_status': 'confirmado',
      };

      expect(TeamMemberAgendaItem.listFromRpcResponse([row]), hasLength(1));
      expect(TeamMemberAgendaItem.listFromRpcResponse(row), hasLength(1));
      expect(TeamMemberAgendaItem.listFromRpcResponse(null), isEmpty);
      expect(TeamMemberAgendaItem.listFromRpcResponse([]), isEmpty);
      expect(
        () => TeamMemberAgendaItem.listFromRpcResponse({'unexpected': true}),
        throwsFormatException,
      );
      expect(
        () => TeamMemberAgendaItem.listFromRpcResponse([
          {'appointment_id': '1'},
        ]),
        throwsFormatException,
      );
    },
  );
}

class _TeamMemberAccessRepository extends SalonRepository {
  _TeamMemberAccessRepository({
    this.failLoadingClients = false,
    this.expireNextAppointmentCreation = false,
    this.updateStatusCompleter,
    this.occupiedPeriods = const [],
  }) : super(client: null, demoMode: true);

  final bool failLoadingClients;
  bool expireNextAppointmentCreation;
  final Completer<void>? updateStatusCompleter;
  final List<OccupiedPeriod> occupiedPeriods;
  final List<String> authenticationPins = [];
  final List<String> createdWithTokens = [];
  String? lastUpdatedStatus;
  String? lastLoadedServicesToken;
  DateTime? lastRequestedDay;

  @override
  Future<TeamMemberAccessSession> authenticateTeamMemberAccess({
    required String teamMemberId,
    required String pin,
  }) async {
    authenticationPins.add(pin);
    return const TeamMemberAccessSession(
      accessToken: 'session-token',
      teamMemberId: 'team-1',
      teamMemberName: 'Ronaldo',
      professionalId: 'salon-1',
    );
  }

  @override
  Future<List<TeamMemberAgendaItem>> listTeamMemberAppointments(
    String accessToken, {
    DateTime? day,
  }) async {
    lastRequestedDay = day;
    return [
      TeamMemberAgendaItem(
        appointmentId: 'appointment-1',
        startsAt: DateTime(day!.year, day.month, day.day, 9, 30),
        clientName: 'Cliente da equipe',
        serviceTitle: 'Corte',
        value: 45,
        status: 'confirmado',
      ),
    ];
  }

  @override
  Future<List<SalonClient>> listTeamMemberClients(String accessToken) async {
    if (failLoadingClients) {
      throw StateError('Falha simulada ao carregar clientes.');
    }
    return const [
      SalonClient(
        id: 'client-1',
        salonClientId: 'client-1',
        name: 'Cliente da equipe',
        phone: '11999990000',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> loadSettings(String professionalId) async {
    return {
      'horario_inicio': '09:00',
      'horario_fim': '18:00',
      'almoco_inicio': null,
      'almoco_fim': null,
      'dias_abertos': [1, 2, 3, 4, 5, 6, 7],
      'dias_folga': <String>[],
    };
  }

  @override
  Future<List<SalonService>> listServices(String professionalId) async {
    return const [
      SalonService(
        id: 'service-1',
        professionalId: 'salon-1',
        title: 'Corte',
        category: 'Cabelo',
        price: 45,
        durationMinutes: 30,
      ),
    ];
  }

  @override
  Future<List<SalonService>> listTeamMemberServices(String accessToken) async {
    lastLoadedServicesToken = accessToken;
    return listServices('salon-1');
  }

  @override
  Future<List<OccupiedPeriod>> listOccupiedPeriods(
    String professionalId,
    DateTime day, {
    String? teamMemberId,
  }) async {
    return occupiedPeriods;
  }

  @override
  Future<void> createTeamMemberAppointment({
    required String accessToken,
    required String clientId,
    required SalonService service,
    required DateTime startsAt,
  }) async {
    createdWithTokens.add(accessToken);
    if (expireNextAppointmentCreation) {
      expireNextAppointmentCreation = false;
      throw PostgrestException(
        message: 'Sessão expirada. Informe novamente o PIN.',
        code: 'P0001',
      );
    }
  }

  @override
  Future<void> updateTeamMemberAppointmentStatus({
    required String accessToken,
    required String appointmentId,
    required String status,
  }) async {
    lastUpdatedStatus = status;
    await updateStatusCompleter?.future;
  }
}
