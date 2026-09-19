import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/event_notifier.dart';
import '../services/global_alert_coordinator.dart';
import '../services/user_provider.dart';

/// Wraps authenticated UI so WebSocket alerts work on every page.
class AppShell extends StatefulWidget {
  final Widget child;
  final bool isDashboard;

  const AppShell({
    super.key,
    required this.child,
    required this.isDashboard,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  GlobalAlertCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCoordinator());
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDashboard != widget.isDashboard) {
      _restartCoordinator();
    }
  }

  Future<void> _startCoordinator() async {
    if (!mounted) return;
    _coordinator?.stop();
    _coordinator = GlobalAlertCoordinator(
      isDashboard: widget.isDashboard,
      isMobileLayout: !widget.isDashboard,
    );
    await _coordinator!.start(context);
  }

  Future<void> _restartCoordinator() async {
    await _coordinator?.stop();
    if (mounted) await _startCoordinator();
  }

  @override
  void dispose() {
    _coordinator?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        if (userProvider.isAuthenticated) {
          // Reload events when user logs in.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final events = context.read<EventNotifier>();
            if (events.events.isEmpty) {
              events.loadFromApi(silent: true);
            }
          });
        }
        return widget.child;
      },
    );
  }
}
