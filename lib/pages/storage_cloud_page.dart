import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../utils/recording_playback_codec.dart';

/// Local recordings & uploads on your HomeGuardian server (no third-party cloud).
class StorageCloudPage extends StatefulWidget {
  const StorageCloudPage({super.key});

  @override
  State<StorageCloudPage> createState() => _StorageCloudPageState();
}

class _StorageCloudPageState extends State<StorageCloudPage> {
  final AuthService _auth = AuthService();

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _eventsWithVideo = [];
  bool _loading = true;
  String? _error;
  int _retentionDays = 30;
  bool _savingRetention = false;
  bool _backupExpanded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    final sum = await _auth.getStorageSummary();
    final ev = await _auth.getEvents();

    if (!mounted) return;

    if (sum['success'] == true) {
      setState(() {
        _summary = sum;
        _retentionDays = (sum['retention_days'] is num)
            ? (sum['retention_days'] as num).toInt()
            : 30;
      });
    } else {
      setState(() => _error = sum['message']?.toString());
    }

    if (ev['success'] == true) {
      final list = List<Map<String, dynamic>>.from(ev['events'] ?? []);
      final withVid = list.where((e) {
        final u = e['video_url']?.toString() ?? '';
        final p = e['video_path']?.toString() ?? '';
        return u.isNotEmpty || p.isNotEmpty;
      }).toList();
      withVid.sort((a, b) {
        final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      if (mounted) {
        setState(() => _eventsWithVideo = withVid.take(20).toList());
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  String _fmtBytes(Object? raw) {
    int? b;
    if (raw is num) {
      b = raw.toInt();
    }
    if (b == null || b <= 0) return '0 B';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
  }

  bool _isFamilyUser() {
    if (!mounted) return false;
    return context.read<UserProvider>().user?.isFamilyMember ?? false;
  }

  Future<void> _applyRetention(int days) async {
    if (_isFamilyUser()) return;
    setState(() => _savingRetention = true);
    final r = await _auth.updateUserOptions({
      'recording_retention_days': days,
    });
    if (!mounted) return;
    setState(() => _savingRetention = false);
    if (r['success'] == true) {
      setState(() => _retentionDays = days);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retention preference saved')),
      );
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r['message']?.toString() ?? 'Could not save'),
        ),
      );
    }
  }

  Future<void> _purgeOld() async {
    final isFamily =
        context.read<UserProvider>().user?.isFamilyMember ?? false;
    if (isFamily) return;
    final days = _retentionDays >= 1 ? _retentionDays : 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove old clips?'),
        content: Text(
          'This deletes video files for events older than $days days. '
          'Event history stays; only the clip is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final res = await _auth.purgeOldClips(days: days);
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${res['events_affected'] ?? 0} clip(s)',
          ),
        ),
      );
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Purge failed')),
      );
    }
  }

  Future<void> _deleteAllRecordings() async {
    if (_isFamilyUser()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all clips?'),
        content: const Text(
          'This deletes every stored recording file for your home and clears '
          'video links on all events. Event titles and times remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all clips'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final res = await _auth.deleteAllRecordings();
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cleared ${res['clips_cleared'] ?? 0} clip(s)',
          ),
        ),
      );
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Failed')),
      );
    }
  }

  Future<void> _deleteEventRow(Map<String, dynamic> e) async {
    if (_isFamilyUser()) return;
    final id = e['id'];
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this event?'),
        content: Text(e['title']?.toString() ?? 'Event #${id.toString()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _auth.deleteEvent(id is int ? id : int.parse('$id'));
    if (!mounted) return;
    if (res['success'] == true) {
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Failed')),
      );
    }
  }

  Future<void> _exportClip(Map<String, dynamic> e) async {
    final raw = e['video_url'] ?? e['video_path'];
    if (raw == null || raw.toString().isEmpty) return;
    final pathStr = raw.toString();
    final url = pathStr.startsWith('http')
        ? pathStr
        : '${AuthService.baseUrl}$pathStr';

    try {
      final headers = <String, String>{};
      final t = await _auth.getToken();
      if (t != null) {
        headers['Authorization'] = 'Bearer $t';
      }
      final res = await http.get(Uri.parse(url), headers: headers).timeout(
            const Duration(seconds: 120),
          );
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final raw = Uint8List.fromList(res.bodyBytes);
      final playable = RecordingPlaybackCodec.playableFromDownloadBody(raw);
      if (playable.isEmpty) {
        throw Exception('Recording is empty after decoding');
      }
      final dir = await getTemporaryDirectory();
      final safeId = e['id']?.toString() ?? 'clip';
      final ext = RecordingPlaybackCodec.extensionForPlayable(playable);
      final out = File('${dir.path}/homeguardian_export_$safeId.$ext');
      await out.writeAsBytes(playable);
      await Share.shareXFiles(
        [XFile(out.path)],
        text: e['title']?.toString() ?? 'HomeGuardian clip',
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export: $err')),
      );
    }
  }

  Future<void> _clearLocalCache() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache clear is for mobile/desktop.')),
      );
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      var n = 0;
      await for (final ent in dir.list()) {
        if (ent is! File) continue;
        final name = ent.path.split(Platform.pathSeparator).last;
        if (name.startsWith('temp_video_') ||
            name.startsWith('homeguardian_export_') ||
            name.endsWith('.webm')) {
          try {
            await ent.delete();
            n++;
          } catch (_) {}
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $n temporary file(s)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cache clear failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final lowDisk = s?['low_disk_warning'] == true;
    final isFamilyUser =
        context.watch<UserProvider>().user?.isFamilyMember ?? false;

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
                      'Storage and Cloud',
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
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: IconButton(
                      onPressed: _loading ? null : _reload,
                      icon: const Icon(Icons.refresh, color: Colors.white),
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (_error != null)
                              Text(
                                _error!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            if (isFamilyUser)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Material(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Family accounts can view usage only. '
                                      'Deleting data is limited to the home owner.',
                                      style: TextStyle(
                                        fontFamily: 'Comfortaa',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (lowDisk)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      'Low disk space on the server (under ~500 MB free). '
                                      'Remove old clips or expand disk.',
                                      style: TextStyle(
                                        fontFamily: 'Comfortaa',
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _card(
                              title: 'Usage on your server',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _kv('Event clips', _fmtBytes(s?['clips_bytes'])),
                                  _kv('Profile photos (home)',
                                      _fmtBytes(s?['profile_images_bytes'])),
                                  _kv('Known faces data',
                                      _fmtBytes(s?['known_faces_bytes'])),
                                  _kv('Events (total)',
                                      '${s?['event_count'] ?? 0}'),
                                  _kv('Events with a clip',
                                      '${s?['events_with_video'] ?? 0}'),
                                  const Divider(),
                                  _kv(
                                    'Disk free on server',
                                    _fmtBytes(s?['disk_free_bytes']),
                                  ),
                                  _kv(
                                    'Disk total',
                                    _fmtBytes(s?['disk_total_bytes']),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _card(
                              title: 'Clip retention',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Used when you tap “Remove clips older than retention”. '
                                    'Does not run automatically yet.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'Comfortaa',
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final d in [
                                        0,
                                        7,
                                        14,
                                        30,
                                        60,
                                        90,
                                      ])
                                        ChoiceChip(
                                          label: Text(
                                            d == 0 ? 'Manual only' : '$d days',
                                          ),
                                          selected: _retentionDays == d,
                                          onSelected: isFamilyUser || _savingRetention
                                              ? null
                                              : (_) => _applyRetention(d),
                                        ),
                                    ],
                                  ),
                                  if (!isFamilyUser) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: _purgeOld,
                                      icon: const Icon(Icons.cleaning_services),
                                      label: const Text(
                                        'Remove clips older than retention',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!isFamilyUser)
                              _card(
                                title: 'Danger zone',
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                      ),
                                      onPressed: _deleteAllRecordings,
                                      icon: const Icon(Icons.delete_forever),
                                      label: const Text(
                                        'Remove all clips from server',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            _card(
                              title: 'Recent clips',
                              child: _eventsWithVideo.isEmpty
                                  ? const Text(
                                      'No clips stored yet.',
                                      style: TextStyle(fontFamily: 'Comfortaa'),
                                    )
                                  : Column(
                                      children: [
                                        for (final e in _eventsWithVideo)
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              e['title']?.toString() ??
                                                  'Event',
                                              style: const TextStyle(
                                                fontFamily: 'Comfortaa',
                                                fontSize: 14,
                                              ),
                                            ),
                                            subtitle: Text(
                                              e['timestamp']?.toString() ?? '',
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.share_outlined,
                                                  ),
                                                  onPressed: () =>
                                                      _exportClip(e),
                                                ),
                                                if (!isFamilyUser)
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                    onPressed: () =>
                                                        _deleteEventRow(e),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 16),
                            _card(
                              title: 'Backup (self-hosted)',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () => setState(() =>
                                        _backupExpanded = !_backupExpanded),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _backupExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'How to back up your server folders',
                                          style: TextStyle(
                                            fontFamily: 'Comfortaa',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_backupExpanded) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'On the machine running HomeGuardian, copy these folders '
                                      'to an external drive or another PC on a schedule:\n\n'
                                      '• recordings/ — event video files\n'
                                      '• uploads/ — profile images\n'
                                      '• known_faces/ — enrolled face photos\n'
                                      '• PostgreSQL database — use pg_dump for the full account.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: Colors.grey.shade800,
                                        fontFamily: 'Comfortaa',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _card(
                              title: 'This phone',
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Clears temporary decrypted video files in app cache.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'Comfortaa',
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: _clearLocalCache,
                                    icon: const Icon(Icons.cleaning_services),
                                    label: const Text('Clear app cache'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Comfortaa',
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: TextStyle(fontFamily: 'Comfortaa', color: Colors.grey.shade800),
          ),
          Text(
            v,
            style: const TextStyle(
              fontFamily: 'Comfortaa',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
