import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/user_provider.dart';
import '../models/user.dart';
import 'package:provider/provider.dart';
import 'home_page.dart';
import 'login_page.dart';

class FaceLoginPage extends StatefulWidget {
  const FaceLoginPage({super.key});

  @override
  State<FaceLoginPage> createState() => _FaceLoginPageState();
}

class _FaceLoginPageState extends State<FaceLoginPage> {
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;
  XFile? _capturedImage;
  bool _isLoading = false;

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

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      setState(() {
        _capturedImage = image;
      });

      // Auto-submit after capture
      _performFaceLogin();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error capturing image: $e')));
    }
  }

  Future<void> _performFaceLogin() async {
    if (_capturedImage == null) return;

    setState(() {
      _isLoading = true;
    });

    final result = await AuthService().faceLogin(_capturedImage!);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face recognized! Logging in...'),
          backgroundColor: Colors.green,
        ),
      );

      // Update UserProvider
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userData = result['data']['user'];
      userProvider.setUser(User.fromJson(userData));

      // Fetch options
      final optionsRes = await AuthService().getOptions();
      if (optionsRes['success']) {
        userProvider.setOptions(UserOptions.fromJson(optionsRes['options']));
      }

      await PushNotificationService.syncTokenWithBackendIfLoggedIn();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SmartHomePage()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: ${result['message']}'),
          backgroundColor: Colors.red,
        ),
      );

      // Allow retrying
      setState(() {
        _capturedImage = null;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              color: Colors.black,
            ),
          ),

          // White Card
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
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Back Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.chevron_left, size: 28),
                          SizedBox(width: 4),
                          Text(
                            'Back to Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Face Login',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                  const Text(
                    'Position your face in the camera',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Camera View
          Positioned(
            top: 250,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 4),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: ClipOval(
                  child:
                      _cameraController != null &&
                          _cameraController!.value.isInitialized
                      ? CameraPreview(_cameraController!)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          ),

          // Loading Overlay or Capture Button
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : ElevatedButton(
                      onPressed: _captureImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Scan Face',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
