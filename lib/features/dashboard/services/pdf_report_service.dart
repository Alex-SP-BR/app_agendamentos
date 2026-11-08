import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/financial_summary.dart';

class PdfReportService {
  Future<void> export(FinancialSummary summary) async {
    final document = pw.Document();
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Relatório financeiro')),
          pw.Text(
            'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.SizedBox(height: 16),
          pw.Text('Ganhos da semana: ${currency.format(summary.weekTotal)}'),
          pw.Text('Ganhos do mês: ${currency.format(summary.monthTotal)}'),
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
          pw.TableHelper.fromTextArray(
            headers: ['Serviço', 'Status', 'Valor'],
            data: summary.appointments
                .map(
                  (row) => [
                    row['servico'],
                    row['status'],
                    currency.format(row['valor']),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }
}
