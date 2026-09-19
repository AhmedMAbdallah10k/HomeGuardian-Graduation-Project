import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/user_provider.dart';
import '../services/websocket_service.dart';

/// Configure the home LAN API server URL (synced via `/api/options` when signed in).
class NetworkEndpointSettingsPage extends StatefulWidget {
  const NetworkEndpointSettingsPage({super.key});

  @override
  State<NetworkEndpointSettingsPage> createState() =>
      _NetworkEndpointSettingsPageState();
}

class _NetworkEndpointSettingsPageState
    extends State<NetworkEndpointSettingsPage> {
  final _homeCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _canSyncToServer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _homeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await AuthService.loadNetworkEndpointsFromPrefs();
    if (!mounted) return;
    final authSvc = AuthService();
    final tok = await authSvc.getToken();
    if (!mounted) return;
    setState(() {
      _homeCtrl.text = snap['home'] ?? AuthService.defaultBaseUrl;
      _canSyncToServer = tok != null;
      _loading = false;
    });

    if (tok != null) {
      final r = await authSvc.getOptions();
      if (!mounted || r['success'] != true) return;
      final snap2 = await AuthService.loadNetworkEndpointsFromPrefs();
      if (!mounted) return;
      setState(() {
        _homeCtrl.text = snap2['home'] ?? AuthService.defaultBaseUrl;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final homeEffective = _homeCtrl.text.trim().isEmpty
        ? AuthService.defaultBaseUrl
        : _homeCtrl.text.trim();
    final userIdBeforeAwait =
        Provider.of<UserProvider>(context, listen: false).user?.id;

    setState(() => _saving = true);

    await AuthService.saveNetworkEndpointsLocal(homeUrl: homeEffective);

    final authSvc = AuthService();
    final loggedInTok = await authSvc.getToken();
    final Map<String, dynamic> res;
    if (loggedInTok != null) {
      res = await authSvc.updateUserOptions({
        'network_route_mode': 'home',
        'api_base_home_url': homeEffective,
        'api_base_tunnel_url': null,
      });
    } else {
      res = {'success': true};
    }
    if (!mounted) return;

    final ws = WebSocketService();
    ws.disconnect();
    if (userIdBeforeAwait != null) {
      await ws.connect(userId: userIdBeforeAwait);
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _canSyncToServer = loggedInTok != null;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (res['success'] == true) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Using home LAN: ${AuthService.baseUrl}'),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Could not sync to server.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server connection'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Home Guardian uses your PC on the local Wi‑Fi network. '
                    'Phone, dashboard, and ESP32 devices must reach this address '
                    '(example: http://192.168.8.188:3000).',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _homeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Server URL (LAN)',
                      hintText: 'http://192.168.8.188:3000',
                      border: OutlineInputBorder(),
                    ),
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Active now: ${AuthService.baseUrl}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_canSyncToServer ? 'Save & reconnect' : 'Save'),
                  ),
                  if (_canSyncToServer)
                    TextButton(
                      onPressed: _saving ? null : _load,
                      child: const Text('Reload from server'),
                    ),
                ],
              ),
            ),
    );
  }
}
