import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/event_notifier.dart';
import 'camera_monitor_page.dart';
import 'dashboard_home_page.dart';
import 'dashboard_login_page.dart';
import 'dashboard_notifications_page.dart';
import 'dashboard_settings_page.dart';
import 'event_page.dart';
import 'lost_items_page.dart';
import 'pet_station_page.dart';

enum _AlertCategory { emergency, safety, security, warning, other }

enum _CategoryFilter { all, emergency, safety, security, warning }

/// Dashboard analytics — KPIs, pie/line/bar/stacked charts, drill-downs.
class DashboardAnalyticsPage extends StatefulWidget {
  const DashboardAnalyticsPage({super.key});

  @override
  State<DashboardAnalyticsPage> createState() => _DashboardAnalyticsPageState();
}

class _DashboardAnalyticsPageState extends State<DashboardAnalyticsPage> {
  final AuthService _auth = AuthService();
  EventNotifier? _eventsNotifier;

  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _storage;
  DateTime? _lastUpdated;
  int _rangeDays = 7;
  _CategoryFilter _filter = _CategoryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _eventsNotifier = context.read<EventNotifier>();
      _eventsNotifier!.addListener(_onEventsNotifierChanged);
    });
  }

  void _onEventsNotifierChanged() {
    if (mounted) _load(silent: true);
  }

  @override
  void dispose() {
    _eventsNotifier?.removeListener(_onEventsNotifierChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final ev = await _auth.getEvents();
      final st = await _auth.getStorageSummary();
      if (!mounted) return;
      List<Map<String, dynamic>> list = [];
      if (ev['success'] == true && ev['events'] is List) {
        list = (ev['events'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      setState(() {
        _events = list;
        _storage = st['success'] == true ? st : null;
        _loading = false;
        _lastUpdated = DateTime.now();
        if (ev['success'] != true) {
          _loadError = ev['message']?.toString() ?? 'Could not load events';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Connection error: $e';
        });
      }
    }
  }

  // ── Theme helpers (match dashboard home) ──

  bool _isLight(BuildContext context) =>
      themeNotifier.value == ThemeMode.light;

  Color _bg(bool light) => light ? Colors.white : Colors.black;
  Color _sidebar(bool light) => light ? Colors.grey[100]! : Colors.grey[900]!;
  Color _primary(bool light) => light ? Colors.black : Colors.white;
  Color _secondary(bool light) =>
      light ? Colors.grey[700]! : Colors.grey[400]!;
  Color _card(bool light) => light ? Colors.grey[200]! : Colors.grey[900]!;
  Color _menuSelected(bool light) => light ? Colors.grey[300]! : Colors.grey[800]!;
  Color _menuUnselected(bool light) =>
      light ? Colors.grey[800]! : Colors.grey[400]!;

  // ── Event parsing ──

  DateTime? _eventTime(Map<String, dynamic> e) {
    final t = e['timestamp'];
    if (t is String) return DateTime.tryParse(t);
    return null;
  }

  static _AlertCategory _categorize(Map<String, dynamic> e) {
    final type = (e['event_type'] ?? '').toString().toLowerCase();
    final title = (e['title'] ?? '').toString().toLowerCase();
    if (type == 'emergency' ||
        title.contains('fire') ||
        title.contains('sharp') ||
        title.contains('stranger') ||
        title.contains('critical')) {
      return _AlertCategory.emergency;
    }
    if (type == 'security' ||
        title.contains('door') ||
        title.contains('window') ||
        title.contains('exit')) {
      return _AlertCategory.security;
    }
    if (type == 'safety' ||
        title.contains('fall') ||
        title.contains('choking') ||
        title.contains('bed exit') ||
        title.contains('stuck')) {
      return _AlertCategory.safety;
    }
    if (type == 'warning' ||
        title.contains('pest') ||
        title.contains('hazard') ||
        title.contains('stillness') ||
        title.contains('food')) {
      return _AlertCategory.warning;
    }
    return _AlertCategory.other;
  }

  static String _categoryLabel(_AlertCategory c) {
    switch (c) {
      case _AlertCategory.emergency:
        return 'Emergency';
      case _AlertCategory.safety:
        return 'Safety';
      case _AlertCategory.security:
        return 'Security';
      case _AlertCategory.warning:
        return 'Warnings';
      case _AlertCategory.other:
        return 'Other';
    }
  }

  static Color _categoryColor(_AlertCategory c, bool light) {
    switch (c) {
      case _AlertCategory.emergency:
        return Colors.red.shade600;
      case _AlertCategory.safety:
        return Colors.deepPurple.shade400;
      case _AlertCategory.security:
        return Colors.blue.shade600;
      case _AlertCategory.warning:
        return Colors.amber.shade700;
      case _AlertCategory.other:
        return light ? Colors.grey.shade600 : Colors.grey.shade400;
    }
  }

  bool _matchesFilter(Map<String, dynamic> e) {
    if (_filter == _CategoryFilter.all) return true;
    final cat = _categorize(e);
    switch (_filter) {
      case _CategoryFilter.emergency:
        return cat == _AlertCategory.emergency;
      case _CategoryFilter.safety:
        return cat == _AlertCategory.safety;
      case _CategoryFilter.security:
        return cat == _AlertCategory.security;
      case _CategoryFilter.warning:
        return cat == _AlertCategory.warning;
      case _CategoryFilter.all:
        return true;
    }
  }

  List<Map<String, dynamic>> _eventsInRange(int days, {int offsetDays = 0}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: offsetDays));
    final start = end.subtract(Duration(days: days - 1));
    return _events.where((e) {
      if (!_matchesFilter(e)) return false;
      final dt = _eventTime(e);
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
  }

  List<Map<String, dynamic>> get _filtered => _eventsInRange(_rangeDays);

  List<Map<String, dynamic>> get _previousPeriod =>
      _eventsInRange(_rangeDays, offsetDays: _rangeDays);

  Map<_AlertCategory, int> get _byCategory {
    final m = <_AlertCategory, int>{};
    for (final e in _filtered) {
      final c = _categorize(e);
      m[c] = (m[c] ?? 0) + 1;
    }
    return m;
  }

  Map<String, int> get _byRoom {
    final m = <String, int>{};
    for (final e in _filtered) {
      final r = (e['room_name'] ?? '').toString().trim();
      final k = r.isEmpty ? 'Unknown' : r;
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  List<int> get _dailyBuckets {
    final counts = List<int>.filled(_rangeDays, 0);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _rangeDays - 1));
    for (final e in _filtered) {
      final dt = _eventTime(e);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = day.difference(start).inDays;
      if (diff >= 0 && diff < _rangeDays) counts[diff]++;
    }
    return counts;
  }

  List<Map<_AlertCategory, int>> get _dailyCategoryBuckets {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _rangeDays - 1));
    return List.generate(_rangeDays, (i) {
      final day = start.add(Duration(days: i));
      final m = <_AlertCategory, int>{};
      for (final e in _filtered) {
        final dt = _eventTime(e);
        if (dt == null) continue;
        if (DateTime(dt.year, dt.month, dt.day) == day) {
          final c = _categorize(e);
          m[c] = (m[c] ?? 0) + 1;
        }
      }
      return m;
    });
  }

  List<String> get _dayLabels {
    final now = DateTime.now();
    final fmt = _rangeDays > 14 ? DateFormat('M/d') : DateFormat('EEE d');
    return List.generate(_rangeDays, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _rangeDays - 1 - i));
      return fmt.format(d);
    });
  }

  List<int> get _hourBuckets {
    final counts = List<int>.filled(24, 0);
    for (final e in _filtered) {
      final dt = _eventTime(e);
      if (dt != null) counts[dt.hour]++;
    }
    return counts;
  }

  bool _hasVideo(Map<String, dynamic> e) {
    final u = e['video_url']?.toString() ?? '';
    final p = e['video_path']?.toString() ?? '';
    return u.isNotEmpty || p.isNotEmpty;
  }

  int get _criticalCount =>
      _filtered.where((e) => _categorize(e) == _AlertCategory.emergency).length;

  String? get _topRoom {
    if (_byRoom.isEmpty) return null;
    final top = _byRoom.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return top.key;
  }

  static String _trendLabel(int current, int previous) {
    if (previous == 0) {
      return current == 0 ? 'No change' : 'New activity';
    }
    final pct = ((current - previous) / previous * 100).round();
    if (pct == 0) return 'Same as prior period';
    return pct > 0 ? '↑ $pct% vs prior period' : '↓ ${pct.abs()}% vs prior period';
  }

  static String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _prettyType(String raw) {
    if (raw.isEmpty || raw == 'unknown') return 'Other';
    return raw
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // ── Drill-down ──

  void _openDrillDown({
    required String title,
    required List<Map<String, dynamic>> events,
    required bool light,
  }) {
    final fmt = DateFormat('EEE MMM d, yyyy · HH:mm');
    final primary = _primary(light);
    final secondary = _secondary(light);
    final sorted = List<Map<String, dynamic>>.from(events)
      ..sort((a, b) {
        final ta = _eventTime(a);
        final tb = _eventTime(b);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: light ? Colors.white : const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: secondary),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: secondary.withValues(alpha: 0.25)),
              Flexible(
                child: sorted.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No events', style: TextStyle(color: secondary)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final e = sorted[i];
                          final dt = _eventTime(e);
                          final timeStr = dt != null ? fmt.format(dt) : '—';
                          final titleStr =
                              (e['title'] ?? _prettyType((e['event_type'] ?? '').toString()))
                                  .toString();
                          final room = (e['room_name'] ?? '').toString().trim();
                          return ListTile(
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EventPage(event: e),
                                ),
                              );
                            },
                            leading: Icon(
                              Icons.notifications_active_outlined,
                              color: _categoryColor(_categorize(e), light),
                              size: 22,
                            ),
                            title: Text(
                              titleStr,
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '$timeStr · ${room.isEmpty ? 'Unknown room' : room}',
                              style: TextStyle(color: secondary, fontSize: 12),
                            ),
                            trailing: _hasVideo(e)
                                ? Icon(Icons.videocam, color: secondary, size: 20)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _eventsForDayIndex(int index) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _rangeDays - 1));
    final day = start.add(Duration(days: index));
    return _filtered.where((e) {
      final dt = _eventTime(e);
      if (dt == null) return false;
      final d = DateTime(dt.year, dt.month, dt.day);
      return d == day;
    }).toList();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        final light = _isLight(context);
        return Scaffold(
          backgroundColor: _bg(light),
          body: Row(
            children: [
              _buildSidebar(context, light),
              Expanded(child: _buildMain(context, light)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context, bool light) {
    return Container(
      width: 240,
      color: _sidebar(light),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'Home',
                    style: TextStyle(
                      color: _secondary(light),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  TextSpan(
                    text: 'Guardian',
                    style: TextStyle(
                      color: _primary(light),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          _navItem(context, light, 'Dashboard', Icons.dashboard, false, () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const DashboardHomePage()),
              );
            }
          }),
          _navItem(context, light, 'Analytics', Icons.analytics, true, null),
          _navItem(context, light, 'Monitor Home', Icons.videocam, false, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CameraMonitorPage()),
            );
          }),
          _navItem(context, light, 'Pet Station', Icons.pets, false, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PetStationPage()),
            );
          }),
          _navItem(context, light, 'Find Items', Icons.search, false, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LostItemsPage()),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Switch(
                  value: light,
                  onChanged: (v) {
                    themeNotifier.value = v ? ThemeMode.light : ThemeMode.dark;
                  },
                ),
                Text(
                  light ? 'Switch to dark' : 'Switch to light',
                  style: TextStyle(color: _primary(light), fontSize: 13),
                ),
              ],
            ),
          ),
          _navItem(context, light, 'Settings', Icons.settings, false, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DashboardSettingsPage()),
            );
          }),
          _navItem(context, light, 'Log out', Icons.logout, false, () async {
            await AuthService().logout();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DashboardLoginPage()),
                (_) => false,
              );
            }
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    bool light,
    String label,
    IconData icon,
    bool active,
    VoidCallback? onTap,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: active
          ? BoxDecoration(
              color: _menuSelected(light),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        leading: Icon(
          icon,
          color: active ? _primary(light) : _menuUnselected(light),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: _primary(light),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildMain(BuildContext context, bool light) {
    final primary = _primary(light);
    final secondary = _secondary(light);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: _loading
          ? _buildSkeleton(light)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analytics',
                              style: TextStyle(
                                color: primary,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _lastUpdated != null
                                  ? 'Monitoring insights · updated ${DateFormat('HH:mm').format(_lastUpdated!)}'
                                  : 'Monitoring insights',
                              style: TextStyle(color: secondary, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                      DashboardBellButton(
                        iconColor: primary,
                        eventCountForBadge: _events.length,
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: primary),
                        tooltip: 'Refresh',
                        onPressed: _load,
                      ),
                    ],
                  ),
                  if (_loadError != null) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.red.shade900.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        leading: const Icon(Icons.error_outline, color: Colors.red),
                        title: Text(_loadError!, style: TextStyle(color: primary)),
                        trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 days')),
                      ButtonSegment(value: 30, label: Text('30 days')),
                    ],
                    selected: {_rangeDays},
                    onSelectionChanged: (s) => setState(() => _rangeDays = s.first),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _CategoryFilter.values.map((f) {
                      final selected = _filter == f;
                      final label = f == _CategoryFilter.all
                          ? 'All'
                          : f.name[0].toUpperCase() + f.name.substring(1);
                      return FilterChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (_) => setState(() => _filter = f),
                        selectedColor: _categoryColor(
                          f == _CategoryFilter.all
                              ? _AlertCategory.other
                              : _AlertCategory.values[f.index - 1],
                          light,
                        ).withValues(alpha: 0.25),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _buildKpiRow(light),
                  const SizedBox(height: 20),
                  LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth >= 900;
                    final pie = _dashCard(
                      light,
                      child: _buildCategoryPie(light),
                    );
                    final line = _dashCard(
                      light,
                      child: _buildLineChart(light),
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: pie),
                          const SizedBox(width: 20),
                          Expanded(flex: 2, child: line),
                        ],
                      );
                    }
                    return Column(
                      children: [pie, const SizedBox(height: 16), line],
                    );
                  }),
                  const SizedBox(height: 16),
                  _dashCard(light, child: _buildStackedDailyChart(light)),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth >= 760;
                    final room = _dashCard(light, child: _buildRoomChart(light));
                    final hour = _dashCard(light, child: _buildHourChart(light));
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: room),
                          const SizedBox(width: 16),
                          Expanded(child: hour),
                        ],
                      );
                    }
                    return Column(
                      children: [room, const SizedBox(height: 16), hour],
                    );
                  }),
                  const SizedBox(height: 16),
                  _dashCard(light, child: _buildRecentCritical(light)),
                  if (_storage != null) ...[
                    const SizedBox(height: 16),
                    _dashCard(light, child: _buildStorageSection(light)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _dashCard(bool light, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card(light),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.08 : 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildKpiRow(bool light) {
    final total = _filtered.length;
    final prev = _previousPeriod.length;
    final critical = _criticalCount;
    final prevCritical = _previousPeriod
        .where((e) => _categorize(e) == _AlertCategory.emergency)
        .length;
    final withVideo =
        _filtered.where(_hasVideo).length;
    final videoPct = total > 0 ? (100 * withVideo / total).round() : 0;
    final topRoom = _topRoom ?? '—';
    final topRoomCount = _topRoom != null ? (_byRoom[_topRoom] ?? 0) : 0;
    final daily = _dailyBuckets;

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : 2;
      final cards = [
        _kpiCard(
          light,
          'Total alerts',
          '$total',
          _trendLabel(total, prev),
          daily,
          Colors.teal,
        ),
        _kpiCard(
          light,
          'Critical / emergency',
          '$critical',
          _trendLabel(critical, prevCritical),
          daily,
          Colors.red,
        ),
        _kpiCard(
          light,
          'With recording',
          total == 0 ? '0' : '$withVideo ($videoPct%)',
          'Clips captured in period',
          daily,
          Colors.blue,
        ),
        _kpiCard(
          light,
          'Most active room',
          topRoom,
          topRoomCount > 0 ? '$topRoomCount alerts' : 'No room data',
          daily,
          Colors.orange,
        ),
      ];
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: cards
            .map((w) => SizedBox(
                  width: cols == 4
                      ? (c.maxWidth - 48) / 4
                      : (c.maxWidth - 16) / 2,
                  child: w,
                ))
            .toList(),
      );
    });
  }

  Widget _kpiCard(
    bool light,
    String title,
    String value,
    String subtitle,
    List<int> sparkData,
    Color accent,
  ) {
    final primary = _primary(light);
    final secondary = _secondary(light);
    return _dashCard(
      light,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: secondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: secondary, fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: _miniSparkline(sparkData, accent, light),
          ),
        ],
      ),
    );
  }

  Widget _miniSparkline(List<int> data, Color color, bool light) {
    if (data.every((v) => v == 0)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('—', style: TextStyle(color: _secondary(light), fontSize: 11)),
      );
    }
    final maxY = data.reduce((a, b) => a > b ? a : b).toDouble().clamp(1.0, 999.0);
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              data.length,
              (i) => FlSpot(i.toDouble(), data[i].toDouble()),
            ),
            isCurved: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String hint, bool light) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _primary(light),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(color: _secondary(light), fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildCategoryPie(bool light) {
    final data = _byCategory;
    final total = _filtered.length;
    final primary = _primary(light);
    final secondary = _secondary(light);

    if (total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Alert mix', 'Tap a slice for details', light),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No alerts in this period',
              style: TextStyle(color: secondary),
            ),
          ),
        ],
      );
    }

    final sections = <PieChartSectionData>[];
    for (final cat in _AlertCategory.values) {
      final v = data[cat] ?? 0;
      if (v == 0) continue;
      sections.add(
        PieChartSectionData(
          value: v.toDouble(),
          title: '${(100 * v / total).round()}%',
          color: _categoryColor(cat, light),
          radius: 52,
          titleStyle: TextStyle(
            color: light ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Alert mix', 'Tap a slice to list matching events', light),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        if (event is! FlTapUpEvent) return;
                        final idx = response?.touchedSection?.touchedSectionIndex;
                        if (idx == null || idx < 0) return;
                        final cats = _AlertCategory.values
                            .where((c) => (data[c] ?? 0) > 0)
                            .toList();
                        if (idx >= cats.length) return;
                        final cat = cats[idx];
                        final evs = _filtered
                            .where((e) => _categorize(e) == cat)
                            .toList();
                        _openDrillDown(
                          title: '${_categoryLabel(cat)} · ${evs.length} events',
                          events: evs,
                          light: light,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _AlertCategory.values
                    .where((c) => (data[c] ?? 0) > 0)
                    .map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _categoryColor(c, light),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_categoryLabel(c)} (${data[c]})',
                          style: TextStyle(color: primary, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineChart(bool light) {
    final counts = _dailyBuckets;
    final labels = _dayLabels;
    final secondary = _secondary(light);
    final color = light ? Colors.teal.shade700 : Colors.tealAccent;

    if (counts.every((c) => c == 0)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Activity trend', 'Line chart · tap a point for that day', light),
          const SizedBox(height: 40),
          Center(child: Text('No activity in range', style: TextStyle(color: secondary))),
        ],
      );
    }

    final maxY =
        counts.reduce((a, b) => a > b ? a : b).toDouble().clamp(4.0, 9999.0);
    final spots = List.generate(
      counts.length,
      (i) => FlSpot(i.toDouble(), counts[i].toDouble()),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Activity trend',
          _rangeDays > 14
              ? 'Best for 30-day overview · tap a point'
              : 'Daily totals · tap a point',
          light,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: light ? Colors.black12 : Colors.white12,
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _rangeDays > 14 ? 5 : 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      if (_rangeDays > 14 && i % 5 != 0 && i != labels.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        labels[i],
                        style: TextStyle(fontSize: 9, color: secondary),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: secondary),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final idx = response?.lineBarSpots?.firstOrNull?.x.toInt();
                  if (idx == null || idx < 0 || idx >= labels.length) return;
                  final evs = _eventsForDayIndex(idx);
                  if (evs.isEmpty) return;
                  _openDrillDown(
                    title: '${labels[idx]} · ${evs.length} events',
                    events: evs,
                    light: light,
                  );
                },
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                      radius: _rangeDays <= 14 ? 4 : 2,
                      color: color,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackedDailyChart(bool light) {
    final buckets = _dailyCategoryBuckets;
    final labels = _dayLabels;
    final secondary = _secondary(light);

    if (_filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Daily breakdown by category', 'Stacked bars', light),
          const SizedBox(height: 32),
          Center(child: Text('No data', style: TextStyle(color: secondary))),
        ],
      );
    }

    double maxY = 4;
    for (final m in buckets) {
      final sum = m.values.fold<int>(0, (a, b) => a + b);
      if (sum > maxY) maxY = sum.toDouble();
    }
    maxY = (maxY + 1).clamp(4.0, 9999.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Daily breakdown by category',
          'Stacked bars · tap a day',
          light,
        ),
        const SizedBox(height: 12),
        _categoryLegend(light),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final idx = response?.spot?.touchedBarGroupIndex;
                  if (idx == null || idx < 0) return;
                  final evs = _eventsForDayIndex(idx);
                  if (evs.isEmpty) return;
                  _openDrillDown(
                    title: '${labels[idx]} · ${evs.length} events',
                    events: evs,
                    light: light,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[i],
                          style: TextStyle(fontSize: 9, color: secondary),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: secondary),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: light ? Colors.black12 : Colors.white12,
                ),
              ),
              barGroups: List.generate(buckets.length, (i) {
                final m = buckets[i];
                double bottom = 0;
                final rods = <BarChartRodData>[];
                for (final cat in _AlertCategory.values) {
                  final v = (m[cat] ?? 0).toDouble();
                  if (v <= 0) continue;
                  rods.add(
                    BarChartRodData(
                      fromY: bottom,
                      toY: bottom + v,
                      width: _rangeDays > 14 ? 8 : 16,
                      color: _categoryColor(cat, light),
                      borderRadius: BorderRadius.zero,
                    ),
                  );
                  bottom += v;
                }
                if (rods.isEmpty) {
                  rods.add(
                    BarChartRodData(
                      toY: 0,
                      width: _rangeDays > 14 ? 8 : 16,
                      color: Colors.transparent,
                    ),
                  );
                }
                return BarChartGroupData(x: i, barRods: rods);
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryLegend(bool light) {
    return Wrap(
      spacing: 12,
      children: _AlertCategory.values.map((c) {
        final n = _byCategory[c] ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              color: _categoryColor(c, light),
            ),
            const SizedBox(width: 4),
            Text(
              '${_categoryLabel(c)} ($n)',
              style: TextStyle(color: _secondary(light), fontSize: 11),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildRoomChart(bool light) {
    final entries = _byRoom.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(8).toList();
    final max = top.isEmpty ? 1 : top.first.value;
    final primary = _primary(light);
    final secondary = _secondary(light);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('By room', 'Horizontal bars · tap a row', light),
        const SizedBox(height: 16),
        if (top.isEmpty)
          Text('—', style: TextStyle(color: secondary))
        else
          ...top.map((e) {
            final frac = e.value / max;
            final isHot = e.key == _topRoom && e.value > 0;
            return InkWell(
              onTap: () {
                final evs = _filtered.where((ev) {
                  final r = (ev['room_name'] ?? '').toString().trim();
                  return (r.isEmpty ? 'Unknown' : r) == e.key;
                }).toList();
                _openDrillDown(
                  title: '${e.key} · ${evs.length} events',
                  events: evs,
                  light: light,
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: primary, fontSize: 13),
                          ),
                        ),
                        if (isHot)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Hotspot',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        Text(
                          '${e.value}',
                          style: TextStyle(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 10,
                        backgroundColor: light ? Colors.black12 : Colors.white12,
                        color: isHot
                            ? Colors.orange.shade700
                            : (light ? Colors.teal.shade700 : Colors.tealAccent),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHourChart(bool light) {
    final counts = _hourBuckets;
    final secondary = _secondary(light);
    final color = light ? Colors.blue.shade700 : Colors.lightBlueAccent;

    int peakHour = 0;
    for (var h = 0; h < 24; h++) {
      if (counts[h] > counts[peakHour]) peakHour = h;
    }

    if (counts.every((c) => c == 0)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Activity by hour', 'Local time', light),
          const SizedBox(height: 32),
          Center(child: Text('No hourly data', style: TextStyle(color: secondary))),
        ],
      );
    }

    final maxY =
        counts.reduce((a, b) => a > b ? a : b).toDouble().clamp(4.0, 9999.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Activity by hour',
          'Peak: ${peakHour.toString().padLeft(2, '0')}:00 · tap a bar',
          light,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final h = response?.spot?.touchedBarGroupIndex;
                  if (h == null || h < 0 || h > 23) return;
                  final evs = _filtered.where((e) {
                    final dt = _eventTime(e);
                    return dt != null && dt.hour == h;
                  }).toList();
                  if (evs.isEmpty) return;
                  _openDrillDown(
                    title: '${h.toString().padLeft(2, '0')}:00 · ${evs.length} events',
                    events: evs,
                    light: light,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, m) {
                      final h = v.toInt();
                      if (h != 0 && h != 6 && h != 12 && h != 18 && h != 23) {
                        return const SizedBox.shrink();
                      }
                      return Text('$h', style: TextStyle(fontSize: 9, color: secondary));
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, m) => Text(
                      v.toInt().toString(),
                      style: TextStyle(fontSize: 10, color: secondary),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: light ? Colors.black12 : Colors.white12,
                ),
              ),
              barGroups: List.generate(24, (h) {
                return BarChartGroupData(
                  x: h,
                  barRods: [
                    BarChartRodData(
                      toY: counts[h].toDouble(),
                      width: 6,
                      color: h == peakHour ? Colors.orange.shade700 : color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentCritical(bool light) {
    final primary = _primary(light);
    final secondary = _secondary(light);
    final critical = _filtered
        .where((e) => _categorize(e) == _AlertCategory.emergency)
        .toList()
      ..sort((a, b) {
        final ta = _eventTime(a);
        final tb = _eventTime(b);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    final recent = critical.take(5).toList();
    final fmt = DateFormat('MMM d · HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Recent critical alerts', 'Latest emergency events', light),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Text(
            'No critical alerts in this period — home looks quiet.',
            style: TextStyle(color: secondary, fontSize: 13),
          )
        else
          ...recent.map((e) {
            final dt = _eventTime(e);
            final title = (e['title'] ?? 'Alert').toString();
            final room = (e['room_name'] ?? 'Unknown').toString();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
              title: Text(
                title,
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                '${dt != null ? fmt.format(dt) : '—'} · $room',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => EventPage(event: e)),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStorageSection(bool light) {
    final s = _storage!;
    final clips = (s['clips_bytes'] as num?)?.toInt() ?? 0;
    final faces = (s['known_faces_bytes'] as num?)?.toInt() ?? 0;
    final prof = (s['profile_images_bytes'] as num?)?.toInt() ?? 0;
    final total = clips + faces + prof;
    final eventsTotal = (s['event_count'] as num?)?.toInt() ?? 0;
    final withVideo = (s['events_with_video'] as num?)?.toInt() ?? 0;
    final retention = (s['retention_days'] as num?)?.toInt() ?? 30;
    final lowDisk = s['low_disk_warning'] == true;
    final primary = _primary(light);
    final secondary = _secondary(light);

    final sections = <PieChartSectionData>[];
    if (total > 0) {
      if (clips > 0) {
        sections.add(PieChartSectionData(
          value: clips.toDouble(),
          color: Colors.teal,
          title: 'Clips',
          radius: 40,
          titleStyle: const TextStyle(fontSize: 9, color: Colors.white),
        ));
      }
      if (faces > 0) {
        sections.add(PieChartSectionData(
          value: faces.toDouble(),
          color: Colors.indigo,
          title: 'Faces',
          radius: 40,
          titleStyle: const TextStyle(fontSize: 9, color: Colors.white),
        ));
      }
      if (prof > 0) {
        sections.add(PieChartSectionData(
          value: prof.toDouble(),
          color: Colors.blueGrey,
          title: 'Profile',
          radius: 40,
          titleStyle: const TextStyle(fontSize: 9, color: Colors.white),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Storage & recordings', '', light),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sections.isNotEmpty)
              SizedBox(
                width: 120,
                height: 120,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    sectionsSpace: 2,
                    centerSpaceRadius: 24,
                  ),
                ),
              ),
            if (sections.isNotEmpty) const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total media: ${_formatBytes(total)}',
                    style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'All-time: $eventsTotal events · $withVideo with video',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  Text(
                    'Retention: $retention days',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DashboardSettingsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Manage retention in Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (lowDisk) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade900.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade200, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Low disk space on server. Consider purging old recordings.',
                    style: TextStyle(color: Colors.amber.shade100, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSkeleton(bool light) {
    final block = Container(
      height: 88,
      decoration: BoxDecoration(
        color: _card(light),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return ListView(
      children: [
        Container(
          height: 32,
          width: 180,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: _card(light),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(4, (_) => SizedBox(width: 200, child: block)),
        ),
        const SizedBox(height: 20),
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: _card(light),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: _card(light),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}
