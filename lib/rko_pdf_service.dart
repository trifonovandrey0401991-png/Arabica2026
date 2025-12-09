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

    // Форматируем имя директора
    // Если directorName не начинается с "ИП", добавляем "ИП "
    String directorDisplayName = shopSettings.directorName;
    if (!directorDisplayName.toUpperCase().startsWith('ИП ')) {
      // Извлекаем имя без "ИП" если оно есть
      String nameWithoutIP = directorDisplayName.replaceFirst(RegExp(r'^ИП\s*', caseSensitive: false), '');
      directorDisplayName = 'ИП $nameWithoutIP';
    }
    
    // Сокращаем ФИО директора для подписей (убираем "ИП" если есть)
    String directorNameForSignature = shopSettings.directorName.replaceFirst(RegExp(r'^ИП\s*', caseSensitive: false), '');
    final directorShortName = shortenFullName(directorNameForSignature);

    // Загружаем шрифт LiberationSerif с поддержкой кириллицы
    // Используем LiberationSerif, как в эталонном PDF
    final fontData = await rootBundle.load('assets/fonts/LiberationSerif-Regular.ttf');
    
    // Создаем шрифт из ByteData
    // pw.Font.ttf принимает ByteData напрямую
    final ttf = pw.Font.ttf(fontData);
    
    print('✅ Шрифт LiberationSerif успешно загружен, размер: ${fontData.lengthInBytes} байт');
    
    // Создаем стили текста с поддержкой кириллицы
    // ВАЖНО: Все стили должны использовать font: ttf для поддержки кириллицы
    // Размеры шрифтов из эталона: 6, 8, 9, 10
    final textStyle = pw.TextStyle(
      fontSize: 10,
      font: ttf,
    );
    final textStyleBold = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      font: ttf,
    );
    final textStyleSmall = pw.TextStyle(
      fontSize: 8,
      font: ttf,
    );
    final textStyleTiny = pw.TextStyle(
      fontSize: 6,
      font: ttf,
    );
    final textStyleMedium = pw.TextStyle(
      fontSize: 9,
      font: ttf,
    );
    final textStyleLarge = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      font: ttf,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        // Минимальные отступы, так как используем абсолютное позиционирование
        margin: const pw.EdgeInsets.all(0),
        build: (pw.Context context) {
          // Используем Stack для абсолютного позиционирования всех элементов
          // Координаты из эталона: Y от верха страницы (0 = верх), X от левого края
          return pw.Stack(
            children: [
              // Заголовок формы (справа вверху) - Y=808.4, X=450.5
              pw.Positioned(
                left: 450.5,
                top: 808.4,
                child: pw.Text(
                  'Унифицированная форма № КО-2',
                  style: textStyleSmall,
                ),
              ),
              
              // Утверждена (справа) - Y=799.2, X=338.0
              pw.Positioned(
                left: 338.0,
                top: 799.2,
                child: pw.Text(
                  'Утверждена постановлением Госкомстата России от 18.08.98 № 88',
                  style: textStyleSmall,
                ),
              ),
              
              // Организация и ИНН (слева) - Y=787.3, X=29.2
              pw.Positioned(
                left: 29.2,
                top: 787.3,
                child: pw.Text(
                  '$directorDisplayName ИНН: ${shopSettings.inn}',
                  style: textStyleBold,
                ),
              ),
              
              // Код (справа) - Y=787.5, X=517.0
              pw.Positioned(
                left: 517.0,
                top: 787.5,
                child: pw.Text(
                  'Код',
                  style: textStyleSmall,
                ),
              ),
              
              // 0310002 (справа под "Код") - Y=776.8, X=428.8
              pw.Positioned(
                left: 428.8,
                top: 776.8,
                child: pw.Text(
                  '0310002',
                  style: textStyleSmall,
                ),
              ),
              
              // Форма по ОКУД (справа) - Y=776.8, X=428.8
              pw.Positioned(
                left: 428.8,
                top: 765.0,
                child: pw.Text(
                  'Форма по ОКУД',
                  style: textStyleSmall,
                ),
              ),
              
              // по ОКПО (справа) - Y=756.9, X=430.9
              pw.Positioned(
                left: 430.9,
                top: 756.9,
                child: pw.Text(
                  'по ОКПО',
                  style: textStyleSmall,
                ),
              ),
              
              // Фактический адрес (слева) - Y=762.9, X=29.2
              pw.Positioned(
                left: 29.2,
                top: 762.9,
                child: pw.Text(
                  'Фактический адрес: ${shopSettings.address}',
                  style: textStyle,
                ),
              ),
              
              // РАСХОДНЫЙ КАССОВЫЙ ОРДЕР (центрирован) - Y=695.3, X=196.1 (центр)
              pw.Positioned(
                left: 196.1,
                top: 695.3,
                child: pw.Text(
                  'РАСХОДНЫЙ КАССОВЫЙ ОРДЕР',
                  style: textStyleLarge,
                ),
              ),
              
              // Номер документа (справа) - Y=707.0, X=403.1
              pw.Positioned(
                left: 403.1,
                top: 707.0,
                child: pw.Text(
                  'Номер документа',
                  style: textStyleSmall,
                ),
              ),
              
              // Дата составления (справа под номером) - Y=707.0+8, X=403.1
              pw.Positioned(
                left: 403.1,
                top: 715.0,
                child: pw.Text(
                  'Дата составления',
                  style: textStyleSmall,
                ),
              ),
              
              // Значение номера документа - Y=695.0, X=396.6
              pw.Positioned(
                left: 396.6,
                top: 695.0,
                child: pw.Text(
                  '$documentNumber',
                  style: textStyle,
                ),
              ),
              
              // Значение даты - Y=695.0, X=396.6+ширина номера
              pw.Positioned(
                left: 396.6,
                top: 683.0,
                child: pw.Text(
                  '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                  style: textStyle,
                ),
              ),
              
              // Таблица с данными - позиция Y=572.9-674.2, X=28.5-440.2
              // Рисуем рамку таблицы
              pw.Positioned(
                left: 28.5,
                top: 572.9,
                child: pw.Container(
                  width: 411.7,
                  height: 101.3,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                  ),
                ),
              ),
              
              // Заголовки таблицы
              // "Дебет" - Y=669.6, X=160.2
              pw.Positioned(
                left: 160.2,
                top: 669.6,
                child: pw.Text('Дебет', style: textStyleSmall),
              ),
              
              // "Сумма, руб. коп." - Y=674.2, X=337.8
              pw.Positioned(
                left: 337.8,
                top: 674.2,
                child: pw.Text('Сумма, руб. коп.', style: textStyleSmall),
              ),
              
              // "Код целевого назначения" - Y=674.2, X=337.8+ширина
              pw.Positioned(
                left: 400.0,
                top: 674.2,
                child: pw.Text('Код целевого назначения', style: textStyleSmall),
              ),
              
              // "код структурного подразделения" - Y=651.3, X=67.7
              pw.Positioned(
                left: 67.7,
                top: 651.3,
                child: pw.Text('код структурного подразделения', style: textStyleSmall),
              ),
              
              // "код аналитического учета" - Y=642.1, X=71.5
              pw.Positioned(
                left: 71.5,
                top: 642.1,
                child: pw.Text('код аналитического учета', style: textStyleSmall),
              ),
              
              // Сумма - Y=627.6, X=324.8
              pw.Positioned(
                left: 324.8,
                top: 627.6,
                child: pw.Text(amount.toStringAsFixed(0), style: textStyle),
              ),
              
              // "Выдать" - Y=610.2, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 610.2,
                child: pw.Text('Выдать', style: textStyle),
              ),
              
              // ФИО сотрудника - Y=610.2, X=100.0
              pw.Positioned(
                left: 100.0,
                top: 610.2,
                child: pw.Text(employeeData.fullName, style: textStyle),
              ),
              
              // "(фамилия, имя, отчество)" - Y=582.9, X=253.5
              pw.Positioned(
                left: 253.5,
                top: 582.9,
                child: pw.Text('(фамилия, имя, отчество)', style: textStyleTiny),
              ),
              
              // "Основание" - Y=572.9, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 572.9,
                child: pw.Text('Основание', style: textStyle),
              ),
              
              // Тип РКО - Y=572.9, X=120.0
              pw.Positioned(
                left: 120.0,
                top: 572.9,
                child: pw.Text(rkoType, style: textStyle),
              ),
              
              // "Сумма" (после таблицы) - Y=527.3, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 527.3,
                child: pw.Text(
                  'Сумма',
                  style: textStyleBold,
                ),
              ),
              
              // Сумма прописью - Y=527.3, X=28.5+ширина "Сумма"
              pw.Positioned(
                left: 100.0,
                top: 527.3,
                child: pw.Text(
                  amountWords,
                  style: textStyle,
                ),
              ),
              
              // "(прописью)." - Y=497.2, X=271.5
              pw.Positioned(
                left: 271.5,
                top: 497.2,
                child: pw.Text(
                  '(прописью).',
                  style: textStyleTiny,
                ),
              ),
              
              // "Приложение" - Y=486.8, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 486.8,
                child: pw.Text(
                  'Приложение',
                  style: textStyleMedium,
                ),
              ),
              
              // "Руководитель организации" - Y=443.5, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 443.5,
                child: pw.Text(
                  'Руководитель организации',
                  style: textStyle,
                ),
              ),
              
              // "ИП" и имя директора - Y=443.5, X=28.5+ширина "Руководитель организации"
              pw.Positioned(
                left: 250.0,
                top: 443.5,
                child: pw.Text(
                  '$directorDisplayName',
                  style: textStyle,
                ),
              ),
              
              // "(должность) (подпись) (расшифровка подписи)" - Y=416.2, X=199.5
              pw.Positioned(
                left: 199.5,
                top: 416.2,
                child: pw.Text(
                  '(должность) (подпись) (расшифровка подписи)',
                  style: textStyleTiny,
                ),
              ),
              
              // "Получил :" и сумма - Y=406.2, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 406.2,
                child: pw.Text(
                  'Получил : $amountWords',
                  style: textStyle,
                ),
              ),
              
              // "(сумма прописью)" - Y=378.9, X=271.5
              pw.Positioned(
                left: 271.5,
                top: 378.9,
                child: pw.Text(
                  '(сумма прописью)',
                  style: textStyleTiny,
                ),
              ),
              
              // Дата - Y=368.9, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 368.9,
                child: pw.Text(
                  '${now.day} ${_getMonthName(now.month)} ${now.year} г.',
                  style: textStyle,
                ),
              ),
              
              // Подпись - Y=368.9, X=справа
              pw.Positioned(
                left: 350.0,
                top: 368.9,
                child: pw.Text(
                  'Подпись _____________________',
                  style: textStyle,
                ),
              ),
              
              // Паспортные данные - Y=340.4, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 340.4,
                child: pw.Text(
                  'По: Серия ${employeeData.passportSeries} Номер ${employeeData.passportNumber} Паспорт Выдан: ${employeeData.issuedBy}',
                  style: textStyle,
                ),
              ),
              
              // Дата выдачи - Y=309.9, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 309.9,
                child: pw.Text(
                  'Дата выдачи : ${employeeData.issueDate}',
                  style: textStyle,
                ),
              ),
              
              // Подсказка для паспорта - Y=292.7, X=174.3
              pw.Positioned(
                left: 174.3,
                top: 292.7,
                child: pw.Text(
                  '(наименование, номер, дата и место выдачи документа, удостоверяющего личность получателя)',
                  style: textStyleTiny,
                ),
              ),
              
              // "Выдал кассир" - Y=254.4, X=28.5
              pw.Positioned(
                left: 28.5,
                top: 254.4,
                child: pw.Text(
                  'Выдал кассир',
                  style: textStyleMedium,
                ),
              ),
              
              // Имя кассира - Y=269.4, X=28.5 (справа)
              pw.Positioned(
                left: 400.0,
                top: 269.4,
                child: pw.Text(
                  directorShortName,
                  style: textStyle,
                ),
              ),
              
              // "(подпись)(расшифровка подписи)" - Y=243.9, X=163.5
              pw.Positioned(
                left: 163.5,
                top: 243.9,
                child: pw.Text(
                  '(подпись)',
                  style: textStyleTiny,
                ),
              ),
              
              pw.Positioned(
                left: 400.0,
                top: 243.9,
                child: pw.Text(
                  '(расшифровка подписи)',
                  style: textStyleTiny,
                ),
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

