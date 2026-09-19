import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// When [enumerated] is empty on web, returns index 0/1 choices so room assignment still works
/// (enumeration often stays empty until the site is allowed to use the camera in the browser).
List<Map<String, dynamic>> cameraRowsOrWebFallback(
  List<Map<String, dynamic>> enumerated,
) {
  if (enumerated.isNotEmpty) return enumerated;
  if (kIsWeb) {
    return [
      {
        'id': '0',
        'name': 'First camera (index 0)',
        'description': 'Usually built-in or first device',
      },
      {
        'id': '1',
        'name': 'Second camera (index 1)',
        'description': 'Second USB webcam if present',
      },
    ];
  }
  return enumerated;
}

/// Optional per-room detectors (configured in Monitor dashboard). IDs match server keys.
/// Fire, window, fridge, face always run; these are extras for that room only.
const List<Map<String, String>> kOptionalMonitorModes = [
  {'id': 'silver', 'label': 'Silver'},
  {'id': 'nanny', 'label': 'Nanny'},
  {'id': 'nurse', 'label': 'Nurse'},
  {'id': 'pet', 'label': 'Pet'},
  {'id': 'home_alone', 'label': 'Home alone'},
];

List<String> monitorModesFromAssignmentField(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    final out = <String>[];
    for (final e in raw) {
      final s = e?.toString().trim().toLowerCase();
      if (s != null &&
          s.isNotEmpty &&
          kOptionalMonitorModes.any((m) => m['id'] == s)) {
        if (!out.contains(s)) out.add(s);
      }
    }
    return out;
  }
  return [];
}

class MonitorRoom {
  final String id;
  final String name;
  final int cameraIndex;
  final String? cameraLabel;
  final List<String> monitorModes;

  const MonitorRoom({
    required this.id,
    required this.name,
    required this.cameraIndex,
    this.cameraLabel,
    this.monitorModes = const [],
  });

  MonitorRoom copyWith({
    String? id,
    String? name,
    int? cameraIndex,
    String? cameraLabel,
    List<String>? monitorModes,
  }) {
    return MonitorRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      cameraLabel: cameraLabel ?? this.cameraLabel,
      monitorModes:
          monitorModes != null ? List<String>.from(monitorModes) : List<String>.from(this.monitorModes),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cameraIndex': cameraIndex,
        if (cameraLabel != null) 'cameraLabel': cameraLabel,
        'monitorModes': monitorModes,
      };

  factory MonitorRoom.fromJson(Map<String, dynamic> m) {
    return MonitorRoom(
      id: m['id'] as String,
      name: m['name'] as String,
      cameraIndex: (m['cameraIndex'] as num).toInt(),
      cameraLabel: m['cameraLabel'] as String?,
      monitorModes:
          monitorModesFromAssignmentField(m['monitorModes'] ?? m['monitor_modes']),
    );
  }
}

class CameraService extends ChangeNotifier {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  CameraController? _controller2; // Second controller for external webcam
  bool _isInitialized = false;
  bool _isInitialized2 = false;
  /// Separate lock per physical camera slot so camera 0 being slow/black/hung upload
  /// does not suppress detection uploads for camera 1.
  final Map<int, bool> _captureBusy = {0: false, 1: false};
  final Map<int, DateTime?> _captureBusySince = {0: null, 1: null};
  bool _isRecording = false; // Add recording state
  Timer? _captureTimer;
  final AuthService _authService = AuthService();
  
  String _statusMessage = 'Initializing...';
  String get statusMessage => _statusMessage;
  bool get isRecording => _isRecording;

  // Track which cameras are currently recording
  final Map<int, bool> _activeRecordings = {0: false, 1: false};
  bool isCameraRecording(int index) => _activeRecordings[index] ?? false;

  // Bed exit: start recording at sit-up (state 1), finalize at alert (state 2)
  final Map<int, DateTime> _bedExitArmStarted = {};
  final Map<int, Timer?> _bedExitFinalizeTimer = {0: null, 1: null};
  final Map<int, Timer?> _bedExitMaxTimer = {0: null, 1: null};

  /// User-configured monitor slots (name + camera index). Empty until configured in Monitor UI.
  final List<MonitorRoom> _monitorRooms = [];
  final Map<String, int> _roomCameraMapping = {};

  static const _prefsKeyMonitorRooms = 'dashboard_monitor_rooms_v2';

  int _availableCameraCount = 0;
  int get availableCameraCount => _availableCameraCount;

  List<MonitorRoom> get monitorRooms => List.unmodifiable(_monitorRooms);

  int get monitorRoomCount => _monitorRooms.length;

  /// Kept for older call sites; uses configured rooms only (not hardware count).
  int get dashboardTileCount => monitorRoomCount;

  static String _newMonitorRoomId() =>
      'm_${DateTime.now().microsecondsSinceEpoch}';

  void _rebuildRoomCameraMapping() {
    _roomCameraMapping.clear();
    for (final r in _monitorRooms) {
      final n = r.name.trim();
      if (n.isNotEmpty) {
        _roomCameraMapping[n] = r.cameraIndex;
      }
    }
  }

  Future<void> _persistMonitorRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _monitorRooms.map((r) => r.toJson()).toList();
      await prefs.setString(_prefsKeyMonitorRooms, jsonEncode(list));
    } catch (e) {
      debugPrint('CameraService: persist monitor rooms failed: $e');
    }
  }

  Future<void> _loadMonitorRoomsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyMonitorRooms);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _monitorRooms
          ..clear()
          ..addAll(
            decoded.map(
              (e) => MonitorRoom.fromJson(Map<String, dynamic>.from(e as Map)),
            ),
          );
        _rebuildRoomCameraMapping();
        return;
      }
    } catch (e) {
      debugPrint('CameraService: monitor rooms prefs error: $e');
    }
    _monitorRooms.clear();
    _rebuildRoomCameraMapping();
  }

  Future<void> applyAssignmentsFromServer(List<dynamic> rows) async {
    _monitorRooms.clear();
    for (final raw in rows) {
      final m = Map<String, dynamic>.from(raw as Map);
      final name = (m['room_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final cid = int.tryParse((m['camera_id'] ?? '0').toString()) ?? 0;
      final id = m['id'] != null
          ? m['id'].toString()
          : '${_newMonitorRoomId()}_${name.hashCode}';
      _monitorRooms.add(MonitorRoom(
        id: id,
        name: name,
        cameraIndex: cid,
        cameraLabel: m['camera_name']?.toString(),
        monitorModes:
            monitorModesFromAssignmentField(m['monitor_modes'] ?? m['monitorModes']),
      ));
    }
    _rebuildRoomCameraMapping();
    await _persistMonitorRooms();
    notifyListeners();
  }

  void replaceMonitorRooms(List<MonitorRoom> next, {bool stopRemoved = true}) {
    if (stopRemoved) {
      final nextIds = next.map((r) => r.id).toSet();
      for (final r in List<MonitorRoom>.from(_monitorRooms)) {
        if (!nextIds.contains(r.id)) {
          stopMonitoring(r.name);
        }
      }
    }
    _monitorRooms
      ..clear()
      ..addAll(next);
    _rebuildRoomCameraMapping();
    _persistMonitorRooms();
    _activePreviewRooms.clear();
    notifyListeners();
  }

  void migrateMonitoringRoomName(String oldName, String newName) {
    final o = oldName.trim();
    final n = newName.trim();
    if (o.isEmpty || n.isEmpty || o == n) return;
    if (_activeRooms.remove(o)) {
      _activeRooms.add(n);
    }
    for (final e in _activePreviewRooms.entries.toList()) {
      if (e.value == o) {
        _activePreviewRooms[e.key] = n;
      }
    }
    notifyListeners();
  }

  void updateRoomCameraMapping(String roomName, int cameraIndex,
      {List<String>? monitorModes}) {
    debugPrint('CameraService: Upsert room "$roomName" -> camera $cameraIndex');
    final name = roomName.trim();
    if (name.isEmpty) return;
    final idx = _monitorRooms.indexWhere((r) => r.name == name);
    if (idx >= 0) {
      _monitorRooms[idx] = _monitorRooms[idx].copyWith(
        cameraIndex: cameraIndex,
        monitorModes: monitorModes ?? _monitorRooms[idx].monitorModes,
      );
    } else {
      _monitorRooms.add(MonitorRoom(
        id: _newMonitorRoomId(),
        name: name,
        cameraIndex: cameraIndex,
        monitorModes: monitorModes ?? const [],
      ));
    }
    _rebuildRoomCameraMapping();
    _activePreviewRooms.clear();
    _persistMonitorRooms();
    notifyListeners();
  }

  Map<String, int> get roomCameraMapping => Map.unmodifiable(_roomCameraMapping);

  int getCameraIndexForRoom(String roomName) {
    final mapped = _roomCameraMapping[roomName];
    if (mapped != null) return mapped;
    const legacy = {
      'Living Room': 0,
      'Bedroom': 0,
      'Reception': 0,
      'Corridor': 1,
    };
    return legacy[roomName] ?? 0;
  }

  String getRoomNameForCameraIndex(int index) {
    try {
      return _monitorRooms.firstWhere((r) => r.cameraIndex == index).name;
    } catch (_) {
      return index == 0 ? 'Living Room' : 'Corridor';
    }
  }

  void setRoomDisplayNameForIndex(int index, String name) {
    final idx = _monitorRooms.indexWhere((r) => r.cameraIndex == index);
    if (idx < 0) return;
    final old = _monitorRooms[idx].name;
    final trimmed = name.trim();
    if (trimmed.isEmpty || old == trimmed) return;
    for (var i = 0; i < _monitorRooms.length; i++) {
      if (i != idx && _monitorRooms[i].name == trimmed) return;
    }
    migrateMonitoringRoomName(old, trimmed);
    _monitorRooms[idx] = _monitorRooms[idx].copyWith(name: trimmed);
    _rebuildRoomCameraMapping();
    _persistMonitorRooms();
    notifyListeners();
  }

  // Keep track of which rooms are currently being monitored
  final Set<String> _activeRooms = {};
  int? _currentUserId;

  // The rooms that currently "own" a live CameraPreview (max one per physical camera)
  final Map<int, String> _activePreviewRooms = {};
  
  bool isRoomPreviewActive(String roomName) {
    int camIdx = getCameraIndexForRoom(roomName);
    return _activePreviewRooms[camIdx] == roomName;
  }

  void togglePreview(String roomName) {
    int camIdx = getCameraIndexForRoom(roomName);
    if (_activePreviewRooms[camIdx] == roomName) {
      _activePreviewRooms.remove(camIdx);
    } else {
      _activePreviewRooms[camIdx] = roomName;
    }
    debugPrint('CameraService: Active previews: $_activePreviewRooms');
    notifyListeners();
  }

  bool _isFullScreenActive = false;
  bool get isFullScreenActive => _isFullScreenActive;

  bool _isSwitching = false;
  bool get isSwitching => _isSwitching;

  CameraController? get controller => _controller;
  CameraController? get controller2 => _controller2;
  
  CameraController? getControllerForRoom(String roomName) {
    final index = getCameraIndexForRoom(roomName);
    // Fallback to controller 1 if controller 2 is not available
    if (index == 1 && (_controller2 == null || !_isInitialized2 || !_controller2!.value.isInitialized)) {
      return _controller;
    }
    return index == 0 ? _controller : _controller2;
  }

  bool isInitializedForRoom(String roomName) {
    final index = getCameraIndexForRoom(roomName);
    // If the room is mapped to a camera that isn't available, 
    // fallback to checking if the main camera is initialized.
    if (index == 1 && (!_isInitialized2 || _controller2 == null || !_controller2!.value.isInitialized)) {
      return _isInitialized && _controller != null && _controller!.value.isInitialized;
    }
    return index == 0 
      ? (_isInitialized && _controller != null && _controller!.value.isInitialized)
      : (_isInitialized2 && _controller2 != null && _controller2!.value.isInitialized);
  }

  bool get isInitialized => _isInitialized;

  void setActivePreview(String? roomName, {bool isFullScreen = false}) {
    if (roomName == null) {
      _activePreviewRooms.clear();
    } else {
      int camIdx = getCameraIndexForRoom(roomName);
      _activePreviewRooms[camIdx] = roomName;
    }
    _isFullScreenActive = isFullScreen;
    notifyListeners();
  }

  bool _isAlertShowing = false;
  bool get isAlertShowing => _isAlertShowing;
  set isAlertShowing(bool value) {
    if (_isAlertShowing == value) return;
    _isAlertShowing = value;
    debugPrint('CameraService: isAlertShowing set to $value');
    notifyListeners();
  }

  Uint8List? _lastFrame;
  Uint8List? get lastFrame => _lastFrame;
  
  // Store last frames per camera index
  final Map<int, Uint8List?> _lastFrames = {0: null, 1: null};
  
  // Track camera health
  final Map<int, DateTime> _lastSuccessfulCapture = {};
  final Map<int, bool> _isCameraFailing = {0: false, 1: false};
  final Map<int, int> _consecutiveFailures = {0: 0, 1: 0};

  Uint8List? getLastFrameForRoom(String roomName) {
    final index = getCameraIndexForRoom(roomName);
    return _lastFrames[index];
  }

  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  Future<void> initialize({bool force = false}) async {
    // If already initializing, wait for it to finish
    if (_isInitializing && _initCompleter != null) {
      return _initCompleter!.future;
    }

    // Check if we actually need to initialize
    if (!force && _isInitialized && _controller != null && _controller!.value.isInitialized) {
      final cameras = await availableCameras();
      _availableCameraCount = cameras.length;
      await _loadMonitorRoomsFromPrefs();
      if (cameras.length <= 1 || (_isInitialized2 && _controller2 != null && _controller2!.value.isInitialized)) {
        notifyListeners();
        return;
      }
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();
    _statusMessage = 'Starting hardware initialization...';
    notifyListeners();
    debugPrint('CameraService: Starting STAGGERED hardware initialization...');

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _availableCameraCount = 0;
        _statusMessage = 'No cameras found. Check permissions.';
        debugPrint('CameraService: No cameras found!');
        _isInitialized = false;
        _isInitialized2 = false;
        notifyListeners();
        return;
      }

      _statusMessage = 'Found ${cameras.length} cameras. Starting...';
      notifyListeners();
      debugPrint('CameraService: Found ${cameras.length} cameras.');

      _availableCameraCount = cameras.length;
      await _loadMonitorRoomsFromPrefs();
      notifyListeners();

      // 1. Initialize Camera 0 (Laptop)
      if (force || _controller == null || !_controller!.value.isInitialized) {
        _statusMessage = 'Starting Camera 1...';
        notifyListeners();
        await _initController(0, cameras[0]);
      }

      // 2. STAGGER: Wait 3 seconds to let the USB bus settle
      if (cameras.length > 1) {
        _statusMessage = 'Waiting for USB bus to settle...';
        notifyListeners();
        debugPrint('CameraService: Waiting for USB bus to settle before starting second camera...');
        await Future.delayed(const Duration(seconds: 3));
        
        // 3. Initialize Camera 1 (Webcam)
        if (force || _controller2 == null || !_controller2!.value.isInitialized) {
          _statusMessage = 'Starting Camera 2...';
          notifyListeners();
          await _initController(1, cameras[1]);
        }
      }

      _statusMessage = 'Hardware ready.';
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Init Error: $e';
      notifyListeners();
      debugPrint('CameraService: Global initialization error: $e');
    } finally {
      _isInitializing = false;
      _initCompleter?.complete();
      _initCompleter = null;
    }
  }

  Future<void> _initController(int index, CameraDescription camera) async {
    try {
      debugPrint('CameraService: Initializing camera $index (${camera.name})...');
      
      // On Web, we should be very careful with presets and format groups
      final ImageFormatGroup? formatGroup = kIsWeb 
          ? null 
          : (Platform.isWindows ? ImageFormatGroup.unknown : ImageFormatGroup.jpeg);

      final controller = CameraController(
        camera, 
        ResolutionPreset.medium, 
        enableAudio: false,
        imageFormatGroup: formatGroup,
      );

      if (index == 0) {
        if (_controller != null) {
          try { await _controller!.dispose(); } catch (_) {}
        }
        _controller = controller;
      } else {
        if (_controller2 != null) {
          try { await _controller2!.dispose(); } catch (_) {}
        }
        _controller2 = controller;
      }

      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('CameraService: Preset medium failed for camera $index, retrying with low...');
        // Fallback for older webcams or restricted browser environments
        if (index == 0) _controller = CameraController(camera, ResolutionPreset.low, enableAudio: false, imageFormatGroup: formatGroup);
        else _controller2 = CameraController(camera, ResolutionPreset.low, enableAudio: false, imageFormatGroup: formatGroup);
        
        final newCtrl = index == 0 ? _controller! : _controller2!;
        await newCtrl.initialize();
      }

      if (index == 0) _isInitialized = true;
      else _isInitialized2 = true;
      
      _isCameraFailing[index] = false;
      _consecutiveFailures[index] = 0;
      debugPrint('CameraService: Camera $index Ready');
    } catch (e) {
      debugPrint('CameraService: CRITICAL failure for camera $index: $e');
      if (index == 0) _isInitialized = false;
      else _isInitialized2 = false;
    }
  }

  // Get list of available physical cameras
  Future<List<Map<String, dynamic>>> getAvailablePhysicalCameras() async {
    try {
      final cameras = await availableCameras();
      return cameras.asMap().entries.map((entry) {
        int idx = entry.key;
        CameraDescription cam = entry.value;
        String name = cam.name;
        if (name.toLowerCase().contains('0') || idx == 0) {
          name = "Built-in Camera";
        } else if (name.toLowerCase().contains('1') || idx == 1) {
          name = "USB Webcam";
        } else {
          name = "Camera ${idx + 1}";
        }

        return {
          'id': idx.toString(),
          'name': name,
          'description': cam.lensDirection.toString().split('.').last,
        };
      }).toList();
    } catch (e) {
      debugPrint('CameraService: Error getting cameras: $e');
      return [];
    }
  }

  void startMonitoring(int userId, String roomName) {
    _currentUserId = userId;
    _activeRooms.add(roomName);

    // Automatically enable live preview for the first room of each physical camera
    int camIdx = getCameraIndexForRoom(roomName);
    if (!_activePreviewRooms.containsKey(camIdx)) {
      _activePreviewRooms[camIdx] = roomName;
      debugPrint('CameraService: Auto-enabled live preview for $roomName (Camera $camIdx)');
    }

    if (_captureTimer == null) {
      // Snapshot every 500ms (2 FPS) for AI detection and a smoother "Live" feel
      _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!_isAlertShowing && !_isRecording) {
          _captureAndSendFrames();
        }
      });
    }
    notifyListeners();
  }

  void stopMonitoring(String roomName) {
    _activeRooms.remove(roomName);
    int camIdx = getCameraIndexForRoom(roomName);
    if (_activePreviewRooms[camIdx] == roomName) {
      _activePreviewRooms.remove(camIdx);
    }
    if (_activeRooms.isEmpty) {
      _captureTimer?.cancel();
      _captureTimer = null;
      _disposeControllers();
    }
  }

  Future<void> _disposeControllers() async {
    if (_controller != null) {
      try { await _controller!.dispose(); } catch (_) {}
      _controller = null;
    }
    if (_controller2 != null) {
      try { await _controller2!.dispose(); } catch (_) {}
      _controller2 = null;
    }
    _isInitialized = false;
    _isInitialized2 = false;
    _activePreviewRooms.clear();
    notifyListeners();
  }

  // --- VIDEO RECORDING LOGIC ---

  Future<void> armBedExitRecording(int cameraIndex) async {
    if (_currentUserId == null) return;
    final ctrl = cameraIndex == 0 ? _controller : _controller2;
    final isInit = cameraIndex == 0 ? _isInitialized : _isInitialized2;

    if (ctrl == null || !isInit || !ctrl.value.isInitialized) {
      debugPrint('CameraService: Cannot arm bed-exit clip, camera $cameraIndex not ready');
      return;
    }
    if (_activeRecordings[cameraIndex] == true) {
      debugPrint('CameraService: Bed-exit arm skipped — camera $cameraIndex already recording');
      return;
    }

    try {
      debugPrint('CameraService: Arming bed-exit recording on camera $cameraIndex');
      _activeRecordings[cameraIndex] = true;
      _isRecording = true;
      _bedExitArmStarted[cameraIndex] = DateTime.now();
      notifyListeners();

      await ctrl.startVideoRecording();

      _bedExitMaxTimer[cameraIndex]?.cancel();
      _bedExitMaxTimer[cameraIndex] = Timer(const Duration(seconds: 15), () {
        _stopBedExitRecording(cameraIndex, null, null);
      });
    } catch (e) {
      debugPrint('CameraService: Bed-exit arm failed: $e');
      _activeRecordings[cameraIndex] = false;
      _bedExitArmStarted.remove(cameraIndex);
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();
    }
  }

  Future<void> finalizeBedExitRecording(
    int cameraIndex,
    int eventId,
    String roomName, {
    double? clipTrimStartSec,
  }) async {
    if (_activeRecordings[cameraIndex] != true ||
        !_bedExitArmStarted.containsKey(cameraIndex)) {
      debugPrint(
        'CameraService: No armed bed-exit clip — fallback 8s record for event $eventId',
      );
      await captureVideoClip(cameraIndex, eventId, roomName, durationSec: 8);
      return;
    }

    _bedExitFinalizeTimer[cameraIndex]?.cancel();
    _bedExitFinalizeTimer[cameraIndex] = Timer(const Duration(seconds: 6), () {
      _stopBedExitRecording(
        cameraIndex,
        eventId,
        roomName,
        clipTrimStartSec: clipTrimStartSec,
      );
    });
  }

  Future<void> _stopBedExitRecording(
    int cameraIndex,
    int? eventId,
    String? roomName, {
    double? clipTrimStartSec,
  }) async {
    _bedExitFinalizeTimer[cameraIndex]?.cancel();
    _bedExitFinalizeTimer[cameraIndex] = null;
    _bedExitMaxTimer[cameraIndex]?.cancel();
    _bedExitMaxTimer[cameraIndex] = null;

    if (_activeRecordings[cameraIndex] != true) return;

    final ctrl = cameraIndex == 0 ? _controller : _controller2;
    if (ctrl == null || !ctrl.value.isRecordingVideo) {
      _activeRecordings[cameraIndex] = false;
      _bedExitArmStarted.remove(cameraIndex);
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();
      return;
    }

    try {
      final XFile file = await ctrl.stopVideoRecording();
      _activeRecordings[cameraIndex] = false;
      _bedExitArmStarted.remove(cameraIndex);
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();

      if (eventId != null && roomName != null) {
        await _uploadVideoClip(
          file,
          eventId,
          roomName,
          clipTrimStartSec: clipTrimStartSec,
        );
      }
    } catch (e) {
      debugPrint('CameraService: Bed-exit stop/upload failed: $e');
      _activeRecordings[cameraIndex] = false;
      _bedExitArmStarted.remove(cameraIndex);
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();
    }
  }

  Future<void> captureVideoClip(
    int cameraIndex,
    int eventId,
    String roomName, {
    int durationSec = 5,
  }) async {
    if (_currentUserId == null) return;
    final ctrl = cameraIndex == 0 ? _controller : _controller2;
    final isInit = cameraIndex == 0 ? _isInitialized : _isInitialized2;

    if (ctrl == null || !isInit || !ctrl.value.isInitialized) {
      debugPrint('CameraService: Cannot record, camera $cameraIndex not ready');
      return;
    }

    if (_activeRecordings[cameraIndex] == true) {
      debugPrint('CameraService: Camera $cameraIndex already recording');
      return;
    }

    try {
      debugPrint('CameraService: Starting 5s video clip for event $eventId on camera $cameraIndex');
      _activeRecordings[cameraIndex] = true;
      _isRecording = true;
      notifyListeners();

      await ctrl.startVideoRecording();
      
      // Record for durationSec seconds
      await Future.delayed(Duration(seconds: durationSec));

      final XFile file = await ctrl.stopVideoRecording();
      _activeRecordings[cameraIndex] = false;
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();

      // Upload the clip
      await _uploadVideoClip(file, eventId, roomName);
      
    } catch (e) {
      debugPrint('CameraService: Error during video capture: $e');
      _activeRecordings[cameraIndex] = false;
      _isRecording = _activeRecordings.values.any((v) => v);
      notifyListeners();
    }
  }

  Future<void> _uploadVideoClip(
    XFile file,
    int eventId,
    String roomName, {
    double? clipTrimStartSec,
  }) async {
    if (_currentUserId == null) return;

    try {
      final rawBytes = await file.readAsBytes();

      final token = await _authService.getToken();

      final uri = Uri.parse('${AuthService.baseUrl}/api/upload-event-clip');
      var request = http.MultipartRequest('POST', uri);

      if (token != null) request.headers['Authorization'] = 'Bearer $token';

      request.fields['user_id'] = _currentUserId.toString();
      request.fields['room_name'] = roomName;
      request.fields['event_id'] = eventId.toString();
      if (clipTrimStartSec != null && clipTrimStartSec > 0.05) {
        request.fields['clip_trim_start_sec'] = clipTrimStartSec.toString();
      }

      // Plain device MP4/WebM so the server can transcode to H.264 MP4 for all clients.
      // Client-side AES used a random per-process IV (IV.fromLength), so the server could never decrypt.
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        rawBytes,
        filename: 'event_clip.mp4',
      ));

      debugPrint('CameraService: Uploading video clip for event $eventId...');
      final response = await request.send().timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        debugPrint('CameraService: Video clip uploaded successfully for event $eventId');
      } else {
        debugPrint('CameraService: Video upload failed with status ${response.statusCode}');
      }

      if (!kIsWeb) {
        try { await File(file.path).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('CameraService: Error uploading video clip: $e');
    }
  }

  Future<void> _captureAndSendFrames() async {
    if (_activeRooms.isEmpty || _currentUserId == null || _isSwitching) return;

    final now = DateTime.now();
    for (final i in const [0, 1]) {
      final since = _captureBusySince[i];
      if (_captureBusy[i] == true &&
          since != null &&
          now.difference(since).inSeconds > 12) {
        debugPrint('CameraService: Capture slot $i stuck; releasing lock.');
        _captureBusy[i] = false;
        _captureBusySince[i] = null;
      }
    }

    String? token;
    try {
      token = await _authService.getToken();
    } catch (e) {
      debugPrint('CameraService: token before capture failed: $e');
      return;
    }

    // Group active rooms by their assigned camera index, with fallback
    final Map<int, List<String>> cameraGroups = {};
    for (var room in _activeRooms) {
      int idx = getCameraIndexForRoom(room);
      // Fallback to camera 0 if camera 1 is not initialized or failing
      if (idx == 1 &&
          (!_isInitialized2 ||
              _controller2 == null ||
              !_controller2!.value.isInitialized ||
              _isCameraFailing[1] == true)) {
        idx = 0;
      }
      cameraGroups.putIfAbsent(idx, () => []).add(room);
    }

    for (final entry in cameraGroups.entries) {
      final idx = entry.key;
      final rooms = entry.value;
      if (_captureBusy[idx] == true) continue;

      _captureBusy[idx] = true;
      _captureBusySince[idx] = DateTime.now();

      unawaited(
        _runCaptureUploadForCamera(idx, rooms, token).whenComplete(() {
          _captureBusy[idx] = false;
          _captureBusySince[idx] = null;
        }),
      );
    }
  }

  Future<void> _runCaptureUploadForCamera(
    int idx,
    List<String> rooms,
    String? token,
  ) async {
    final ctrl = idx == 0 ? _controller : _controller2;
    final isInit = idx == 0 ? _isInitialized : _isInitialized2;

    try {
      if (ctrl == null || !isInit || !ctrl.value.isInitialized) {
        return;
      }

      if (ctrl.value.isTakingPicture) {
        return;
      }

      List<String> roomsToReport = rooms;
      final activeRoomInGroup = _activePreviewRooms[idx];
      if (activeRoomInGroup != null && rooms.contains(activeRoomInGroup)) {
        roomsToReport = [activeRoomInGroup];
      } else if (rooms.length > 1) {
        roomsToReport = [rooms.first];
      }

      final XFile file =
          await ctrl.takePicture().timeout(const Duration(seconds: 3));
      final bytes = await file.readAsBytes();

      _lastFrames[idx] = bytes;
      if (idx == 0) _lastFrame = bytes;
      _lastSuccessfulCapture[idx] = DateTime.now();
      _isCameraFailing[idx] = false;
      _consecutiveFailures[idx] = 0;

      notifyListeners();

      final roomList = roomsToReport.join(',');
      final uri = Uri.parse('${AuthService.baseUrl}/api/laptop-monitor')
          .replace(queryParameters: {
        'user_id': _currentUserId.toString(),
        'room_name': roomList,
        'camera_id': idx.toString(),
      });

      var request = http.MultipartRequest('POST', uri);
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'frame.jpg'),
      );

      await request.send().timeout(const Duration(seconds: 8));
      if (!kIsWeb) {
        try {
          await File(file.path).delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('CameraService: Error capturing from camera $idx: $e');
      _consecutiveFailures[idx] = (_consecutiveFailures[idx] ?? 0) + 1;

      if (_consecutiveFailures[idx]! >= 3) {
        debugPrint('CameraService: Camera $idx marked as FAILING after multiple errors.');
        _isCameraFailing[idx] = true;

        final lastSuccess = _lastSuccessfulCapture[idx];
        if (lastSuccess == null ||
            DateTime.now().difference(lastSuccess).inSeconds > 15) {
          debugPrint('CameraService: Attempting auto-recovery for camera $idx...');
          _consecutiveFailures[idx] = 0;
          initialize(force: true);
        }
      }
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _disposeControllers();
    super.dispose();
  }
}
