import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.startsAt,
    required this.clientName,
    required this.serviceTitle,
    required this.value,
    required this.status,
    required this.actionTooltip,
    required this.onStatusSelected,
    this.paymentLabel,
    this.cancelActionLabel = 'Cancelar atendimento',
    this.margin = const EdgeInsets.symmetric(vertical: 3),
    super.key,
  });

  final DateTime startsAt;
  final String clientName;
  final String serviceTitle;
  final double value;
  final String status;
  final String actionTooltip;
  final ValueChanged<String> onStatusSelected;
  final String? paymentLabel;
  final String cancelActionLabel;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(startsAt);
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final card = Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(
                time,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clientName.trim().isNotEmpty ? clientName : 'Cliente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          serviceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currency.format(value),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  if (paymentLabel != null)
                    Text(
                      paymentLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            if (status == 'pendente' || status == 'confirmado')
              PopupMenuButton<String>(
                tooltip: actionTooltip,
                onSelected: onStatusSelected,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
                iconSize: 20,
                itemBuilder: (context) => [
                  if (status == 'pendente')
                    const PopupMenuItem(
                      value: 'confirmado',
                      child: Text('Confirmar'),
                    ),
                  const PopupMenuItem(
                    value: 'concluido',
                    child: Text('Marcar como concluído'),
                  ),
                  PopupMenuItem(
                    value: 'cancelado',
                    child: Text(cancelActionLabel),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
    return card;
  }
}
