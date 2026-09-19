import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/user_provider.dart';
import '../models/user.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'face_login_page.dart';
import 'family_member_login_page.dart';
import 'network_endpoint_settings_page.dart';

// --- LOGIN PAGE WIDGETS ---

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Custom Widget to combine Label and TextField for the HomeGuardian style
  Widget _buildHomeGuardianTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      keyboardType: TextInputType.emailAddress,
      style: const TextStyle(
        fontSize: 16,
        fontFamily: 'Comfortaa',
        color: Colors.black,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Comfortaa'),
        filled: true,
        fillColor: Colors.white, // White fill color matching original design
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
        ),
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        suffixIcon: suffixIcon,
      ),
    );
  }

  // Widget to display the HomeGuardian Logo/Title
  Widget _buildHomeGuardianHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 48), // Added top spacing
        const Text(
          'HomeGuardian',
          style: TextStyle(
            fontSize: 35,
            color: Colors.white,
            fontFamily: 'Comfortaa',
          ),
        ),
        const SizedBox(
          height: 8,
        ), // Increased spacing between title and subtitle
        const Text(
          'Always watching, never intruding',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontFamily: 'Comfortaa',
          ),
        ),
        const SizedBox(height: 10),
        // Security Camera Illustration Placeholder
        // --- MODIFIED: Added Transform.translate to shift the image ---
        Transform.translate(
          // Offset: 120px right, -13px up
          offset: const Offset(110, -130),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              // change the size of the image here
              height: 350,
              width: 350,
              // --- UPDATED: Using correct asset path ---
              child: Image.asset(
                'assets/images/3d_home.png',
                height: 200,
                width: 200,
                fit: BoxFit.contain, // Ensure it fits well
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Container(
                    height: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(Icons.error_outline, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // --- END UPDATED SECTION ---
            ),
          ),
        ),
        // --- END MODIFIED SECTION ---
      ],
    );
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // isDashboard is false by default for mobile
      final result = await _authService.login(
        email,
        password,
        isDashboard: false,
      );

      if (result['success']) {
        if (mounted) {
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          final userData = result['data']['user'];
          userProvider.setUser(User.fromJson(userData));

          final optionsRes = await _authService.getOptions();
          if (optionsRes['success']) {
            userProvider.setOptions(
              UserOptions.fromJson(optionsRes['options']),
            );
          }

          await PushNotificationService.syncTokenWithBackendIfLoggedIn();

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const SmartHomePage()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login failed: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The Scaffold's background is the light grey that shows around the card and at the bottom
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: Stack(
        children: [
          // 1. Dark Background (Full width, covers the top of the screen)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height:
                  MediaQuery.of(context).size.height *
                  0.5, // Extend deep enough
              width: double.infinity,
              color: Colors.black, // Dark color
            ),
          ),

          // 2. White Login Card (Appears 'in front' and contains the content)
          Positioned(
            top: 250, // Positioned lower so the black area can show the title
            left: 0,
            right: 0,
            bottom: 0,
            // Removed ClipPath
            child: Container(
              decoration: BoxDecoration(
                color: const Color(
                  0xFFF0F0F0,
                ), // Light grey background for the login section
                // APPLYING NEW BORDER RADIUS: 70 only on TopLeft, 0 everywhere else.
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(70),
                  topRight: Radius.circular(0),
                  bottomLeft: Radius.circular(0),
                  bottomRight: Radius.circular(0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 25,
                  left: 34.0,
                  right: 24.0,
                  bottom: 24.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // "Login" Title (Moved down to sit correctly inside the white area)
                    const SizedBox(
                      height: 20,
                    ), // Spacer to push Login below the black header
                    const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Comfortaa',
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 30),

                    // --- Email Input (Original HomeGuardian Style) ---
                    _buildHomeGuardianTextField(
                      controller: _emailController,
                      hintText: 'Email',
                      icon: Icons.mail_outline,
                    ),
                    const SizedBox(height: 16),

                    // --- Password Input (Original HomeGuardian Style) ---
                    _buildHomeGuardianTextField(
                      controller: _passwordController,
                      hintText: 'Password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.black87,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const FamilyMemberLoginPage(),
                            ),
                          );
                        },
                        child: const Text(
                          'Log in as family member',
                          style: TextStyle(
                            color: Colors.black54,
                            fontFamily: 'Comfortaa',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                const NetworkEndpointSettingsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_ethernet, size: 20),
                      label: const Text(
                        'Set server URL before login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Comfortaa',
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Login Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontFamily: 'Comfortaa',
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Face Login Button
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const FaceLoginPage(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.face_unlock_outlined,
                        color: Colors.black,
                      ),
                      label: const Text(
                        'Login with Face',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Sign Up Text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have account? ",
                          style: TextStyle(
                            color: Colors.grey,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignUpPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Status Bar and Header Content (Always on top)
          Positioned(
            top: 0,
            left: 24,
            right: 24,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status bar
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "9:41",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.signal_cellular_4_bar,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.wifi,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 22,
                              height: 10,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              padding: const EdgeInsets.all(1),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // HomeGuardian Text and Illustration
                  _buildHomeGuardianHeader(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
