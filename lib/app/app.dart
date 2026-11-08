import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_themes.dart';
import '../core/theme/theme_controller.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/booking/presentation/public_booking_page.dart';
import '../features/dashboard/presentation/professional_dashboard_page.dart';
import '../features/dashboard/data/report_repository.dart';
import '../features/salon/data/salon_repository.dart';
import '../features/salon/presentation/team_member_access_page.dart';

class SalonApp extends StatelessWidget {
  const SalonApp({
    required this.themeController,
    required this.supabaseConfigured,
    this.publicAppBaseUrl,
    super.key,
  });

  final ThemeController themeController;
  final bool supabaseConfigured;
  final String? publicAppBaseUrl;

  SalonRepository get _salonRepository => SalonRepository(
    client: supabaseConfigured ? Supabase.instance.client : null,
    demoMode: !supabaseConfigured,
  );

  ReportRepository get _reportRepository => ReportRepository(
    client: supabaseConfigured ? Supabase.instance.client : null,
    demoMode: !supabaseConfigured,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final option = themeController.selected;
        return MaterialApp(
          title: 'Agenda Pro',
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: createAppTheme(dark: false, colorful: option.colorful),
          darkTheme: createAppTheme(dark: true, colorful: option.colorful),
          themeMode: option.mode,
          onGenerateRoute: (settings) {
            final path = settings.name ?? '/';
            final routeUri = Uri.tryParse(path);
            final routePath = routeUri?.path ?? path;
            final bookingMatch = RegExp(
              r'^/agendar/([^/]+)$',
            ).firstMatch(routePath);
            final teamMemberMatch = RegExp(r'^/equipe/([^/]+)$')
                .firstMatch(routePath);
            if (teamMemberMatch != null) {
              if (!supabaseConfigured) {
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => const Scaffold(
                    body: Center(
                      child: Text(
                        'O acesso da equipe requer conexão com o Supabase.',
                      ),
                    ),
                  ),
                );
              }
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => TeamMemberAccessPage(
                  teamMemberId: teamMemberMatch.group(1)!,
                  repository: _salonRepository,
                  initialDay: DateTime.tryParse(
                    routeUri?.queryParameters['day'] ?? '',
                  ),
                ),
              );
            }
            if (bookingMatch != null) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => PublicBookingPage(
                  professionalId: bookingMatch.group(1)!,
                  repository: _salonRepository,
                  demoMode: !supabaseConfigured,
                  themeController: themeController,
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => _home(),
            );
          },
        );
      },
    );
  }

  Widget _home() {
    if (!supabaseConfigured) {
      return ProfessionalDashboardPage(
        professionalId: 'demo-professional',
        demoMode: true,
        salonRepository: _salonRepository,
        reportRepository: _reportRepository,
        themeController: themeController,
        publicAppBaseUrl:
            publicAppBaseUrl ?? AppConfig.teamMemberAccessBaseUrl,
      );
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          return AuthPage(
            client: Supabase.instance.client,
            themeController: themeController,
            authErrorMessage: snapshot.hasError ? _authFailureMessage() : null,
          );
        }
        return FutureBuilder<Map<String, dynamic>?>(
          future: _loadProfile(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Não foi possível confirmar os dados da sua conta. '
                          'Tente novamente mais tarde.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final profile = profileSnapshot.data;
            final isPlatformAdmin = user.appMetadata['role'] == 'admin';

            if (profile == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Agenda Pro')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Conta não encontrada. Verifique os seus dados ou '
                          'crie uma nova conta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (!isPlatformAdmin && profile['tipo'] != 'profissional') {
              return Scaffold(
                appBar: AppBar(title: const Text('Agenda Pro')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Esta conta não tem acesso profissional ao Agenda Pro.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final accessStatus = profile['status_acesso'] as String?;
            if (!isPlatformAdmin &&
                accessStatus != 'ativo' &&
                accessStatus != 'cortesia') {
              return _accessStatusNotice(
                accessStatus ?? 'pendente',
                profile['plano_assinatura'] as String? ?? 'gratis',
              );
            }

            return ProfessionalDashboardPage(
              professionalId: user.id,
              professionalName: profile['nome'] as String?,
              demoMode: false,
              isPlatformAdmin: isPlatformAdmin,
              salonRepository: _salonRepository,
              reportRepository: _reportRepository,
              themeController: themeController,
              publicAppBaseUrl:
                  publicAppBaseUrl ?? AppConfig.teamMemberAccessBaseUrl,
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _loadProfile(User user) {
    return Supabase.instance.client
        .from('perfis')
        .select('nome, tipo, status_acesso, plano_assinatura')
        .eq('id', user.id)
        .maybeSingle();
  }

  Widget _accessStatusNotice(String status, String plan) {
    final message = switch (status) {
      'bloqueado' => 'O acesso a esta conta está bloqueado.',
      'recusado' =>
        'O pedido de ativação foi recusado. Entre em contato '
            'com o responsável pela conta para solicitar uma nova avaliação.',
      'pendente' => 'A conta aguarda ativação ou confirmação do pagamento.',
      _ => 'O status desta conta não permite o acesso ao painel.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Ativação da conta')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_outlined, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Plano: $plan', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              const Text(
                'Entre em contato com o responsável pela conta para obter '
                'mais informações.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _authFailureMessage() {
    return 'Não foi possível iniciar sessão. '
        'Verifique os seus dados e tente novamente.';
  }
}
