import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница предпросмотра PDF в горизонтальном режиме на весь экран
class SchedulePdfPreviewPage extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final String title;

  const SchedulePdfPreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.title,
  });

  @override
  State<SchedulePdfPreviewPage> createState() => _SchedulePdfPreviewPageState();
}

class _SchedulePdfPreviewPageState extends State<SchedulePdfPreviewPage> {
  @override
  void initState() {
    super.initState();
    // Принудительно переключаем в горизонтальный режим
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Скрываем системный UI для полноэкранного режима
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Восстанавливаем портретный режим
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // Восстанавливаем системный UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // PDF на весь экран
            Positioned.fill(
              child: PdfPreview(
                build: (format) async => widget.pdfBytes,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                pdfFileName: widget.fileName,
                initialPageFormat: PdfPageFormat.a4.landscape,
                useActions: false,
                allowSharing: false,
                allowPrinting: false,
                padding: EdgeInsets.zero,
                previewPageMargin: EdgeInsets.zero,
              ),
            ),
            // Кнопки управления сверху
            Positioned(
              top: 8.h,
              left: 8.w,
              right: 8.w,
              child: Row(
                children: [
                  // Кнопка назад
                  _buildControlButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                    tooltip: 'Назад',
                  ),
                  SizedBox(width: 8),
                  // Заголовок
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  // Кнопка поделиться
                  _buildControlButton(
                    icon: Icons.share,
                    onTap: () async {
                      await Printing.sharePdf(
                        bytes: widget.pdfBytes,
                        filename: widget.fileName,
                      );
                    },
                    tooltip: 'Поделиться',
                  ),
                  SizedBox(width: 8),
                  // Кнопка печати
                  _buildControlButton(
                    icon: Icons.print,
                    onTap: () async {
                      await Printing.layoutPdf(
                        onLayout: (format) async => widget.pdfBytes,
                        name: widget.fileName,
                        format: PdfPageFormat.a4.landscape,
                      );
                    },
                    tooltip: 'Печать',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
