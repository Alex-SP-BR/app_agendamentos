import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeOption {
  light('Claro'),
  dark('Escuro'),
  colorfulLight('Colorido claro'),
  colorfulDark('Colorido escuro');

  const AppThemeOption(this.label);
  final String label;

  ThemeMode get mode => switch (this) {
    AppThemeOption.light || AppThemeOption.colorfulLight => ThemeMode.light,
    AppThemeOption.dark || AppThemeOption.colorfulDark => ThemeMode.dark,
  };

  bool get colorful =>
      this == AppThemeOption.colorfulLight ||
      this == AppThemeOption.colorfulDark;
}

class ThemeController extends ChangeNotifier {
  static const _storageKey = 'preferred_theme';
  AppThemeOption _selected = AppThemeOption.light;

  AppThemeOption get selected => _selected;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedName = preferences.getString(_storageKey);
    _selected = AppThemeOption.values.firstWhere(
      (option) => option.name == storedName,
      orElse: () => AppThemeOption.light,
    );
  }

  Future<void> select(AppThemeOption option) async {
    _selected = option;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, option.name);
  }
}
