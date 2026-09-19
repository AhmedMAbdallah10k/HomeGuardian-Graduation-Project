import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../models/user.dart';

class ManageNotificationsPage extends StatefulWidget {
  const ManageNotificationsPage({super.key});

  @override
  State<ManageNotificationsPage> createState() => _ManageNotificationsPageState();
}

class _ManageNotificationsPageState extends State<ManageNotificationsPage> {
  final _auth = AuthService();
  bool _mobilePush = true;
  bool _emailNotifications = false;
  bool _smsAlerts = true;
  bool _inAppAlerts = true;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final res = await _auth.getOptions();
    if (!mounted) return;
    if (res['success'] == true && res['options'] != null) {
      final o = res['options'] as Map<String, dynamic>;
      setState(() {
        _mobilePush = o['notifications_enabled'] != false;
        _emailNotifications = o['email_notifications_enabled'] == true;
        _inAppAlerts = o['in_app_alerts_enabled'] != false;
        _loadingPrefs = false;
      });
    } else {
      setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _onMobilePushChanged(bool val) async {
    final user = context.read<UserProvider>().user;
    if (user?.isFamilyMember == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only the home owner can change this setting.')),
        );
      }
      return;
    }

    setState(() => _mobilePush = val);
    final res = await _auth.updateUserOptions({'notifications_enabled': val});
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() => _mobilePush = !val);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Could not save')),
      );
    }
  }

  Future<void> _onEmailNotificationsChanged(bool val) async {
    final user = context.read<UserProvider>().user;
    if (user?.isFamilyMember == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only the home owner can change email alerts. They are sent to the home owner\'s email only.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _emailNotifications = val);
    final res =
        await _auth.updateUserOptions({'email_notifications_enabled': val});
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() => _emailNotifications = !val);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Could not save')),
      );
    }
  }

  Future<void> _onInAppAlertsChanged(bool val) async {
    final user = context.read<UserProvider>().user;
    if (user?.isFamilyMember == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only the home owner can change this. It applies to everyone in the home.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _inAppAlerts = val);
    final res = await _auth.updateUserOptions({'in_app_alerts_enabled': val});
    if (!mounted) return;
    if (res['success'] == true && res['options'] != null) {
      context.read<UserProvider>().setOptions(
            UserOptions.fromJson(res['options'] as Map<String, dynamic>),
          );
    } else {
      setState(() => _inAppAlerts = !val);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Could not save')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFamily = context.watch<UserProvider>().user?.isFamilyMember ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
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
                    child: const Text(
                      'Manage Notifications',
                      style: TextStyle(
                        fontSize: 24,
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
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: _loadingPrefs
                    ? const Center(child: CircularProgressIndicator(color: Colors.black))
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            if (isFamily)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Push alerts follow the home owner account. Some settings can only be changed by the owner.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontFamily: 'Comfortaa', fontSize: 13),
                                ),
                              ),
                            if (isFamily) const SizedBox(height: 16),
                            _buildNotificationItem(
                              icon: Icons.notifications_active,
                              title: 'Mobile Push Notifications',
                              subtitle: 'Server alerts when events are detected (FCM)',
                              value: _mobilePush,
                              onChanged: isFamily ? null : _onMobilePushChanged,
                            ),
                            _buildDivider(),
                            _buildNotificationItem(
                              icon: Icons.email,
                              title: 'Email Notifications',
                              subtitle:
                                  'Security alerts sent to the home owner\'s email only',
                              value: _emailNotifications,
                              onChanged:
                                  isFamily ? null : _onEmailNotificationsChanged,
                            ),
                            _buildDivider(),
                            _buildNotificationItem(
                              icon: Icons.sms,
                              title: 'SMS Alerts',
                              value: _smsAlerts,
                              onChanged: (val) => setState(() => _smsAlerts = val),
                            ),
                            _buildDivider(),
                            _buildNotificationItem(
                              icon: Icons.notifications_paused,
                              title: 'In-app security banners',
                              subtitle:
                                  'Pop-up alerts while the app is open. Does not affect mobile push or email.',
                              value: _inAppAlerts,
                              onChanged: isFamily ? null : _onInAppAlertsChanged,
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

  Widget _buildNotificationItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: Colors.black),
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700], fontFamily: 'Comfortaa'),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Colors.grey[400],
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.black;
              }
              return Colors.grey[600];
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.grey[400];
              }
              return Colors.grey[300];
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 80, right: 40),
      child: Divider(color: Colors.grey[400], thickness: 1),
    );
  }
}
