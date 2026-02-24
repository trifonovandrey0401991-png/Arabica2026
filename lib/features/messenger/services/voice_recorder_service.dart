import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Сервис записи голосовых сообщений.
/// Использует пакет `record` для захвата аудио с микрофона.
class VoiceRecorderService {
  static final VoiceRecorderService _instance = VoiceRecorderService._();
  static VoiceRecorderService get instance => _instance;
  VoiceRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startTime;
  String? _currentPath;

  bool get isRecording => _currentPath != null;

  /// Запрашивает разрешение на микрофон и начинает запись.
  /// Возвращает true если запись началась успешно.
  Future<bool> startRecording() async {
    // Запрос разрешения
    final status = await Permission.microphone.request();
    if (!status.isGranted) return false;

    // Проверяем что рекордер доступен
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    // Временный файл для записи
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentPath = '${dir.path}/voice_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );

    _startTime = DateTime.now();
    return true;
  }

  /// Останавливает запись и возвращает файл + длительность в секундах.
  /// Возвращает null если запись не была начата или файл пуст.
  Future<VoiceRecordResult?> stopRecording() async {
    if (_currentPath == null) return null;

    final path = await _recorder.stop();
    final startTime = _startTime;
    _currentPath = null;
    _startTime = null;

    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final fileSize = await file.length();
    if (fileSize < 1000) {
      // Слишком короткая запись — удаляем
      await file.delete();
      return null;
    }

    final duration = startTime != null
        ? DateTime.now().difference(startTime).inSeconds
        : 0;

    return VoiceRecordResult(
      file: file,
      durationSeconds: duration < 1 ? 1 : duration,
    );
  }

  /// Отменяет текущую запись и удаляет файл.
  Future<void> cancelRecording() async {
    if (_currentPath == null) return;

    await _recorder.stop();
    final file = File(_currentPath!);
    _currentPath = null;
    _startTime = null;

    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Освобождает ресурсы.
  void dispose() {
    _recorder.dispose();
  }
}

class VoiceRecordResult {
  final File file;
  final int durationSeconds;

  const VoiceRecordResult({
    required this.file,
    required this.durationSeconds,
  });
}
