import 'package:flutter/material.dart';

import '../data/salon_repository.dart';

class TeamMemberFormPage extends StatefulWidget {
  const TeamMemberFormPage({
    required this.professionalId,
    required this.repository,
    super.key,
  });

  final String professionalId;
  final SalonRepository repository;

  @override
  State<TeamMemberFormPage> createState() => _TeamMemberFormPageState();
}

class _TeamMemberFormPageState extends State<TeamMemberFormPage> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.addTeamMember(
        widget.professionalId,
        _nameController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar à equipa: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar à equipa')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome do profissional',
                  hintText: 'Ex.: Tati',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome'
                    : null,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Salvando...' : 'Adicionar profissional'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
