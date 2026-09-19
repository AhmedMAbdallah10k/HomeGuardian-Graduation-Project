import 'dart:typed_data';

import '../services/security_service.dart';

/// Server stores clips AES-encrypted at rest (.enc); plain MP4/WebM is legacy only.
/// After an authenticated GET, normalize bytes for ExoPlayer / file save.
class RecordingPlaybackCodec {
  static bool isLikelyWebmOrMatroska(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3;
  }

  static bool isLikelyMp4(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
  }

  /// Encrypted payloads from the server decrypt with [SecurityService] (AES-CBC, zero IV).
  static Uint8List playableFromDownloadBody(Uint8List raw) {
    if (isLikelyWebmOrMatroska(raw) || isLikelyMp4(raw)) {
      return raw;
    }
    return SecurityService().decryptBytes(raw);
  }

  static String extensionForPlayable(Uint8List playable) {
    if (isLikelyMp4(playable)) return 'mp4';
    if (isLikelyWebmOrMatroska(playable)) return 'webm';
    return 'mp4';
  }

  /// Blob MIME for [createWebVideoUrl] on web (MP4 must not be labelled as WebM).
  static String mimeTypeForPlayable(Uint8List playable) {
    if (isLikelyMp4(playable)) return 'video/mp4';
    if (isLikelyWebmOrMatroska(playable)) return 'video/webm';
    return 'video/mp4';
  }
}
