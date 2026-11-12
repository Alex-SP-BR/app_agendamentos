import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/financial_summary.dart';

class PdfReportService {
  Future<void> export(FinancialSummary summary) async {
    final document = pw.Document();
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final reportMonth = DateFormat(
      'MMMM yyyy',
      'pt_BR',
    ).format(summary.reportMonth);
    final serviceDetails = <String, Map<String, Map<int, int>>>{};
    for (final appointment in summary.appointments) {
      final service = appointment['servico']?.toString() ?? 'Serviço';
      final professional =
          appointment['profissional']?.toString() ??
          'Profissional não identificado';
      final valueInCents = ((appointment['valor'] as num) * 100).round();
      final quantities = serviceDetails
          .putIfAbsent(service, () => <String, Map<int, int>>{})
          .putIfAbsent(professional, () => <int, int>{});
      quantities.update(
        valueInCents,
        (quantity) => quantity + 1,
        ifAbsent: () => 1,
      );
    }

    int totalForService(Map<String, Map<int, int>> professionals) =>
        professionals.values.fold<int>(
          0,
          (total, prices) =>
              total +
              prices.entries.fold<int>(
                0,
                (sum, entry) => sum + entry.key * entry.value,
              ),
        );

    pw.Widget serviceCell(
      String text, {
      bool bold = false,
      double indent = 0,
      pw.Alignment alignment = pw.Alignment.centerLeft,
      PdfColor? color,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(6 + indent, 6, 6, 6),
        child: pw.Align(
          alignment: alignment,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      );
    }

    final sortedServices = serviceDetails.entries.toList()
      ..sort((left, right) {
        final totalComparison = totalForService(
          right.value,
        ).compareTo(totalForService(left.value));
        return totalComparison != 0
            ? totalComparison
            : left.key.compareTo(right.key);
      });
    final serviceTableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        children: [
          serviceCell(
            'Serviço / profissional',
            bold: true,
            color: PdfColors.white,
          ),
          serviceCell(
            'Qtd.',
            bold: true,
            alignment: pw.Alignment.center,
            color: PdfColors.white,
          ),
          serviceCell(
            'Valor unitário',
            bold: true,
            alignment: pw.Alignment.centerRight,
            color: PdfColors.white,
          ),
          serviceCell(
            'Total ganhos',
            bold: true,
            alignment: pw.Alignment.centerRight,
            color: PdfColors.white,
          ),
        ],
      ),
    ];

    for (final service in sortedServices) {
      final professionals = service.value;
      final serviceQuantity = professionals.values.fold<int>(
        0,
        (total, prices) =>
            total + prices.values.fold<int>(0, (sum, quantity) => sum + quantity),
      );
      final serviceTotalCents = totalForService(professionals);
      serviceTableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            serviceCell(service.key, bold: true),
            serviceCell('', bold: true, alignment: pw.Alignment.center),
            serviceCell('', bold: true, alignment: pw.Alignment.centerRight),
            serviceCell('', bold: true, alignment: pw.Alignment.centerRight),
          ],
        ),
      );

      final professionalNames = professionals.keys.toList()..sort();
      for (final professional in professionalNames) {
        final quantitiesByPrice = professionals[professional]!;
        final prices = quantitiesByPrice.keys.toList()..sort();
        for (final priceInCents in prices) {
          final quantity = quantitiesByPrice[priceInCents]!;
          serviceTableRows.add(
            pw.TableRow(
              children: [
                serviceCell(professional, indent: 8),
                serviceCell(
                  quantity.toString(),
                  alignment: pw.Alignment.center,
                ),
                serviceCell(
                  currency.format(priceInCents / 100),
                  alignment: pw.Alignment.centerRight,
                ),
                serviceCell(
                  currency.format(priceInCents * quantity / 100),
                  alignment: pw.Alignment.centerRight,
                ),
              ],
            ),
          );
        }
      }

      serviceTableRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
          children: [
            serviceCell('Subtotal do serviço', bold: true),
            serviceCell(
              serviceQuantity.toString(),
              bold: true,
              alignment: pw.Alignment.center,
            ),
            serviceCell('', bold: true, alignment: pw.Alignment.centerRight),
            serviceCell(
              currency.format(serviceTotalCents / 100),
              bold: true,
              alignment: pw.Alignment.centerRight,
            ),
          ],
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Relatório financeiro')),
          pw.Text(
            'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Ganhos do período: ${currency.format(summary.monthTotal)}',
          ),
          pw.Text(
            'Ganhos do mês de $reportMonth: '
            '${currency.format(summary.monthTotal)}',
          ),
          pw.SizedBox(height: 24),
          pw.Header(level: 1, child: pw.Text('Ganhos por profissional')),
          pw.TableHelper.fromTextArray(
            headers: ['Profissional', 'Ganhos no mês'],
            data: [
              ...summary.teamMemberEarnings.map(
                (earning) => [earning.name, currency.format(earning.amount)],
              ),
              ['Total geral do salão', currency.format(summary.monthTotal)],
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.6),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(4.5),
              1: pw.FixedColumnWidth(36),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(2.3),
            },
            children: serviceTableRows,
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }
}
