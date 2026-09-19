import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../services/fire_detection_service.dart';
import '../services/event_notifier.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'profile_page.dart';
import 'settings_page.dart';
import 'room_detail_page.dart';
import 'login_page.dart';
import 'silver_mode_page.dart';
import 'nanny_mode_page.dart';
import 'nurse_mode_page.dart';
import 'pet_mode_page.dart';
import 'home_alone_mode_page.dart';
import 'trusted_persons_list_page.dart';
import 'family_members_page.dart';
import 'add_more_modes_page.dart';
import 'event_page.dart';
import 'device_management_page.dart';
import 'activity_data_page.dart';

/// Rotate illustrations for dashboard-configured rooms on the home screen.
const _kRoomHomeAssets = [
  'assets/images/living-room.png',
  'assets/images/bed-room.png',
  'assets/images/bath.png',
];

class SmartHomePage extends StatefulWidget {
  const SmartHomePage({super.key});

  @override
  State<SmartHomePage> createState() => _SmartHomePageState();
}

class _SmartHomePageState extends State<SmartHomePage> {
  bool _modesExpanded = false;
  final FireDetectionService _fireService = FireDetectionService();
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  bool _familyLimited() {
    final u = Provider.of<UserProvider>(context, listen: false).user;
    return u?.isFamilyMember ?? false;
  }

  void _openBedroomQuickAction() {
    if (_familyLimited()) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const RoomDetailPage(roomName: 'Bedroom'),
        ),
      );
      return;
    }
    _showFireDetectionOptions();
  }

  Future<void> _handleFireDetection(File file, {bool isVideo = false}) async {
    setState(() => _isProcessing = true);
    try {
      final token = await AuthService().getToken();
      
      final headers = {
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final result = isVideo 
          ? await _fireService.detectFireFromVideo(file)
          : await _fireService.detectFireFromImage(file, headers: headers);

      if (!mounted) return;

      if (result['success'] == true) {
        final bool fireDetected = result['fire_detected'] ?? false;
        final double confidence = (result['confidence'] ?? 0.0) * 100;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              fireDetected ? 'ALERT: Fire Detected!' : 'Safe: No Fire Detected',
              style: TextStyle(
                color: fireDetected ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Confidence: ${confidence.toStringAsFixed(1)}%'),
                if (fireDetected) const Text('\nEmergency services and family members will be notified.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Detection failed: ${result['error'] ?? 'Unknown error'}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDoorDetection(File file) async {
    setState(() => _isProcessing = true);
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse('${AuthService.baseUrl}/api/detect-door');

      var request = http.MultipartRequest('POST', uri);
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final bool eventDetected = data['event_detected'] ?? false;
          final detections = data['detections'] as List? ?? [];
          
          String message = eventDetected 
              ? "Door state event detected!" 
              : "No door state events detected.";
          
            if (detections.isNotEmpty) {
            final first = detections[0];
            message += "\n\nDetected: ${first['class']} (${(first['confidence'] * 100).toStringAsFixed(1)}%)";
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                eventDetected ? 'Door Alert!' : 'Door Status',
                style: TextStyle(
                  color: eventDetected ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Detection Disabled'),
              content: Text(data['error'] ?? 'Detection failed'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Detection failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showFireDetectionOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bedroom Fire Detection',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Comfortaa',
              ),
            ),
            const SizedBox(height: 10),
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                _buildDetectionAction(
                  icon: Icons.camera_alt,
                  label: 'Capture',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
                    if (photo != null) _handleFireDetection(File(photo.path));
                  },
                ),
                _buildDetectionAction(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.orange,
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? video = await _picker.pickVideo(source: ImageSource.camera);
                    if (video != null) _handleFireDetection(File(video.path), isVideo: true);
                  },
                ),
                _buildDetectionAction(
                  icon: Icons.image,
                  label: 'Upload',
                  color: Colors.blue,
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) _handleFireDetection(File(image.path));
                  },
                ),
                _buildDetectionAction(
                  icon: Icons.door_front_door,
                  label: 'Door Pic',
                  color: Colors.green,
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) _handleDoorDetection(File(image.path));
                  },
                ),
                _buildDetectionAction(
                  icon: Icons.live_tv,
                  label: 'Monitor',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RoomDetailPage(roomName: 'Bedroom'),
                      ),
                    );
                  },
                ),
              ],
              ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _drawerModeItem(String modeName) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        modeName,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      onTap: () {
        Navigator.of(context).pop();
        if (modeName == 'Silver Mode') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => SilverModePage()));
        } else if (modeName == 'Nanny Mode') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => NannyModePage()));
        } else if (modeName == 'Nurse Mode') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => NurseModePage()));
        } else if (modeName == 'Pet Mode') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => PetModePage()));
        } else if (modeName == 'Home Alone Mode') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => HomeAloneModePage()));
        }
      },
    );
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EventNotifier? _eventsNotifier;
  int _lastHomePresenceVersion = 0;
  int _lastMonitoringVersion = 0;
  Timer? _atHomePollTimer;

  /// Rooms configured on the dashboard (GET /api/monitoring/assignment).
  List<Map<String, dynamic>> _monitoringRooms = [];
  bool _loadingMonitoringRooms = true;

  List<Map<String, dynamic>> _events = [];
  bool _isLoadingEvents = false;

  /// At-home strip: `name`, optional `photoUrl` (network), for `/api/family/status` + owner-only photos.
  List<Map<String, String?>> _atHomePeople = [];
  bool _loadingAtHome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _eventsNotifier = context.read<EventNotifier>();
      _eventsNotifier!.addListener(_onEventNotifierChanged);
      _eventsNotifier!.loadFromApi();
    });
    _fetchAtHome();
    _fetchMonitoringRooms();
    _atHomePollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _fetchAtHome(silent: true);
        _fetchMonitoringRooms(silent: true);
      }
    });
  }

  void _onEventNotifierChanged() {
    if (!mounted || _eventsNotifier == null) return;
    setState(() {
      _events = List<Map<String, dynamic>>.from(_eventsNotifier!.events);
      _isLoadingEvents = _eventsNotifier!.isLoading;
    });
    if (_eventsNotifier!.homePresenceVersion != _lastHomePresenceVersion) {
      _lastHomePresenceVersion = _eventsNotifier!.homePresenceVersion;
      _fetchAtHome(silent: true);
    }
    if (_eventsNotifier!.monitoringAssignmentsVersion !=
        _lastMonitoringVersion) {
      _lastMonitoringVersion = _eventsNotifier!.monitoringAssignmentsVersion;
      _fetchMonitoringRooms(silent: true);
    }
  }

  @override
  void dispose() {
    _atHomePollTimer?.cancel();
    _eventsNotifier?.removeListener(_onEventNotifierChanged);
    super.dispose();
  }

  Future<void> _fetchMonitoringRooms({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingMonitoringRooms = true);
    }
    try {
      final res = await AuthService().getCameraAssignment();
      if (!mounted) return;
      if (res['success'] == true) {
        final list = <Map<String, dynamic>>[];
        if (res['assignments'] != null &&
            (res['assignments'] as List).isNotEmpty) {
          for (final raw in res['assignments'] as List) {
            final m = Map<String, dynamic>.from(raw as Map);
            final name = m['room_name']?.toString().trim() ?? '';
            if (name.isNotEmpty) {
              list.add(m);
            }
          }
        } else if (res['assignment'] != null) {
          final m = Map<String, dynamic>.from(res['assignment'] as Map);
          final name = m['room_name']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            list.add(m);
          }
        }
        setState(() {
          _monitoringRooms = list;
          _loadingMonitoringRooms = false;
        });
      } else if (mounted) {
        setState(() => _loadingMonitoringRooms = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMonitoringRooms = false);
      }
    }
  }

  void _onDashboardRoomTap(String roomName) {
    if (roomName.isEmpty) return;
    if (_familyLimited()) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoomDetailPage(roomName: roomName),
        ),
      );
      return;
    }
    if (roomName.toLowerCase() == 'bedroom') {
      _openBedroomQuickAction();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RoomDetailPage(roomName: roomName),
        ),
      );
    }
  }

  Widget _buildMonitoringRoomsStrip() {
    if (_loadingMonitoringRooms && _monitoringRooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_monitoringRooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Text(
          'No rooms yet. Add rooms from Monitor Home on your dashboard—they will appear here with the same names.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: Colors.grey.shade700,
            fontFamily: 'Comfortaa',
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < _monitoringRooms.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              _buildDashboardRoomTile(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardRoomTile(int index) {
    final row = _monitoringRooms[index];
    final name = row['room_name']?.toString().trim() ?? 'Room';
    final asset = _kRoomHomeAssets[index % _kRoomHomeAssets.length];
    return GestureDetector(
      onTap: () => _onDashboardRoomTap(name),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roomCircle(asset),
          const SizedBox(height: 8),
          SizedBox(
            width: 92,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                fontFamily: 'Comfortaa',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAtHome({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingAtHome = true);
    }
    final auth = AuthService();
    final statusRes = await auth.getFamilyStatus();

    final List<Map<String, String?>> rows = [];
    if (statusRes['success'] == true || statusRes['members'] != null) {
      final raw = statusRes['members'] ?? statusRes['data'];
      final List list = raw is List ? raw : [];
      final atHome = list
          .where((e) {
            if (e is! Map) return false;
            final s = (e['status'] ?? '').toString().toLowerCase();
            return s == 'at home';
          })
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      Map<String, String?> photoByName = {};
      if (!_familyLimited()) {
        final memRes = await auth.getFamilyMembers();
        if (memRes['success'] == true) {
          for (final m in List<Map<String, dynamic>>.from(memRes['members'] ?? [])) {
            final n = (m['name'] ?? '').toString();
            if (n.isEmpty) continue;
            photoByName[n] = auth.buildPhotoUrl(m['photo_path']?.toString());
          }
        }
      }

      for (final e in atHome) {
        final name = (e['name'] ?? '').toString();
        if (name.isEmpty) continue;
        String? url;
        final pp = e['photo_path']?.toString();
        if (pp != null && pp.isNotEmpty) {
          url = auth.buildPhotoUrl(pp);
        } else {
          url = photoByName[name];
        }
        rows.add({'name': name, 'photoUrl': url});
      }
    }

    if (mounted) {
      setState(() {
        _atHomePeople = rows;
        _loadingAtHome = false;
      });
    }
  }

  Widget _buildAtHomeStrip() {
    if (_loadingAtHome && _atHomePeople.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
          ),
        ),
      );
    }
    if (_atHomePeople.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Text(
          'No one detected at home right now.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Comfortaa',
            color: Colors.grey.shade700,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _atHomePeople.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            _buildAtHomePersonTile(
              _atHomePeople[i]['name']!,
              _atHomePeople[i]['photoUrl'],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAtHomePersonTile(String name, String? photoUrl) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(38),
              topRight: Radius.circular(38),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(60),
            ),
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(38),
              topRight: Radius.circular(38),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(60),
            ),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    width: 80,
                    height: 80,
                    errorBuilder: (_, __, ___) => _atHomePlaceholder(name),
                  )
                : _atHomePlaceholder(name),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 96,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Comfortaa',
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _atHomePlaceholder(String name) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFFE8E8E8),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          fontFamily: 'Comfortaa',
          color: Colors.black54,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Black header bar at the top
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
                    child: Text(
                      'Hello ${user?.name ?? ''}!',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () {
                        _scaffoldKey.currentState?.openDrawer();
                      },
                      child: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Main white container with large border radius top left
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        // At Home section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'At Home',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                    fontFamily: 'Comfortaa',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Avatars row — live names from /api/family/status
                        Container(
                          decoration: const BoxDecoration(
                            color: const Color(0xFFF3F5F4),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(38),
                              topRight: Radius.circular(38),
                              bottomLeft: Radius.circular(0),
                              bottomRight: Radius.circular(60),
                            ),
                          ),
                          child: _buildAtHomeStrip(),
                        ),
                        const SizedBox(height: 18),
                        // Rooms section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Rooms',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                    fontFamily: 'Comfortaa',
                                  ),
                                ),
                              ),
                              _moreButtonGrey(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Room icons row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3F5F4),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(38),
                                topRight: Radius.circular(38),
                                bottomLeft: Radius.circular(0),
                                bottomRight: Radius.circular(60),
                              ),
                            ),
                            child: _buildMonitoringRoomsStrip(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Today's Events section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  "Today's Events",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                    fontFamily: 'Comfortaa',
                                  ),
                                ),
                              ),
                              _moreButtonGrey(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Events list clipped in rounded card
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              color: Color(0xFFF3F5F4),
                              width: double.infinity,
                              constraints: BoxConstraints(
                                maxHeight: 440,
                              ), // adjust height as needed
                              child: _isLoadingEvents
                                  ? const Center(child: CircularProgressIndicator())
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      shrinkWrap: true,
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      itemCount: _events.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, index) {
                                        final event = _events[index];
                                        return Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () {
                                              print('Home Page: Event clicked: ${event['id']}');
                                              try {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        EventPage(event: event),
                                                  ),
                                                );
                                                print('Home Page: Navigation triggered');
                                              } catch (e) {
                                                print('Home Page: Navigation error: $e');
                                              }
                                            },
                                            child: _eventCard(
                                              event['timestamp'] != null
                                                  ? TimeOfDay.fromDateTime(
                                                      DateTime.parse(event['timestamp']),
                                                    ).format(context)
                                                  : "Now",
                                              event['title'] ?? "Alert",
                                              "Recent",
                                              event: event,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCircle(String imagePath) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFF3F5F4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(60)),
        child: Image.asset(imagePath, fit: BoxFit.cover, width: 60, height: 60),
      ),
    );
  }

  Widget _roomCircle(String imagePath) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(60)),
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain,
          width: 60,
          height: 60,
        ),
      ),
    );
  }

  Widget _moreButtonGrey() {
    return Container(
      width: 60,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'More >',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
            fontFamily: 'Comfortaa',
          ),
        ),
      ),
    );
  }

  bool _isFireEvent(String title, Map<String, dynamic>? event) {
    final t = title.toLowerCase();
    if (t.contains('fire')) return true;
    if (event == null) return false;
    final desc = event['description']?.toString().toLowerCase() ?? '';
    return desc.contains('fire');
  }

  Widget _eventCard(
    String time,
    String description,
    String ago, {
    Map<String, dynamic>? event,
  }) {
    final showFireEmoji = _isFireEvent(description, event);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: description.contains('-')
                        ? Colors.grey[400]
                        : Colors.grey[600],
                    fontFamily: 'Comfortaa',
                  ),
                ),
                if (showFireEmoji) ...[
                  const SizedBox(height: 2),
                  const Text(
                    '🔥',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ago,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              fontFamily: 'Comfortaa',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            _scaffoldKey.currentState?.openDrawer();
          },
          child: const Icon(Icons.menu, color: Colors.black, size: 24),
        ),
        const SizedBox(width: 16),
        const Text(
          'Hello Arwa',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildAtHomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "At Home" label with exact styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F5F4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Text(
            'At Home',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 35),
        // Horizontal scrollable row of profiles
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildProfileWithName('assets/images/man.png', 'Ahmed'),
                const SizedBox(width: 35),
                _buildProfileWithName('assets/images/avatar-user.png', 'Arwa'),
                const SizedBox(width: 35),
                _buildProfileWithName('assets/images/artist.png', 'Shahd'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // More button at bottom right
        Align(alignment: Alignment.centerRight, child: _buildMoreButton()),
      ],
    );
  }

  Widget _buildProfileCircle(String imagePath) {
    if (imagePath == 'assets/images/boy.png' ||
        imagePath == 'assets/images/girl.png' ||
        imagePath == 'assets/images/woman.png') {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(38),
            topRight: Radius.circular(38),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(60),
          ),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(38),
            topRight: Radius.circular(38),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(60),
          ),
          child: Image.asset(
            imagePath,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
          color: const Color(0xFFF3F5F4),
        ),
        child: ClipOval(
          child: Image.asset(
            imagePath,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
  }

  Widget _buildProfileWithName(String imagePath, String name) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
            color: const Color(0xFFF3F5F4),
          ),
          child: ClipOval(
            child: Image.asset(
              imagePath,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildMoreButton() {
    return Column(
      children: [
        Container(
          width: 70,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'More >',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F5F4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Text(
            'Rooms',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 35),
        _buildMonitoringRoomsStrip(),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerRight, child: _buildMoreButton()),
      ],
    );
  }

  Widget _buildRoomIcon(String name, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RoomDetailPage(roomName: name),
          ),
        );
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
          color: const Color(0xFFF3F5F4),
        ),
        child: Icon(icon, color: color, size: 34),
      ),
    );
  }

  Widget _buildRoomWithName(String name, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        if (name == 'Bedroom') {
          _openBedroomQuickAction();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RoomDetailPage(roomName: name),
            ),
          );
        }
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              color: Colors.white,
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaysEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Today's Events" label with exact styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const Text(
            "Today's Events",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Event cards matching the exact design
        _buildEventCard('10:00 AM', 'Person fell in the Kitchen', '6 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('09:58 PM', 'Main door left open', '4 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('11:00 AM', '---', '3 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('10:00 AM', '---', '1 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard(
          '08:30 AM',
          'Motion detected in Living Room',
          '2 hour ago',
        ),
        const SizedBox(height: 12),
        _buildEventCard('07:15 AM', 'Temperature sensor alert', '3 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('06:45 AM', 'Security camera offline', '4 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('05:20 AM', 'Door sensor triggered', '5 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('04:10 AM', 'Smoke detector test', '6 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('03:30 AM', 'Window left open', '7 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('02:45 AM', 'Power outage detected', '8 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard('01:20 AM', 'Water leak sensor alert', '9 hour ago'),
        const SizedBox(height: 12),
        _buildEventCard(
          '12:00 AM',
          'System maintenance completed',
          '10 hour ago',
        ),
      ],
    );
  }

  Widget _buildEventCard(String time, String description, String ago) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(
            ago,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor:
          Colors.transparent, // Transparent to show the custom container shape
      elevation: 0,
      width: 320, // Wider drawer as implicitly requested by layout needs
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A), // Dark background similar to mockup
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Back Button and Name
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Expanded(
                      child: Text(
                        'Menu', // Placeholder name as in mockup, or dynamic
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          // The "Hello Arwa" text in the mockup is actually quite dark, almost black, which is low contrast on dark bg.
                          // But usually it should be white. I will stick to readable white/grey for now unless specified.
                          // Actually re-examining image: The "Hello Arwa" is at the top right, but the drawer background is dark.
                          // The text looks like it might be on a lighter part or just styled that way.
                          // I'll make it readable: Grey/White.
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Comfortaa',
                          color: Color(0xFFE0E0E0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20), // Balance
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  children: [
                    _buildMenuItem(
                      iconAsset: 'assets/images/user.png',
                      title: 'My Profile',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => MyProfilePage(),
                          ),
                        );
                      },
                    ),

                    if (!_familyLimited()) ...[
                      _buildMenuItem(
                        icon: Icons.person_add_alt_1_outlined,
                        title: 'Add trusted person',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const TrustedPersonsListPage(),
                            ),
                          );
                        },
                      ),
                      _buildModesDropdown(),
                      _buildMenuItem(
                        iconAsset: 'assets/images/setting.png',
                        title: 'Settings',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => SettingsPage(),
                            ),
                          );
                        },
                      ),
                      _buildMenuItem(
                        iconAsset: 'assets/images/relationship.png',
                        title: 'Family Members',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FamilyMembersPage(),
                            ),
                          );
                        },
                      ),
                    ],

                    if (!_familyLimited())
                      _buildMenuItem(
                        iconAsset: 'assets/images/smart-home.png',
                        title: 'Device & System Management',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DeviceManagementPage(),
                            ),
                          );
                        },
                      ),

                    _buildMenuItem(
                      iconAsset: 'assets/images/clipboard.png',
                      title: 'Activity and Data',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ActivityDataPage(),
                          ),
                        );
                      },
                    ),

                    _buildMenuItem(
                      iconAsset: 'assets/images/logout.png',
                      title: 'Logout',
                      onTap: () async {
                        await AuthService().logout();
                        context.read<UserProvider>().clear();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                          (route) => false,
                        );
                      },
                      isLast: true, // No underline
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Custom Menu Item Builder
  Widget _buildMenuItem({
    IconData? icon,
    String? iconAsset,
    required String title,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 0.0), // Spacing handled inside
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                bottom: 12.0,
              ), // Space between content and divider
              child: Row(
                crossAxisAlignment: CrossAxisAlignment
                    .center, // Center Icon and Text vertically
                children: [
                  // Left padding "margin" + Icon
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0, right: 20.0),
                    child: icon != null
                        ? Icon(icon, color: Colors.grey[400], size: 24)
                        : Image.asset(
                            iconAsset!,
                            width: 24,
                            height: 24,
                            color: Colors.grey[400], // Greyish icon color
                            fit: BoxFit.contain,
                          ),
                  ),
                  // Text
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 30.0),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0), // Off-white text
                          fontSize: 15,
                          fontFamily: 'Comfortaa',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Divider
            if (!isLast)
              Padding(
                padding: const EdgeInsets.only(
                  left: 74.0,
                  right: 30.0,
                  bottom: 20.0,
                ), // Indent to match text start (30+24+20), right padding 30, bottom margin 20
                child: Container(
                  height: 1,
                  color: Colors.grey[800], // Dark divider
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModesDropdown() {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _modesExpanded = !_modesExpanded;
            });
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 30.0, right: 20.0),
                      child: Icon(
                        _modesExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: Colors.grey[400],
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 30.0),
                        child: Text(
                          'Modes',
                          style: TextStyle(
                            color: Color(0xFFE0E0E0),
                            fontSize: 15,
                            fontFamily: 'Comfortaa',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 74.0,
                  right: 30.0,
                  bottom: 20.0,
                ),
                child: Container(height: 1, color: Colors.grey[800]),
              ),
            ],
          ),
        ),
        if (_modesExpanded)
          Column(
            children: [
              _buildSubMenuItem(
                'Silver Mode',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SilverModePage(),
                    ),
                  );
                },
              ),
              _buildSubMenuItem(
                'Nanny Mode',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NannyModePage(),
                    ),
                  );
                },
              ),
              _buildSubMenuItem(
                'Nurse Mode',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NurseModePage(),
                    ),
                  );
                },
              ),
              _buildSubMenuItem(
                'Pet Mode',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PetModePage(),
                    ),
                  );
                },
              ),
              _buildSubMenuItem(
                'Home Alone Mode',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HomeAloneModePage(),
                    ),
                  );
                },
              ),
              _buildMenuItem(
                icon: Icons.add,
                title: 'Add more modes',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AddMoreModesPage(),
                    ),
                  );
                },
                isLast: false, // Keep separator
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSubMenuItem(String title, {VoidCallback? onTap}) {
    // Simplified item for sub-modes, indented
    return InkWell(
      onTap:
          onTap ??
          () {
            // Handle mode selection if needed, currently just closes drawer or generic action
            Navigator.pop(context);
          },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 15, left: 80, right: 30),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 13,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 0.5, color: Colors.grey[850]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
