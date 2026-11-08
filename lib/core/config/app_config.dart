class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const teamMemberAccessBaseUrl = String.fromEnvironment(
    'TEAM_MEMBER_ACCESS_BASE_URL',
    defaultValue: 'https://agenda-pro-sp.netlify.app',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static Uri publicAppUrl(String route, {String? baseUrl, Uri? currentUri}) {
    if (!route.startsWith('/')) {
      throw ArgumentError.value(route, 'route', 'A rota deve começar com /.');
    }
    final configuredBase = (baseUrl ?? teamMemberAccessBaseUrl).trim();
    final base = configuredBase.isEmpty
        ? currentUri ?? Uri.base
        : Uri.tryParse(configuredBase);
    final hasRootHashRoute =
        base != null &&
        base.hasFragment &&
        (base.fragment.isEmpty || base.fragment == '/');
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        !const {'http', 'https'}.contains(base.scheme.toLowerCase()) ||
        (configuredBase.isNotEmpty &&
            (base.hasQuery || (base.hasFragment && !hasRootHashRoute)))) {
      if (configuredBase.isEmpty) {
        throw const FormatException(
          'TEAM_MEMBER_ACCESS_BASE_URL deve ser configurada para compartilhar links em plataformas nativas.',
        );
      }
      throw FormatException(
        'TEAM_MEMBER_ACCESS_BASE_URL deve ser uma URL base pública http(s), sem query ou fragmento de rota (somente #/ é aceito).',
        configuredBase,
      );
    }
    final normalizedBase = Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
    ).toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase/#$route');
  }
}
