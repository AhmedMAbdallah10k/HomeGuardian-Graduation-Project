import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';

class CameraMonitorWidget extends StatefulWidget {
  final String roomName;
  final int userId;
  final bool isLive;
  final bool isFullScreen;

  const CameraMonitorWidget({
    super.key,
    required this.roomName,
    required this.userId,
    this.isLive = false,
    this.isFullScreen = false,
  });

  @override
  State<CameraMonitorWidget> createState() => _CameraMonitorWidgetState();
}

class _CameraMonitorWidgetState extends State<CameraMonitorWidget> {
  final CameraService _cameraService = CameraService();

  @override
  void initState() {
    super.initState();
    if (widget.isLive) {
      _startMonitoring();
    }
  }

  @override
  void didUpdateWidget(CameraMonitorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && oldWidget.roomName != widget.roomName) {
      setState(() {});
      return;
    }
    if (widget.isLive && !oldWidget.isLive) {
      _startMonitoring();
    } else if (!widget.isLive && oldWidget.isLive) {
      _stopMonitoring();
    }
  }

  Future<void> _startMonitoring() async {
    debugPrint('CameraMonitorWidget: _startMonitoring for ${widget.roomName}');
    try {
      // Increased timeout to 15 seconds to account for staggered initialization (3s delay)
      // and multiple camera setup time.
      await _cameraService.initialize().timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('CameraMonitorWidget: Initialization timed out for ${widget.roomName}');
      });
      
      if (mounted) {
        debugPrint('CameraMonitorWidget: Initialization attempt finished for ${widget.roomName}');
        _cameraService.startMonitoring(widget.userId, widget.roomName);
        setState(() {});
      }
    } catch (e) {
      debugPrint('CameraMonitorWidget: Error in _startMonitoring for ${widget.roomName}: $e');
      if (mounted) {
        // Retry after a longer delay if it's a transient error
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && widget.isLive) _startMonitoring();
        });
      }
    }
  }

  void _onActivePreviewChanged() {
    if (mounted) {
      final isInit = _cameraService.isInitializedForRoom(widget.roomName);
      if (widget.isLive && !isInit && !_cameraService.isSwitching) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && !_cameraService.isInitializedForRoom(widget.roomName) && widget.isLive) {
            _startMonitoring();
          }
        });
      }
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cameraService.removeListener(_onActivePreviewChanged);
    _cameraService.addListener(_onActivePreviewChanged);
  }

  void _stopMonitoring() {
    if (_cameraService.isRoomPreviewActive(widget.roomName)) {
      _cameraService.togglePreview(widget.roomName);
    }
    _cameraService.stopMonitoring(widget.roomName);
  }

  @override
  void dispose() {
    _cameraService.removeListener(_onActivePreviewChanged);
    _stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLive) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white24, size: 48),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _cameraService,
      builder: (context, child) {
        final isInit = _cameraService.isInitializedForRoom(widget.roomName);
        final controller = _cameraService.getControllerForRoom(widget.roomName);
        final lastFrame = _cameraService.getLastFrameForRoom(widget.roomName);

        if (!isInit || controller == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '${_cameraService.statusMessage} (${widget.roomName})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _cameraService.initialize(force: true),
                  child: const Text('Retry Hardware Init', style: TextStyle(color: Colors.blue, fontSize: 10)),
                ),
              ],
            ),
          );
        }

        final bool isMaster = _cameraService.isRoomPreviewActive(widget.roomName);
        final bool isSwitching = _cameraService.isSwitching;
        
        // Use Image.memory as a primary source if CameraPreview is flickering or black
        // This ensures the user ALWAYS sees something.
        return Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Show last frame as a background/placeholder to prevent black screens
              if (lastFrame != null)
                Image.memory(
                  lastFrame,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),

              // Overlay the Live Preview only if it's the master
              if (isMaster && !isSwitching)
                Center(
                  child: AspectRatio(
                    key: ValueKey('camera_preview_${widget.roomName}_${controller.hashCode}'), 
                    aspectRatio: controller.value.aspectRatio,
                    child: RepaintBoundary(
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              
              if (lastFrame == null && (!isMaster || isSwitching))
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off, color: Colors.white24, size: 48),
                      SizedBox(height: 8),
                      Text('Starting feed...', style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                ),
            
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: isMaster ? Colors.green : Colors.orange, size: 8),
                    const SizedBox(width: 4),
                    Text(
                      isMaster ? 'Live: ${widget.roomName}' : 'Monitoring: ${widget.roomName}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            
            Positioned(
              bottom: 8,
              right: 8,
              child: InkWell(
                onTap: () => _cameraService.togglePreview(widget.roomName),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isMaster ? Icons.videocam : Icons.refresh, 
                    color: isMaster ? Colors.green : Colors.white, 
                    size: 16
                  ),
                ),
              ),
            ),
            ],
          ),
        );
      },
    );
  }
}
