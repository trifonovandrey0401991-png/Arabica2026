import 'shift_report_model.dart';
import 'google_drive_service.dart';

/// Сервис синхронизации отчетов
class ShiftSyncService {
  /// Синхронизировать все отчеты
  static Future<void> syncAllReports() async {
    try {
      final reports = await ShiftReport.loadAllReports();
      
      // Удаляем старые отчеты (старше недели) и их фото из Google Drive
      final oldReports = reports.where((r) => r.isOlderThanWeek).toList();
      for (var report in oldReports) {
        // Удаляем фото из Google Drive
        for (var answer in report.answers) {
          if (answer.photoDriveId != null) {
            try {
              await GoogleDriveService.deletePhoto(answer.photoDriveId!);
            } catch (e) {
              print('⚠️ Ошибка удаления фото ${answer.photoDriveId}: $e');
            }
          }
        }
        // Удаляем отчет локально
        await ShiftReport.deleteReport(report.id);
      }

      // Синхронизируем несинхронизированные отчеты
      final unsyncedReports = reports.where((r) => !r.isSynced && !r.isOlderThanWeek).toList();
      for (var report in unsyncedReports) {
        try {
          // Загружаем фото, которые еще не загружены
          final List<ShiftAnswer> syncedAnswers = [];
          for (var answer in report.answers) {
            if (answer.photoPath != null && answer.photoDriveId == null) {
              try {
                final fileName = '${report.id}_${report.answers.indexOf(answer)}.jpg';
                final driveId = await GoogleDriveService.uploadPhoto(
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
          print('⚠️ Ошибка синхронизации отчета ${report.id}: $e');
        }
      }
    } catch (e) {
      print('❌ Ошибка синхронизации отчетов: $e');
    }
  }
}










