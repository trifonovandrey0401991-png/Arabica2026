import 'shift_report_model.dart';
import 'google_drive_service.dart';
import 'utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис синхронизации отчетов
class ShiftSyncService {
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const Duration _syncInterval = Duration(hours: 1); // Синхронизировать не чаще раза в час
  
  /// Синхронизировать все отчеты (с проверкой интервала)
  static Future<void> syncAllReports() async {
    try {
      // Проверяем, нужно ли синхронизировать
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestamp = prefs.getInt(_lastSyncKey);
      
      if (lastSyncTimestamp != null) {
        final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp);
        final now = DateTime.now();
        final timeSinceLastSync = now.difference(lastSync);
        
        if (timeSinceLastSync < _syncInterval) {
          Logger.debug('Синхронизация пропущена: прошло только ${timeSinceLastSync.inMinutes} минут');
          return;
        }
      }
      
      Logger.debug('Начало синхронизации отчетов...');
      final reports = await ShiftReport.loadAllReports();
      
      // Удаляем старые отчеты (старше недели) и их фото из Google Drive
      final oldReports = reports.where((r) => r.isOlderThanWeek).toList();
      for (var report in oldReports) {
        // Удаляем фото из Google Drive параллельно
        final photoDeleteFutures = <Future>[];
        for (var answer in report.answers) {
          if (answer.photoDriveId != null) {
            photoDeleteFutures.add(
              GoogleDriveService.deletePhoto(answer.photoDriveId!)
                .catchError((e) {
                  Logger.warning('Ошибка удаления фото ${answer.photoDriveId}: $e');
                  return null; // Продолжаем даже при ошибке
                })
            );
          }
        }
        // Ждем завершения всех удалений параллельно
        if (photoDeleteFutures.isNotEmpty) {
          await Future.wait(photoDeleteFutures);
        }
        // Удаляем отчет локально
        await ShiftReport.deleteReport(report.id);
      }

      // Синхронизируем несинхронизированные отчеты
      final unsyncedReports = reports.where((r) => !r.isSynced && !r.isOlderThanWeek).toList();
      Logger.debug('Найдено несинхронизированных отчетов: ${unsyncedReports.length}');
      
      for (var report in unsyncedReports) {
        try {
          // Загружаем фото параллельно, которые еще не загружены
          final uploadFutures = <int, Future<String?>>{};

          for (int i = 0; i < report.answers.length; i++) {
            final answer = report.answers[i];
            if (answer.photoPath != null && answer.photoDriveId == null) {
              final fileName = '${report.id}_$i.jpg';
              uploadFutures[i] = GoogleDriveService.uploadPhoto(
                answer.photoPath!,
                fileName,
              ).catchError((e) {
                Logger.warning('Ошибка загрузки фото для ответа $i: $e');
                return null; // Возвращаем null при ошибке
              });
            }
          }

          // Ждем завершения всех загрузок параллельно
          final uploadResults = uploadFutures.isEmpty
            ? <int, String?>{}
            : await Future.wait(
                uploadFutures.entries.map((e) async => MapEntry(e.key, await e.value))
              ).then((entries) => Map.fromEntries(entries));

          // Создаем список синхронизированных ответов
          final List<ShiftAnswer> syncedAnswers = [];
          for (int i = 0; i < report.answers.length; i++) {
            final answer = report.answers[i];
            final driveId = uploadResults[i];

            if (driveId != null) {
              // Фото успешно загружено
              syncedAnswers.add(ShiftAnswer(
                question: answer.question,
                textAnswer: answer.textAnswer,
                numberAnswer: answer.numberAnswer,
                photoPath: answer.photoPath,
                photoDriveId: driveId,
              ));
            } else {
              // Фото либо не требовалось загружать, либо загрузка не удалась
              syncedAnswers.add(answer);
            }
          }

          // Обновляем отчет как синхронизированный
          final syncedReport = ShiftReport(
            id: report.id,
            employeeName: report.employeeName,
            shopAddress: report.shopAddress,
            createdAt: report.createdAt,
            answers: syncedAnswers,
            isSynced: true,
          );

          await ShiftReport.updateReport(syncedReport);
        } catch (e) {
          Logger.warning('Ошибка синхронизации отчета ${report.id}: $e');
        }
      }
      
      // Сохраняем время последней синхронизации
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      Logger.success('Синхронизация завершена');
    } catch (e) {
      Logger.error('Ошибка синхронизации отчетов', e);
    }
  }
}












