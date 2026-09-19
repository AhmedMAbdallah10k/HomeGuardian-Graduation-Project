import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

///
/// IMPORTANT: Must not use [encrypt.AES] default mode (**SIC/CTR**) or
/// `IV.fromLength` (**random IV**); those broke decryption of Python-encrypted recordings.
/// Optional env on server `RECORDINGS_AES_KEY` → first 32 UTF-8 bytes; keep this Dart key aligned.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  // In a production app, this key should be securely stored or derived from user credentials
  static final _key = encrypt.Key.fromUtf8('my32characterultrasecretkey12345');

  /// Must match server's `_CLIP_AES_IV` / PyCryptodome `bytes(16)`.
  static final _iv = encrypt.IV.allZerosOfLength(16);

  static final encrypt.Encrypter _cbc = encrypt.Encrypter(
    encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );

  /// Encrypts raw bytes — same packing as server's `_encrypt_bytes_at_rest`.
  Uint8List encryptBytes(Uint8List bytes) {
    try {
      final encrypted = _cbc.encryptBytes(bytes, iv: _iv);
      return encrypted.bytes;
    } catch (e) {
      debugPrint('SecurityService: Encryption error: $e');
      return bytes; // Fallback to unencrypted if it fails (not ideal for security but prevents crash)
    }
  }

  /// Decrypts AES-CBC payloads produced by Python or [encryptBytes].
  Uint8List decryptBytes(Uint8List encryptedBytes) {
    try {
      final decrypted = _cbc.decryptBytes(
        encrypt.Encrypted(encryptedBytes),
        iv: _iv,
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint('SecurityService: Decryption error: $e');
      return encryptedBytes; // Fallback (caller treats as ciphertext if magic bytes wrong)
    }
  }
}
