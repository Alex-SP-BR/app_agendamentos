import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializa o formato de data com tratamento de erro
  try {
    await initializeDateFormatting('pt_BR').timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Erro ao inicializar data formatting: $e');
  }

  // 2. Carrega o tema com proteção contra travamento
  final themeController = ThemeController();
  try {
    await themeController.load().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Erro ao carregar tema: $e');
  }

  // 3. Inicializa o Supabase com timeout de rede
  try {
    await Supabase.initialize(
      url: 'https://zsqiauvdwjvubwavzone.supabase.co',
      publishableKey: 'sb_publishable_3N_fc-XUAgccULeHlHQiBw_tvAnOsCx',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: true),
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Erro crítico ao inicializar Supabase: $e');
  }

  // Garante que o app sempre inicia a interface, mesmo se houver falhas nas etapas acima
  runApp(SalonApp(themeController: themeController, supabaseConfigured: true));
}