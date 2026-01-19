/// Модель категории данных для очистки.
class CleanupCategory {
  final String id;
  final String name;
  final int count;
  final int sizeBytes;
  final DateTime? oldestDate;
  final DateTime? newestDate;

  const CleanupCategory({
    required this.id,
    required this.name,
    required this.count,
    required this.sizeBytes,
    this.oldestDate,
    this.newestDate,
  });

  factory CleanupCategory.fromJson(Map<String, dynamic> json) {
    return CleanupCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      count: json['count'] as int? ?? 0,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      oldestDate: json['oldestDate'] != null
          ? DateTime.tryParse(json['oldestDate'] as String)
          : null,
      newestDate: json['newestDate'] != null
          ? DateTime.tryParse(json['newestDate'] as String)
          : null,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
