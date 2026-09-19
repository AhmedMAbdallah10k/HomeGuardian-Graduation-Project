import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import 'event_page.dart';

enum _TypeFilter { all, emergency, security }

/// Full timeline of owner-scoped security events (same data as `/api/events`).
class ViewActivityPage extends StatefulWidget {
  const ViewActivityPage({super.key});

  @override
  State<ViewActivityPage> createState() => _ViewActivityPageState();
}

class _ViewActivityPageState extends State<ViewActivityPage> {
  final AuthService _auth = AuthService();

  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  _TypeFilter _typeFilter = _TypeFilter.all;
  String? _roomFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final result = await _auth.getEvents();

    if (!mounted) return;

    if (result['success'] == true) {
      final raw = result['events'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      list.sort((a, b) {
        final da = _parseTime(a['timestamp']);
        final db = _parseTime(b['timestamp']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      setState(() {
        _events = list;
        _loading = false;
      });
    } else {
      setState(() {
        _events = [];
        _loading = false;
        _error = result['message']?.toString() ?? 'Failed to load activity';
      });
    }
  }

  DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  List<String> get _roomNames {
    final s = <String>{};
    for (final e in _events) {
      final r = e['room_name']?.toString().trim();
      if (r != null && r.isNotEmpty) s.add(r);
    }
    final list = s.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _visible {
    var list = List<Map<String, dynamic>>.from(_events);
    switch (_typeFilter) {
      case _TypeFilter.emergency:
        list = list
            .where(
              (e) =>
                  (e['event_type']?.toString().toLowerCase() ?? '') ==
                  'emergency',
            )
            .toList();
      case _TypeFilter.security:
        list = list
            .where(
              (e) =>
                  (e['event_type']?.toString().toLowerCase() ?? '') ==
                  'security',
            )
            .toList();
      case _TypeFilter.all:
        break;
    }
    if (_roomFilter != null && _roomFilter!.isNotEmpty) {
      list = list
          .where((e) => (e['room_name']?.toString() ?? '') == _roomFilter)
          .toList();
    }
    return list;
  }

  String _formatSubtitle(DateTime? when) {
    if (when == null) return 'Unknown time';
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat.yMMMd().add_jm().format(when);
  }

  (IconData, Color) _iconFor(Map<String, dynamic> e) {
    final t = (e['event_type'] ?? '').toString().toLowerCase();
    if (t == 'emergency') {
      return (Icons.emergency_outlined, Colors.red.shade700);
    }
    if (t == 'security') {
      return (Icons.shield_outlined, Colors.deepOrange.shade700);
    }
    return (Icons.notifications_none_outlined, Colors.black87);
  }

  Map<String, dynamic> _eventForDetail(Map<String, dynamic> e) {
    final copy = Map<String, dynamic>.from(e);
    final vu = e['video_url'] ?? e['video_path'];
    if (vu != null) {
      copy['video_path'] = vu;
      copy['video_url'] = vu;
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _roomNames;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 90,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(60),
                ),
              ),
              child: Stack(
                children: [
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'View Activity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
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
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: _typeFilter == _TypeFilter.all,
                              onSelected: (_) => setState(
                                () => _typeFilter = _TypeFilter.all,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Emergency'),
                              selected: _typeFilter == _TypeFilter.emergency,
                              onSelected: (_) => setState(
                                () => _typeFilter = _TypeFilter.emergency,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Security'),
                              selected: _typeFilter == _TypeFilter.security,
                              onSelected: (_) => setState(
                                () => _typeFilter = _TypeFilter.security,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (rooms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('All rooms'),
                                selected: _roomFilter == null,
                                onSelected: (_) =>
                                    setState(() => _roomFilter = null),
                              ),
                              ...rooms.map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: FilterChip(
                                    label: Text(r),
                                    selected: _roomFilter == r,
                                    onSelected: (selected) => setState(
                                      () => _roomFilter = selected ? r : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _loading
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              )
                            : _visible.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(32),
                                    children: [
                                      Icon(
                                        Icons.event_note,
                                        size: 56,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _events.isEmpty
                                            ? 'No activity yet.'
                                            : 'No activity matches these filters.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade700,
                                          fontFamily: 'Comfortaa',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Pull down to refresh.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontFamily: 'Comfortaa',
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      16,
                                      20,
                                      24,
                                    ),
                                    itemCount: _visible.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final e = _visible[index];
                                      final ts = _parseTime(e['timestamp']);
                                      final (icon, color) = _iconFor(e);
                                      final title =
                                          e['title']?.toString() ?? 'Event';
                                      final room =
                                          e['room_name']?.toString() ?? '';
                                      final hasVideo =
                                          (e['video_url'] != null &&
                                              e['video_url']
                                                  .toString()
                                                  .isNotEmpty) ||
                                          (e['video_path'] != null &&
                                              e['video_path']
                                                  .toString()
                                                  .isNotEmpty);

                                      return Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          16,
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    EventPage(
                                                  event: _eventForDetail(e),
                                                ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(icon, color: color),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFamily:
                                                              'Comfortaa',
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                      if (room.isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          room,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors
                                                                .grey.shade700,
                                                            fontFamily:
                                                                'Comfortaa',
                                                          ),
                                                        ),
                                                      ],
                                                      if ((e['description'] ??
                                                                  '')
                                                              .toString()
                                                              .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Text(
                                                          e['description']
                                                              .toString(),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey.shade600,
                                                            fontFamily:
                                                                'Comfortaa',
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      _formatSubtitle(ts),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade600,
                                                        fontFamily: 'Comfortaa',
                                                      ),
                                                    ),
                                                    if (hasVideo) ...[
                                                      const SizedBox(height: 6),
                                                      Icon(
                                                        Icons.videocam_outlined,
                                                        size: 18,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
