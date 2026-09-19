import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Lets the user enable / disable monitoring modes after onboarding.
/// Uses the same canonical mode names as [ModesPage] so `selected_modes`
/// stays compatible with the backend substring matching in `main.py`.
///
/// Each toggle auto-saves to `/api/options` via [AuthService.updateSelectedModes].
class ManageModesPage extends StatefulWidget {
  const ManageModesPage({super.key});

  @override
  State<ManageModesPage> createState() => _ManageModesPageState();
}

class _ManageModesPageState extends State<ManageModesPage> {
  final AuthService _auth = AuthService();

  static const List<String> _modeNames = [
    'Silver Mode',
    'Nanny Mode',
    'Nurse Mode',
    'Pet Mode',
    'Home alone Mode',
  ];

  static const List<String> _desc = [
    'Alerts when little movement is detected for a while (elderly care).',
    'Stranger detection and related alerts near children.',
    'Extended monitoring presets (optional).',
    'Recognize your pets and flag unknown animals.',
    'Door, exit, and occupancy-focused alerts when nobody should be home.',
  ];

  static const List<IconData> _icons = [
    Icons.elderly,
    Icons.child_care,
    Icons.local_hospital_outlined,
    Icons.pets,
    Icons.home_work_outlined,
  ];

  late List<bool> _on;
  bool _loading = true;
  Future<void> _saveQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _on = List.filled(_modeNames.length, false);
    _load();
  }

  List<String> _selectedTitles() {
    final out = <String>[];
    for (var i = 0; i < _modeNames.length; i++) {
      if (_on[i]) out.add(_modeNames[i]);
    }
    return out;
  }

  List<String> _parseModesFromOptions(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return _parseModesFromOptions(decoded);
      } catch (_) {
        return [];
      }
      return [];
    }
    if (raw is List) {
      return raw.map((e) {
        if (e is String) return e;
        if (e is Map && e['title'] != null) return e['title'].toString();
        return e.toString();
      }).toList();
    }
    return [];
  }

  bool _savedListContainsMode(List<String> saved, String canonical) {
    final c = canonical.toLowerCase().trim();
    for (final s in saved) {
      if (s.toLowerCase().trim() == c) return true;
    }
    return false;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _auth.getOptions();
    if (!mounted) return;
    if (res['success'] == true) {
      final opts = res['options'];
      final saved =
          _parseModesFromOptions(opts is Map ? opts['selected_modes'] : null);
      setState(() {
        for (var i = 0; i < _modeNames.length; i++) {
          _on[i] = _savedListContainsMode(saved, _modeNames[i]);
        }
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      _toast(res['message']?.toString() ?? 'Could not load modes', error: true);
    }
  }

  Future<void> _onToggle(int index, bool value) async {
    setState(() => _on[index] = value);

    // Chain saves so rapid toggles always end on the correct combined list.
    _saveQueue = _saveQueue.then((_) async {
      final modes = _selectedTitles();
      final result = await _auth.updateSelectedModes(modes);
      if (!mounted) return;
      if (result['success'] == true) {
        _toast('${_modeNames[index]} ${value ? 'on' : 'off'}');
      } else {
        await _load();
        _toast(result['message']?.toString() ?? 'Could not save', error: true);
      }
    });
    await _saveQueue;
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
              'Manage Modes',
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
              color: Colors.black,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                children: [
                  Text(
                    'Choose which extra monitoring modes are active. '
                    'Fire, window, fridge, and face recognition stay on for all accounts.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontFamily: 'Comfortaa',
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _modeNames.length; i++) ...[
                    _modeCard(i),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  _footerNote(),
                ],
              ),
            ),
    );
  }

  Widget _modeCard(int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F5F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_icons[index], color: Colors.black87, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modeNames[index],
                  style: const TextStyle(
                    fontFamily: 'Comfortaa',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _desc[index],
                  style: TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.92,
            child: Switch.adaptive(
              value: _on[index],
              onChanged: (v) => _onToggle(index, v),
              activeTrackColor: Colors.black,
              activeColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changes apply on the next camera frame from your dashboard. '
              'Pull down to refresh this list.',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Comfortaa',
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
