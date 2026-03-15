import '../../../core/utils/date_formatter.dart';

class Participant {
  final String phone;
  final String? name;
  final String role; // 'admin' | 'member'
  final DateTime? joinedAt;
  final DateTime? lastReadAt;
  final String? avatarUrl;

  Participant({
    required this.phone,
    this.name,
    this.role = 'member',
    this.joinedAt,
    this.lastReadAt,
    this.avatarUrl,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      phone: (json['phone'] as String?) ?? '',
      name: json['name'] as String?,
      role: (json['role'] as String?) ?? 'member',
      joinedAt: parseServerDate(json['joined_at']),
      lastReadAt: parseServerDate(json['last_read_at']),
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
}
