import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'manage_modes_page.dart';
import 'manage_rooms_page.dart';

/// Device & System Management screen.
/// The "Device Status" row now performs a real periodic health check
/// against the backend (/api/health) and shows live online/offline/checking
/// state, plus the most recent ping latency. Other menu items remain
/// navigation to Manage Modes / Manage Rooms.
class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

enum _ServerStatus { checking, online, offline }

class _DeviceManagementPageState extends State<DeviceManagementPage> with WidgetsBindingObserver {
  _ServerStatus _status = _ServerStatus.checking;
  int? _latencyMs;
  DateTime? _lastSuccess;
  String? _errorMessage;
  Timer? _pollTimer;
  bool _isPinging = false;

  static const Duration _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ping();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _ping());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns to the app, refresh immediately so we don't
    // show a stale status from before the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      _ping();
    }
  }

  Future<void> _ping() async {
    if (_isPinging) return;
    _isPinging = true;
    if (mounted && _status == _ServerStatus.offline) {
      // Show "checking" briefly when transitioning from offline back to online
      setState(() => _status = _ServerStatus.checking);
    }
    final result = await AuthService().pingServer();
    if (!mounted) {
      _isPinging = false;
      return;
    }
    setState(() {
      if (result['online'] == true) {
        _status = _ServerStatus.online;
        _latencyMs = result['latencyMs'] as int?;
        _lastSuccess = DateTime.now();
        _errorMessage = null;
      } else {
        _status = _ServerStatus.offline;
        _latencyMs = result['latencyMs'] as int?;
        _errorMessage = result['error']?.toString();
      }
      _isPinging = false;
    });
  }

  Color get _dotColor {
    switch (_status) {
      case _ServerStatus.online:
        return Colors.green;
      case _ServerStatus.offline:
        return Colors.red;
      case _ServerStatus.checking:
        return Colors.amber;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case _ServerStatus.online:
        return 'Online';
      case _ServerStatus.offline:
        return 'Offline';
      case _ServerStatus.checking:
        return 'Checking...';
    }
  }

  String get _subText {
    switch (_status) {
      case _ServerStatus.online:
        final latency = _latencyMs != null ? ' • ${_latencyMs}ms' : '';
        return 'Connected to ${AuthService.baseUrl}$latency';
      case _ServerStatus.offline:
        if (_lastSuccess != null) {
          return 'Last connected ${_formatRelative(_lastSuccess!)}';
        }
        return _errorMessage ?? 'Cannot reach server';
      case _ServerStatus.checking:
        return 'Pinging ${AuthService.baseUrl}...';
    }
  }

  String _formatRelative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
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
                      _buildDeviceStatusItem(),
                      _buildDivider(),
                      _buildSettingsItem(
                        title: 'Manage modes',
                        icon: Icons.grid_view,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ManageModesPage(),
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildSettingsItem(
                        title: 'Manage Rooms',
                        icon: Icons.meeting_room,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ManageRoomsPage(),
                            ),
                          );
                        },
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

  Widget _buildHeader() {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(60)),
      ),
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.center,
            child: Text(
              'Device & System Management',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
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
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusItem() {
    return GestureDetector(
      onTap: _ping,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Device Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildStatusDot(),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _dotColor,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ],
              ),
            ),
            // Tap-to-refresh affordance
            Icon(
              Icons.refresh,
              size: 20,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot() {
    // Pulsing-style dot: the "checking" state uses a small circular indicator;
    // online/offline use a solid colored dot.
    if (_status == _ServerStatus.checking) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(_dotColor),
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _dotColor,
        boxShadow: [
          BoxShadow(
            color: _dotColor.withOpacity(0.35),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({required String title, required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 28, color: Colors.black),
            const SizedBox(width: 40),
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
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.only(left: 80, right: 40),
      child: Divider(color: Color(0xFFE0E0E0), thickness: 1, height: 1),
    );
  }
}
