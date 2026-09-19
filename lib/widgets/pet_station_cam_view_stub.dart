import 'package:flutter/widgets.dart';

/// Non-web fallback: poll ESP32 /snapshot directly.
Widget buildPetStationCamView({
  required String camIp,
  required int refreshTick,
}) {
  final url = 'http://$camIp/snapshot?t=$refreshTick';
  return Image.network(
    url,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => Center(
      child: Text(
        'Open http://$camIp in your browser to test the camera.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
