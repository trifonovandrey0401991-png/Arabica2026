import '../models/shift_report_model.dart';
import '../../../core/services/photo_upload_service.dart';
import '../../../core/utils/logger.dart';
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
        // Удаляем фото из Google Drive
        for (var answer in report.answers) {
          if (answer.photoDriveId != null) {
            try {
              await PhotoUploadService.deletePhoto(answer.photoDriveId!);
            } catch (e) {
              Logger.debug('⚠️ Ошибка удаления фото ${answer.photoDriveId}: $e');
            }
          }
        }
        // Удаляем отчет локально
        await ShiftReport.deleteReport(report.id);
      }

      // Синхронизируем несинхронизированные отчеты
      final unsyncedReports = reports.where((r) => !r.isSynced && !r.isOlderThanWeek).toList();
      Logger.debug('Найдено несинхронизированных отчетов: ${unsyncedReports.length}');
      
      for (var report in unsyncedReports) {
        try {
          // Загружаем фото, которые еще не загружены
          final List<ShiftAnswer> syncedAnswers = [];
          for (var answer in report.answers) {
            if (answer.photoPath != null && answer.photoDriveId == null) {
              try {
                final fileName = '${report.id}_${report.answers.indexOf(answer)}.jpg';
                final driveId = await PhotoUploadService.uploadPhoto(
                  answer.photoPath!,
                  fileName,
                );
                syncedAnswers.add(ShiftAnswer(
                  question: answer.question,
                  textAnswer: answer.textAnswer,
                  numberAnswer: answer.numberAnswer,
                  photoPath: answer.photoPath,
                  photoDriveId: driveId,
                ));
              } catch (e) {
                // Если не удалось загрузить, оставляем как есть
                syncedAnswers.add(answer);
              }
            } else {
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
          Logger.debug('⚠️ Ошибка синхронизации отчета ${report.id}: $e');
        }
      }
      
      // Сохраняем время последней синхронизации
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      Logger.debug('✅ Синхронизация завершена');
    } catch (e) {
      Logger.error('Ошибка синхронизации отчетов', e);
    }
  }
}












