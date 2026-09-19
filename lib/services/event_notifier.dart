import 'package:flutter/foundation.dart';

import 'alert_message_mapper.dart';
import 'auth_service.dart';

/// Shared live events list + refresh signals for all event UIs.
class EventNotifier extends ChangeNotifier {
  final AuthService _auth = AuthService();

  List<Map<String, dynamic>> events = [];
  bool isLoading = false;
  String? loadError;

  int homePresenceVersion = 0;
  int monitoringAssignmentsVersion = 0;
  int lostItemsVersion = 0;

  Future<void> loadFromApi({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      loadError = null;
      notifyListeners();
    }

    final result = await _auth.getEvents();
    if (result['success'] == true) {
      final raw = result['events'];
      events = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      loadError = null;
    } else {
      if (!silent) {
        loadError = result['message']?.toString() ?? 'Failed to load events';
      }
    }
    isLoading = false;
    notifyListeners();
  }

  void applyWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    if (type == null) return;

    switch (type) {
      case 'event_created':
        final raw = message['event'];
        if (raw is Map) {
          final newEvent = Map<String, dynamic>.from(raw);
          if (message['recording_expected'] == true) {
            newEvent['recording_expected'] = true;
          }
          _insertEvent(newEvent);
        }
        break;
      case 'recording_ready':
        final eventId = message['event_id'];
        final videoUrl = message['video_url']?.toString();
        if (eventId == null || videoUrl == null) break;
        for (var i = 0; i < events.length; i++) {
          if (events[i]['id'] == eventId) {
            events[i] = Map<String, dynamic>.from(events[i])
              ..['video_path'] = videoUrl
              ..['video_url'] = videoUrl;
            notifyListeners();
            break;
          }
        }
        break;
      case 'home_presence_updated':
        homePresenceVersion++;
        notifyListeners();
        break;
      case 'monitoring_assignments_updated':
        monitoringAssignmentsVersion++;
        notifyListeners();
        break;
      case 'lost_items_updated':
        lostItemsVersion++;
        notifyListeners();
        break;
      default:
        if (isAlertWebSocketType(type)) {
          // Typed alerts usually precede event_created; refresh as fallback.
          loadFromApi(silent: true);
        }
        break;
    }
  }

  void _insertEvent(Map<String, dynamic> newEvent) {
    final id = newEvent['id'];
    if (id != null) {
      events.removeWhere((e) => e['id'] == id);
    }
    events.insert(0, newEvent);
    notifyListeners();
  }

  void removeEventById(dynamic eventId) {
    if (eventId == null) return;
    final idStr = eventId.toString();
    events.removeWhere((e) => e['id']?.toString() == idStr);
    notifyListeners();
  }
}
