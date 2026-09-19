import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'signup_page.dart';
import 'register_family_members_page.dart';

/// Register device page: QR code scanner with same layout as scan face page.
class RegisterDevicePage extends StatefulWidget {
  const RegisterDevicePage({super.key});

  @override
  State<RegisterDevicePage> createState() => _RegisterDevicePageState();
}

class _RegisterDevicePageState extends State<RegisterDevicePage> {
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      // prefer back camera for QR scanning, fallback to first available
      _selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.isNotEmpty
            ? cameras.first
            : throw Exception('No camera available'),
      );

      _cameraController = CameraController(
        _selectedCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      // ignore errors for now — UI shows placeholders until camera is ready
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
          // Dark top background (like login/signup pages)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              color: Colors.black,
            ),
          ),

          // White content card positioned lower with a large top-left radius
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Back link (matches SignUp style)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const SignUpPage(),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left,
                            color: Colors.black,
                            size: 28,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Move Scan Device a little bit to bottom and right
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 3),
                      child: const Text(
                        'Scan Device',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),

                    // (camera moved to bottom using a Positioned widget below)
                  ],
                ),
              ),
            ),
          ),

          // QR scanner box pinned near the bottom (to bottom)
          Positioned(
            bottom: 230,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                // to bottom
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black87, width: 6),
                ),
                child: Builder(
                  builder: (context) {
                    if (_cameraController != null &&
                        _cameraController!.value.isInitialized) {
                      final previewSize = _cameraController!.value.previewSize;
                      final aspect =
                          (previewSize != null && previewSize.height != 0)
                          ? previewSize.width / previewSize.height
                          : 1.0;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: 380 * aspect,
                            height: 380,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      );
                    }

                    return Stack(
                      children: [
                        const SizedBox.expand(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: const Text(
                                'Waiting for camera...',
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontFamily: 'Comfortaa',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // QR code instruction text and icon at bottom
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const RegisterFamilyMembersPage(),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/qr-code.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.qr_code_2,
                        size: 48,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan the QR of the Smart Hub',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontFamily: 'Comfortaa',
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top header with the 3d_home image overlapping the card (same pattern as signup/login)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8.0,
                      bottom: 8.0,
                      left: 12,
                      right: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          '9:41',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                        SizedBox.shrink(),
                      ],
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(
                      offset: const Offset(80, -100),
                      child: SizedBox(
                        height: 300,
                        width: 300,
                        child: Image.asset(
                          'assets/images/3d_home.png',
                          height: 200,
                          width: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
