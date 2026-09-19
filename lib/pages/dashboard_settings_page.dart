import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';
import 'profile_page.dart';
import 'network_endpoint_settings_page.dart';
import 'dashboard_notifications_page.dart';

/// Web dashboard hub: logged-in profile + shortcuts (connection, etc.).
class DashboardSettingsPage extends StatelessWidget {
  const DashboardSettingsPage({super.key});

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    final a = parts.first[0];
    final last = parts.last;
    final b = last.isNotEmpty ? last[0] : '';
    return ('$a$b').toUpperCase();
  }

  static Widget _roleLabel(ThemeData theme, User u) {
    final text = u.isFamilyMember ? 'Family member' : _formatRole(u.role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  static String _formatRole(String role) {
    if (role.isEmpty) return 'Account';
    return role.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F4),
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          DashboardBellButton(
            iconColor: isDark ? Colors.white : Colors.black87,
          ),
        ],
      ),
      body: Consumer<UserProvider>(
        builder: (context, up, _) {
          final u = up.user;
          if (u == null) {
            return const Center(child: Text('Not signed in.'));
          }

          final photoUrl = AuthService().buildPhotoUrl(u.profileImage);
          final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Your account',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const MyProfilePage(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.grey.shade700,
                          child: ClipOval(
                            child: photoUrl != null
                                ? Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    width: 72,
                                    height: 72,
                                    errorBuilder:
                                        (_, __, ___) => Text(
                                          _initials(u.name),
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                  )
                                : Text(
                                    _initials(u.name),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                u.email,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                              if (u.phone != null && u.phone!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    u.phone!.trim(),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _roleLabel(theme, u),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: theme.hintColor),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Connections',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.settings_ethernet),
                  title: const Text('Server connection'),
                  subtitle: Text(
                    AuthService.baseUrl,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const NetworkEndpointSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
