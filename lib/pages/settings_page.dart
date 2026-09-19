import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../models/user.dart';
import 'profile_page.dart';
import 'security_page.dart';
import 'manage_notifications_page.dart';
import 'language_settings_page.dart';
import 'network_endpoint_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkTheme = false;

  static String _initials(User u) {
    final parts = u.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    final a = parts.first[0];
    final last = parts.last;
    final b = last.isNotEmpty ? last[0] : '';
    return ('$a$b').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 90,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(60),
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      l10n.settings,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            
            // Body
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),

                      Consumer<UserProvider>(
                        builder: (context, up, _) {
                          final u = up.user;
                          if (u == null) return const SizedBox.shrink();
                          final photoUrl =
                              AuthService().buildPhotoUrl(u.profileImage);
                          final roleText = u.isFamilyMember
                              ? 'Family member'
                              : u.role.replaceAll('_', ' ');
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) =>
                                              const MyProfilePage(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 18,
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 32,
                                            backgroundColor:
                                                Colors.grey.shade700,
                                            child: ClipOval(
                                              child: photoUrl != null
                                                  ? Image.network(
                                                      photoUrl,
                                                      width: 64,
                                                      height: 64,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) => Text(
                                                        _initials(u),
                                                        style: const TextStyle(
                                                          fontFamily:
                                                              'Comfortaa',
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    )
                                                  : Text(
                                                      _initials(u),
                                                      style: const TextStyle(
                                                        fontFamily:
                                                            'Comfortaa',
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  u.name,
                                                  style: const TextStyle(
                                                    fontFamily: 'Comfortaa',
                                                    fontSize: 17,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  u.email,
                                                  style: TextStyle(
                                                    fontFamily: 'Comfortaa',
                                                    fontSize: 13,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  roleText,
                                                  style: TextStyle(
                                                    fontFamily: 'Comfortaa',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey[900],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey[600],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      // Settings List
                      _buildSettingsItem(
                        icon: Icons.lock,
                        title: l10n.securityAndBiometrics,
                        onTap: () {
                           Navigator.push(
                             context,
                             MaterialPageRoute(builder: (context) => const SecurityAndBiometricsPage()),
                           );
                        }
                      ),
                      _buildDivider(),
                      _buildSettingsItem(
                        icon: Icons.notifications,
                        title: l10n.manageNotifications,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ManageNotificationsPage()),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsItem(
                        icon: Icons.router_outlined,
                        title: 'Server connection',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const NetworkEndpointSettingsPage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsItem(
                        icon: Icons.translate,
                        title: l10n.languageSettings,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LanguageSettingsPage()),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsItem(
                        icon: Icons.contrast, 
                        title: l10n.appTheme,
                        trailing: Switch(
                          value: _isDarkTheme,
                          activeColor: Colors.black,
                          activeTrackColor: Colors.grey[400],
                          inactiveThumbColor: Colors.grey[600],
                          inactiveTrackColor: Colors.grey[300],
                          onChanged: (value) {
                            setState(() {
                              _isDarkTheme = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
       child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        child: Row(
           children: [
             Icon(icon, size: 28, color: Colors.black),
             const SizedBox(width: 40), // Large gap as seen in image
             Expanded(
               child: Text(
                 title,
                 style: const TextStyle(
                   fontSize: 16,
                   fontWeight: FontWeight.w500,
                   color: Colors.black,
                   fontFamily: 'Comfortaa',
                 ),
               ),
             ),
             if (trailing != null) trailing,
           ],
        ),
      ),
    );
  }
  
  Widget _buildDivider() {
     return Padding(
       padding: const EdgeInsets.only(left: 80, right: 40), // Indented divider
       child: Divider(color: Colors.grey[400], thickness: 1),
     );
  }
}
