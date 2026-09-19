import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/auth_service.dart';
import '../services/event_notifier.dart';
import '../services/websocket_service.dart';
import '../utils/recording_playback_codec.dart';
import '../services/user_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/video_helper_stub.dart'
    if (dart.library.html) '../utils/video_helper_web.dart';

class EventPage extends StatefulWidget {
  final Map<String, dynamic>? event;
  const EventPage({super.key, this.event});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isWaitingForRecording = false;
  bool _attemptedRetranscode = false;
  final WebSocketService _webSocketService = WebSocketService();
  StreamSubscription? _wsSubscription;
  String? _currentVideoPath;
  String? _tempVideoUrl;
  File? _tempVideoFile;
  String? _videoError;
  bool _actionBusy = false;

  int? get _eventId {
    final raw = widget.event?['id'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  bool get _hasClip =>
      _currentVideoPath != null &&
      _currentVideoPath!.trim().isNotEmpty &&
      !_isWaitingForRecording;

  bool get _canDelete {
    final user = context.read<UserProvider>().user;
    return user != null && !user.isFamilyMember;
  }

  @override
  void initState() {
    super.initState();
    _currentVideoPath = widget.event?['video_path'] ?? widget.event?['video_url'];
    _isWaitingForRecording = _currentVideoPath == null &&
        (widget.event?['recording_expected'] == true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureWebSocket());
    _initializeVideo();
    _setupWebSocket();
  }

  Future<void> _ensureWebSocket() async {
    if (!mounted) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    await _webSocketService.connect(userId: user.effectiveOwnerId);
  }

  static bool _recordingReadyMatches(Map<String, dynamic> message, dynamic eventId) {
    final mid = message['event_id'];
    if (mid == null || eventId == null) return false;
    return mid.toString() == eventId.toString();
  }

  void _setupWebSocket() {
    _wsSubscription = _webSocketService.messageStream.listen((message) {
      if (message['type'] == 'recording_ready' &&
          _recordingReadyMatches(message, widget.event?['id'])) {
        if (mounted) {
          setState(() {
            _isWaitingForRecording = false;
            _currentVideoPath = message['video_url']?.toString();
            _videoError = null;
            _attemptedRetranscode = false;
            _initializeVideo();
          });
        }
      }
    });
  }

  Future<void> _initializeVideo() async {
    if (_currentVideoPath == null) return;

    setState(() {
      _videoError = null;
      _isInitialized = false;
    });
    if (kIsWeb && _tempVideoUrl != null) {
      revokeWebVideoUrl(_tempVideoUrl!);
      _tempVideoUrl = null;
    }
    await _controller?.dispose();
    _controller = null;

    try {
      final fullUrl = _currentVideoPath!.startsWith('http')
          ? _currentVideoPath!
          : '${AuthService.baseUrl}$_currentVideoPath';

      final auth = AuthService();
      final headers = <String, String>{};
      final token = await auth.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(Uri.parse(fullUrl), headers: headers)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        throw Exception(
          'Download failed (HTTP ${response.statusCode}). '
          'Check server URL and Wi‑Fi.',
        );
      }

      final raw = Uint8List.fromList(response.bodyBytes);
      if (raw.isEmpty) {
        throw Exception(
          'Downloaded clip is empty. Re-record from the laptop or check the server.',
        );
      }
      final Uint8List playable = RecordingPlaybackCodec.playableFromDownloadBody(raw);
      if (playable.isEmpty) {
        throw Exception('Clip has no playable data after processing.');
      }
      if (!RecordingPlaybackCodec.isLikelyMp4(playable) &&
          !RecordingPlaybackCodec.isLikelyWebmOrMatroska(playable)) {
        throw Exception(
          'Recording is not playable after download. '
          'If clips were encrypted on the server, check that RECORDINGS_AES_KEY matches the app key '
          '(or leave RECORDINGS_AES_KEY unset to use the default).',
        );
      }

      if (kIsWeb) {
        final mime = RecordingPlaybackCodec.mimeTypeForPlayable(playable);
        _tempVideoUrl = createWebVideoUrl(playable, mime);
        _controller = VideoPlayerController.networkUrl(Uri.parse(_tempVideoUrl!));
      } else {
        final tempDir = await getTemporaryDirectory();
        final ext = RecordingPlaybackCodec.extensionForPlayable(playable);
        _tempVideoFile =
            File('${tempDir.path}/temp_video_${widget.event?['id']}.$ext');
        await _tempVideoFile!.writeAsBytes(playable);
        _controller = VideoPlayerController.file(
          _tempVideoFile!,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _videoError = null;
        });
        _controller?.play();
        _controller?.setLooping(true);
      }
    } catch (e) {
      final errStr = e.toString();
      final idRaw = widget.event?['id'];
      final idNum = idRaw == null ? null : int.tryParse(idRaw.toString());
      if (!_attemptedRetranscode &&
          idNum != null &&
          (errStr.contains('ExoPlaybackException') ||
              errStr.contains('Video player had error') ||
              errStr.contains('MEDIA_ERR_SRC_NOT_SUPPORTED') ||
              errStr.contains('DEMUXER_ERROR'))) {
        _attemptedRetranscode = true;
        final r = await AuthService().retranscodeEventVideo(idNum);
        if (r['success'] == true &&
            r['video_path'] != null &&
            mounted) {
          setState(() {
            _currentVideoPath = r['video_path'].toString();
            _videoError = null;
          });
          await _initializeVideo();
          return;
        }
        if (mounted) {
          setState(() {
            _isInitialized = false;
            _videoError =
                '${r['message'] ?? r}\nOriginal: $errStr';
          });
        }
        return;
      }
      if (mounted) {
        var message = errStr;
        if (message.contains('ExoPlaybackException') &&
            message.contains('Source error')) {
          message =
              '$message\n\n'
              'This usually means the phone cannot decode the file (often VP9 WebM). '
              'The app tried to rebuild the clip as MP4 on the server. If it still fails, '
              'open server logs: you should see [STARTUP] ffmpeg: ... when the API starts. '
              'Set FFMPEG_PATH in server/.env to ffmpeg.exe, restart the server, open this '
              'event again (or record a new clip).';
        }
        setState(() {
          _isInitialized = false;
          _videoError = message;
        });
      }
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _controller?.dispose();
    
    // Clean up temporary resources
    if (kIsWeb && _tempVideoUrl != null) {
      revokeWebVideoUrl(_tempVideoUrl!);
    } else if (_tempVideoFile != null) {
      try { _tempVideoFile!.delete(); } catch (_) {}
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    final screenSize = MediaQuery.sizeOf(context);
    final hPad = screenSize.width < 600 ? 16.0 : 24.0;
    final vPad = screenSize.width < 600 ? 16.0 : 24.0;
    final useSideBySideCards = screenSize.width >= 640;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.event?['title'] ?? 'Event Detail',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Player Section
            LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final videoHeight = (maxW * 9 / 16).clamp(200.0, 480.0);
                return Container(
                  width: double.infinity,
                  height: videoHeight,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      alignment: Alignment.center,
                      fit: StackFit.expand,
                      children: [
                    if (_isInitialized)
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    else if (_videoError != null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade300, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Could not play this clip',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _videoError!,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else if (_currentVideoPath != null)
                      const CircularProgressIndicator(color: Colors.white)
                    else if (_isWaitingForRecording)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.greenAccent),
                          const SizedBox(height: 24),
                          Text(
                            "Capturing video clip...",
                            style: TextStyle(color: Colors.grey[400], fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "This will take about 7 seconds",
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      )
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_off, color: Colors.grey[700], size: 80),
                          const SizedBox(height: 16),
                          Text(
                            "No recording available",
                            style: TextStyle(color: Colors.grey[600], fontSize: 18),
                          ),
                        ],
                      ),
                    
                    // Controls Overlay
                    if (_isInitialized)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                                  });
                                },
                              ),
                              Expanded(
                                child: VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.greenAccent,
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                _formatDuration(_controller!.value.position),
                                style: const TextStyle(color: Colors.white),
                              ),
                              const Text(" / ", style: TextStyle(color: Colors.white54)),
                              Text(
                                _formatDuration(_controller!.value.duration),
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                    ),
                  ),
                );
              },
            ),

            SizedBox(height: screenSize.width < 600 ? 20 : 24),

            // Event info + actions: stack on phones, side‑by‑side on wide screens
            if (useSideBySideCards)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _eventInfoCard(cardColor, textColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _actionsCard(cardColor, textColor),
                  ),
                ],
              )
            else ...[
              _eventInfoCard(cardColor, textColor),
              const SizedBox(height: 16),
              _actionsCard(cardColor, textColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventInfoCard(Color cardColor, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event information',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            Icons.room,
            'Location',
            widget.event?['room_name']?.toString() ?? 'Unknown',
            textColor,
          ),
          const Divider(height: 28),
          _buildInfoRow(
            Icons.access_time,
            'Time',
            _formatTimestamp(widget.event?['timestamp']?.toString()),
            textColor,
          ),
          const Divider(height: 28),
          _buildInfoRow(
            Icons.info_outline,
            'Details',
            widget.event?['description']?.toString() ?? 'No details provided',
            textColor,
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(Color cardColor, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButton(
            Icons.download,
            'Download clip',
            Colors.blue,
            _hasClip && !_actionBusy ? _downloadClip : null,
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            Icons.share,
            'Share event',
            Colors.green,
            _hasClip && !_actionBusy ? _shareEvent : null,
          ),
          if (_canDelete) ...[
            const SizedBox(height: 12),
            _buildActionButton(
              Icons.delete_outline,
              'Delete event',
              Colors.redAccent,
              !_actionBusy ? _confirmDeleteEvent : null,
            ),
          ],
          if (_actionBusy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return "Unknown";
    try {
      final dt = DateTime.parse(timestamp);
      return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: Colors.grey[500], size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 4),
              SelectableText(
                value,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _exportBaseName() {
    final id = widget.event?['id']?.toString() ?? 'clip';
    final title = (widget.event?['title']?.toString() ?? 'event')
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return 'homeguardian_${title}_$id';
  }

  String _shareText() {
    final title = widget.event?['title']?.toString() ?? 'HomeGuardian event';
    final room = widget.event?['room_name']?.toString();
    final time = _formatTimestamp(widget.event?['timestamp']?.toString());
    final parts = [title];
    if (room != null && room.isNotEmpty) parts.add(room);
    parts.add(time);
    return parts.join(' — ');
  }

  Future<Uint8List?> _fetchPlayableBytes() async {
    if (_tempVideoFile != null && await _tempVideoFile!.exists()) {
      return _tempVideoFile!.readAsBytes();
    }
    if (_currentVideoPath == null) return null;

    final fullUrl = _currentVideoPath!.startsWith('http')
        ? _currentVideoPath!
        : '${AuthService.baseUrl}$_currentVideoPath';

    final auth = AuthService();
    final headers = <String, String>{};
    final token = await auth.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http
        .get(Uri.parse(fullUrl), headers: headers)
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('Download failed (HTTP ${response.statusCode})');
    }

    final raw = Uint8List.fromList(response.bodyBytes);
    if (raw.isEmpty) {
      throw Exception('Recording file is empty');
    }
    final playable = RecordingPlaybackCodec.playableFromDownloadBody(raw);
    if (playable.isEmpty) {
      throw Exception('Recording has no playable data');
    }
    return playable;
  }

  Future<void> _downloadClip() async {
    if (!_hasClip || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final playable = await _fetchPlayableBytes();
      if (playable == null) {
        throw Exception('No recording available');
      }
      final ext = RecordingPlaybackCodec.extensionForPlayable(playable);
      final mime = RecordingPlaybackCodec.mimeTypeForPlayable(playable);
      final filename = '${_exportBaseName()}.$ext';

      if (kIsWeb) {
        downloadFileOnWeb(playable, filename, mime);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download started')),
          );
        }
        return;
      }

      Directory? dir = await getDownloadsDirectory();
      dir ??= await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/$filename');
      await out.writeAsBytes(playable);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${out.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _shareEvent() async {
    if (!_hasClip || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final playable = await _fetchPlayableBytes();
      if (playable == null) {
        throw Exception('No recording available');
      }
      final ext = RecordingPlaybackCodec.extensionForPlayable(playable);
      final filename = '${_exportBaseName()}.$ext';
      final text = _shareText();

      if (kIsWeb) {
        final mime = RecordingPlaybackCodec.mimeTypeForPlayable(playable);
        downloadFileOnWeb(playable, filename, mime);
        await Share.share(text);
        return;
      }

      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/$filename');
      await out.writeAsBytes(playable);
      await Share.shareXFiles([XFile(out.path)], text: text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _confirmDeleteEvent() async {
    if (_actionBusy) return;
    final id = _eventId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text(
          'This removes the event and its recording from your account. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      final result = await AuthService().deleteEvent(id);
      if (!mounted) return;
      if (result['success'] == true) {
        context.read<EventNotifier>().removeEventById(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event deleted')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Delete failed'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }
}
