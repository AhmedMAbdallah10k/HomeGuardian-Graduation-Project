import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';

class DoorDetectionService {
  /// Detect door state in an image file
  /// ONLY works if HomeAlone mode is active on the server
  Future<Map<String, dynamic>> detectDoorFromImage(File imageFile) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/api/detect-door'),
      );

      // Add Authorization header
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      // Send request
      var streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}',
          'message': errorData['detail'] ?? errorData['error'] ?? response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
