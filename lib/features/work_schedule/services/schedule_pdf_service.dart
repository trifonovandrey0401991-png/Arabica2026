import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/work_schedule_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Сервис для генерации PDF графика работы
class SchedulePdfService {
  static final _morningColor = PdfColor.fromInt(0xFFB9F6CA); // Салатовый - утро
  static final _dayColor = PdfColor.fromInt(0xFFFFF59D); // Светло-жёлтый - день
  static final _eveningColor = PdfColor.fromInt(0xFFE0E0E0); // Светло-серый - вечер
  static final _headerColor = PdfColor.fromInt(0xFF004D40); // Тёмно-зелёный

  /// Генерирует PDF с графиком работы (один горизонтальный лист)
  static Future<Uint8List> generateSchedulePdf({
    required WorkSchedule schedule,
    required List<String> employeeNames,
    required DateTime month,
    required int startDay,
    required int endDay,
    Map<String, Map<ShiftType, String>>? abbreviations,
  }) async {
    final pdf = pw.Document();

    // Загружаем шрифт для кириллицы
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    // Получаем дни периода
    final days = <DateTime>[];
    for (int d = startDay; d <= endDay; d++) {
      final date = DateTime(month.year, month.month, d);
      if (date.month == month.month) {
        days.add(date);
      }
    }

    // Создаём один горизонтальный лист A4
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.all(12.w),
        build: (context) => _buildPage(
          schedule: schedule,
          employeeNames: employeeNames,
          days: days,
          month: month,
          abbreviations: abbreviations,
          font: font,
          fontBold: fontBold,
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPage({
    required WorkSchedule schedule,
    required List<String> employeeNames,
    required List<DateTime> days,
    required DateTime month,
    Map<String, Map<ShiftType, String>>? abbreviations,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Компактный заголовок
        _buildHeader(month, days, fontBold),
        pw.SizedBox(height: 6),

        // Таблица
        pw.Expanded(
          child: _buildTable(
            schedule: schedule,
            employeeNames: employeeNames,
            days: days,
            abbreviations: abbreviations,
            font: font,
            fontBold: fontBold,
          ),
        ),

        // Компактная легенда
        pw.SizedBox(height: 4),
        _buildLegend(font),
      ],
    );
  }

  static pw.Widget _buildHeader(
    DateTime month,
    List<DateTime> days,
    pw.Font fontBold,
  ) {
    final monthNames = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];

    final startDay = days.first.day;
    final endDay = days.last.day;

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: pw.BoxDecoration(
        color: _headerColor,
        borderRadius: pw.BorderRadius.circular(6.r),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ГРАФИК РАБОТЫ - ${monthNames[month.month - 1]} ${month.year}',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 14.sp,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            'Период: $startDay - $endDay',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10.sp,
              color: PdfColor.fromInt(0xB3FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTable({
    required WorkSchedule schedule,
    required List<String> employeeNames,
    required List<DateTime> days,
    Map<String, Map<ShiftType, String>>? abbreviations,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    final weekdayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    // Строим заголовок таблицы
    final headerRow = pw.TableRow(
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFE8F5E9),
      ),
      children: [
        // Колонка "Сотрудник"
        pw.Container(
          padding: pw.EdgeInsets.all(3.w),
          child: pw.Text(
            'Сотрудник',
            style: pw.TextStyle(font: fontBold, fontSize: 6.sp),
          ),
        ),
        // Колонки дней
        ...days.map((day) {
          final isWeekend = day.weekday == 6 || day.weekday == 7;
          return pw.Container(
            padding: pw.EdgeInsets.all(1.w),
            decoration: isWeekend
                ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFF3E0))
                : null,
            child: pw.Column(
              children: [
                pw.Text(
                  '${day.day}',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 6.sp,
                    color: isWeekend ? _eveningColor : PdfColors.black,
                  ),
                ),
                pw.Text(
                  weekdayNames[day.weekday - 1],
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 5.sp,
                    color: isWeekend ? _eveningColor : PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );

    // Строим строки для каждого сотрудника
    final dataRows = employeeNames.map((employeeName) {
      return pw.TableRow(
        children: [
          // Имя сотрудника
          pw.Container(
            padding: pw.EdgeInsets.symmetric(horizontal: 3.w, vertical: 2.h),
            child: pw.Text(
              employeeName,
              style: pw.TextStyle(font: font, fontSize: 5.5.sp),
              maxLines: 1,
            ),
          ),
          // Смены по дням
          ...days.map((day) {
            final entry = schedule.entries.firstWhere(
              (e) =>
                  e.employeeName == employeeName &&
                  e.date.year == day.year &&
                  e.date.month == day.month &&
                  e.date.day == day.day,
              orElse: () => WorkScheduleEntry(
                id: '',
                employeeId: '',
                employeeName: '',
                shopAddress: '',
                date: day,
                shiftType: ShiftType.morning,
              ),
            );

            if (entry.id.isEmpty) {
              // Нет смены
              return pw.Container(
                alignment: pw.Alignment.center,
                padding: pw.EdgeInsets.all(1.w),
                child: pw.Text(
                  '-',
                  style: pw.TextStyle(font: font, fontSize: 6.sp, color: PdfColors.grey400),
                ),
              );
            }

            // Есть смена - показываем аббревиатуру
            final abbr = _getAbbreviation(entry, abbreviations);
            final color = _getShiftColor(entry.shiftType);

            return pw.Container(
              alignment: pw.Alignment.center,
              margin: pw.EdgeInsets.all(1.w),
              padding: pw.EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.circular(2.r),
              ),
              child: pw.Text(
                abbr,
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 5.5.sp,
                  color: PdfColors.black, // чёрный текст
                ),
              ),
            );
          }),
        ],
      );
    }).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
      columnWidths: {
        0: pw.FixedColumnWidth(65), // Колонка имён (компактнее)
        for (var i = 0; i < days.length; i++)
          i + 1: pw.FlexColumnWidth(1), // Колонки дней
      },
      children: [headerRow, ...dataRows],
    );
  }

  static String _getAbbreviation(
    WorkScheduleEntry entry,
    Map<String, Map<ShiftType, String>>? abbreviations,
  ) {
    // Пробуем получить аббревиатуру из настроек магазина
    if (abbreviations != null) {
      final shopAbbr = abbreviations[entry.shopAddress];
      if (shopAbbr != null) {
        final abbr = shopAbbr[entry.shiftType];
        if (abbr != null && abbr.isNotEmpty) {
          return abbr;
        }
      }
    }

    // Стандартные аббревиатуры
    switch (entry.shiftType) {
      case ShiftType.morning:
        return 'У';
      case ShiftType.day:
        return 'Д';
      case ShiftType.evening:
        return 'В';
    }
  }

  static PdfColor _getShiftColor(ShiftType type) {
    switch (type) {
      case ShiftType.morning:
        return _morningColor;
      case ShiftType.day:
        return _dayColor;
      case ShiftType.evening:
        return _eveningColor;
    }
  }

  static pw.Widget _buildLegend(pw.Font font) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4.r),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'Легенда: ',
            style: pw.TextStyle(font: font, fontSize: 7.sp, color: PdfColors.grey700),
          ),
          _buildLegendItem('У', 'Утро', _morningColor, font),
          pw.SizedBox(width: 12),
          _buildLegendItem('Д', 'День', _dayColor, font),
          pw.SizedBox(width: 12),
          _buildLegendItem('В', 'Вечер', _eveningColor, font),
        ],
      ),
    );
  }

  static pw.Widget _buildLegendItem(String abbr, String label, PdfColor color, pw.Font font) {
    return pw.Row(
      children: [
        pw.Container(
          width: 12,
          height: 12,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(2.r),
          ),
          child: pw.Text(
            abbr,
            style: pw.TextStyle(font: font, fontSize: 6.sp, color: PdfColors.black),
          ),
        ),
        pw.SizedBox(width: 3),
        pw.Text(
          label,
          style: pw.TextStyle(font: font, fontSize: 7.sp),
        ),
      ],
    );
  }
}
