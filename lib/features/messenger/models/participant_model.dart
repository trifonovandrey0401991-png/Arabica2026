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
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'].toString())
          : null,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
}
