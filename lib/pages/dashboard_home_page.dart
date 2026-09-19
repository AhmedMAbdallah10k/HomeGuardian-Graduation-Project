import 'package:flutter/material.dart';
import 'dashboard_login_page.dart';
import 'dashboard_analytics_page.dart';
import 'camera_monitor_page.dart';
import 'dashboard_notifications_page.dart';
import 'dashboard_settings_page.dart';
import 'event_page.dart';
import 'pet_station_page.dart';
import 'lost_items_page.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../services/auth_service.dart';
import '../services/event_notifier.dart';
import '../services/camera_service.dart';
import 'dart:async';

// --- Dashboard Home Page (Stateful Widget) ---

class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key});

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage> {
  bool isLight = false;
  List<dynamic> _events = [];
  List<dynamic> _familyStatus = [];
  bool _isLoadingEvents = true;
  bool _isLoadingFamily = true;
  Map<String, dynamic>? _storageSummary;
  bool _isLoadingStorage = true;
  final AuthService _authService = AuthService();
  EventNotifier? _eventsNotifier;
  Timer? _autoLogoutTimer;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _loadFamilyStatus();
    _loadStorageSummary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _eventsNotifier = context.read<EventNotifier>();
      _eventsNotifier!.addListener(_onEventNotifierChanged);
    });
    _startAutoLogoutTimer();
    
    // Refresh family status every 30 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadFamilyStatus();
    });
  }

  @override
  void dispose() {
    _eventsNotifier?.removeListener(_onEventNotifierChanged);
    _autoLogoutTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _onEventNotifierChanged() {
    if (!mounted || _eventsNotifier == null) return;
    setState(() {
      _events = List<dynamic>.from(_eventsNotifier!.events);
      _isLoadingEvents = _eventsNotifier!.isLoading;
    });
  }

  Future<void> _loadFamilyStatus() async {
    final response = await _authService.getFamilyStatus();
    if (mounted) {
      setState(() {
        if (response['success'] == true) {
          _familyStatus = response['members'];
        }
        _isLoadingFamily = false;
      });
    }
  }

  Future<void> _loadStorageSummary() async {
    final sum = await _authService.getStorageSummary();
    if (!mounted) return;
    setState(() {
      _isLoadingStorage = false;
      if (sum['success'] == true) {
        _storageSummary = sum;
      } else {
        _storageSummary = null;
      }
    });
  }

  void _startAutoLogoutTimer() {
    _autoLogoutTimer?.cancel();
    _autoLogoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        _logout();
      }
    });
  }

  void _resetTimer() {
    _startAutoLogoutTimer();
  }

  void _logout() {
    // We do NOT clear the token here for auto-logout
    // This allows a reload to keep the user logged in
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DashboardLoginPage()),
      (route) => false,
    );
  }

  Future<void> _showCameraSelectionDialog(BuildContext context) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userProvider.user == null) return;

    // 1. Check if we already have assignment(s)
    final assignmentResponse = await _authService.getCameraAssignment();
    if (assignmentResponse['success'] == true) {
      List<dynamic> list = [];
      if (assignmentResponse['assignments'] != null &&
          (assignmentResponse['assignments'] as List).isNotEmpty) {
        list = assignmentResponse['assignments'] as List;
      } else if (assignmentResponse['assignment'] != null) {
        list = [assignmentResponse['assignment']];
      }
      if (list.isNotEmpty) {
        await CameraService().applyAssignmentsFromServer(list);
        for (final raw in list) {
          final m = raw as Map;
          final name = m['room_name']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            CameraService().startMonitoring(userProvider.user!.id, name);
          }
        }
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CameraMonitorPage(),
            ),
          );
        }
        return;
      }
    }

    // 2. If no assignment, show the setup dialog
    final TextEditingController roomController = TextEditingController(text: 'Living Room');
    final setupMonitorModes = <String>{};

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: cardColor,
            title: Text('Setup Camera Monitoring', style: TextStyle(color: mainTextPrimary)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign this laptop to a room:', style: TextStyle(color: mainTextSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: roomController,
                    style: TextStyle(color: mainTextPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. Bedroom, Kitchen',
                      hintStyle: TextStyle(color: mainTextSecondary.withOpacity(0.5)),
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Optional modes for this room (fire, window, fridge, face always run):',
                    style: TextStyle(color: mainTextSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final m in kOptionalMonitorModes)
                        FilterChip(
                          label: Text(
                            m['label']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: mainTextPrimary,
                            ),
                          ),
                          selected: setupMonitorModes.contains(m['id']!),
                          onSelected: (v) {
                            setDialogState(() {
                              final id = m['id']!;
                              if (v) {
                                setupMonitorModes.add(id);
                              } else {
                                setupMonitorModes.remove(id);
                              }
                            });
                          },
                          selectedColor:
                              Colors.blue.withValues(alpha: 0.25),
                          checkmarkColor: mainTextPrimary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Select Camera:', style: TextStyle(color: mainTextSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: CameraService().getAvailablePhysicalCameras(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(),
                        ));
                      }
                      
                      final cameras = snapshot.data ?? [];
                      
                      if (cameras.isEmpty) {
                        return Column(
                          children: [
                            const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('No active cameras found.', style: TextStyle(color: mainTextSecondary)),
                          ],
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: cameras.length,
                        itemBuilder: (context, index) {
                          final camera = cameras[index];
                          return ListTile(
                            leading: const Icon(Icons.videocam, color: Colors.greenAccent),
                            title: Text(camera['name'], style: TextStyle(color: mainTextPrimary)),
                            subtitle: Text('Direction: ${camera['description']}', style: TextStyle(color: mainTextSecondary)),
                            onTap: () async {
                              final roomName = roomController.text.trim();
                              if (roomName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter a room name'))
                                );
                                return;
                              }

                              // Save assignment to database
                              await _authService.saveCameraAssignment(
                                roomName: roomName,
                                cameraId: camera['id'].toString(),
                                cameraName: camera['name'],
                                monitorModes: setupMonitorModes.toList()..sort(),
                              );

                              // Start local monitoring
                              CameraService().updateRoomCameraMapping(
                                roomName,
                                int.parse(camera['id']),
                                monitorModes: setupMonitorModes.toList(),
                              );
                              CameraService().startMonitoring(userProvider.user!.id, roomName);
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const CameraMonitorPage(),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadEvents() async {
    try {
      await context.read<EventNotifier>().loadFromApi();
      if (mounted) {
        setState(() {
          _events = List<dynamic>.from(context.read<EventNotifier>().events);
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingEvents = false);
    }
  }

  // Dynamic Color Getters
  Color get backgroundColor => isLight ? Colors.white : Colors.black;
  Color get sidebarColor => isLight ? Colors.grey[100]! : Colors.grey[900]!;
  Color get sidebarTextPrimary => isLight ? Colors.black : Colors.white;
  Color get sidebarTextSecondary =>
      isLight ? Colors.grey[700]! : const Color.fromARGB(255, 142, 142, 142);
  Color get sidebarMenuSelected =>
      isLight ? Colors.grey[300]! : Colors.grey[800]!;
  Color get sidebarMenuUnselected =>
      isLight ? Colors.grey[800]! : Colors.grey[400]!;
  Color get mainTextPrimary => isLight ? Colors.black : Colors.white;
  Color get mainTextSecondary =>
      isLight ? Colors.grey[700]! : Colors.grey[400]!;
  Color get cardColor => isLight ? Colors.grey[200]! : Colors.grey[900]!;
  Color get cardShadow => Colors.black.withOpacity(0.08);
  Color get inputBg => isLight ? Colors.grey[200]! : Colors.grey[850]!;
  Color get inputText => isLight ? Colors.black : Colors.white;
  Color get inputHint => isLight ? Colors.grey : Colors.grey;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerUp: (_) => _resetTimer(),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 240,
              color: sidebarColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  // Menu
                  _SidebarMenu(
                    isLight: isLight,
                    sidebarMenuSelected: sidebarMenuSelected,
                    sidebarMenuUnselected: sidebarMenuUnselected,
                    sidebarTextPrimary: sidebarTextPrimary,
                    onMonitorTap: _showCameraSelectionDialog,
                  ),
                  const Spacer(),
                  // Switch to light/dark
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Switch(
                          value: isLight,
                          onChanged: (val) {
                            setState(() {
                              isLight = val;
                            });
                          },
                        ),
                        Text(
                          isLight ? 'Switch to dark' : 'Switch to light',
                          style: TextStyle(color: sidebarTextPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Consumer<UserProvider>(
                                builder: (context, userProvider, _) {
                                  final userName = userProvider.user?.name ?? '';
                                  return Text(
                                    'Hello${userName.isNotEmpty ? ', $userName' : ''}!',
                                    style: TextStyle(
                                      color: mainTextPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Welcome back to your dashboard',
                                style: TextStyle(
                                  color: mainTextSecondary,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              DashboardBellButton(
                                iconColor: mainTextPrimary,
                                eventCountForBadge: _events.length,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // Dashboard grid
                      _DashboardGrid(
                        isLight: isLight,
                        cardColor: cardColor,
                        mainTextPrimary: mainTextPrimary,
                        mainTextSecondary: mainTextSecondary,
                        events: _events,
                        isLoadingEvents: _isLoadingEvents,
                        familyStatus: _familyStatus,
                        isLoadingFamily: _isLoadingFamily,
                        storageSummary: _storageSummary,
                        isLoadingStorage: _isLoadingStorage,
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
}

// --- Sidebar Widgets ---

class _SidebarMenu extends StatelessWidget {
  final bool isLight;
  final Color sidebarMenuSelected;
  final Color sidebarMenuUnselected;
  final Color sidebarTextPrimary;
  final Function(BuildContext) onMonitorTap;

  const _SidebarMenu({
    required this.isLight,
    required this.sidebarMenuSelected,
    required this.sidebarMenuUnselected,
    required this.sidebarTextPrimary,
    required this.onMonitorTap,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SidebarMenuItem(
          icon: Icons.dashboard,
          label: 'Dashboard',
          selected: true,
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
        ),
        _SidebarMenuItem(
          icon: Icons.analytics,
          label: 'Analytics',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
        ),
        _SidebarMenuItem(
          icon: Icons.videocam,
          label: 'Monitor Home',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
          onTap: () => onMonitorTap(context),
        ),
        _SidebarMenuItem(
          icon: Icons.pets,
          label: 'Pet Station',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PetStationPage(),
              ),
            );
          },
        ),
        _SidebarMenuItem(
          icon: Icons.search,
          label: 'Find Items',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const LostItemsPage(),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _SidebarMenuItem(
          icon: Icons.settings,
          label: 'Settings',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DashboardSettingsPage(),
              ),
            );
          },
        ),
        _SidebarMenuItem(
          icon: Icons.logout,
          label: 'Log out',
          selectedColor: sidebarMenuSelected,
          unselectedColor: sidebarMenuUnselected,
          textColor: sidebarTextPrimary,
        ),
      ],
    );
  }
}

class _SidebarMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final Color textColor;
  final VoidCallback? onTap;
  const _SidebarMenuItem({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.selectedColor,
    required this.unselectedColor,
    required this.textColor,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
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
        onTap: onTap ?? () async {
          if (label == 'Log out') {
            // Manual logout DOES clear the token
            await AuthService().logout();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => const DashboardLoginPage()),
                (route) => false,
              );
            }
          } else if (label == 'Monitor Home') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const CameraMonitorPage(),
              ),
            );
          } else if (label == 'Analytics') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DashboardAnalyticsPage(),
              ),
            );
          } else if (label == 'Pet Station') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PetStationPage(),
              ),
            );
          } else if (label == 'Find Items') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const LostItemsPage(),
              ),
            );
          } else if (label == 'Settings') {
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
}

// --- Dashboard Grid and Cards (Top-Level Widgets) ---

class _DashboardGrid extends StatelessWidget {
  final bool isLight;
  final Color cardColor;
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  final List<dynamic> events;
  final bool isLoadingEvents;
  final List<dynamic> familyStatus;
  final bool isLoadingFamily;
  final Map<String, dynamic>? storageSummary;
  final bool isLoadingStorage;

  const _DashboardGrid({
    required this.isLight,
    required this.cardColor,
    required this.mainTextPrimary,
    required this.mainTextSecondary,
    required this.events,
    required this.isLoadingEvents,
    required this.familyStatus,
    required this.isLoadingFamily,
    required this.storageSummary,
    required this.isLoadingStorage,
  });

  static String _formatBytes(int b) {
    if (b <= 0) return '0 B';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final String dataValue;
    final String dataSubtitle;
    if (isLoadingStorage) {
      dataValue = '—';
      dataSubtitle = 'Loading storage…';
    } else if (storageSummary == null) {
      dataValue = '—';
      dataSubtitle = 'Could not load storage';
    } else {
      final s = storageSummary!;
      final clips = (s['clips_bytes'] as num?)?.toInt() ?? 0;
      final faces = (s['known_faces_bytes'] as num?)?.toInt() ?? 0;
      final prof = (s['profile_images_bytes'] as num?)?.toInt() ?? 0;
      final total = clips + faces + prof;
      final eventsTotal = (s['event_count'] as num?)?.toInt() ?? 0;
      final retention = (s['retention_days'] as num?)?.toInt() ?? 30;
      final lowDisk = s['low_disk_warning'] == true;
      dataValue = _formatBytes(total);
      dataSubtitle = lowDisk
          ? 'Low disk — $eventsTotal events · ${retention}d retention'
          : '$eventsTotal events · ${retention}d retention';
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _DashboardCard(
                color: cardColor,
                child: _AlertsCard(
                  mainTextPrimary: mainTextPrimary,
                  mainTextSecondary: mainTextSecondary,
                  events: events,
                  isLoading: isLoadingEvents,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: _DashboardCard(
                color: cardColor,
                child: _DeviceStatusCard(mainTextPrimary: mainTextPrimary),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: _DashboardCard(
                color: cardColor,
                child: _StatCard(
                  title: 'Data Usage',
                  value: dataValue,
                  subtitle: dataSubtitle,
                  textColor: mainTextPrimary,
                  subTextColor: mainTextSecondary,
                  showTrendIcon: false,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _DashboardCard(
                color: cardColor,
                height: 350, // Increased height for list
                child: _RecentActivityCard(
                  mainTextPrimary: mainTextPrimary,
                  mainTextSecondary: mainTextSecondary,
                  events: events,
                  isLoading: isLoadingEvents,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  _DashboardCard(
                    color: cardColor,
                    height: 200,
                    child: _WhosHomeCard(
                      mainTextPrimary: mainTextPrimary,
                      mainTextSecondary: mainTextSecondary,
                      members: familyStatus,
                      isLoading: isLoadingFamily,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _DashboardCard(
                    color: cardColor,
                    height: 150,
                    child: _EmergencyContactsCard(
                      mainTextPrimary: mainTextPrimary,
                      mainTextSecondary: mainTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _DashboardCard(
                    color: cardColor,
                    height: 120,
                    child: _NetworkStatusCard(
                      mainTextPrimary: mainTextPrimary,
                      mainTextSecondary: mainTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final double? height;
  final Widget child;
  final Color? color;
  const _DashboardCard({this.height, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: color ?? Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16.0), child: child),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color? textColor;
  final Color? subTextColor;
  final bool showTrendIcon;
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.textColor,
    this.subTextColor,
    this.showTrendIcon = true,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: subTextColor ?? Colors.grey[300],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (showTrendIcon) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.trending_up,
                  color: Colors.greenAccent,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: subTextColor ?? Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Parsed event timestamp for dashboard widgets.
DateTime? _parseDashboardEventTime(dynamic event) {
  if (event is! Map) return null;
  final t = event['timestamp'];
  if (t is! String) return null;
  return DateTime.tryParse(t);
}

/// Types that count toward the security / emergency load (matches server labels like emergency, security, safety).
bool _eventTypeIsSecurityOrEmergency(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return false;
  const keys = ['emergency', 'security', 'safety', 'fire'];
  return keys.any((k) => t == k || t.contains(k));
}

/// Count of matching events in the last 24 hours and bar fill 0..1 (full at 8+ events).
({int count24h, double barFraction}) _securityEmergencyMetrics(List<dynamic> events) {
  final cutoff = DateTime.now().subtract(const Duration(hours: 24));
  var n = 0;
  for (final raw in events) {
    if (raw is! Map) continue;
    final type = (raw['event_type'] ?? '').toString();
    if (!_eventTypeIsSecurityOrEmergency(type)) continue;
    final dt = _parseDashboardEventTime(raw);
    if (dt == null || dt.isBefore(cutoff)) continue;
    n++;
  }
  const cap = 8.0;
  return (count24h: n, barFraction: (n / cap).clamp(0.0, 1.0));
}

class _AlertsCard extends StatelessWidget {
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  final List<dynamic> events;
  final bool isLoading;

  const _AlertsCard({
    required this.mainTextPrimary,
    required this.mainTextSecondary,
    required this.events,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = _securityEmergencyMetrics(events);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Recent Alerts',
          style: TextStyle(color: Colors.red[400], fontSize: 14, fontWeight: FontWeight.w600),
        ),
        Text(
          'Security & emergency · last 24 hours',
          style: TextStyle(color: mainTextSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: mainTextSecondary,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  minHeight: 4,
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Icon(
                metrics.count24h > 0 ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                color: metrics.count24h > 0 ? Colors.redAccent : Colors.greenAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metrics.count24h == 0
                      ? 'All clear — no security or emergency alerts'
                      : '${metrics.count24h} security / emergency alert${metrics.count24h == 1 ? '' : 's'}',
                  style: TextStyle(color: mainTextPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: metrics.barFraction,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                metrics.count24h > 0 ? Colors.redAccent : Colors.greenAccent.withValues(alpha: 0.35),
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metrics.count24h > 0
                ? 'Load rises with more alerts (full at 8 in 24h)'
                : 'Bar stays low when there are no matching events',
            style: TextStyle(color: mainTextSecondary, fontSize: 10),
          ),
        ],
      ],
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  final Color mainTextPrimary;
  const _DeviceStatusCard({required this.mainTextPrimary});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.devices_other, color: Colors.cyanAccent, size: 28),
          const SizedBox(height: 8),
          Text(
            'Device Status',
            style: TextStyle(
              color: mainTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'All sensors online',
            style: TextStyle(color: Colors.green, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  final List<dynamic> events;
  final bool isLoading;
  const _RecentActivityCard({
    required this.mainTextPrimary,
    required this.mainTextSecondary,
    required this.events,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                color: mainTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isLoading
              ? const Center(child: Text('Loading events...'))
              : events.isEmpty
                  ? Center(
                      child: Text(
                        'No unusual activity detected',
                        style: TextStyle(color: mainTextSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (context, index) => Divider(
                        color: mainTextSecondary.withOpacity(0.1),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final type = event['event_type'] ?? 'info';
                        
                        IconData iconData = Icons.info_outline;
                        Color iconColor = Colors.blue;
                        
                        if (type == 'emergency' || type == 'fire') {
                          iconData = Icons.local_fire_department;
                          iconColor = Colors.redAccent;
                        } else if (type == 'security' || type == 'door') {
                          iconData = Icons.security;
                          iconColor = Colors.orangeAccent;
                        }

                        // Format timestamp
                        String timeStr = 'Just now';
                        try {
                          if (event['timestamp'] != null) {
                            final dt = DateTime.parse(event['timestamp']);
                            timeStr = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                          }
                        } catch (_) {}

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EventPage(event: event),
                              ),
                            );
                          },
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, color: iconColor, size: 20),
                          ),
                          title: Text(
                            event['title'] ?? 'Unknown Event',
                            style: TextStyle(
                              color: mainTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            event['description'] ?? '',
                            style: TextStyle(
                              color: mainTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            timeStr,
                            style: TextStyle(
                              color: mainTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _EmergencyContactsCard extends StatelessWidget {
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  const _EmergencyContactsCard({
    required this.mainTextPrimary,
    required this.mainTextSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Emergency Contacts',
            style: TextStyle(color: Colors.red[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          _ContactItem(Icons.phone, 'Police', '100', mainTextPrimary),
          _ContactItem(Icons.phone, 'Fire Department', '101', mainTextPrimary),
          _ContactItem(Icons.phone, 'Family Doctor', '102', mainTextPrimary),
        ],
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String phone;
  final Color textColor;
  const _ContactItem(this.icon, this.label, this.phone, this.textColor);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontSize: 12)),
          const Spacer(),
          Text(phone, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }
}

class _NetworkStatusCard extends StatelessWidget {
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  const _NetworkStatusCard({
    required this.mainTextPrimary,
    required this.mainTextSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Network Status',
            style: TextStyle(color: Colors.blue[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.wifi, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              const Text('Connected', style: TextStyle(color: Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last checked: 2 min ago',
            style: TextStyle(color: mainTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _WhosHomeCard extends StatelessWidget {
  final Color mainTextPrimary;
  final Color mainTextSecondary;
  final List<dynamic> members;
  final bool isLoading;

  const _WhosHomeCard({
    required this.mainTextPrimary,
    required this.mainTextSecondary,
    required this.members,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Who\'s Home',
              style: TextStyle(
                color: mainTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: isLoading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : members.isEmpty
                  ? Center(
                      child: Text(
                        'No members registered',
                        style: TextStyle(color: mainTextSecondary, fontSize: 12),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: member['status'] == 'At Home'
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              child: Icon(
                                Icons.person,
                                size: 16,
                                color: member['status'] == 'At Home'
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member['name'],
                                    style: TextStyle(
                                      color: mainTextPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    member['status'],
                                    style: TextStyle(
                                      color: member['status'] == 'At Home'
                                          ? Colors.green[400]
                                          : mainTextSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (member['status'] == 'At Home')
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
