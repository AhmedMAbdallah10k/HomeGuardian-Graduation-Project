import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/camera_service.dart';

/// Lists dashboard-configured rooms (name, camera, per-room modes) and allows delete.
class ManageRoomsPage extends StatefulWidget {
  const ManageRoomsPage({super.key});

  @override
  State<ManageRoomsPage> createState() => _ManageRoomsPageState();
}

class _ManageRoomsPageState extends State<ManageRoomsPage> {
  final AuthService _auth = AuthService();

  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;
  String? _deletingRoom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _auth.getCameraAssignment();
    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ??
            res['error']?.toString() ??
            'Could not load rooms';
      });
      return;
    }

    final list = <Map<String, dynamic>>[];
    if (res['assignments'] != null && (res['assignments'] as List).isNotEmpty) {
      for (final raw in res['assignments'] as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final name = m['room_name']?.toString().trim() ?? '';
        if (name.isNotEmpty) list.add(m);
      }
    } else if (res['assignment'] != null) {
      final m = Map<String, dynamic>.from(res['assignment'] as Map);
      final name = m['room_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) list.add(m);
    }

    setState(() {
      _rooms = list;
      _loading = false;
    });
  }

  String _modeLabels(dynamic raw) {
    final ids = monitorModesFromAssignmentField(raw);
    if (ids.isEmpty) {
      return 'Default only (fire, fridge, face, food, pests, lost items)';
    }
    final labels = ids.map((id) {
      for (final m in kOptionalMonitorModes) {
        if (m['id'] == id) return m['label']!;
      }
      return id;
    }).toList();
    return labels.join(' · ');
  }

  String _cameraLabel(Map<String, dynamic> room) {
    final name = room['camera_name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final id = room['camera_id']?.toString().trim();
    if (id != null && id.isNotEmpty) return 'Camera $id';
    return 'No camera assigned';
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(String roomName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete room?',
          style: TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Remove "$roomName" from monitoring? '
          'You can add it again from Monitor Home on the dashboard.',
          style: const TextStyle(fontFamily: 'Comfortaa'),
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

    if (ok != true || !mounted) return;

    setState(() => _deletingRoom = roomName);
    final res = await _auth.deleteCameraAssignment(roomName: roomName);
    if (!mounted) return;
    setState(() => _deletingRoom = null);

    if (res['success'] == true) {
      _toast('Removed $roomName');
      await _load();
    } else {
      _toast(
        res['message']?.toString() ??
            res['error']?.toString() ??
            'Could not delete room',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(60)),
      ),
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.center,
            child: Text(
              'Manage Rooms',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'Comfortaa',
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5F4),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: _load,
              color: Colors.black,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Comfortaa',
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }

    if (_rooms.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        children: [
          Icon(Icons.meeting_room_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          const Text(
            'No rooms yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFamily: 'Comfortaa',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add rooms from Monitor Home on your dashboard. '
            'They will appear here with their names and modes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.grey.shade600,
              fontFamily: 'Comfortaa',
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      itemCount: _rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final roomName = room['room_name']?.toString() ?? 'Room';
        final modes = room['monitor_modes'] ?? room['monitorModes'];
        final isDeleting = _deletingRoom == roomName;

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.meeting_room, color: Colors.black87),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _cameraLabel(room),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Modes',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _modeLabels(modes),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ],
                ),
              ),
              isDeleting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Delete room',
                      onPressed: () => _confirmDelete(roomName),
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                    ),
            ],
          ),
        );
      },
    );
  }
}
