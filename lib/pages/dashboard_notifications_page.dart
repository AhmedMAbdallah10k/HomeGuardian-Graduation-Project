import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import 'event_page.dart';
import 'manage_notifications_page.dart';

/// Lists recent alerts / events — opened from dashboard header bells.
class DashboardNotificationsPage extends StatefulWidget {
  const DashboardNotificationsPage({super.key});

  @override
  State<DashboardNotificationsPage> createState() =>
      _DashboardNotificationsPageState();
}

class _DashboardNotificationsPageState
    extends State<DashboardNotificationsPage> {
  final _auth = AuthService();
  List<dynamic> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _auth.getEvents();
    if (!mounted) return;
    if (r['success'] == true) {
      final raw = r['events'];
      setState(() {
        _events = raw is List ? List<dynamic>.from(raw) : [];
        _loading = false;
      });
    } else {
      setState(() {
        _error = r['message']?.toString() ?? 'Could not load events';
        _loading = false;
      });
    }
  }

  static (IconData, Color) _iconForType(dynamic typeRaw) {
    final type = (typeRaw ?? 'info').toString();
    if (type == 'emergency' || type == 'fire') {
      return (Icons.local_fire_department, Colors.redAccent);
    }
    if (type == 'security' || type == 'door') {
      return (Icons.security, Colors.orangeAccent);
    }
    return (Icons.notifications_none_rounded, Colors.blueAccent);
  }

  static String _timestampLabel(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    try {
      dt = DateTime.parse(ts.toString());
    } catch (_) {
      return '';
    }
    final local = dt.toLocal();
    final today = DateTime.now();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return DateFormat.Hm().format(local);
    }
    return DateFormat('MMM d, HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? Colors.white : Colors.black87;
    final secondary = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F4),
      appBar: AppBar(
        title: const Text('Alerts & activity'),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: primary,
        actions: [
          IconButton(
            tooltip: 'Notification preferences',
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageNotificationsPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _events.isEmpty
                  ? Center(
                      child: Text(
                        'No activity yet.',
                        style: TextStyle(color: secondary, fontSize: 16),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: secondary.withValues(alpha: 0.15)),
                        itemBuilder: (context, index) {
                          final raw = _events[index];
                          final event =
                              raw is Map
                                  ? Map<String, dynamic>.from(raw)
                                  : <String, dynamic>{};
                          final type = event['event_type'] ?? '';
                          final iconPair = _iconForType(type);
                          final iconData = iconPair.$1;
                          final iconColor = iconPair.$2;
                          final timeStr = _timestampLabel(event['timestamp']);

                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(iconData, color: iconColor, size: 22),
                            ),
                            title: Text(
                              event['title']?.toString() ?? 'Alert',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              event['description']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: secondary, fontSize: 13),
                            ),
                            trailing: timeStr.isEmpty
                                ? null
                                : Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EventPage(event: event),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Opens [DashboardNotificationsPage]. Optional [eventCountForBadge] shows a badge.
class DashboardBellButton extends StatelessWidget {
  final Color iconColor;
  final int eventCountForBadge;

  const DashboardBellButton({
    super.key,
    required this.iconColor,
    this.eventCountForBadge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      Icons.notifications_none_outlined,
      color: iconColor,
      size: 28,
    );

    Widget child = iconWidget;
    final n = eventCountForBadge;
    if (n > 0) {
      final label =
          n > 99 ? '99+' : '$n';
      child = Badge(
        backgroundColor: Colors.pink.shade300,
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        child: iconWidget,
      );
    }

    return IconButton(
      tooltip: 'Recent alerts',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DashboardNotificationsPage(),
          ),
        );
      },
      icon: child,
    );
  }
}
