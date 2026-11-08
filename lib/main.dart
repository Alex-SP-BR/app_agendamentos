import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final themeController = ThemeController();
  await themeController.load();

  await Supabase.initialize(
    url: 'https://zsqiauvdwjvubwavzone.supabase.co',
    publishableKey: 'sb_publishable_3N_fc-XUAgccULeHlHQiBw_tvAnOsCx',
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: true),
  );

  runApp(SalonApp(themeController: themeController, supabaseConfigured: true));
}
