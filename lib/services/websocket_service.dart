import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth_service.dart';

/// Single shared connection so all screens (e.g. [EventPage]) receive `recording_ready`.
class WebSocketService {
  WebSocketService._internal();
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _messageController;
  bool _isConnected = false;
  Timer? _pingTimer;
  /// Last origin used for the active socket — forces reconnect after [AuthService.baseUrl] changes.
  String? _lastConnectedBaseUrl;

  Stream<Map<String, dynamic>> get messageStream {
    _messageController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _messageController!.stream;
  }

  bool get isConnected => _isConnected;

  Future<void> connect({int? userId}) async {
    final apiBaseUrl = AuthService.baseUrl;
    if (_lastConnectedBaseUrl != null &&
        _lastConnectedBaseUrl != apiBaseUrl) {
      disconnect();
    }
    if (_isConnected && _channel != null) {
      return;
    }

    try {
      // Convert http to ws — read each connect so LAN / Tunnel switches apply.
      final wsUrl = apiBaseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');

      String urlString = '$wsUrl/ws/fire-alerts';
      final uri = Uri.parse(urlString);

      _channel = WebSocketChannel.connect(uri);

      // If we have a userId, send it as the first message to join the room
      if (userId != null) {
        _channel!.sink.add(userId.toString());
      }

      _isConnected = true;

      // Start ping timer to keep connection alive
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_isConnected && _channel != null) {
          _channel!.sink.add('ping');
        }
      });

      // Listen for messages
      _channel!.stream.listen(
        (data) {
          if (data == 'pong') {
            print('WebSocket: Received pong');
            return;
          }
          try {
            print('WebSocket: Received message: $data');
            final Map<String, dynamic> message = json.decode(data);
            
            // Check if this is an event that should be shown in Recent Activity
            if (message['type'] == 'fire_alert' || message['type'] == 'door_alert') {
              // Create a synthesized event_created message if the server didn't send one
              _messageController?.add({
                'type': 'event_created',
                'event': {
                  'title': message['type'] == 'fire_alert' ? 'Fire Detected!' : 'Door Activity!',
                  'description': message['type'] == 'fire_alert' ? 'Fire detected by camera.' : 'Activity detected on door.',
                  'event_type': message['type'] == 'fire_alert' ? 'emergency' : 'security',
                  'room_name': message['room_name'] ?? 'Unknown',
                  'timestamp': message['timestamp'] ?? DateTime.now().toIso8601String(),
                }
              });
            }
            
            _messageController?.add(message);
          } catch (e) {
            print('Error decoding WebSocket message: $e | Data: $data');
          }
        },
        onDone: () {
          print('WebSocket: Connection closed by server');
          _isConnected = false;
          _messageController?.add({'type': 'disconnected'});
        },
        onError: (error) {
          print('WebSocket: Connection error: $error');
          _isConnected = false;
          _messageController?.add({
            'type': 'error',
            'message': error.toString(),
          });
        },
      );

      _lastConnectedBaseUrl = apiBaseUrl;
      print('WebSocket connected successfully');
    } catch (e) {
      print('Error connecting WebSocket: $e');
      _isConnected = false;
      _messageController?.add({
        'type': 'error',
        'message': 'Failed to connect: $e',
      });
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _lastConnectedBaseUrl = null;
    print('WebSocket disconnected');
  }

  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
  }
}
