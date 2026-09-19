import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'signup_page.dart';
import 'register_family_members_page.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../models/user.dart';

/// Scan face page: central framed area and four small camera previews at the corners.
class ScanFacePage extends StatefulWidget {
  final String? name;
  final String? email;
  final String? password;
  final String? phone;

  const ScanFacePage({
    super.key,
    this.name,
    this.email,
    this.password,
    this.phone,
  });

  @override
  State<ScanFacePage> createState() => _ScanFacePageState();
}

class _ScanFacePageState extends State<ScanFacePage> {
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  List<Uint8List> _capturedPhotos = [];

  // Each photo targets a specific angle to maximize recognition accuracy
  static const int _requiredPhotos = 5;
  static const List<String> _angleLabels = [
    'Front (look straight ahead)',
    'Turn slightly LEFT',
    'Turn slightly RIGHT',
    'Tilt head UP slightly',
    'Tilt head DOWN slightly',
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available');
      }
      
      // prefer front camera, fallback to first available
      _selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint("Camera error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (_capturedPhotos.length < _requiredPhotos) {
      // If camera is ready, try to capture the next photo
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          final XFile file = await _cameraController!.takePicture();
          final bytes = await file.readAsBytes();
          setState(() {
            _capturedPhotos.add(bytes);
          });
          
          if (_capturedPhotos.length < _requiredPhotos) {
            final nextAngle = _angleLabels[_capturedPhotos.length];
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Photo ${_capturedPhotos.length}/$_requiredPhotos captured! Next: $nextAngle'),
                duration: const Duration(seconds: 2),
              ),
            );
            return; // Don't signup yet, need more photos
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error capturing photo: $e')),
          );
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not ready. Please wait.')),
        );
        return;
      }
    }

    // If we have all required photos, proceed with signup
    setState(() => _isLoading = true);

    try {
      List<String> base64Photos = _capturedPhotos.map((Uint8List bytes) => base64Encode(bytes)).toList();

      // Call the real signup API
      final result = await _authService.signup(
        name: widget.name ?? '',
        email: widget.email ?? '',
        password: widget.password ?? '',
        phone: widget.phone ?? '',
        profileImages: base64Photos,
        isDashboard: false,
      );

      if (result['success'] == true) {
        if (!mounted) return;

        // Update UserProvider
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        if (result['user'] != null) {
          userProvider.setUser(User.fromJson(result['user']));
        }

        await PushNotificationService.syncTokenWithBackendIfLoggedIn();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const RegisterFamilyMembersPage(),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: ${result['message']}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // White card with text
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => const SignUpPage(),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.chevron_left, size: 28),
                          SizedBox(width: 4),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Scan face',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Face recognition ensures it\'s really you.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_requiredPhotos, (index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: index < _capturedPhotos.length ? Colors.green : Colors.grey[300]!,
                                width: 2,
                              ),
                              image: index < _capturedPhotos.length
                                  ? DecorationImage(
                                      image: MemoryImage(_capturedPhotos[index]),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: index >= _capturedPhotos.length
                                ? Icon(Icons.camera_alt, color: Colors.grey[300], size: 18)
                                : null,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _capturedPhotos.length < _requiredPhotos 
                            ? 'Next pose: ${_angleLabels[_capturedPhotos.length]}'
                            : 'All $_requiredPhotos angles captured!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _capturedPhotos.length < _requiredPhotos ? Colors.black87 : Colors.green,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        _capturedPhotos.length < _requiredPhotos
                            ? '${_capturedPhotos.length}/$_requiredPhotos photos — more angles = better recognition'
                            : 'Tap Sign Up to continue',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Camera frame
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      _cameraController != null &&
                          _cameraController!.value.isInitialized
                      ? CameraPreview(_cameraController!)
                      : const Center(child: Text('Initializing camera...')),
                ),
              ),
            ),
          ),

          // Action button
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _capturedPhotos.length < _requiredPhotos 
                              ? 'Capture Photo ${_capturedPhotos.length + 1}/$_requiredPhotos' 
                              : 'Sign Up',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading ? null : () async {
                    // Skip face scan and proceed with signup without profile images
                    setState(() => _isLoading = true);
                    try {
                      final result = await _authService.signup(
                        name: widget.name ?? '',
                        email: widget.email ?? '',
                        password: widget.password ?? '',
                        phone: widget.phone ?? '',
                        profileImages: [],
                        isDashboard: false,
                      );
                      
                      if (result['success']) {
                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const RegisterFamilyMembersPage(),
                          ),
                        );
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Signup failed: ${result['message']}')),
                        );
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                      fontFamily: 'Comfortaa',
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
