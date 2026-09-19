import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String defaultBaseUrl = 'http://192.168.43.16:3000';

  static const _kPrefNetworkMode = 'network_route_mode';
  static const _kPrefApiHome = 'api_base_home_url';

  static String _effectiveBaseUrl = defaultBaseUrl;

  /// Current API origin (HTTP/HTTPS, no trailing slash). All services should use this getter.
  static String get baseUrl => _effectiveBaseUrl;

  static String? _normalizeOrigin(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    return s;
  }

  static void _recomputeEffectiveBase(SharedPreferences p) {
    final home = _normalizeOrigin(p.getString(_kPrefApiHome)) ?? defaultBaseUrl;
    _effectiveBaseUrl = home;
  }

  /// Call from [main] before [runApp]; use saved home URL or [defaultBaseUrl].
  static Future<void> bootstrapNetworkFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kPrefApiHome);
    if (saved == null || saved.trim().isEmpty) {
      await p.setString(_kPrefApiHome, defaultBaseUrl);
    }
    await p.setString(_kPrefNetworkMode, 'home');
    _recomputeEffectiveBase(p);
  }

  /// Applies `/api/options` payload — home LAN only.
  static Future<void> applyNetworkFromUserOptions(
    Map<String, dynamic> json,
  ) async {
    final p = await SharedPreferences.getInstance();
    var dirty = false;
    await p.setString(_kPrefNetworkMode, 'home');
    dirty = true;
    final h = json['api_base_home_url'];
    if (h != null && h.toString().trim().isNotEmpty) {
      await p.setString(_kPrefApiHome, _normalizeOrigin(h.toString())!);
      dirty = true;
    }
    if (dirty) {
      _recomputeEffectiveBase(p);
    }
  }

  /// Loads persisted LAN server URL.
  static Future<Map<String, String>> loadNetworkEndpointsFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    return {
      'mode': 'home',
      'home': p.getString(_kPrefApiHome) ?? defaultBaseUrl,
    };
  }

  /// Persists home LAN URL and recomputes [baseUrl].
  static Future<void> saveNetworkEndpointsLocal({
    required String homeUrl,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefNetworkMode, 'home');
    final hn = _normalizeOrigin(homeUrl);
    if (hn != null) await p.setString(_kPrefApiHome, hn);
    _recomputeEffectiveBase(p);
  }

  final _storage = const FlutterSecureStorage();

  // Login
  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    bool isDashboard = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'is_dashboard': isDashboard,
            }),
          )
          .timeout(Duration(seconds: isDashboard ? 30 : 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data['requires_verification'] == true) {
          return {'success': true, 'data': data, 'requires_verification': true};
        }
        // Handle both old and new response formats
        if (data['success'] == true || data['access_token'] != null) {
          if (data['access_token'] != null) {
            await _storage.write(
              key: 'auth_token',
              value: data['access_token'],
            );
          }
          return {'success': true, 'data': data};
        }
        return {
          'success': false,
          'message': data['message'] ?? 'Login failed',
          'data': data,
        };
      } else {
        final detail = data['detail'];
        final msg = detail is String ? detail : 'Login failed';
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      final hint =
          'Could not reach $baseUrl — phone must be on the same Wi‑Fi as the '
          'server. Tap "Set server URL before login" (e.g. http://192.168.8.58:3000).';
      if (e is TimeoutException) {
        return {'success': false, 'message': 'Connection timed out. $hint'};
      }
      return {'success': false, 'message': 'Connection error: $e\n$hint'};
    }
  }

  // Signup
  Future<Map<String, dynamic>> signup({
    required String name,
    required String email,
    required String password,
    String? phone,
    List<String>?
    profileImages, // Changed from String? profileImage to List<String>? profileImages
    bool isDashboard = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'phone': phone,
              'profile_images': profileImages ?? [], // Updated field name
              'is_dashboard': isDashboard,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Return structure that works for both Mobile (expects 'user' or 'success') and Dashboard
        if (data['access_token'] != null) {
          await _storage.write(key: 'auth_token', value: data['access_token']);
        }
        return {
          'success': true,
          'message': data['message'],
          'user': data['user'], // Keep this for mobile app
          'data': data,
        };
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Signup failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Verify OTP
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save token
        await _storage.write(key: 'auth_token', value: data['access_token']);
        return {'success': true, 'data': data};
      } else {
        final detail = data['detail'];
        final msg = detail is String ? detail : 'Verification failed';
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Public: validate an invite code and return the enrolled display name.
  Future<Map<String, dynamic>> lookupFamilyInvite(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/family/join/lookup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'name': data['name']?.toString() ?? '',
          'member_id': data['member_id'],
        };
      }
      final detail = data['detail'];
      return {
        'success': false,
        'message': detail is String ? detail : 'Invalid or expired code',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// First-time family signup: consumes the single-use invite code.
  Future<Map<String, dynamic>> joinFamilyAccount({
    required String code,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/family/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code.trim(),
              'email': email.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201 && data['access_token'] != null) {
        await _storage.write(key: 'auth_token', value: data['access_token']);
        return {'success': true, 'data': data};
      }
      final detail = data['detail'];
      return {
        'success': false,
        'message': detail is String ? detail : 'Could not complete signup',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Owner: generate or replace the invite code for a member who has not yet created an app login.
  Future<Map<String, dynamic>> regenerateFamilyInviteCode(int memberId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/family/$memberId/invite-code'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'invite_code': data['invite_code']?.toString(),
        };
      }
      final detail = data['detail'];
      return {
        'success': false,
        'message': detail is String ? detail : 'Failed to create invite',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Add Family Member
  Future<Map<String, dynamic>> addFamilyMember({
    required String name,
    required String relationship,
    required String phone,
    List<String>? photos, // base64 images
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/family'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({
              'name': name,
              'relationship': relationship,
              'phone': phone,
              'photos': photos ?? [],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to add family member',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// List all family members for the current user.
  /// Returns `{'success': true, 'members': List<Map<String, dynamic>>}` on success.
  /// Each member map has: id, name, relationship, phone, created_at, photo_path.
  Future<Map<String, dynamic>> getFamilyMembers() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/family'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'members': List<Map<String, dynamic>>.from(data['members'] ?? []),
        };
      } else {
        return {
          'success': false,
          'message':
              'Failed to load family members (HTTP ${response.statusCode})',
          'members': <Map<String, dynamic>>[],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
        'members': <Map<String, dynamic>>[],
      };
    }
  }

  /// Update a family member's name / relationship / phone.
  /// Any null field is left unchanged. If `name` changes, the backend also
  /// renames their known_faces folder and invalidates the cache.
  Future<Map<String, dynamic>> updateFamilyMember({
    required int memberId,
    String? name,
    String? relationship,
    String? phone,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (relationship != null) body['relationship'] = relationship;
      if (phone != null) body['phone'] = phone;

      final response = await http
          .put(
            Uri.parse('$baseUrl/api/family/$memberId'),
            headers: await _getAuthHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to update member',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Permanently delete a family member: DB row, photos, known_faces folder, and cache.
  Future<Map<String, dynamic>> deleteFamilyMember(int memberId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/family/$memberId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to delete member',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Lightweight health check. Returns:
  ///   { 'online': bool, 'latencyMs': int?, 'error': String? }
  /// Online means HTTP 200 within the timeout. No auth required.
  Future<Map<String, dynamic>> pingServer({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(timeout);
      stopwatch.stop();
      if (response.statusCode == 200) {
        return {
          'online': true,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'error': null,
        };
      }
      return {
        'online': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      stopwatch.stop();
      return {'online': false, 'latencyMs': null, 'error': e.toString()};
    }
  }

  /// Build a fully qualified URL for a member's photo path (returned by [getFamilyMembers]).
  /// Returns null if the path is null/empty.
  String? buildPhotoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) return null;
    final cleaned = photoPath.replaceAll('\\', '/');
    if (cleaned.startsWith('http')) return cleaned;
    final prefixed = cleaned.startsWith('/') ? cleaned : '/$cleaned';
    return '$baseUrl$prefixed';
  }

  // Add Trusted Person
  Future<Map<String, dynamic>> addTrustedPerson({
    required String name,
    required String relationship,
    required String phone,
    required String email,
    List<String>? photos,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/trusted'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({
              'name': name,
              'relationship': relationship,
              'phone': phone,
              'email': email.trim().toLowerCase(),
              'photos': photos ?? [],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to add trusted person',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getTrustedPersons() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/trusted'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'trusted_persons': data['trusted_persons'] ?? [],
        };
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to load trusted persons',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> updateTrustedPerson({
    required int personId,
    String? name,
    String? relationship,
    String? phone,
    String? email,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (relationship != null) body['relationship'] = relationship;
      if (phone != null) body['phone'] = phone;
      if (email != null) body['email'] = email.trim().toLowerCase();

      final response = await http
          .put(
            Uri.parse('$baseUrl/api/trusted/$personId'),
            headers: await _getAuthHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to update trusted person',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteTrustedPerson(int personId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/trusted/$personId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to delete trusted person',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get Token
  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  // Face Login
  Future<Map<String, dynamic>> faceLogin(XFile imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/face-login'),
      );

      // Add the image file
      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'face_login.jpg',
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );
      }

      // Send request
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      var response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save token
        await _storage.write(key: 'auth_token', value: data['access_token']);
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Face login failed',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) {
        await unregisterFcmToken(t);
      }
    } catch (_) {}
    await _storage.delete(key: 'auth_token');
  }

  /// Register this device for FCM (call after login).
  Future<void> registerFcmToken(
    String token, {
    String platform = 'android',
  }) async {
    try {
      if (await getToken() == null) {
        return;
      }
      await http
          .post(
            Uri.parse('$baseUrl/api/me/fcm-token'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'token': token, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Remove FCM token from server (call before clearing auth).
  Future<void> unregisterFcmToken(String token) async {
    try {
      if (await getToken() == null) {
        return;
      }
      final uri = Uri.parse(
        '$baseUrl/api/me/fcm-token',
      ).replace(queryParameters: {'token': token});
      await http
          .delete(uri, headers: await _getAuthHeaders())
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // Helper for authenticated headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Change password: verifies current password on server, updates hash.
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/change-password'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? 'Password updated',
        };
      }
      final detail = data['detail'];
      String msg = 'Could not change password';
      if (detail is String) {
        msg = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          msg = first['msg'].toString();
        }
      }
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> verifyPassword(String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/verify-password'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {'success': true};
      }
      final detail = data['detail'];
      String msg = 'Verification failed';
      if (detail is String) {
        msg = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          msg = first['msg'].toString();
        }
      }
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Upload/replace home owner face login photo (base64, optional data URL prefix).
  Future<Map<String, dynamic>> uploadFaceLoginPhoto(String imageBase64) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/me/face-login-photo'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'image_base64': imageBase64}),
          )
          .timeout(const Duration(seconds: 90));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          if (data['user'] != null) 'user': data['user'],
        };
      }
      final detail = data['detail'];
      String msg = 'Could not update Face ID';
      if (detail is String) {
        msg = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          msg = first['msg'].toString();
        }
      }
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Clear enrolled face login photo after password check (home owner only).
  Future<Map<String, dynamic>> clearFaceLogin(String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/me/clear-face-login'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {
          'success': true,
          if (data['user'] != null) 'user': data['user'],
        };
      }
      final detail = data['detail'];
      String msg = 'Could not remove Face ID';
      if (detail is String) {
        msg = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          msg = first['msg'].toString();
        }
      }
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get User Profile
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/me'), headers: await _getAuthHeaders())
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'user': data};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to fetch profile',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get User Options
  Future<Map<String, dynamic>> getOptions() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/options'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final m = Map<String, dynamic>.from(data as Map);
        await applyNetworkFromUserOptions(m);
        return {'success': true, 'options': m};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to fetch options',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// PATCH-style update for `/api/options` (only sends keys you pass).
  Future<Map<String, dynamic>> updateUserOptions(
    Map<String, dynamic> patch,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/options'),
            headers: await _getAuthHeaders(),
            body: jsonEncode(patch),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final m = Map<String, dynamic>.from(data as Map);
        await applyNetworkFromUserOptions(m);
        return {'success': true, 'options': m};
      }
      return {
        'success': false,
        'message': data is Map && data['detail'] != null
            ? data['detail'].toString()
            : 'Failed to update options',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Create Event
  Future<Map<String, dynamic>> createEvent({
    required String title,
    String? description,
    String? eventType,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/events'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({
              'title': title,
              'description': description,
              'event_type': eventType,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'event': data};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to create event',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Error creating event: $e'};
    }
  }

  // Get User Events
  Future<Map<String, dynamic>> getEvents() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/events'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'events': data};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to fetch events',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getStorageSummary() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/storage/summary'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {...data, 'success': true};
      }
      return {
        'success': false,
        'message': data['detail']?.toString() ?? 'Failed to load storage',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteEvent(int eventId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/events/$eventId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data is Map && data['detail'] != null
            ? data['detail'].toString()
            : 'Delete failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Re-run server-side WebM→MP4 for an existing event (fixes old .enc clips on disk).
  Future<Map<String, dynamic>> retranscodeEventVideo(int eventId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/events/$eventId/retranscode-video'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 180));

      final rawBody = response.body;
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
      if (response.statusCode == 200) {
        return {'success': true, 'video_path': data['video_path']};
      }
      return {
        'success': false,
        'message': data['detail'] != null
            ? data['detail'].toString()
            : 'Retranscode failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> purgeOldClips({int? days}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/storage/purge-old'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({if (days != null) 'days': days}),
          )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {...data, 'success': true};
      }
      return {
        'success': false,
        'message': data['detail']?.toString() ?? 'Purge failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteAllRecordings() async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/storage/recordings/all'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {...data, 'success': true};
      }
      return {
        'success': false,
        'message': data['detail']?.toString() ?? 'Delete failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Set Active Monitoring Session
  Future<Map<String, dynamic>> setMonitoringSession(
    int userId,
    String? roomName, {
    String? cameraId,
    String action = 'add',
  }) async {
    try {
      final headers = await _getAuthHeaders();
      headers.remove('Content-Type');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/monitoring/session'),
            headers: headers,
            body: {
              'user_id': userId.toString(),
              if (roomName != null) 'room_name': roomName,
              if (cameraId != null) 'camera_id': cameraId,
              'action': action,
            },
          )
          .timeout(const Duration(seconds: 10));

      return jsonDecode(response.body);
    } catch (e) {
      print('AuthService: Error setting session: $e');
      return {'success': false, 'message': 'Error setting session: $e'};
    }
  }

  // Get Active Cameras
  Future<Map<String, dynamic>> getActiveCameras() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/monitoring/cameras'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'cameras': data['cameras']};
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to fetch cameras',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get Camera Assignment
  Future<Map<String, dynamic>> getCameraAssignment() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/monitoring/assignment'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Save Camera Assignment
  Future<Map<String, dynamic>> saveCameraAssignment({
    required String roomName,
    required String cameraId,
    String? cameraName,
    List<String>? monitorModes,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      headers.remove('Content-Type');

      final body = <String, String>{
        'room_name': roomName,
        'camera_id': cameraId,
        if (cameraName != null) 'camera_name': cameraName,
        if (monitorModes != null)
          'monitor_modes_json': jsonEncode(monitorModes),
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/monitoring/assignment'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// List pets for home owner (`GET /api/pets`).
  Future<Map<String, dynamic>> fetchRegisteredPets() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pets'), headers: await _getAuthHeaders())
          .timeout(const Duration(seconds: 15));

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      body['_status_code'] = response.statusCode;
      return body;
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Remove one DB row and uploads file (`DELETE /api/pets/photos/{id}`).
  Future<Map<String, dynamic>> deletePetPhoto(int photoId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pets/photos/$photoId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      body['_status_code'] = response.statusCode;
      return body;
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Remove pet and all its photos (`DELETE /api/pets/{id}`).
  Future<Map<String, dynamic>> deleteRegisteredPet(int petId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pets/$petId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      body['_status_code'] = response.statusCode;
      return body;
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Delete Camera Assignment (all rows, or one room when [roomName] is set)
  Future<Map<String, dynamic>> deleteCameraAssignment({
    String? roomName,
  }) async {
    try {
      final uri = roomName != null && roomName.isNotEmpty
          ? Uri.parse(
              '$baseUrl/api/monitoring/assignment',
            ).replace(queryParameters: {'room_name': roomName})
          : Uri.parse('$baseUrl/api/monitoring/assignment');
      final response = await http
          .delete(uri, headers: await _getAuthHeaders())
          .timeout(const Duration(seconds: 10));

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get Family Status
  Future<Map<String, dynamic>> getFamilyStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/family/status'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to get status',
        };
      }
    } catch (e) {
      print('AuthService: Error getting family status: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Track Onboarding Skip
  Future<Map<String, dynamic>> trackOnboardingSkip(String stepName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/onboarding/skip'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'step_name': stepName}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Skip tracking failed',
        };
      }
    } catch (e) {
      print('AuthService: Error tracking skip: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Update Selected Modes
  Future<Map<String, dynamic>> updateSelectedModes(List<String> modes) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/options'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({'selected_modes': modes}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['detail'] ?? 'Update failed'};
      }
    } catch (e) {
      print('AuthService: Error updating modes: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Pet Station IoT feeder — poll status for dashboard.
  Future<Map<String, dynamic>> getPetStationStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pet-station/status'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Could not load pet station status',
      };
    } catch (e) {
      print('AuthService: getPetStationStatus error: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Save CAM / main ESP32 IPs; optional [regenerateToken] rotates device token.
  Future<Map<String, dynamic>> savePetStationSettings({
    required String camIp,
    required String mainIp,
    bool regenerateToken = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pet-station/settings'),
            headers: await _getAuthHeaders(),
            body: jsonEncode({
              'cam_ip': camIp.trim(),
              'main_ip': mainIp.trim(),
              'regenerate_token': regenerateToken,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Could not save pet station settings',
      };
    } catch (e) {
      print('AuthService: savePetStationSettings error: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Lost item tracker — list all item+room rows (`GET /api/lost-items`).
  Future<Map<String, dynamic>> getLostItems() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/lost-items'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'items': data['items'] ?? []};
      }
      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['detail'] ?? 'Could not load lost items',
      };
    } catch (e) {
      print('AuthService: getLostItems error: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  /// Single lost-item record (`GET /api/lost-items/{id}`).
  Future<Map<String, dynamic>> getLostItem(int itemId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/lost-items/$itemId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'item': data['item']};
      }
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['detail'] ?? 'Item not found'};
    } catch (e) {
      print('AuthService: getLostItem error: $e');
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
