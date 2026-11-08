import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_selector_button.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.client,
    required this.themeController,
    this.authErrorMessage,
    super.key,
  });

  final SupabaseClient client;
  final ThemeController themeController;
  final String? authErrorMessage;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_creatingAccount) {
        final response = await widget.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'nome': _nameController.text.trim(), 'tipo': 'profissional'},
        );
        if (mounted && response.session == null) {
          setState(() {
            _creatingAccount = false;
            _nameController.clear();
            _passwordController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cadastro concluído. Confirme seu e-mail e entre na sua conta.',
              ),
            ),
          );
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } catch (_) {
      if (mounted) {
        _showError(
          _creatingAccount
              ? 'Não foi possível criar a conta. Verifique os dados e tente novamente.'
              : 'Não foi possível iniciar sessão. Verifique o e-mail e a '
                    'palavra-passe e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final launched = await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? Uri.base.origin
            : 'io.supabase.agendapro://login-callback',
      );
      if (!launched && mounted) {
        _showError(
          'Não foi possível iniciar sessão com o Google. Tente novamente.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showError(
          'Não foi possível iniciar sessão com o Google. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colorScheme.error,
        content: Text(message, style: TextStyle(color: colorScheme.onError)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda Pro'),
        actions: [ThemeSelectorButton(controller: widget.themeController)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.spa,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _creatingAccount ? 'Crie sua conta' : 'Bem-vindo(a)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (widget.authErrorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.authErrorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_creatingAccount) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Nome'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Informe seu nome'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Informe um e-mail válido'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Senha'),
                        validator: (value) => value == null || value.length < 6
                            ? 'Use pelo menos 6 caracteres'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(
                          _loading
                              ? 'Aguarde...'
                              : _creatingAccount
                              ? 'Criar conta'
                              : 'Entrar',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Entrar com o Google (Gmail)'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sua sessão permanece salva neste dispositivo.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(
                                () => _creatingAccount = !_creatingAccount,
                              ),
                        child: Text(
                          _creatingAccount
                              ? 'Já tenho uma conta'
                              : 'Criar uma conta',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
