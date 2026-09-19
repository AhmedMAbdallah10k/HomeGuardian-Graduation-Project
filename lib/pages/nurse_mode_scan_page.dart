import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import 'nurse_mode_page.dart';

class NurseModeScanPage extends StatefulWidget {
  const NurseModeScanPage({Key? key}) : super(key: key);

  @override
  State<NurseModeScanPage> createState() => _NurseModeScanPageState();
}

class _NurseModeScanPageState extends State<NurseModeScanPage> {
  CameraController? _cameraController;
  CameraDescription? _selectedCamera;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await CameraService().initialize();
      if (!mounted) return;
      setState(() {
        _cameraController = CameraService().controller;
      });
    } catch (e) {
      debugPrint('NurseModeScanPage: Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Release the camera when leaving the scan page
    CameraService().setActivePreview(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              color: Colors.black,
            ),
          ),
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
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const NurseModePage(),
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
                    const SizedBox(height: 22, width: 52),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 3),
                      child: const Text(
                        'Scan face',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 230,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
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
                      child: CameraPreview(_cameraController!),
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
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/face-id.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.person_outline,
                      size: 48,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please open your eyes',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                      fontFamily: 'Comfortaa',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 320,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const NurseModePage(),
                            ),
                          );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Take Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
