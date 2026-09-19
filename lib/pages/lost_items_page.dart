import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../services/websocket_service.dart';
import 'camera_monitor_page.dart';
import 'dashboard_analytics_page.dart';
import 'dashboard_home_page.dart';
import 'dashboard_login_page.dart';
import 'dashboard_settings_page.dart';
import 'pet_station_page.dart';

/// Dashboard: items detected by the lost-item AI (one row per item + room).
class LostItemsPage extends StatefulWidget {
  const LostItemsPage({super.key});

  @override
  State<LostItemsPage> createState() => _LostItemsPageState();
}

class _LostItemsPageState extends State<LostItemsPage> {
  final AuthService _auth = AuthService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsSub;
  Timer? _pollTimer;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
    _setupWebSocket();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadItems(silent: true));
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _setupWebSocket() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;
    _ws.connect(userId: user.id);
    _wsSub = _ws.messageStream.listen((message) {
      if (message['type'] == 'lost_items_updated') {
        _loadItems(silent: true);
      }
    });
  }

  Future<void> _loadItems({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await _auth.getLostItems();
    if (!mounted) return;
    if (res['success'] == true) {
      final raw = res['items'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _loading = false;
        _items = list;
        _error = null;
      });
    } else {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Could not load items';
      });
    }
  }

  IconData _iconForClass(String? cls) {
    final c = (cls ?? '').toLowerCase();
    if (c.contains('key')) return Icons.key;
    if (c.contains('wallet')) return Icons.account_balance_wallet;
    if (c.contains('charger')) return Icons.battery_charging_full;
    if (c.contains('sunglass') || c.contains('glass')) return Icons.visibility;
    return Icons.inventory_2_outlined;
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown time';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('MMM d, yyyy · h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  void _openDetail(Map<String, dynamic> item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LostItemDetailPage(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sidebarColor = isLight ? Colors.grey[100]! : Colors.grey[900]!;
    final sidebarTextPrimary = isLight ? Colors.black : Colors.white;
    final sidebarTextSecondary = isLight ? Colors.grey[600]! : Colors.grey[400]!;
    final sidebarMenuSelected = isLight ? Colors.grey[300]! : Colors.grey[800]!;
    final sidebarMenuUnselected = isLight ? Colors.grey[500]! : Colors.grey[600]!;
    final mainTextPrimary = isLight ? Colors.black87 : Colors.white;
    final mainTextSecondary = isLight ? Colors.grey[700]! : Colors.grey[400]!;
    final cardColor = isLight ? Colors.white : Colors.grey[850]!;
    final bg = isLight ? const Color(0xFFF3F5F4) : const Color(0xFF121212);

    return Scaffold(
      backgroundColor: bg,
      body: Row(
        children: [
          Container(
            width: 240,
            color: sidebarColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Home',
                            style: TextStyle(
                              color: sidebarTextSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                          TextSpan(
                            text: 'Guardian',
                            style: TextStyle(
                              color: sidebarTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.dashboard,
                  'Dashboard',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const DashboardHomePage()),
                    (r) => false,
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.analytics,
                  'Analytics',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DashboardAnalyticsPage(),
                    ),
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.videocam,
                  'Monitor Home',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CameraMonitorPage(),
                    ),
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.pets,
                  'Pet Station',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PetStationPage(),
                    ),
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.search,
                  'Find Items',
                  true,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  null,
                ),
                const SizedBox(height: 16),
                _sidebarItem(
                  context,
                  Icons.settings,
                  'Settings',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DashboardSettingsPage(),
                    ),
                  ),
                ),
                _sidebarItem(
                  context,
                  Icons.logout,
                  'Log out',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () async {
                    await _auth.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const DashboardLoginPage(),
                        ),
                        (_) => false,
                      );
                    }
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeNotifier,
                    builder: (context, mode, _) {
                      final light = mode == ThemeMode.light;
                      return Row(
                        children: [
                          Switch(
                            value: light,
                            onChanged: (v) {
                              themeNotifier.value =
                                  v ? ThemeMode.light : ThemeMode.dark;
                            },
                          ),
                          Text(
                            light ? 'Switch to dark' : 'Switch to light',
                            style: TextStyle(color: sidebarTextPrimary),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search, color: mainTextPrimary, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Find My Items',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: mainTextPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _loadItems,
                        icon: Icon(Icons.refresh, color: mainTextSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items the AI has recently seen while monitoring. '
                    'Each row is one item in one room.',
                    style: TextStyle(color: mainTextSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: Colors.red.shade400),
                                ),
                              )
                            : _items.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 64,
                                          color: mainTextSecondary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No items tracked yet',
                                          style: TextStyle(
                                            color: mainTextPrimary,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Start monitoring a room — when the AI sees\n'
                                          'Keys, Wallet, Charger, or sunglasses, they appear here.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: mainTextSecondary),
                                        ),
                                      ],
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadItems,
                                    child: ListView.separated(
                                      itemCount: _items.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, index) {
                                        final item = _items[index];
                                        final cls =
                                            item['item_class']?.toString() ?? 'Item';
                                        final room =
                                            item['room_name']?.toString() ?? 'Unknown';
                                        return Material(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(12),
                                          elevation: isLight ? 1 : 0,
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor:
                                                  Colors.green.shade100,
                                              child: Icon(
                                                _iconForClass(cls),
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                            title: Text(
                                              cls,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: mainTextPrimary,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Room: $room · ${_formatTime(item['last_seen_at']?.toString())}',
                                              style: TextStyle(
                                                color: mainTextSecondary,
                                              ),
                                            ),
                                            trailing: Icon(
                                              Icons.chevron_right,
                                              color: mainTextSecondary,
                                            ),
                                            onTap: () => _openDetail(item),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    Color selectedColor,
    Color unselectedColor,
    Color textColor,
    VoidCallback? onTap,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: selected
          ? BoxDecoration(
              color: selectedColor,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        leading: Icon(icon, color: selected ? textColor : unselectedColor),
        title: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class LostItemDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;

  const LostItemDetailPage({super.key, required this.item});

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown time';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('EEEE, MMM d, yyyy · h:mm:ss a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final cls = item['item_class']?.toString() ?? 'Item';
    final room = item['room_name']?.toString() ?? 'Unknown';
    final shotUrl = auth.buildPhotoUrl(item['screenshot_path']?.toString());
    final conf = item['confidence'];
    final confStr = conf is num ? '${(conf * 100).toStringAsFixed(0)}%' : null;
    final screenH = MediaQuery.of(context).size.height;
    final imageHeight = (screenH * 0.55).clamp(320.0, 560.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(cls),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shotUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Image.network(
                    shotUrl,
                    width: double.infinity,
                    height: imageHeight,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: imageHeight,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: imageHeight,
                      alignment: Alignment.center,
                      color: Colors.grey.shade800,
                      child: const Text('Could not load screenshot'),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: imageHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No screenshot available'),
              ),
            const SizedBox(height: 8),
            Text(
              'Full room view · yellow box marks where the AI saw this item. Pinch to zoom.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _detailRow(Icons.meeting_room_outlined, 'Room', room),
            const SizedBox(height: 12),
            _detailRow(
              Icons.schedule,
              'Last seen',
              _formatTime(item['last_seen_at']?.toString()),
            ),
            if (confStr != null) ...[
              const SizedBox(height: 12),
              _detailRow(Icons.analytics_outlined, 'Confidence', confStr),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Colors.green.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
