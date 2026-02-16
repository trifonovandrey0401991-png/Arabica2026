import 'dart:io';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../shops/models/shop_settings_model.dart';
import '../../employees/models/employee_registration_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import 'rko_reports_service.dart';

// http и dart:convert оставлены для получения binary PDF ответа от сервера

class RKOPDFService {
  /// Конвертировать число в пропись на русском языке
  static String numberToWords(double amount) {
    final rubles = amount.toInt();
    final kopecks = ((amount - rubles) * 100).round();

    if (rubles == 0 && kopecks == 0) {
      return 'Ноль рублей 00 копеек';
    }

    String rublesStr = _numberToWords(rubles);
    String kopecksStr = kopecks.toString().padLeft(2, '0');

    // Склонение рублей
    String rubleWord = _getRubleWord(rubles);
    
    return '$rublesStr $rubleWord $kopecksStr копеек';
  }

  static String _numberToWords(int number) {
    if (number == 0) return 'ноль';

    final units = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
    final unitsFeminine = ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
    final teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 
                   'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'];
    final tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 
                  'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
    final hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 
                      'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];

    if (number < 10) {
      return units[number];
    } else if (number < 20) {
      return teens[number - 10];
    } else if (number < 100) {
      final ten = number ~/ 10;
      final unit = number % 10;
      return unit == 0 ? tens[ten] : '${tens[ten]} ${units[unit]}';
    } else if (number < 1000) {
      final hundred = number ~/ 100;
      final remainder = number % 100;
      if (remainder == 0) {
        return hundreds[hundred];
      }
      return '${hundreds[hundred]} ${_numberToWords(remainder)}';
    } else if (number < 1000000) {
      final thousand = number ~/ 1000;
      final remainder = number % 1000;
      
      // Для тысяч используем женский род
      String thousandStr = _numberToWordsThousand(thousand, unitsFeminine, teens, tens, hundreds);
      String thousandWord = _getThousandWord(thousand);
      
      if (remainder == 0) {
        return '$thousandStr $thousandWord';
      }
      return '$thousandStr $thousandWord ${_numberToWords(remainder)}';
    }

    return number.toString();
  }

  static String _numberToWordsThousand(int number, List<String> units, List<String> teens, 
                                       List<String> tens, List<String> hundreds) {
    if (number == 0) return '';
    if (number < 10) {
      return units[number];
    } else if (number < 20) {
      return teens[number - 10];
    } else if (number < 100) {
      final ten = number ~/ 10;
      final unit = number % 10;
      return unit == 0 ? tens[ten] : '${tens[ten]} ${units[unit]}';
    } else if (number < 1000) {
      final hundred = number ~/ 100;
      final remainder = number % 100;
      if (remainder == 0) {
        return hundreds[hundred];
      }
      return '${hundreds[hundred]} ${_numberToWordsThousand(remainder, units, teens, tens, hundreds)}';
    }
    return number.toString();
  }

  static String _getThousandWord(int number) {
    if (number % 10 == 1 && number % 100 != 11) {
      return 'тысяча';
    } else if ((number % 10 >= 2 && number % 10 <= 4) && (number % 100 < 10 || number % 100 >= 20)) {
      return 'тысячи';
    }
    return 'тысяч';
  }

  static String _getRubleWord(int number) {
    if (number % 10 == 1 && number % 100 != 11) {
      return 'рубль';
    } else if ((number % 10 >= 2 && number % 10 <= 4) && (number % 100 < 10 || number % 100 >= 20)) {
      return 'рубля';
    }
    return 'рублей';
  }

  /// Генерировать имя файла РКО
  static String generateFileName({
    required DateTime date,
    required String shopAddress,
    required String employeeLastName,
  }) {
    final dateStr = '${date.day.toString().padLeft(2, '0')}_${date.month.toString().padLeft(2, '0')}_${date.year}';
    // Заменяем все пробелы и спецсимволы на подчеркивания
    final addressStr = shopAddress
        .replaceAll(' ', '_')
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('/', '_');
    final lastNameStr = employeeLastName.split(' ').first; // Берем только фамилию
    
    return '${dateStr}_${addressStr}_$lastNameStr.pdf';
  }

  /// Сократить ФИО до формата "Фамилия И. О."
  static String shortenFullName(String fullName) {
    final parts = fullName.trim().split(' ');
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts[0];
    
    final surname = parts[0];
    String initials = '';
    
    for (int i = 1; i < parts.length && i <= 2; i++) {
      if (parts[i].isNotEmpty) {
        initials += '${parts[i][0]}. ';
      }
    }
    
    return '$surname ${initials.trim()}';
  }

  /// Создать РКО PDF через .docx шаблон
  static Future<File> generateRKOFromDocx({
    required String shopAddress,
    required ShopSettings shopSettings,
    required int documentNumber,
    required EmployeeRegistration employeeData,
    required double amount,
    required String rkoType,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.serverUrl}/api/rko/generate-from-docx');

      final response = await http.post(
        url,
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'shopAddress': shopAddress,
          'shopSettings': shopSettings.toJson(),
          'documentNumber': documentNumber,
          'employeeData': employeeData.toJson(),
          'amount': amount,
          'rkoType': rkoType,
        }),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode == 200) {
        // Проверяем, не вернул ли сервер JSON ошибку вместо PDF
        // Сервер может вернуть 200 с {"success":false,"error":"..."}
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json') ||
            (response.bodyBytes.length < 500 && response.body.contains('"success"'))) {
          // Это JSON ответ с ошибкой, а не PDF
          Logger.debug('Сервер вернул JSON вместо PDF: ${response.body}');
          throw Exception('Сервер не поддерживает генерацию из DOCX');
        }

        // Генерируем имя файла
        final fileName = generateFileName(
          date: DateTime.now(),
          shopAddress: shopAddress,
          employeeLastName: employeeData.fullName.split(' ').first,
        );

        if (kIsWeb) {
          // Для веб создаем временный файл в памяти без использования file system
          // Создаем виртуальный путь для идентификации
          final virtualFile = _MemoryFile(fileName, response.bodyBytes);
          return virtualFile;
        } else {
          // Для мобильных сохраняем в временную директорию
          final directory = await getTemporaryDirectory();
          final file = File(path.join(directory.path, fileName));
          await file.writeAsBytes(response.bodyBytes);
          return file;
        }
      } else {
        throw Exception('Ошибка генерации РКО: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка генерации РКО из .docx', e);
      // Fallback на старый метод
      return generateRKO(
        shopAddress: shopAddress,
        shopSettings: shopSettings,
        documentNumber: documentNumber,
        employeeData: employeeData,
        amount: amount,
        rkoType: rkoType,
      );
    }
  }

  /// Создать РКО PDF (fallback — без сервера, через dart:pdf)
  /// Визуально повторяет форму КО-2 из эталонного DOCX шаблона
  static Future<File> generateRKO({
    required String shopAddress,
    required ShopSettings shopSettings,
    required int documentNumber,
    required EmployeeRegistration employeeData,
    required double amount,
    required String rkoType,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final amountWords = numberToWords(amount);
    final employeeLastName = employeeData.fullName.split(' ').first;
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final dateWords = '${now.day} ${_getMonthName(now.month)} ${now.year} г.';

    // Форматируем имя директора
    String directorFullName = shopSettings.directorName.replaceFirst(RegExp(r'^ИП\s*', caseSensitive: false), '').trim();
    final directorShortName = shortenFullName(directorFullName);

    // Загружаем шрифт
    final fontData = await rootBundle.load('assets/fonts/LiberationSerif-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    // Стили (фиксированные размеры в pt — НЕ зависят от экрана)
    final s10 = pw.TextStyle(fontSize: 10, font: ttf);
    final s10b = pw.TextStyle(fontSize: 10, font: ttf, fontWeight: pw.FontWeight.bold);
    final s9 = pw.TextStyle(fontSize: 9, font: ttf);
    final s8 = pw.TextStyle(fontSize: 8, font: ttf);
    final s7 = pw.TextStyle(fontSize: 7, font: ttf);

    // Вспомогательные виджеты
    pw.Widget line() => pw.Container(height: 0.5, color: PdfColors.black);
    pw.Widget gap(double h) => pw.SizedBox(height: h);
    pw.Widget hint(String text) => pw.Center(child: pw.Text(text, style: s7));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 25, 30, 25),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // === Шапка: правый блок «Унифицированная форма» ===
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Унифицированная форма № КО-2', style: s8),
                    pw.Text('Утверждена постановлением Госкомстата России от 18.08.98 № 88', style: s8),
                  ],
                ),
              ),
              gap(8),

              // === Организация + Код (две колонки) ===
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 7,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('$directorFullName ИНН: ${shopSettings.inn}', style: s10b),
                        line(),
                        gap(2),
                        pw.Text('Фактический адрес: ${shopSettings.address}', style: s10),
                        line(),
                        gap(1),
                        hint('(организация)'),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Table(
                      border: pw.TableBorder.all(),
                      columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
                      children: [
                        pw.TableRow(children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Форма по\nОКУД', style: s8)),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Код\n0310002', style: s8)),
                        ]),
                        pw.TableRow(children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('по ОКПО', style: s8)),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('', style: s8)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              gap(2),
              hint('(структурное подразделение)'),
              gap(10),

              // === Заголовок + номер/дата (две колонки) ===
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    flex: 6,
                    child: pw.Center(
                      child: pw.Text('РАСХОДНЫЙ КАССОВЫЙ ОРДЕР', style: s10b),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Table(
                      border: pw.TableBorder.all(),
                      children: [
                        pw.TableRow(children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Номер документа', style: s8)),
                          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Дата составления', style: s8)),
                        ]),
                        pw.TableRow(children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text('$documentNumber', style: s10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text(dateStr, style: s10))),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              gap(6),

              // === Основная таблица Дебет / Сумма / Код целевого ===
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  // Заголовки
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(child: pw.Text('Дебет', style: s8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('', style: s8)),
                    pw.Padding(padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(child: pw.Text('Сумма,\nруб. коп.', style: s8, textAlign: pw.TextAlign.center))),
                    pw.Padding(padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(child: pw.Text('Код целевого\nназначения', style: s8, textAlign: pw.TextAlign.center))),
                  ]),
                  // Подзаголовки
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(child: pw.Text('код структурного\nподразделения', style: s8, textAlign: pw.TextAlign.center))),
                    pw.Padding(padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(child: pw.Text('код аналитического\nучета', style: s8, textAlign: pw.TextAlign.center))),
                    pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('', style: s8)),
                    pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('', style: s8)),
                  ]),
                  // Значения
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('', style: s10)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('', style: s10)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                      child: pw.Center(child: pw.Text(amount.toStringAsFixed(0), style: s10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('', style: s10)),
                  ]),
                ],
              ),
              gap(8),

              // === Выдать ===
              pw.Row(children: [
                pw.Text('Выдать', style: s10),
                pw.SizedBox(width: 40),
                pw.Expanded(child: pw.Text(employeeData.fullName, style: s10)),
              ]),
              line(),
              hint('(фамилия, имя, отчество)'),
              gap(8),

              // === Основание ===
              pw.Row(children: [
                pw.Text('Основание', style: s10),
                pw.SizedBox(width: 25),
                pw.Expanded(child: pw.Text('Заработная плата', style: s10)),
              ]),
              gap(12),

              // === Сумма прописью ===
              pw.Row(children: [
                pw.Text('Сумма', style: s10),
                pw.SizedBox(width: 40),
                pw.Expanded(child: pw.Text(amountWords, style: s10)),
              ]),
              gap(2),
              hint('(прописью).'),
              gap(6),

              // === Приложение ===
              pw.Text('Приложение', style: s9),
              gap(16),

              // === Руководитель ===
              pw.Row(children: [
                pw.Text('Руководитель организации', style: s10),
                pw.SizedBox(width: 20),
                pw.Text('ИП', style: s10),
                pw.Expanded(child: pw.Container()),
                pw.Text(directorShortName, style: s10),
              ]),
              gap(2),
              pw.Row(children: [
                pw.SizedBox(width: 160),
                pw.Text('(должность)', style: s7),
                pw.Expanded(child: pw.Container()),
                pw.Text('(подпись)', style: s7),
                pw.SizedBox(width: 40),
                pw.Text('(расшифровка подписи)', style: s7),
              ]),
              gap(10),

              // === Получил ===
              pw.Row(children: [
                pw.Text('Получил :', style: s10),
                pw.SizedBox(width: 30),
                pw.Expanded(child: pw.Text(amountWords, style: s10)),
              ]),
              gap(2),
              hint('(сумма прописью)'),
              gap(8),

              // === Дата + подпись ===
              pw.Row(children: [
                pw.Text(dateWords, style: s10),
                pw.Expanded(child: pw.Container()),
                pw.Text('Подпись _____________________', style: s10),
              ]),
              gap(10),

              // === Паспорт ===
              pw.Text(
                'По: Серия ${employeeData.passportSeries} Номер ${employeeData.passportNumber} Паспорт Выдан ${employeeData.issuedBy}',
                style: s10,
              ),
              gap(4),
              pw.Text('Дата Выдачи : ${employeeData.issueDate}', style: s10),
              gap(2),
              hint('(наименование, номер, дата и место выдачи документа, удостоверяющего личность получателя)'),
              gap(16),

              // === Кассир ===
              pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(directorShortName, style: s10)),
              pw.Row(children: [
                pw.Text('Выдал кассир', style: s9),
                pw.SizedBox(width: 10),
                pw.Expanded(child: line()),
                pw.SizedBox(width: 40),
                pw.Expanded(child: line()),
              ]),
              gap(2),
              pw.Row(children: [
                pw.SizedBox(width: 100),
                pw.Text('(подпись)', style: s7),
                pw.Expanded(child: pw.Container()),
                pw.Text('(расшифровка подписи)', style: s7),
              ]),
            ],
          );
        },
      ),
    );

    // Генерируем имя файла и сохраняем
    final fileName = generateFileName(date: now, shopAddress: shopSettings.address, employeeLastName: employeeLastName);
    final pdfBytes = await pdf.save();

    if (kIsWeb) {
      return _MemoryFile(fileName, pdfBytes);
    } else {
      Directory directory;
      try {
        directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final downloadsPath = '${directory.path}/Download';
        final downloadsDir = Directory(downloadsPath);
        if (await downloadsDir.exists()) {
          directory = downloadsDir;
        } else {
          final documentsDir = Directory('${directory.path}/RKOs');
          if (!await documentsDir.exists()) {
            await documentsDir.create(recursive: true);
          }
          directory = documentsDir;
        }
      } catch (e) {
        directory = await getApplicationDocumentsDirectory();
        final rkoDir = Directory('${directory.path}/RKOs');
        if (!await rkoDir.exists()) {
          await rkoDir.create(recursive: true);
        }
        directory = rkoDir;
      }

      final file = File(path.join(directory.path, fileName));
      await file.writeAsBytes(pdfBytes);
      return file;
    }
  }

  /// Загрузить РКО на сервер после генерации
  static Future<bool> uploadRKOToServer({
    required File pdfFile,
    required String fileName,
    required String employeeName,
    required String shopAddress,
    required DateTime date,
    required double amount,
    required String rkoType,
  }) async {
    return await RKOReportsService.uploadRKO(
      pdfFile: pdfFile,
      fileName: fileName,
      employeeName: employeeName,
      shopAddress: shopAddress,
      date: date,
      amount: amount,
      rkoType: rkoType,
    );
  }

  static String _getMonthName(int month) {
    final months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return months[month - 1];
  }
}

/// Класс для работы с файлами в памяти (для веб-платформы)
/// Имитирует интерфейс File, но хранит данные в памяти
class _MemoryFile implements File {
  final String _path;
  final Uint8List _bytes;

  _MemoryFile(String path, List<int> bytes)
      : _path = path,
        _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  String get path => _path;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Uint8List readAsBytesSync() => _bytes;

  // Минимальная реализация остальных методов File для совместимости
  @override
  Future<File> writeAsBytes(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) async {
    throw UnsupportedError('writeAsBytes not supported in web memory file');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

