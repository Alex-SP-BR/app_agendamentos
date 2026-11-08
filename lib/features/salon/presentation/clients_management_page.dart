import 'package:flutter/material.dart';

import '../data/salon_repository.dart';
import '../models/salon_client.dart';

class ClientsManagementPage extends StatefulWidget {
  const ClientsManagementPage({
    required this.professionalId,
    required this.repository,
    super.key,
  });

  final String professionalId;
  final SalonRepository repository;

  @override
  State<ClientsManagementPage> createState() => _ClientsManagementPageState();
}

class _ClientsManagementPageState extends State<ClientsManagementPage> {
  late Future<List<SalonClient>> _clientsFuture;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  void _loadClients() {
    _clientsFuture = widget.repository.listClients(widget.professionalId);
  }

  Future<void> _editClient(SalonClient client) async {
    final formKey = GlobalKey<FormState>();
    var name = client.name;
    var phone = client.phone;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar cliente'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: client.name,
                decoration: const InputDecoration(labelText: 'Nome'),
                onSaved: (value) => name = value!.trim(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome do cliente.'
                    : null,
              ),
              TextFormField(
                initialValue: client.phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
                onSaved: (value) => phone = value!.trim(),
                validator: (value) {
                  final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                  return digits.length < 8 || digits.length > 15
                      ? 'Informe um telefone válido.'
                      : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(context, true);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.updateSalonClient(
        professionalId: widget.professionalId,
        clientId: client.salonClientId!,
        name: name,
        phone: phone,
      );
      if (!mounted) return;
      setState(_loadClients);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente atualizado com sucesso.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar o cliente.')),
      );
    }
  }

  Future<void> _deleteClient(SalonClient client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir cliente'),
        content: const Text('Tem certeza que deseja excluir este cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteSalonClient(
        professionalId: widget.professionalId,
        clientId: client.salonClientId!,
      );
      if (!mounted) return;
      setState(_loadClients);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente excluído com sucesso.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir o cliente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: FutureBuilder<List<SalonClient>>(
        future: _clientsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro ao carregar clientes: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Ainda não há clientes cadastrados neste salão.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_loadClients);
              await _clientsFuture;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final client = snapshot.data![index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(client.name),
                    subtitle: Text(
                      client.phone.isEmpty
                          ? 'Telefone não informado'
                          : client.phone,
                    ),
                    trailing: client.isSalonContact
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar cliente',
                                onPressed: () => _editClient(client),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Excluir cliente',
                                onPressed: () => _deleteClient(client),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
