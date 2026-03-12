import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../models/oos_table_model.dart';

/// Generates a landscape PDF of the OOS table
class OosPdfService {
  static final _headerColor = PdfColor.fromInt(0xFF1A4D4D); // emerald
  static final _zeroColor = PdfColor.fromInt(0xFFFFCDD2); // light red
  static final _normalColor = PdfColor.fromInt(0xFFE8F5E9); // light green

  /// Generate OOS table as landscape PDF
  static Future<Uint8List> generateTablePdf({
    required List<OosTableRow> rows,
    required List<OosShopInfo> shops,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    // Calculate font size based on number of columns
    final colCount = shops.length + 1; // +1 for product name
    final fontSize = colCount > 10 ? 6.0 : colCount > 6 ? 7.0 : 8.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'OOS — Отсутствие товаров',
            style: pw.TextStyle(font: fontBold, fontSize: 14),
          ),
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            context: context,
            cellAlignment: pw.Alignment.center,
            headerStyle: pw.TextStyle(
              font: fontBold,
              fontSize: fontSize,
              color: PdfColors.white,
            ),
            cellStyle: pw.TextStyle(font: font, fontSize: fontSize),
            headerDecoration: pw.BoxDecoration(color: _headerColor),
            headerAlignments: {
              0: pw.Alignment.centerLeft,
              for (int i = 1; i <= shops.length; i++) i: pw.Alignment.center,
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              for (int i = 1; i <= shops.length; i++) i: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              for (int i = 1; i <= shops.length; i++) i: const pw.FlexColumnWidth(1),
            },
            headers: [
              'Товар',
              ...shops.map((s) => s.name),
            ],
            data: rows.map((row) {
              return [
                row.productName,
                ...shops.map((shop) {
                  final stock = row.shopStocks[shop.id];
                  return stock?.toString() ?? '-';
                }),
              ];
            }).toList(),
            cellDecoration: (index, data, rowNum) {
              if (rowNum < 0) return pw.BoxDecoration(color: _headerColor);
              if (rowNum >= rows.length) return const pw.BoxDecoration();

              // Color cells based on stock value
              final row = rows[rowNum];
              // Check if any shop in this row has zero stock
              final hasZero = row.shopStocks.values.any((s) => s != null && s <= 0);
              if (hasZero) {
                return pw.BoxDecoration(
                  color: rowNum.isEven ? _zeroColor : PdfColor.fromInt(0xFFFFE0E0),
                );
              }
              return pw.BoxDecoration(
                color: rowNum.isEven ? _normalColor : PdfColors.white,
              );
            },
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Open PDF preview page with share button
  static Future<void> previewTablePdf({
    required BuildContext context,
    required List<OosTableRow> rows,
    required List<OosShopInfo> shops,
  }) async {
    final bytes = await generateTablePdf(rows: rows, shops: shops);
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OosPdfPreviewPage(pdfBytes: bytes),
      ),
    );
  }
}

/// Full-screen landscape PDF preview with share button and zoom
class _OosPdfPreviewPage extends StatefulWidget {
  final Uint8List pdfBytes;

  const _OosPdfPreviewPage({required this.pdfBytes});

  @override
  State<_OosPdfPreviewPage> createState() => _OosPdfPreviewPageState();
}

class _OosPdfPreviewPageState extends State<_OosPdfPreviewPage> {
  @override
  void initState() {
    super.initState();
    // Force landscape orientation for PDF preview
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore portrait orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emeraldDark,
        title: const Text('OOS — Предпросмотр PDF'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Поделиться',
            onPressed: () {
              Printing.sharePdf(
                bytes: widget.pdfBytes,
                filename: 'oos_report.pdf',
              );
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => widget.pdfBytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'oos_report.pdf',
        allowSharing: false,
        allowPrinting: false,
        useActions: false,
      ),
    );
  }
}
