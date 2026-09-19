import 'otp_page.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../models/user.dart';
import 'dashboard_home_page.dart';

class DashboardLoginPage extends StatelessWidget {
  const DashboardLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double boxWidth = (constraints.maxWidth > 1800)
                ? 1600
                : (constraints.maxWidth > 1200 ? 1400 : 700);
            final double boxHeight = (constraints.maxHeight > 1600)
                ? 1400
                : (constraints.maxHeight > 1200
                      ? 1000
                      : (constraints.maxHeight > 900 ? 800 : 600));
            return Center(
              child: Container(
                width: boxWidth,
                height: boxHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Left: Black & white image
                    Expanded(
                      flex: 5,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(36),
                          bottomLeft: Radius.circular(36),
                        ),
                        child: Image.asset(
                          'assets/images/home_wallpaper.png',
                          fit: BoxFit.cover,
                          height: double.infinity,
                        ),
                      ),
                    ),
                    // Right: Login Form
                    Expanded(flex: 6, child: _DashboardLoginForm()),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardLoginForm extends StatefulWidget {
  @override
  State<_DashboardLoginForm> createState() => _DashboardLoginFormState();
}

class _DashboardLoginFormState extends State<_DashboardLoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    final result = await _authService.login(
      _emailController.text,
      _passwordController.text,
      isDashboard: true,
    );
    setState(() => _isLoading = false);

    final data = result['data'];
    if (data != null && data['requires_verification'] == true) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                OtpPage(email: _emailController.text, isSignUp: false),
          ),
        );
      }
    } else if (result['success']) {
      // Success login (should not happen for dashboard due to forced OTP, but kept for safety)
      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.setUser(User.fromJson(data['user']));
        // Fetch options too
        final optionsRes = await _authService.getOptions();
        if (optionsRes['success']) {
          userProvider.setOptions(UserOptions.fromJson(optionsRes['options']));
        }

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const DashboardHomePage()),
            (route) => false,
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
          topLeft: Radius.circular(0),
          bottomLeft: Radius.circular(0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Welcome Back!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'Comfortaa',
            ),
          ),
          const SizedBox(height: 32),
          _DashboardTextField(
            hintText: 'Email Address',
            icon: Icons.email_outlined,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Colors.grey, width: 1),
            ),
            controller: _emailController,
          ),
          const SizedBox(height: 16),
          _DashboardTextField(
            hintText: 'Password',
            icon: Icons.lock_outline,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Colors.grey, width: 1),
            ),
            obscureText: true,
            controller: _passwordController,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('Sign In', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              "Please use the HomeGuardian mobile app to create an account.",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontFamily: 'Comfortaa',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTextField extends StatelessWidget {
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final InputBorder border;
  final TextEditingController? controller;
  const _DashboardTextField({
    required this.hintText,
    required this.icon,
    required this.border,
    this.obscureText = false,
    this.controller,
  });
  @override
  Widget build(BuildContext context) {
    final whiteBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: Colors.white, width: 1),
    );
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Colors.white54,
          fontFamily: 'Comfortaa',
        ),
        filled: true,
        fillColor: Colors.black,
        prefixIcon: Icon(icon, color: Colors.white38),
        border: border,
        enabledBorder: border,
        focusedBorder: whiteBorder,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}
