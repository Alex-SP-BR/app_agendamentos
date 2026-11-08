import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/salon_repository.dart';
import '../models/salon_service.dart';
import 'service_form_page.dart';

class ServicesManagementPage extends StatefulWidget {
  const ServicesManagementPage({
    required this.professionalId,
    required this.demoMode,
    required this.repository,
    super.key,
  });

  final String professionalId;
  final bool demoMode;
  final SalonRepository repository;

  @override
  State<ServicesManagementPage> createState() => _ServicesManagementPageState();
}

class _ServicesManagementPageState extends State<ServicesManagementPage> {
  late Future<List<SalonService>> _services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _services = widget.repository.listServices(widget.professionalId);
  }

  Future<void> _editService([SalonService? service]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ServiceFormPage(
          professionalId: widget.professionalId,
          repository: widget.repository,
          service: service,
        ),
      ),
    );
    if (!mounted) return;
    if (saved != true) return;
    setState(_load);
  }

  Future<void> _deactivate(SalonService service) async {
    try {
      await widget.repository.deactivateService(service.id);
      if (!mounted) return;
      setState(_load);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível salvar o serviço: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Scaffold(
      appBar: AppBar(title: const Text('Meus serviços')),
      floatingActionButton: widget.demoMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editService(),
              icon: const Icon(Icons.add),
              label: const Text('Novo serviço'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.demoMode)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Os serviços de demonstração são somente para visualização.',
                ),
              ),
            ),
          FutureBuilder<List<SalonService>>(
            future: _services,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Erro ao carregar serviços: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Text('Cadastre seu primeiro serviço.');
              }
              return Column(
                children: snapshot.data!
                    .map(
                      (service) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(service.title),
                          subtitle: Text(
                            '${service.category} · ${service.durationMinutes} min',
                          ),
                          trailing: SizedBox(
                            width: 145,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(currency.format(service.price)),
                                if (!widget.demoMode) ...[
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: () => _editService(service),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Desativar',
                                    onPressed: () => _deactivate(service),
                                    icon: const Icon(Icons.archive_outlined),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
