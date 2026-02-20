class MessengerContact {
  final String phone;
  final String? name;
  final String userType; // 'employee' | 'client'

  MessengerContact({
    required this.phone,
    this.name,
    this.userType = 'client',
  });

  factory MessengerContact.fromJson(Map<String, dynamic> json) {
    return MessengerContact(
      phone: json['phone'] as String,
      name: json['name'] as String?,
      userType: (json['userType'] as String?) ?? (json['user_type'] as String?) ?? 'client',
    );
  }

  String get displayName => name ?? phone;
}
