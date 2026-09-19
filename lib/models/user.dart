class User {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? profileImage;
  final String role;
  final DateTime createdAt;
  final int? ownerUserId;
  final int? familyMemberId;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.profileImage,
    required this.role,
    required this.createdAt,
    this.ownerUserId,
    this.familyMemberId,
  });

  /// Home owner user id for scoped data (WebSocket, events). Same as [id] for owners.
  int get effectiveOwnerId => ownerUserId ?? id;

  bool get isFamilyMember => role == 'family';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      profileImage: json['profile_image'],
      role: json['role'] ?? 'user',
      createdAt: DateTime.parse(json['created_at']),
      ownerUserId: json['owner_user_id'] == null
          ? null
          : (json['owner_user_id'] as num).toInt(),
      familyMemberId: json['family_member_id'] == null
          ? null
          : (json['family_member_id'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'profile_image': profileImage,
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'owner_user_id': ownerUserId,
      'family_member_id': familyMemberId,
    };
  }
}

class UserOptions {
  final int id;
  final int userId;
  final String theme;
  final bool notificationsEnabled;
  final bool emailNotificationsEnabled;
  final bool inAppAlertsEnabled;
  final String language;
  /// `home` = LAN / normal IP, `tunnel` = Tailscale (or other VPN mesh).
  final String networkRouteMode;
  final String? apiBaseHomeUrl;
  final String? apiBaseTunnelUrl;

  UserOptions({
    required this.id,
    required this.userId,
    required this.theme,
    required this.notificationsEnabled,
    required this.emailNotificationsEnabled,
    required this.inAppAlertsEnabled,
    required this.language,
    this.networkRouteMode = 'home',
    this.apiBaseHomeUrl,
    this.apiBaseTunnelUrl,
  });

  factory UserOptions.fromJson(Map<String, dynamic> json) {
    return UserOptions(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      userId: json['user_id'] is num
          ? (json['user_id'] as num).toInt()
          : 0,
      theme: (json['theme'] ?? 'light').toString(),
      notificationsEnabled: json['notifications_enabled'] != false,
      emailNotificationsEnabled: json['email_notifications_enabled'] == true,
      inAppAlertsEnabled: json['in_app_alerts_enabled'] != false,
      language: (json['language'] ?? 'en').toString(),
      networkRouteMode: (json['network_route_mode'] ?? 'home').toString(),
      apiBaseHomeUrl: json['api_base_home_url']?.toString(),
      apiBaseTunnelUrl: json['api_base_tunnel_url']?.toString(),
    );
  }
}
