import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/user_provider.dart';
import '../models/user.dart';
import '../pages/start_page.dart';
import '../pages/home_page.dart';

import '../pages/dashboard_home_page.dart';
import '../pages/dashboard_login_page.dart';
import 'app_shell.dart';

class AuthWrapper extends StatefulWidget {
  final bool isDashboard;
  const AuthWrapper({super.key, this.isDashboard = false});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App entered background
      _pausedAt = DateTime.now();
      print('AuthWrapper: App paused at $_pausedAt');
    } else if (state == AppLifecycleState.resumed) {
      // App returned to foreground
      print('AuthWrapper: App resumed');
      _checkSessionTimeout();
    }
  }

  Future<void> _checkSessionTimeout() async {
    if (_pausedAt != null) {
      final now = DateTime.now();
      final difference = now.difference(_pausedAt!);
      print(
        'AuthWrapper: Time spent in background: ${difference.inSeconds} seconds',
      );

      // If spent more than 2 minutes (120 seconds) in background
      if (difference.inMinutes >= 2) {
        print('AuthWrapper: Session timeout! Logging out...');
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        if (userProvider.isAuthenticated) {
          await _authService.logout();
          userProvider.clear();
          // No need to navigate here, the build method will react to provider change
        }
      }
      _pausedAt = null; // Reset
    }
  }

  Future<void> _checkAuth() async {
    print('AuthWrapper: Starting _checkAuth...');
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    try {
      final token = await _authService.getToken();
      print('AuthWrapper: Stored token found: ${token != null}');

      if (token != null) {
        print(
          'AuthWrapper: Fetching user profile from ${AuthService.baseUrl}...',
        );
        // Add a timeout to prevent infinite hang
        final profileRes = await _authService.getUserProfile().timeout(
          const Duration(seconds: 10),
          onTimeout: () => {
            'success': false,
            'message': 'Connection timed out',
          },
        );
        print('AuthWrapper: Profile fetch result: ${profileRes['success']}');

        if (profileRes['success']) {
          final u = User.fromJson(profileRes['user'] as Map<String, dynamic>);
          if (widget.isDashboard && u.isFamilyMember) {
            await _authService.logout();
            userProvider.clear();
          } else {
            userProvider.setUser(u);
            await PushNotificationService.syncTokenWithBackendIfLoggedIn();
            print('AuthWrapper: User set in provider');

            final optionsRes = await _authService.getOptions();
            if (optionsRes['success']) {
              userProvider.setOptions(
                UserOptions.fromJson(optionsRes['options']),
              );
              print('AuthWrapper: Options set in provider');
            }
          }
        } else {
          print('AuthWrapper: Profile fetch failed or token invalid');
          await _authService.logout();
          userProvider.clear();
        }
      } else {
        print('AuthWrapper: No token found, proceeding to StartPage');
      }
    } catch (e) {
      print('AuthWrapper: Auth check error: $e');
    } finally {
      print('AuthWrapper: Finalizing _checkAuth, setting _isLoading to false');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }

    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        if (userProvider.isAuthenticated) {
          return AppShell(
            isDashboard: widget.isDashboard,
            child: widget.isDashboard
                ? const DashboardHomePage()
                : const SmartHomePage(),
          );
        } else {
          return widget.isDashboard
              ? const DashboardLoginPage()
              : const StartPage();
        }
      },
    );
  }
}
