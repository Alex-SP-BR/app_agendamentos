import 'package:flutter/material.dart';

import 'theme_controller.dart';

class ThemeSelectorButton extends StatelessWidget {
  const ThemeSelectorButton({required this.controller, super.key});

  final ThemeController controller;

  Future<void> _showOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Tema do aplicativo')),
            RadioGroup<AppThemeOption>(
              groupValue: controller.selected,
              onChanged: (value) async {
                if (value == null) return;
                try {
                  await controller.select(value);
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Não foi possível salvar o tema: $error'),
                      ),
                    );
                  }
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: AppThemeOption.values
                    .map(
                      (option) => RadioListTile<AppThemeOption>(
                        title: Text(option.label),
                        value: option,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Tema',
    onPressed: () => _showOptions(context),
    icon: const Icon(Icons.palette_outlined),
  );
}
