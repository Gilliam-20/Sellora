import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/plan_text.dart';
import '../../../data/models/billing_history_entry_model.dart';
import '../../../data/models/billing_profile_model.dart';
import '../../../data/models/user_model.dart';

/// Everything one invoice shows: a paid billing entry and who it's made out
/// to. The in-app invoice sheet and the PDF both read this, so they can't
/// disagree.
class Invoice {
  const Invoice({
    required this.entry,
    required this.billedTo,
    required this.email,
    this.taxId,
  });

  /// [entry] must be paid ([BillingHistoryEntryModel.hasInvoice]).
  factory Invoice.of(BillingHistoryEntryModel entry,
          {required UserModel? user, BillingProfileModel? profile}) =>
      Invoice(
        entry: entry,
        billedTo: _orNull(profile?.billingName) ??
            _orNull(user?.name) ??
            'Sellora seller',
        email: user?.email ?? '',
        taxId: _orNull(profile?.taxId),
      );

  final BillingHistoryEntryModel entry;
  final String billedTo;
  final String email;
  final String? taxId;

  String get number => entry.invoiceNumber ?? entry.id;
  DateTime get issuedOn => entry.paidAt ?? entry.createdAt;

  /// "Growth plan, 1 month" or with dates when the period is recorded.
  String get description {
    final base =
        '${entry.planName} plan, ${entry.billingPeriodDays == 30 ? '1 month' : PlanText.period(entry.billingPeriodDays)}';
    final start = entry.periodStart, end = entry.periodEnd;
    if (start == null || end == null) return base;
    return '$base (${date(start)} to ${date(end)})';
  }

  /// "KES 1,300.00" — plain ASCII, since the PDF's built-in font has no
  /// glyph for some currency symbols.
  String get amount =>
      'KES ${NumberFormat('#,##0.00').format(entry.amountKes)}';

  String get paidWith => [
        entry.paymentMethodLabel ?? 'IntaSend',
        if (entry.paymentReference case final ref? when ref.isNotEmpty)
          'ref. $ref',
      ].join(', ');

  String get fileName => '$number.pdf';

  static String date(DateTime d) => DateFormat('d MMM y').format(d.toLocal());

  static String? _orNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// The invoice as an A4 PDF. [theme] sets its fonts; the default
  /// Helvetica only covers Latin-1.
  Future<Uint8List> toPdf({pw.ThemeData? theme}) {
    final doc = pw.Document(
        theme: theme, title: 'Sellora invoice $number', author: 'Sellora');
    const navy = PdfColor.fromInt(0xFF303F9F);
    const muted = PdfColor.fromInt(0xFF7A8194);
    const hairline = PdfColor.fromInt(0xFFE2E5E4);
    pw.Widget label(String text) => pw.Text(text.toUpperCase(),
        style: const pw.TextStyle(fontSize: 8, color: muted, letterSpacing: 1));

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Sellora',
                      style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: navy)),
                  pw.Text('sellora.app',
                      style: const pw.TextStyle(fontSize: 9, color: muted)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: navy)),
                  pw.Text(number, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Issued ${date(issuedOn)}',
                      style: const pw.TextStyle(fontSize: 9, color: muted)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 32),
          label('Billed to'),
          pw.SizedBox(height: 4),
          pw.Text(billedTo,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (email.isNotEmpty) pw.Text(email),
          if (taxId != null) pw.Text('Tax ID: $taxId'),
          pw.SizedBox(height: 28),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: hairline))),
            child: pw.Row(children: [
              pw.Expanded(child: label('Description')),
              label('Amount'),
            ]),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                    child: pw.Text('Sellora subscription: $description')),
                pw.SizedBox(width: 16),
                pw.Text(amount),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: hairline))),
            child: pw.Row(children: [
              pw.Expanded(
                  child: pw.Text('Total paid',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Text(amount,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 28),
          label('Payment'),
          pw.SizedBox(height: 4),
          pw.Text('Paid ${date(issuedOn)} by $paidWith'),
          pw.Spacer(),
          pw.Text(
              'Thank you for selling with Sellora. '
              'Questions about this invoice? Contact Sellora support and quote its number.',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ),
    ));
    return doc.save();
  }
}
