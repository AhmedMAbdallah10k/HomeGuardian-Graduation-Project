import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation for video operations.
String createWebVideoUrl(Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeWebVideoUrl(String url) {
  try {
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    // Ignore cleanup errors
  }
}

/// Trigger a browser file download (dashboard / web).
void downloadFileOnWeb(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
