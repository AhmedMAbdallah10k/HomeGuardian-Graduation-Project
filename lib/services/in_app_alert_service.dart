import 'dart:async';

import 'package:flutter/material.dart';

import 'alert_message_mapper.dart';
import 'camera_service.dart';

/// Root navigator — set on [MaterialApp.navigatorKey].
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Shows a global overlay banner above any route (dashboard or mobile).
class InAppAlertService {
  InAppAlertService._();
  static final InAppAlertService instance = InAppAlertService._();

  OverlayEntry? _entry;
  Timer? _autoDismiss;
  bool _mobileLayout = false;

  void show(AlertDisplay display, {bool mobileLayout = false}) {
    _mobileLayout = mobileLayout;
    _dismiss();

    final overlayState = rootNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    CameraService().isAlertShowing = true;

    _entry = OverlayEntry(
      builder: (context) => _AlertBanner(
        display: display,
        mobileLayout: _mobileLayout,
        onClose: _dismiss,
      ),
    );
    overlayState.insert(_entry!);

    _autoDismiss?.cancel();
    _autoDismiss = Timer(const Duration(seconds: 5), _dismiss);
  }

  void showForMessage(
    Map<String, dynamic> message, {
    bool mobileLayout = false,
  }) {
    final display = alertDisplayForMessage(message);
    if (display != null) {
      show(display, mobileLayout: mobileLayout);
    }
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _entry?.remove();
    _entry = null;
    CameraService().isAlertShowing = false;
  }
}

class _AlertBanner extends StatelessWidget {
  final AlertDisplay display;
  final bool mobileLayout;
  final VoidCallback onClose;

  const _AlertBanner({
    required this.display,
    required this.mobileLayout,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (mobileLayout) {
      return Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 16,
        right: 16,
        child: _card(onClose),
      );
    }
    return Positioned(
      top: 20,
      right: 20,
      width: 350,
      child: _card(onClose),
    );
  }

  Widget _card(VoidCallback onClose) {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: display.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            if (display.icon != null) ...[
              Icon(display.icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                display.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'Comfortaa',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
