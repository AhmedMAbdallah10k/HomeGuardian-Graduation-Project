import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../services/websocket_service.dart';
import '../services/alert_message_mapper.dart';
import 'room_playback_page.dart';
import 'event_page.dart';

class RoomDetailPage extends StatefulWidget {
  final String roomName;

  const RoomDetailPage({super.key, required this.roomName});

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  // Remote monitoring and WebSocket state
  Uint8List? _remoteFrameBytes;
  late AuthService _authService;
  late WebSocketService _webSocketService;
  StreamSubscription? _webSocketSubscription;

  // Events management
  List<Map<String, dynamic>> _events = [];
  bool _isLoadingEvents = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _webSocketService = WebSocketService();

    // Initialize monitoring session
    Future.delayed(Duration.zero, () => _initializeApp());
  }

  Future<void> _initializeApp() async {
    try {
      _fetchEvents();

      if (!mounted) return;
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) return;

      // Watch-only: same WebSocket scope as the home owner (family members included).
      // Do not start a phone camera session or call setMonitoringSession — that would
      // steal or overwrite the laptop's active camera for the room.
      _setupWebSocketListener();
      await _webSocketService.connect(userId: user.effectiveOwnerId);
    } catch (e) {
      debugPrint('RoomDetailPage: Init error: $e');
    }
  }

  void _setupWebSocketListener() {
    _webSocketSubscription = _webSocketService.messageStream.listen((message) {
      if (!mounted) return;
      final type = message['type']?.toString();
      if (type == 'remote_frame') {
        if (message['room_name'] == widget.roomName) {
          setState(() {
            _remoteFrameBytes = base64Decode(message['frame']);
          });
        }
        return;
      }
      if (type == 'event_created' || isAlertWebSocketType(type)) {
        _fetchEvents();
        if (message['room_name'] == widget.roomName) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _fetchEvents() async {
    setState(() => _isLoadingEvents = true);
    final result = await _authService.getEvents();
    if (mounted) {
      setState(() {
        if (result['success'] == true) {
          // Filter events for this specific room
          _events = List<Map<String, dynamic>>.from(result['events'])
              .where((event) => event['room_name'] == widget.roomName)
              .toList();
        }
        _isLoadingEvents = false;
      });
    }
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.roomName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),

                  Positioned(
                    right: 24,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _remoteFrameBytes != null
                              ? Colors.red
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_circle_fill,
                              color: _remoteFrameBytes != null
                                  ? Colors.white
                                  : Colors.grey,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _remoteFrameBytes != null ? "LIVE" : "WAITING",
                              style: TextStyle(
                                color: _remoteFrameBytes != null
                                    ? Colors.white
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                fontFamily: 'Comfortaa',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 30),

                    // Video Player Area
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAEAEA),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.black, width: 5),
                          ),
                            child: Stack(
                              children: [
                                Center(
                                  child: _remoteFrameBytes != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(44),
                                          child: Image.memory(
                                            _remoteFrameBytes!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            gaplessPlayback: true,
                                          ),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.laptop_mac,
                                                size: 48,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Waiting for live video from the dashboard for this room.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.grey[700],
                                                  fontFamily: 'Comfortaa',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),

                              // Controls Overlay
                              Positioned(
                                bottom: 24,
                                left: 24,
                                right: 24,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.play_arrow,
                                      size: 36,
                                      color: Colors.black,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: _remoteFrameBytes != null
                                            ? 1.0
                                            : 0.0,
                                        backgroundColor: Colors.grey[400],
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.fullscreen,
                                      size: 30,
                                      color: Colors.black,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Playback Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RoomPlaybackPage(
                                    roomName: widget.roomName,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Playback",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Comfortaa',
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(height: 1, color: Colors.grey[300]),
                    ),

                    const SizedBox(height: 16),

                    // Events Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              "Recent Events",
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Comfortaa',
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Events List
                    Expanded(
                      child: _isLoadingEvents
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              itemCount: _events.length > 5
                                  ? 5
                                  : _events.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      print('Room Detail Page: Event clicked: ${event['id']}');
                                      try {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EventPage(event: event),
                                          ),
                                        );
                                        print('Room Detail Page: Navigation triggered');
                                      } catch (e) {
                                        print('Room Detail Page: Navigation error: $e');
                                      }
                                    },
                                    child: _buildEventCard(
                                      time: event['timestamp'] != null
                                          ? TimeOfDay.fromDateTime(
                                              DateTime.parse(event['timestamp']),
                                            ).format(context)
                                          : "Now",
                                      description: event['title'] ?? "Alert",
                                      ago: "Recent",
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard({
    required String time,
    required String description,
    required String ago,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontFamily: 'Comfortaa',
                  ),
                ),
              ],
            ),
          ),
          Text(
            ago,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              fontFamily: 'Comfortaa',
            ),
          ),
        ],
      ),
    );
  }
}
