import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/user_provider.dart';
import 'home_page.dart';
import 'network_endpoint_settings_page.dart';

/// Mobile-only flow: single-use invite for first setup, then email + password only.
class FamilyMemberLoginPage extends StatefulWidget {
  const FamilyMemberLoginPage({super.key});

  @override
  State<FamilyMemberLoginPage> createState() => _FamilyMemberLoginPageState();
}

class _FamilyMemberLoginPageState extends State<FamilyMemberLoginPage> {
  final _auth = AuthService();
  bool _firstTime = true;

  // First-time
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _enrolledName;
  bool _codeValidated = false;
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final code = _codeController.text.trim();
    if (code.length < 8) {
      _toast('Enter the invite code from your home owner.', error: true);
      return;
    }
    setState(() => _loading = true);
    final res = await _auth.lookupFamilyInvite(code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      setState(() {
        _enrolledName = res['name']?.toString();
        _codeValidated = true;
      });
    } else {
      _toast(res['message']?.toString() ?? 'Invalid code', error: true);
    }
  }

  Future<void> _completeJoin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _toast('Email and password are required.', error: true);
      return;
    }
    setState(() => _loading = true);
    final res = await _auth.joinFamilyAccount(
      code: _codeController.text.trim(),
      email: email,
      password: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.setUser(User.fromJson(data['user'] as Map<String, dynamic>));
      final optionsRes = await _auth.getOptions();
      if (optionsRes['success'] == true && optionsRes['options'] != null) {
        userProvider.setOptions(UserOptions.fromJson(optionsRes['options']));
      }
      await PushNotificationService.syncTokenWithBackendIfLoggedIn();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SmartHomePage()),
        (_) => false,
      );
    } else {
      _toast(res['message']?.toString() ?? 'Signup failed', error: true);
    }
  }

  Future<void> _returningLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _toast('Email and password are required.', error: true);
      return;
    }
    setState(() => _loading = true);
    final result = await _auth.login(email, password, isDashboard: false);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      final userMap = data?['user'] as Map<String, dynamic>?;
      if (userMap == null) {
        _toast('Login response missing user', error: true);
        return;
      }
      final user = User.fromJson(userMap);
      if (!user.isFamilyMember) {
        _toast('This account is not a family login. Use the main Login page.', error: true);
        return;
      }
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.setUser(user);
      final optionsRes = await _auth.getOptions();
      if (optionsRes['success'] == true && optionsRes['options'] != null) {
        userProvider.setOptions(UserOptions.fromJson(optionsRes['options']));
      }
      await PushNotificationService.syncTokenWithBackendIfLoggedIn();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SmartHomePage()),
        (_) => false,
      );
    } else {
      _toast(result['message']?.toString() ?? 'Login failed', error: true);
    }
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: error ? Colors.red : Colors.green[800]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Family member', style: TextStyle(fontFamily: 'Comfortaa')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Access your home’s shared activity on this device.',
              style: TextStyle(fontFamily: 'Comfortaa', fontSize: 15, color: Colors.black87),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const NetworkEndpointSettingsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.dns_outlined, size: 20),
                label: const Text(
                  'Set server URL (home Wi‑Fi)',
                  style: TextStyle(fontFamily: 'Comfortaa', fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('First time'), icon: Icon(Icons.mail_lock_outlined, size: 18)),
                ButtonSegment(value: false, label: Text('I have an account'), icon: Icon(Icons.login, size: 18)),
              ],
              selected: {_firstTime},
              onSelectionChanged: (s) {
                setState(() {
                  _firstTime = s.first;
                  _codeValidated = false;
                  _enrolledName = null;
                });
              },
            ),
            const SizedBox(height: 24),
            if (_firstTime) ..._firstTimeFields() else ..._returningFields(),
          ],
        ),
      ),
    );
  }

  List<Widget> _firstTimeFields() {
    return [
      if (!_codeValidated) ...[
        TextField(
          controller: _codeController,
          decoration: _decoration('Invite code from owner', Icons.key),
          style: const TextStyle(fontFamily: 'Comfortaa'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _validateCode,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Continue', style: TextStyle(fontFamily: 'Comfortaa')),
        ),
      ] else ...[
        Text(
          'Name (from home owner)',
          style: TextStyle(fontFamily: 'Comfortaa', color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _enrolledName ?? '',
            style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 16),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration('Your email', Icons.mail_outline),
          style: const TextStyle(fontFamily: 'Comfortaa'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: _decoration('Choose a password', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          style: const TextStyle(fontFamily: 'Comfortaa'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _completeJoin,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create account & log in', style: TextStyle(fontFamily: 'Comfortaa')),
        ),
      ],
    ];
  }

  List<Widget> _returningFields() {
    return [
      const Text(
        'Use the same email and password you set the first time.',
        style: TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: Colors.black54),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: _decoration('Email', Icons.mail_outline),
        style: const TextStyle(fontFamily: 'Comfortaa'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        decoration: _decoration('Password', Icons.lock_outline).copyWith(
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        style: const TextStyle(fontFamily: 'Comfortaa'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _loading ? null : _returningLogin,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Log in', style: TextStyle(fontFamily: 'Comfortaa')),
      ),
    ];
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Comfortaa'),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
    );
  }
}
