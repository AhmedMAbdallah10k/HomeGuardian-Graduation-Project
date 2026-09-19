import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../main.dart'; // Import to access themeNotifier
import '../widgets/camera_monitor_widget.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../services/auth_service.dart';
import '../services/camera_service.dart';
import 'dashboard_login_page.dart';
import 'dashboard_analytics_page.dart';
import 'dashboard_settings_page.dart';
import 'dashboard_notifications_page.dart';
import 'full_screen_camera_page.dart';
import 'pet_station_page.dart';
import 'lost_items_page.dart';
import 'dart:async';

class CameraMonitorPage extends StatefulWidget {
  const CameraMonitorPage({super.key});

  @override
  State<CameraMonitorPage> createState() => _CameraMonitorPageState();
}

class _CameraMonitorPageState extends State<CameraMonitorPage> {
  @override
  void initState() {
    super.initState();
    CameraService().initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncMonitorRoomsFromBackend();
    });
  }

  Future<void> _syncMonitorRoomsFromBackend() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null || !mounted) return;

    final res = await AuthService().getCameraAssignment();
    if (!mounted) return;
    if (res['success'] != true) return;

    List<dynamic> list = [];
    if (res['assignments'] != null && (res['assignments'] as List).isNotEmpty) {
      list = res['assignments'] as List;
    } else if (res['assignment'] != null) {
      list = [res['assignment']];
    }
    if (list.isEmpty) return;

    await CameraService().applyAssignmentsFromServer(list);
    for (final raw in list) {
      final m = raw as Map;
      final name = m['room_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        CameraService().startMonitoring(user.id, name);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we are on a large screen or small screen (mobile)
    // For this specific design, it looks like a tablet/desktop dashboard.
    // We will use a Row for the sidebar and content.
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Expanded(flex: 2, child: _buildSidebar(context)),
          // Main Content
          Expanded(flex: 8, child: _buildMainContent(context)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sidebarColor = isLight
        ? Colors.grey[100]!
        : const Color(0xFF1E1E1E); // Adjusted to dark grey for consistency
    final sidebarTextPrimary = isLight ? Colors.black : Colors.white;
    final sidebarTextSecondary = isLight
        ? Colors.grey[700]!
        : const Color.fromARGB(255, 142, 142, 142);
    final sidebarMenuSelected = isLight ? Colors.grey[300]! : Colors.grey[800]!;
    final sidebarMenuUnselected = isLight
        ? Colors.grey[800]!
        : Colors.grey[400]!;

    return Container(
      color: sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo / Title
          Padding(
            padding: const EdgeInsets.all(24.0),
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

          // Menu Items
          _buildSidebarItem(
            context,
            'Dashboard',
            Icons.dashboard,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ),
          _buildSidebarItem(
            context,
            'Analytics',
            Icons.analytics_outlined,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ),
          _buildSidebarItem(
            context,
            'Monitor Home',
            Icons.videocam,
            true,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ), // Active Item
          _buildSidebarItem(
            context,
            'Pet Station',
            Icons.pets,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ),
          _buildSidebarItem(
            context,
            'Find Items',
            Icons.search,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ),
          const SizedBox(height: 24),
          _buildSidebarItem(
            context,
            'Settings',
            Icons.settings_outlined,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
          ),
          _buildSidebarItem(
            context,
            'Log out',
            Icons.logout,
            false,
            sidebarMenuSelected,
            sidebarMenuUnselected,
            sidebarTextPrimary,
            isLogout: true,
          ),
          const Spacer(),

          // Theme Toggle
          _buildThemeToggle(sidebarTextPrimary),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context,
    String title,
    IconData icon,
    bool isActive,
    Color selectedColor,
    Color unselectedColor,
    Color textColor, {
    bool isLogout = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: isActive
          ? BoxDecoration(
              color: selectedColor,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        leading: Icon(icon, color: isActive ? textColor : unselectedColor),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: () async {
          if (isLogout) {
            // Manual logout DOES clear the token
            await AuthService().logout();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => const DashboardLoginPage()),
                (route) => false,
              );
            }
          } else if (title == 'Dashboard') {
            Navigator.of(context).pop();
          } else if (title == 'Analytics') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DashboardAnalyticsPage(),
              ),
            );
          } else if (title == 'Pet Station') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PetStationPage(),
              ),
            );
          } else if (title == 'Find Items') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const LostItemsPage(),
              ),
            );
          } else if (title == 'Settings') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DashboardSettingsPage(),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildThemeToggle(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, mode, child) {
          bool isLight = mode == ThemeMode.light;
          return GestureDetector(
            onTap: () {
              themeNotifier.value = isLight ? ThemeMode.dark : ThemeMode.light;
            },
            child: Row(
              children: [
                Switch(
                  value: isLight,
                  onChanged: (val) {
                    themeNotifier.value = val
                        ? ThemeMode.light
                        : ThemeMode.dark;
                  },
                ),
                Text(
                  isLight ? 'Switch to dark' : 'Switch to light',
                  style: TextStyle(color: textColor),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    // Determine background based on theme (though specific design calls for black everywhere,
    // the user asked for light/dark modes).
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? Colors.black : const Color(0xFFF5F5F5),
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
                    'Hello!',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    'Welcome back to your dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey : Colors.grey[700],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DashboardBellButton(
                    iconColor: isDark ? Colors.white : Colors.black,
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh,
                        color: isDark ? Colors.white : Colors.black, size: 28),
                    onPressed: () => CameraService().initialize(force: true),
                    tooltip: 'Reset Cameras',
                  ),
                  IconButton(
                    icon: Icon(Icons.settings,
                        color: isDark ? Colors.white : Colors.black, size: 28),
                    onPressed: () => _showMonitorRoomsConfig(context),
                    tooltip: 'Configure rooms',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ListenableBuilder(
                  listenable: CameraService(),
                  builder: (context, _) {
                    final cs = CameraService();
                    final tileCount = cs.monitorRoomCount;
                    if (tileCount == 0) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.meeting_room_outlined,
                                size: 56,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'No rooms yet',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Use Configure rooms to add a room, name it, and assign a camera. Each room you add appears here as another tile.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                  height: 1.35,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 28),
                              FilledButton.icon(
                                onPressed: () =>
                                    _showMonitorRoomsConfig(context),
                                icon: const Icon(Icons.add_home_work_outlined),
                                label: const Text('Configure rooms'),
                              ),
                              if (cs.availableCameraCount <= 0) ...[
                                const SizedBox(height: 20),
                                Text(
                                  cs.statusMessage.contains('No cameras')
                                      ? 'No camera hardware detected. Connect cameras and use refresh (toolbar).'
                                      : 'Initializing cameras…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: tileCount,
                      itemBuilder: (context, index) {
                        final room = cs.monitorRooms[index];
                        return _buildCameraWindow(context, room);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showMonitorRoomsConfig(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => _MonitorRoomsConfigDialog(isDark: isDark),
    );
  }

  Widget _buildCameraWindow(BuildContext context, MonitorRoom room) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final userId = userProvider.user?.id ?? 0;
        return GestureDetector(
          onTap: () {
            debugPrint('CameraMonitorPage: Opening full screen for ${room.name}');
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FullScreenCameraPage(roomName: room.name),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: userId == 0
                  ? const Center(child: Text('Please login'))
                  : CameraMonitorWidget(
                      key: ValueKey('cam_${room.id}'),
                      roomName: room.name,
                      userId: userId,
                      isLive: true,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomDraft {
  final String id;
  final TextEditingController nameCtrl;
  int cameraIndex;
  final Set<String> monitorModes;

  _RoomDraft({
    required this.id,
    required this.nameCtrl,
    this.cameraIndex = 0,
    Set<String>? monitorModes,
  }) : monitorModes = Set<String>.from(monitorModes ?? const []);
}

class _MonitorRoomsConfigDialog extends StatefulWidget {
  final bool isDark;

  const _MonitorRoomsConfigDialog({required this.isDark});

  @override
  State<_MonitorRoomsConfigDialog> createState() =>
      _MonitorRoomsConfigDialogState();
}

class _MonitorRoomsConfigDialogState extends State<_MonitorRoomsConfigDialog> {
  late List<_RoomDraft> _drafts;
  bool _saving = false;
  late Future<List<Map<String, dynamic>>> _camerasFuture;

  @override
  void initState() {
    super.initState();
    final cs = CameraService();
    _drafts = cs.monitorRooms
        .map(
          (r) => _RoomDraft(
            id: r.id,
            nameCtrl: TextEditingController(text: r.name),
            cameraIndex: r.cameraIndex,
            monitorModes: Set<String>.from(r.monitorModes),
          ),
        )
        .toList();
    _camerasFuture = CameraService().getAvailablePhysicalCameras();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _camerasFuture = CameraService().getAvailablePhysicalCameras();
      });
    });
  }

  void _refreshCameraList() {
    setState(() {
      _camerasFuture = CameraService().getAvailablePhysicalCameras();
    });
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.nameCtrl.dispose();
    }
    super.dispose();
  }

  void _addDraft() {
    setState(() {
      _drafts.add(
        _RoomDraft(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}',
          nameCtrl: TextEditingController(),
          cameraIndex: 0,
          monitorModes: {},
        ),
      );
    });
  }

  void _removeDraftAt(int index) {
    setState(() {
      _drafts[index].nameCtrl.dispose();
      _drafts.removeAt(index);
    });
  }

  Future<void> _save(BuildContext context) async {
    final cs = CameraService();
    final auth = AuthService();
    final prev = List<MonitorRoom>.from(cs.monitorRooms);
    final userId = Provider.of<UserProvider>(context, listen: false).user?.id;

    final next = <MonitorRoom>[];
    final seenNames = <String>{};
    for (final d in _drafts) {
      final name = d.nameCtrl.text.trim();
      if (name.isEmpty) continue;
      if (seenNames.contains(name)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Duplicate room name: $name')),
          );
        }
        return;
      }
      seenNames.add(name);
      final sortedModes = d.monitorModes.toList()..sort();
      next.add(MonitorRoom(
        id: d.id,
        name: name,
        cameraIndex: d.cameraIndex,
        monitorModes: sortedModes,
      ));
    }

    setState(() => _saving = true);
    try {
      final enumerated = await CameraService().getAvailablePhysicalCameras();
      final cameras = cameraRowsOrWebFallback(enumerated);
      String? labelFor(int idx) {
        for (final c in cameras) {
          if (int.tryParse(c['id']?.toString() ?? '') == idx) {
            return c['name']?.toString();
          }
        }
        return null;
      }

      final prevById = {for (final r in prev) r.id: r};

      for (final p in prev) {
        if (!next.any((n) => n.id == p.id)) {
          await auth.deleteCameraAssignment(roomName: p.name);
        }
      }

      for (final n in next) {
        final p = prevById[n.id];
        if (p != null && p.name != n.name) {
          cs.migrateMonitoringRoomName(p.name, n.name);
          await auth.deleteCameraAssignment(roomName: p.name);
        }
        await auth.saveCameraAssignment(
          roomName: n.name,
          cameraId: n.cameraIndex.toString(),
          cameraName: labelFor(n.cameraIndex),
          monitorModes: n.monitorModes,
        );
      }

      cs.replaceMonitorRooms(next, stopRemoved: true);

      if (userId != null) {
        for (final n in next) {
          cs.startMonitoring(userId, n.name);
        }
      }

      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      title: Text(
        'Configure rooms',
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a room name and pick which physical camera feeds it. You can edit assignments anytime.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _camerasFuture,
                builder: (context, snap) {
                  final raw = snap.data ?? [];
                  final cameras = cameraRowsOrWebFallback(raw);
                  final done = snap.connectionState == ConnectionState.done;
                  final showWebPermissionHint =
                      kIsWeb && done && raw.isEmpty;

                  if (_drafts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No rows yet. Tap "Add room" below.',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showWebPermissionHint) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.amber.shade900.withValues(alpha: 0.35)
                                : Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Camera access in the browser',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'If the address bar shows a blocked camera icon, click it (or the lock icon), set Camera to Allow, reload if needed, then tap "Refresh list" below. Until then the site may not list devices—even if a webcam is plugged in.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _refreshCameraList,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Refresh camera list'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You can still choose camera index 0 or 1 for this room; live preview needs permission.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (!kIsWeb && done && raw.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No cameras were detected.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _refreshCameraList,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ...List.generate(_drafts.length, (index) {
                      final d = _drafts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: d.nameCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Room name',
                                      border: const OutlineInputBorder(),
                                      labelStyle: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: !done
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Text(
                                            'Loading cameras…',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : cameras.isEmpty
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 12),
                                              child: Text(
                                                'No cameras',
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.white54
                                                      : Colors.black45,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : DropdownButtonFormField<int>(
                                              value: cameras.any((c) =>
                                                      int.tryParse(
                                                            c['id']
                                                                    ?.toString() ??
                                                                '',
                                                          ) ==
                                                          d.cameraIndex)
                                                  ? d.cameraIndex
                                                  : int.parse(
                                                      cameras.first['id'].toString(),
                                                    ),
                                              decoration: InputDecoration(
                                                labelText: 'Camera',
                                                border:
                                                    const OutlineInputBorder(),
                                                labelStyle: TextStyle(
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                              dropdownColor: isDark
                                                  ? const Color(0xFF2E2E2E)
                                                  : Colors.white,
                                              items: cameras.map((c) {
                                                final id =
                                                    int.parse(c['id'].toString());
                                                return DropdownMenuItem(
                                                  value: id,
                                                  child: Text(
                                                    c['name']?.toString() ??
                                                        'Camera $id',
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (v) {
                                                if (v != null) {
                                                  setState(() => d.cameraIndex = v);
                                                }
                                              },
                                            ),
                                ),
                                IconButton(
                                  onPressed: () => _removeDraftAt(index),
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.redAccent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Optional modes for this room (fire, window, fridge, and face always run)',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final m in kOptionalMonitorModes)
                                  FilterChip(
                                    label: Text(m['label']!),
                                    selected: d.monitorModes.contains(m['id']!),
                                    onSelected: (v) {
                                      setState(() {
                                        final id = m['id']!;
                                        if (v) {
                                          d.monitorModes.add(id);
                                        } else {
                                          d.monitorModes.remove(id);
                                        }
                                      });
                                    },
                                    selectedColor:
                                        Colors.blue.withValues(alpha: 0.35),
                                    checkmarkColor:
                                        isDark ? Colors.white : Colors.black87,
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      color:
                                          isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    ],
                  );
                },
              ),
              TextButton.icon(
                onPressed: _saving ? null : _addDraft,
                icon: const Icon(Icons.add),
                label: const Text('Add room'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : () => _save(context),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
