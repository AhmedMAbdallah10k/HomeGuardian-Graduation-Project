import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final Set<String> _registeredCamViews = {};

/// Web: embed ESP32 MJPEG stream in an iframe (same as opening the CAM in a tab).
Widget buildPetStationCamView({
  required String camIp,
  required int refreshTick,
}) {
  final viewType = 'pet-station-cam-$camIp';

  if (!_registeredCamViews.contains(viewType)) {
    _registeredCamViews.add(viewType);
    final streamUrl = 'http://$camIp:81/stream';
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = streamUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      },
    );
  }

  return HtmlElementView(viewType: viewType);
}
