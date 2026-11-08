import 'package:flutter/material.dart';

import '../data/salon_repository.dart';
import '../models/salon_service.dart';

class ServiceFormPage extends StatefulWidget {
  const ServiceFormPage({
    required this.professionalId,
    required this.repository,
    this.service,
    super.key,
  });

  final String professionalId;
  final SalonRepository repository;
  final SalonService? service;

  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final TextEditingController _durationController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _titleController = TextEditingController(text: service?.title ?? '');
    _categoryController = TextEditingController(text: service?.category ?? '');
    _priceController = TextEditingController(
      text: service?.price.toString() ?? '',
    );
    _durationController = TextEditingController(
      text: service?.durationMinutes.toString() ?? '30',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveService(
        id: widget.service?.id,
        professionalId: widget.professionalId,
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        price: double.parse(_priceController.text.trim().replaceAll(',', '.')),
        durationMinutes: int.parse(_durationController.text),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar o serviço: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.service == null ? 'Novo serviço' : 'Editar serviço'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Informações do serviço',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Nome do serviço'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Categoria'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe a categoria'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Preço (R\$)'),
                validator: (value) {
                  final parsed = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  return parsed == null || parsed < 0
                      ? 'Informe um preço válido'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duração (minutos)',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  return parsed == null || parsed < 5 || parsed > 600
                      ? 'Use um valor de 5 a 600 minutos'
                      : null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Salvando...' : 'Salvar serviço'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
