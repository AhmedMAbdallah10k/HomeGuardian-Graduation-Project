import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'auth_service.dart';

class FireDetectionService {

  /// Detect fire/smoke in an image file
  ///
  /// [imageFile] - The image file to analyze
  /// Returns a Map with detection results
  Future<Map<String, dynamic>> detectFireFromImage(
    File imageFile, {
    Map<String, String>? headers,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/api/detect-fire'),
      );

      // Add headers if provided
      if (headers != null) {
        request.headers.addAll(headers);
      }

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      // Send request
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}',
          'message': response.body,
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Detect fire/smoke in a video file (sends first frame)
  ///
  /// [videoFile] - The video file to analyze
  /// Returns a Map with detection results
  Future<Map<String, dynamic>> detectFireFromVideo(File videoFile) async {
    // For now, we'll extract the first frame and send it as an image
    // In a more advanced implementation, you could process multiple frames
    return detectFireFromImage(videoFile);
  }
}
