import 'dart:typed_data';

/// A stub for web-only video operations to prevent mobile build errors.
String createWebVideoUrl(Uint8List bytes, String mimeType) {
  return '';
}

void revokeWebVideoUrl(String url) {
  // Do nothing
}

void downloadFileOnWeb(Uint8List bytes, String filename, String mimeType) {
  // No-op on mobile/desktop native builds
}
