import 'package:flutter/material.dart';
import '../widgets/camera_monitor_widget.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../services/camera_service.dart';

class FullScreenCameraPage extends StatefulWidget {
  final String roomName;

  const FullScreenCameraPage({super.key, required this.roomName});

  @override
  State<FullScreenCameraPage> createState() => _FullScreenCameraPageState();
}

class _FullScreenCameraPageState extends State<FullScreenCameraPage> {
  @override
  void initState() {
    super.initState();
    // Claim the live preview for this room immediately
    final cameraService = CameraService();
    cameraService.setActivePreview(widget.roomName, isFullScreen: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          debugPrint('FullScreenCameraPage: Returning to grid');
          // Home page will automatically re-claim master on rebuild
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Camera feed integrated
            Center(
              child: Consumer<UserProvider>(
                builder: (context, userProvider, _) {
                  final userId = userProvider.user?.id ?? 0;
                  if (userId == 0) {
                    return const Center(child: Text('Please login', style: TextStyle(color: Colors.white)));
                  }
                // We use a unique key per room to ensure a fresh widget
                return CameraMonitorWidget(
                  key: ValueKey('fullscreen_${widget.roomName}'),
                  roomName: widget.roomName,
                  userId: userId,
                  isLive: true,
                  isFullScreen: true,
                );
                },
              ),
            ),
          
          // Back button - using a standard IconButton for better reliability
          Positioned(
            top: 40,
            left: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  debugPrint('FullScreenCameraPage: Back button pressed');
                  Navigator.of(context).pop();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Back', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),

            // Live indicator
            const Positioned(
              top: 40,
              right: 20, 
              child: Row(
                children: [
                  Icon(Icons.circle, color: Colors.red, size: 12),
                  SizedBox(width: 8),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
