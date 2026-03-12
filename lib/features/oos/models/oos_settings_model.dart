/// OOS module settings — flagged product IDs + check interval
class OosSettings {
  final List<String> flaggedProductIds;
  final int checkIntervalMinutes;
  final String? updatedAt;

  OosSettings({
    this.flaggedProductIds = const [],
    this.checkIntervalMinutes = 60,
    this.updatedAt,
  });

  factory OosSettings.fromJson(Map<String, dynamic> json) {
    return OosSettings(
      flaggedProductIds: List<String>.from(json['flaggedProductIds'] ?? []),
      checkIntervalMinutes: json['checkIntervalMinutes'] ?? 60,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'flaggedProductIds': flaggedProductIds,
    'checkIntervalMinutes': checkIntervalMinutes,
  };

  OosSettings copyWith({
    List<String>? flaggedProductIds,
    int? checkIntervalMinutes,
  }) {
    return OosSettings(
      flaggedProductIds: flaggedProductIds ?? this.flaggedProductIds,
      checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
      updatedAt: updatedAt,
    );
  }
}
