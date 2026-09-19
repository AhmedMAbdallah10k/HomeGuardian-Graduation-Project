import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'alert_message_mapper.dart';
import 'camera_service.dart';
import 'event_notifier.dart';
import 'in_app_alert_service.dart';
import 'user_provider.dart';
import 'websocket_service.dart';

/// One WebSocket listener for the whole app — popups on any page.
class GlobalAlertCoordinator {
  GlobalAlertCoordinator({
    required this.isDashboard,
    required this.isMobileLayout,
  });

  final bool isDashboard;
  final bool isMobileLayout;

  final WebSocketService _ws = WebSocketService();
  StreamSubscription<Map<String, dynamic>>? _subscription;

  Future<void> start(BuildContext context) async {
    await stop();

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    final userId = isDashboard ? user.id : user.effectiveOwnerId;
    await _ws.connect(userId: userId);

    if (!context.mounted) return;

    final events = Provider.of<EventNotifier>(context, listen: false);
    if (events.events.isEmpty && !events.isLoading) {
      unawaited(events.loadFromApi(silent: true));
    }

    _subscription = _ws.messageStream.listen((message) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final events = Provider.of<EventNotifier>(ctx, listen: false);
      final userProvider = Provider.of<UserProvider>(ctx, listen: false);
      _handleMessage(message, events, userProvider);
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _ws.disconnect();
  }

  void _handleMessage(
    Map<String, dynamic> message,
    EventNotifier events,
    UserProvider userProvider,
  ) {
    final type = message['type']?.toString();
    if (type == null || type == 'disconnected' || type == 'error') return;

    if (type == 'recording_ready' && isDashboard) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null &&
          Provider.of<UserProvider>(ctx, listen: false).inAppAlertsEnabled) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text('Video recording ready for event!'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    events.applyWebSocketMessage(message);

    if (isDashboard) {
      _handleDashboardRecording(message);
      _handleDashboardSnackbars(message);
    }

    final ctx = rootNavigatorKey.currentContext;
    final inApp = ctx != null
        ? Provider.of<UserProvider>(ctx, listen: false).inAppAlertsEnabled
        : userProvider.inAppAlertsEnabled;
    if (!inApp) return;
    if (!isAlertWebSocketType(type)) return;

    InAppAlertService.instance.showForMessage(
      message,
      mobileLayout: isMobileLayout,
    );
  }

  void _handleDashboardSnackbars(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'camera_list_updated') return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final cameras = message['cameras'];
    final count = cameras is List ? cameras.length : 0;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('Camera list updated: $count cameras online'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _handleDashboardRecording(Map<String, dynamic> message) {
    final type = message['type']?.toString();

    if (type == 'bed_exit_arm_recording') {
      final roomName = message['room_name']?.toString() ?? 'Unknown';
      final camIdx = CameraService().getCameraIndexForRoom(roomName);
      CameraService().armBedExitRecording(camIdx);
      return;
    }

    if (type == 'bed_exit_alert' &&
        message['finalize_bed_exit_recording'] == true &&
        message['event_id'] != null) {
      final roomName = message['room_name']?.toString() ?? 'Unknown';
      final eventId = message['event_id'];
      final camIdx = CameraService().getCameraIndexForRoom(roomName);
      final trim = message['clip_trim_start_sec'];
      final trimSec = trim is num ? trim.toDouble() : null;
      CameraService().finalizeBedExitRecording(
        camIdx,
        eventId,
        roomName,
        clipTrimStartSec: trimSec,
      );
      return;
    }

    if (message['start_recording'] == true && message['event_id'] != null) {
      final roomName = message['room_name']?.toString() ?? 'Unknown';
      final eventId = message['event_id'];
      final camIdx = CameraService().getCameraIndexForRoom(roomName);
      CameraService().captureVideoClip(camIdx, eventId, roomName);
    }
  }
}
