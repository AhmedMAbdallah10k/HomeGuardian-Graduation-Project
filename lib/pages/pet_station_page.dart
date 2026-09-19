import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../services/websocket_service.dart';
import '../widgets/pet_station_cam_view.dart';
import 'camera_monitor_page.dart';
import 'dashboard_analytics_page.dart';
import 'dashboard_login_page.dart';
import 'dashboard_notifications_page.dart';
import 'dashboard_settings_page.dart';
import 'lost_items_page.dart';

/// IoT Pet Station dashboard — live ESP32-CAM feed + feeder status (LAN direct video).
class PetStationPage extends StatefulWidget {
  const PetStationPage({super.key});

  @override
  State<PetStationPage> createState() => _PetStationPageState();
}

class _PetStationPageState extends State<PetStationPage> {
  final AuthService _auth = AuthService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsSub;
  Timer? _statusTimer;
  Timer? _snapshotTimer;

  bool _loading = true;
  bool _saving = false;
  bool _configured = false;
  String? _camIp;
  String? _mainIp;
  String? _deviceToken;
  String? _lastSeen;
  Map<String, dynamic> _lastDetection = {};
  List<String> _events = [];

  late final TextEditingController _camCtrl;
  late final TextEditingController _mainCtrl;

  int _snapshotTick = 0;
  String _feedMode = 'Connecting…';

  @override
  void initState() {
    super.initState();
    _camCtrl = TextEditingController();
    _mainCtrl = TextEditingController();
    _loadStatus();
    _setupWebSocket();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _statusTimer?.cancel();
    _snapshotTimer?.cancel();
    _camCtrl.dispose();
    _mainCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final res = await _auth.getPetStationStatus();
    if (!mounted) return;

    if (res['success'] == true) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _loading = false;
        _configured = data['configured'] == true;
        _camIp = data['cam_ip']?.toString();
        _mainIp = data['main_ip']?.toString();
        _deviceToken = data['device_token']?.toString();
        _lastSeen = data['last_seen']?.toString();
        _lastDetection = Map<String, dynamic>.from(
          (data['last_detection'] as Map?) ?? {},
        );
        _events = _parseEventList(data['events']);
        // Keep text fields in sync with saved DB values (unless user is typing).
        if (!_camCtrl.selection.isValid || _camCtrl.text.isEmpty) {
          _camCtrl.text = _camIp ?? '';
        }
        if (!_mainCtrl.selection.isValid || _mainCtrl.text.isEmpty) {
          _mainCtrl.text = _mainIp ?? '';
        }
      });
      _restartSnapshotPolling();
    } else {
      setState(() => _loading = false);
    }
  }

  void _restartSnapshotPolling() {
    _snapshotTimer?.cancel();
    final ip = (_camIp ?? '').trim();
    if (ip.isEmpty) {
      setState(() => _feedMode = 'Set CAM IP in settings');
      return;
    }
    setState(() {
      _feedMode = kIsWeb
          ? 'Live stream · http://$ip:81/stream'
          : 'Snapshot from CAM (3s)';
      _snapshotTick = 0;
    });
    if (!kIsWeb) {
      _snapshotTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() => _snapshotTick++);
      });
    }
  }

  void _setupWebSocket() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;
    _ws.connect(userId: user.id);
    _wsSub = _ws.messageStream.listen((message) {
      final type = message['type']?.toString() ?? '';
      if (type == 'pet_station_alert' ||
          type == 'food_dispensed' ||
          type == 'food_cancelled' ||
          type == 'event_created') {
        final msg = message['message']?.toString().trim() ?? '';
        if (msg.isNotEmpty && mounted) {
          setState(() {
            _events.remove(msg);
            _events.insert(0, msg);
            if (_events.length > 30) {
              _events = _events.take(30).toList();
            }
          });
        }
        _loadStatus();
      }
      final inApp =
          Provider.of<UserProvider>(context, listen: false).inAppAlertsEnabled;
      if (!mounted || !inApp) return;
      if (type == 'food_dispensed') {
        _showSnack('Pet food dispensed', Colors.green.shade700);
      } else if (type == 'food_cancelled') {
        _showSnack('Pet feeding cancelled', Colors.orange.shade800);
      } else if (type == 'pet_station_alert') {
        _showSnack(message['message']?.toString() ?? 'Pet Station alert', Colors.blue.shade800);
      }
    });
  }

  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _saveSettings({bool regenerateToken = false}) async {
    setState(() => _saving = true);
    final res = await _auth.savePetStationSettings(
      camIp: _camCtrl.text,
      mainIp: _mainCtrl.text,
      regenerateToken: regenerateToken,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (res['success'] == true) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _configured = true;
        _camIp = data['cam_ip']?.toString();
        _mainIp = data['main_ip']?.toString();
        _deviceToken = data['device_token']?.toString();
      });
      _restartSnapshotPolling();
      _showSnack('Pet Station settings saved', Colors.green.shade700);
    } else {
      _showSnack(res['message']?.toString() ?? 'Save failed', Colors.red.shade800);
    }
  }

  String get _analyzeUrl => '${AuthService.baseUrl}/api/pet-station/analyze';
  String get _eventUrl => '${AuthService.baseUrl}/api/pet-station/event';

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sidebarColor = isLight ? Colors.grey[100]! : Colors.grey[900]!;
    final sidebarTextPrimary = isLight ? Colors.black : Colors.white;
    final sidebarTextSecondary =
        isLight ? Colors.grey[700]! : const Color.fromARGB(255, 142, 142, 142);
    final sidebarMenuSelected = isLight ? Colors.grey[300]! : Colors.grey[800]!;
    final sidebarMenuUnselected = isLight ? Colors.grey[800]! : Colors.grey[400]!;
    final mainTextPrimary = isLight ? Colors.black : Colors.white;
    final mainTextSecondary = isLight ? Colors.grey[700]! : Colors.grey[400]!;
    final cardColor = isLight ? Colors.grey[200]! : Colors.grey[900]!;
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
                  () => Navigator.of(context).popUntil((r) => r.isFirst),
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
                  true,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  null,
                ),
                _sidebarItem(
                  context,
                  Icons.search,
                  'Find Items',
                  false,
                  sidebarMenuSelected,
                  sidebarMenuUnselected,
                  sidebarTextPrimary,
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LostItemsPage(),
                    ),
                  ),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pet Station',
                                  style: TextStyle(
                                    color: mainTextPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Smart feeder · ESP32-CAM + main controller',
                                  style: TextStyle(
                                    color: mainTextSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DashboardBellButton(iconColor: mainTextPrimary),
                                IconButton(
                                  icon: Icon(Icons.refresh, color: mainTextPrimary),
                                  tooltip: 'Refresh',
                                  onPressed: _loadStatus,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSettingsCard(
                          cardColor,
                          mainTextPrimary,
                          mainTextSecondary,
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 900;
                            final feed = _buildFeedCard(
                              cardColor,
                              mainTextPrimary,
                              mainTextSecondary,
                            );
                            final side = Column(
                              children: [
                                _buildStatusCard(
                                  cardColor,
                                  mainTextPrimary,
                                  mainTextSecondary,
                                ),
                                const SizedBox(height: 16),
                                _buildEventsCard(
                                  cardColor,
                                  mainTextPrimary,
                                  mainTextSecondary,
                                ),
                              ],
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: feed),
                                  const SizedBox(width: 20),
                                  Expanded(flex: 2, child: side),
                                ],
                              );
                            }
                            return Column(
                              children: [feed, const SizedBox(height: 16), side],
                            );
                          },
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

  Widget _buildFeedCard(Color cardColor, Color primary, Color secondary) {
    final ip = (_camIp ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videocam, color: primary),
              const SizedBox(width: 8),
              Text(
                'Live Camera Feed',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ip.isEmpty
                  ? Center(
                      child: Text(
                        'Configure CAM IP below',
                        style: TextStyle(color: secondary),
                      ),
                    )
                  : buildPetStationCamView(
                      camIp: ip,
                      refreshTick: _snapshotTick,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(_feedMode, style: TextStyle(color: secondary, fontSize: 12)),
          if (ip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Direct from ESP32-CAM on your Wi‑Fi',
              style: TextStyle(color: secondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(Color cardColor, Color primary, Color secondary) {
    final det = _lastDetection;
    final detected = det['detected'] == true;
    final eating = det['eating'] == true;
    final petClass = det['class']?.toString();
    final lastTime = det['time']?.toString() ?? 'Never';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Status',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _statusRow('Configured', _configured ? 'Yes' : 'No', primary, secondary),
          _statusRow(
            'Last detection',
            detected ? (petClass ?? 'pet') : 'No pet',
            primary,
            secondary,
            valueColor: detected ? Colors.green : Colors.orange,
          ),
          _statusRow(
            'Eating',
            eating ? 'Yes' : 'No',
            primary,
            secondary,
            valueColor: eating ? Colors.green : Colors.orange,
          ),
          _statusRow('Last check', lastTime, primary, secondary),
          if (_lastSeen != null)
            _statusRow('Device last seen', _formatIso(_lastSeen!), primary, secondary),
        ],
      ),
    );
  }

  Widget _statusRow(
    String label,
    String value,
    Color primary,
    Color secondary, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: secondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsCard(Color cardColor, Color primary, Color secondary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eventTextColor = _eventTextColor(isDark);
    final eventBoxColor = _eventBoxColor(isDark);
    final visibleEvents = _events
        .map((e) => _formatEventLine(e))
        .where((e) => e.isNotEmpty)
        .take(12)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Events',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          if (visibleEvents.isEmpty)
            Text('No events yet', style: TextStyle(color: secondary))
          else
            ...visibleEvents.map(
              (e) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: eventBoxColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: _eventBorderColor(e),
                      width: 4,
                    ),
                  ),
                ),
                child: SelectableText(
                  e,
                  style: TextStyle(
                    color: eventTextColor,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _parseEventList(dynamic raw) {
    if (raw is! List) return [];
    final out = <String>[];
    for (final item in raw) {
      final line = _eventToDisplayLine(item);
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  String _eventToDisplayLine(dynamic item) {
    if (item is String) return _formatEventLine(item);
    if (item is Map) {
      final m = Map<String, dynamic>.from(item);
      final ts = (m['time'] ?? m['timestamp'] ?? '').toString().trim();
      final ev = (m['event'] ?? m['message'] ?? m['title'] ?? '').toString().trim();
      final st = (m['state'] ?? '').toString().trim();
      if (ts.isNotEmpty || ev.isNotEmpty || st.isNotEmpty) {
        return _formatEventLine('$ts | $ev | state=$st');
      }
    }
    return _formatEventLine(item.toString());
  }

  String _formatEventLine(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == '| state=' || s == 'state=') {
      return '';
    }
    final parts = s.split('|').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) {
      return '${parts[0]}  ·  ${parts[1]}  ·  ${parts[2]}';
    }
    if (parts.length == 2) {
      return '${parts[0]}  ·  ${parts[1]}';
    }
    return s;
  }

  Color _eventBorderColor(String e) {
    final lower = e.toLowerCase();
    if (lower.contains('dispense')) return Colors.green;
    if (lower.contains('cancel')) return Colors.red;
    if (lower.contains('not_eating')) return Colors.orange;
    if (lower.contains('eating')) return Colors.green;
    return Colors.blue;
  }

  Color _eventTextColor(bool isDark) =>
      isDark ? Colors.white : Colors.black87;

  Color _eventBoxColor(bool isDark) =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFFAFAFA);

  Widget _buildSettingsCard(Color cardColor, Color primary, Color secondary) {
    final user = Provider.of<UserProvider>(context).user;
    final isOwner = user != null && !user.isFamilyMember;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwner ? Colors.green.withValues(alpha: 0.35) : Colors.orange.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, color: isOwner ? Colors.green : Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                'Device Setup — edit IPs here',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!isOwner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'You are logged in as a family member. Log out and sign in with the '
                'home owner account to edit these fields and save.',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
              ),
            )
          else
            Text(
              'Type your board IPs below, then click Save settings. '
              '(System Status above is read-only.)',
              style: TextStyle(color: secondary, fontSize: 13),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _camCtrl,
            enabled: isOwner,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'ESP32-CAM IP (editable)',
              hintText: 'e.g. 172.24.150.185',
              helperText: 'From CAM Serial Monitor: "CAM IP: ..."',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mainCtrl,
            enabled: isOwner,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Main ESP32 IP (editable)',
              hintText: 'e.g. 172.24.149.191',
              helperText: 'From main board Serial: "WiFi: ..."',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(height: 16),
            if ((_deviceToken ?? '').isNotEmpty) ...[
              Text('Device token (X-Device-Token)', style: TextStyle(color: secondary)),
              const SizedBox(height: 6),
              SelectableText(
                _deviceToken!,
                style: TextStyle(color: primary, fontFamily: 'monospace', fontSize: 12),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _deviceToken!));
                  _showSnack('Token copied', Colors.green.shade700);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy token'),
              ),
            ],
            const SizedBox(height: 8),
            _endpointRow('Analyze URL', _analyzeUrl, primary, secondary),
            _endpointRow('Event URL', _eventUrl, primary, secondary),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : () => _saveSettings(),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save settings'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Regenerate token?'),
                              content: const Text(
                                'You must update both ESP32 devices with the new token.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Regenerate'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await _saveSettings(regenerateToken: true);
                        },
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('New token'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _endpointRow(
    String label,
    String url,
    Color primary,
    Color secondary,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: secondary, fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              url,
              style: TextStyle(color: primary, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              _showSnack('Copied', Colors.green.shade700);
            },
          ),
        ],
      ),
    );
  }

  String _formatIso(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
