import 'package:flutter/material.dart';

/// Visual payload for a global in-app alert banner.
class AlertDisplay {
  final String message;
  final Color color;
  final IconData? icon;

  const AlertDisplay({
    required this.message,
    required this.color,
    this.icon,
  });
}

/// WebSocket types that represent AI detections or saved events.
const Set<String> kAlertWebSocketTypes = {
  'event_created',
  'fire_alert',
  'door_alert',
  'window_alert',
  'exit_alert',
  'stillness_alert',
  'choking_alert',
  'fall_alert',
  'bed_exit_alert',
  'pet_alert',
  'fridge_alert',
  'sharp_object_alert',
  'pest_alert',
  'hazard_alert',
  'stuck_in_room_alert',
  'sleep_fell_asleep',
  'sleep_woke_up',
  'stranger_alert',
  'pet_station_alert',
  'food_dispensed',
  'food_cancelled',
  'food_alert',
};

bool isAlertWebSocketType(String? type) =>
    type != null && kAlertWebSocketTypes.contains(type);

/// Maps server WebSocket payloads to banner text / color / icon.
AlertDisplay? alertDisplayForMessage(Map<String, dynamic> message) {
  final type = message['type']?.toString();
  if (type == null) return null;

  if (type == 'event_created') {
    final event = message['event'];
    if (event is! Map) return null;
    final title = event['title']?.toString().trim();
    if (title == null || title.isEmpty) return null;
    final room = event['room_name']?.toString();
    final roomSuffix =
        room != null && room.isNotEmpty ? ' in $room' : '';
    final eventType = event['event_type']?.toString().toLowerCase() ?? '';
    final color = eventType.contains('emergency')
        ? Colors.red.shade700
        : eventType.contains('security')
            ? Colors.orange.shade800
            : Colors.blueGrey.shade700;
    return AlertDisplay(
      message: '$title$roomSuffix',
      color: color,
      icon: Icons.notifications_active,
    );
  }

  if (!kAlertWebSocketTypes.contains(type)) return null;

  switch (type) {
    case 'fire_alert':
      return AlertDisplay(
        message: 'FIRE ALERT in ${message['room_name']}!',
        color: Colors.red,
        icon: Icons.local_fire_department,
      );
    case 'door_alert':
      return AlertDisplay(
        message: 'DOOR ACTIVITY in ${message['room_name']}!',
        color: Colors.orange,
        icon: Icons.door_front_door,
      );
    case 'window_alert':
      return AlertDisplay(
        message: 'WINDOW OPEN in ${message['room_name']}!',
        color: Colors.blue,
        icon: Icons.window,
      );
    case 'exit_alert':
      return AlertDisplay(
        message: 'PERSON EXITED in ${message['room_name']}!',
        color: Colors.purple,
        icon: Icons.exit_to_app,
      );
    case 'stillness_alert':
      return AlertDisplay(
        message:
            'STILLNESS DETECTED (${message['elapsed_time']}s) in ${message['room_name']}!',
        color: Colors.amber,
        icon: Icons.warning,
      );
    case 'choking_alert':
      final wr = message['window_ratio'];
      final extra = wr is num ? ' (~${(wr * 100).toInt()}%)' : '';
      return AlertDisplay(
        message:
            'POSSIBLE CHOKING in ${message['room_name']}$extra — check now!',
        color: Colors.red.shade900,
        icon: Icons.masks_rounded,
      );
    case 'fall_alert':
      final p = message['probability'];
      final extra = p is num ? ' (p=${p.toStringAsFixed(2)})' : '';
      return AlertDisplay(
        message:
            'POSSIBLE FALL in ${message['room_name']}$extra — check now!',
        color: Colors.deepPurple,
        icon: Icons.elderly,
      );
    case 'bed_exit_alert':
      final critical = message['alert_type'] == 'critical';
      return AlertDisplay(
        message: critical
            ? 'CRITICAL: BED EXIT in ${message['room_name']}!'
            : 'BED EXIT WARNING in ${message['room_name']}!',
        color: critical ? Colors.red.shade900 : Colors.orange.shade800,
        icon: Icons.single_bed,
      );
    case 'pet_alert':
      return AlertDisplay(
        message: 'UNKNOWN PET in ${message['room_name']}!',
        color: Colors.cyan,
        icon: Icons.pets,
      );
    case 'fridge_alert':
      return AlertDisplay(
        message:
            'FRIDGE LEFT OPEN (${message['elapsed_time']}s) in ${message['room_name']}!',
        color: Colors.teal,
        icon: Icons.kitchen,
      );
    case 'sharp_object_alert':
      return AlertDisplay(
        message: 'SHARP OBJECT in ${message['room_name']}!',
        color: Colors.redAccent,
        icon: Icons.report_problem,
      );
    case 'pest_alert':
      final labels = message['labels'];
      final labelStr =
          labels is List && labels.isNotEmpty ? labels.join(', ') : 'Pest';
      return AlertDisplay(
        message: '$labelStr DETECTED in ${message['room_name']}!',
        color: Colors.green.shade800,
        icon: Icons.bug_report,
      );
    case 'hazard_alert':
      final subject = message['subject']?.toString() ?? 'Subject';
      final label = message['label']?.toString() ?? 'hazard';
      final status = message['status']?.toString() ?? 'near';
      final severity = message['severity']?.toString() ?? '';
      final sevPrefix = severity.isNotEmpty ? '[$severity] ' : '';
      return AlertDisplay(
        message:
            '$sevPrefix${subject.toUpperCase()} $status "$label" in ${message['room_name']}!',
        color: severity == 'CRITICAL'
            ? Colors.red.shade900
            : severity == 'HIGH'
                ? Colors.orange.shade800
                : Colors.amber.shade800,
        icon: Icons.warning_amber_rounded,
      );
    case 'stuck_in_room_alert':
      final subject = message['subject_type']?.toString() ?? 'subject';
      final title = message['title']?.toString();
      final text = title != null && title.isNotEmpty
          ? '$title in ${message['room_name']}!'
          : '${subject.toUpperCase()} MAY BE STUCK in ${message['room_name']}!';
      return AlertDisplay(
        message: text,
        color: Colors.deepOrange.shade800,
        icon: Icons.door_sliding,
      );
    case 'sleep_fell_asleep':
      return AlertDisplay(
        message: 'FELL ASLEEP in ${message['room_name']}!',
        color: Colors.indigo,
        icon: Icons.bedtime,
      );
    case 'sleep_woke_up':
      final dur = message['duration_label']?.toString() ?? '';
      final extra = dur.isNotEmpty ? ' (slept $dur)' : '';
      return AlertDisplay(
        message: 'WOKE UP in ${message['room_name']}$extra!',
        color: Colors.lightBlue,
        icon: Icons.wb_sunny,
      );
    case 'stranger_alert':
      return AlertDisplay(
        message: 'UNKNOWN PERSON in ${message['room_name']}!',
        color: Colors.deepOrange,
        icon: Icons.person_search,
      );
    case 'food_dispensed':
      return AlertDisplay(
        message: 'PET FOOD DISPENSED at Pet Station',
        color: Colors.green.shade700,
        icon: Icons.restaurant,
      );
    case 'food_cancelled':
      return AlertDisplay(
        message: 'PET FEEDING CANCELLED at Pet Station',
        color: Colors.orange.shade800,
        icon: Icons.cancel,
      );
    case 'pet_station_alert':
      return AlertDisplay(
        message: message['message']?.toString() ?? 'Pet Station alert',
        color: Colors.blue.shade800,
        icon: Icons.pets,
      );
    case 'food_alert':
      return AlertDisplay(
        message: 'FOOD LEFT OUT in ${message['room_name']}!',
        color: Colors.brown.shade600,
        icon: Icons.restaurant_menu,
      );
    default:
      return null;
  }
}
