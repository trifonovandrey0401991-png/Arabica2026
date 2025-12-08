import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'shop_settings_model.dart';
import 'employee_registration_model.dart';
import 'rko_reports_service.dart';

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

  /// Создать РКО PDF
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
    
    // Получаем фамилию сотрудника (первое слово из ФИО)
    final employeeLastName = employeeData.fullName.split(' ').first;

    // Загружаем шрифты с поддержкой кириллицы
    final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);
    
    // Создаем стили текста с поддержкой кириллицы
    final textStyle = pw.TextStyle(
      fontSize: 10,
      font: ttf,
    );
    final textStyleBold = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      font: ttfBold,
    );
    final textStyleSmall = pw.TextStyle(
      fontSize: 8,
      font: ttf,
    );
    final textStyleLarge = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      font: ttfBold,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Заголовок формы
              pw.Text(
                'Унифицированная форма № KO-2',
                style: textStyle,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Утверждена постановлением Госкомстата России от 18.08.98 № 88',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${shopSettings.directorName} ИНН: ${shopSettings.inn}',
                style: textStyleBold,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Форма по Код ОКУД 0310002',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Фактический адрес: ${shopSettings.address}',
                style: textStyle,
              ),
              pw.SizedBox(height: 16),
              
              // Заголовок документа
              pw.Center(
                child: pw.Text(
                  'РАСХОДНЫЙ КАССОВЫЙ ОРДЕР',
                  style: textStyleLarge,
                ),
              ),
              pw.SizedBox(height: 16),
              
              // Таблица с данными
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('(отраженные подразделения)', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Номер документа', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Дата составления', style: textStyleSmall),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('$documentNumber', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                          style: textStyleSmall,
                        ),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Дебет', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Сумма, руб. коп.', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Код целевого назначения', style: textStyleSmall),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('код структурного подразделения', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('код аналитического учета', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('', style: textStyleSmall),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('1000', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('', style: textStyleSmall),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Выдать', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(employeeData.fullName, style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('(фамилия, имя, отчество)', style: textStyleSmall),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('Основание', style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(rkoType, style: textStyleSmall),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('', style: textStyleSmall),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              
              // Сумма
              pw.Text(
                'Сумма',
                style: textStyleBold,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                amountWords,
                style: textStyle,
              ),
              pw.SizedBox(height: 16),
              
              // Приложение
              pw.Text(
                'Приложение',
                style: textStyle,
              ),
              pw.SizedBox(height: 8),
              
              // Руководитель
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Руководитель организации ${shopSettings.directorName}',
                    style: textStyleSmall,
                  ),
                  pw.Text(
                    '(должность) (подпись) (расшифровка подписи)',
                    style: textStyleSmall,
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              
              // Получил
              pw.Text(
                'Получил: $amountWords',
                style: textStyle,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${now.day} ${_getMonthName(now.month)} ${now.year} г. (сумма прописью) Подпись',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 16),
              
              // Паспортные данные
              pw.Text(
                'По: Серия ${employeeData.passportSeries} Номер ${employeeData.passportNumber} Паспорт',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Выдан : ${employeeData.issuedBy}',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Дата выдачи : ${employeeData.issueDate}',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '(наименование, номер, дата и место выдачи документа, удостоверяющего личность получателя)',
                style: textStyleSmall,
              ),
              pw.SizedBox(height: 16),
              
              // Выдал кассир
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    shopSettings.directorName,
                    style: textStyleSmall,
                  ),
                  pw.Text(
                    'Выдал кассир (подпись) (расшифровка подписи)',
                    style: textStyleSmall,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Сохраняем PDF
    Directory directory;
    if (kIsWeb) {
      // Для веб используем временную директорию
      directory = await getTemporaryDirectory();
    } else {
      // Для мобильных используем Downloads или Documents
      try {
        directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        // Пытаемся найти папку Downloads
        final downloadsPath = '${directory.path}/Download';
        final downloadsDir = Directory(downloadsPath);
        if (await downloadsDir.exists()) {
          directory = downloadsDir;
        } else {
          // Если Downloads нет, создаем в Documents
          final documentsDir = Directory('${directory.path}/RKOs');
          if (!await documentsDir.exists()) {
            await documentsDir.create(recursive: true);
          }
          directory = documentsDir;
        }
      } catch (e) {
        // Если не удалось получить внешнее хранилище, используем Documents
        directory = await getApplicationDocumentsDirectory();
        final rkoDir = Directory('${directory.path}/RKOs');
        if (!await rkoDir.exists()) {
          await rkoDir.create(recursive: true);
        }
        directory = rkoDir;
      }
    }

    final fileName = generateFileName(
      date: now,
      shopAddress: shopSettings.address,
      employeeLastName: employeeLastName,
    );
    
    final file = File(path.join(directory.path, fileName));
    await file.writeAsBytes(await pdf.save());

    return file;
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
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return months[month - 1];
  }
}

