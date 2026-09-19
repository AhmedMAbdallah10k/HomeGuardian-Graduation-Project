import 'otp_page.dart';
import 'package:flutter/material.dart';
import 'dashboard_login_page.dart';
import '../services/auth_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

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
                    // Right: Form
                    Expanded(flex: 6, child: _DashboardForm()),
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

class _DashboardForm extends StatefulWidget {
  @override
  State<_DashboardForm> createState() => _DashboardFormState();
}

class _DashboardFormState extends State<_DashboardForm> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  void _signUp() async {
    if (_passwordController.text != _repeatPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.signup(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      isDashboard: true,
    );
    setState(() => _isLoading = false);

    if (result['success']) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                OtpPage(email: _emailController.text, isSignUp: true),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'])),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: Colors.grey, width: 0.7),
    );
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
            'Hello!\nWe are glad to see you :)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'Comfortaa',
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _DashboardTextField(
                  hintText: 'Name',
                  icon: Icons.person_outline,
                  border: inputBorder,
                  controller: _nameController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _DashboardTextField(
                  hintText: 'Email Address',
                  icon: Icons.email_outlined,
                  border: inputBorder,
                  controller: _emailController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DashboardTextField(
                  hintText: 'Password',
                  icon: Icons.lock_outline,
                  border: inputBorder,
                  obscureText: true,
                  controller: _passwordController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _DashboardTextField(
                  hintText: 'Repeat Password',
                  icon: Icons.lock_outline,
                  border: inputBorder,
                  obscureText: true,
                  controller: _repeatPasswordController,
                ),
              ),
            ],
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
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('Sign Up', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontFamily: 'Comfortaa',
                ),
                children: [
                  const TextSpan(text: 'Already have account? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const DashboardLoginPage(),
                          ),
                        );
                      },
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          decoration: TextDecoration.underline,
                          fontFamily: 'Comfortaa',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
      borderSide: const BorderSide(color: Colors.white, width: 0.9),
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

class _SocialIconButton extends StatelessWidget {
  final IconData icon;
  const _SocialIconButton({required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black),
        onPressed: () {},
      ),
    );
  }
}
