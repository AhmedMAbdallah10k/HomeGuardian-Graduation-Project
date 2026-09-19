import 'package:flutter/material.dart';
import 'start_page.dart';
import 'scan_face_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // Controllers for the input fields
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  final bool _isLoading = false;

  // --- WIDGET BUILDERS ---

  Widget _buildHomeGuardianTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 16,
        fontFamily: 'Comfortaa',
        color: Colors.black,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey[600], fontFamily: 'Comfortaa'),
        filled: true,
        fillColor: Colors.white, // Pure white background
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18, // Slightly taller padding
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
        ),
        prefixIcon: Icon(icon, color: Colors.grey[600]),
      ),
    );
  }

  // Widget to display the HomeGuardian Illustration and Status Bar
  Widget _buildHomeGuardianHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status bar section (9:41, wifi, signal)
        Padding(
          padding: const EdgeInsets.only(
            top: 8.0,
            bottom: 20.0,
            left: 24,
            right: 24,
          ),
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
                  const Icon(Icons.wifi, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Container(
                    width: 22,
                    height: 10,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1),
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
        // Illustration (positioned slightly down and to the right)
        Align(
          alignment: Alignment.centerRight,
          child: Transform.translate(
            offset: const Offset(
              80,
              -100,
            ), // Move 80 right, 100 up (relative to its position)
            child: SizedBox(
              height: 350,
              width: 350,
              child: Image.asset(
                'assets/images/3d_home.png',
                height: 200,
                width: 200,
                fit: BoxFit.contain,
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
            ),
          ),
        ),
      ],
    );
  }

  // Function to navigate to scan face page with user data
  void _navigateToScanFace() {
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      _showError('Please enter your name');
      return;
    }

    if (email.isEmpty) {
      _showError('Please enter your email');
      return;
    }

    if (password.isEmpty) {
      _showError('Please enter a password');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    // Navigate to scan face page with user data
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ScanFacePage(
          name: name,
          email: email,
          password: password,
          phone: _phoneController.text.trim(),
        ),
      ),
    );
  }

  // Helper to show error messages
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background below the light card
      body: Stack(
        children: [
          // 1. Dark Background Area
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.5,
              width: double.infinity,
              color: Colors.black,
            ),
          ),

          // 2. White/Light Gray Content Card
          Positioned(
            top: 150,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(70),
                  topRight: Radius.circular(0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 20,
                  left: 24.0,
                  right: 24.0,
                  bottom: 24.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    // Back link
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const StartPage(),
                          ),
                        );
                      },
                      child: const Row(
                        children: [
                          Icon(
                            Icons.chevron_left,
                            color: Colors.black,
                            size: 28,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Sign Up Title
                    const Text(
                      'Sign Up',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Comfortaa',
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 40),

                    // Input Fields
                    Column(
                      children: [
                        _buildHomeGuardianTextField(
                          controller: _fullNameController,
                          icon: Icons.person_outline,
                          hintText: 'Full Name',
                        ),
                        const SizedBox(height: 16),
                        _buildHomeGuardianTextField(
                          controller: _emailController,
                          icon: Icons.email_outlined,
                          hintText: 'Email',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        _buildHomeGuardianTextField(
                          controller: _passwordController,
                          icon: Icons.lock_outline,
                          hintText: 'Password',
                          isPassword: true,
                        ),
                        const SizedBox(height: 16),
                        _buildHomeGuardianTextField(
                          controller: _confirmPasswordController,
                          icon: Icons.lock_outline,
                          hintText: 'Confirm Password',
                          isPassword: true,
                        ),
                        const SizedBox(height: 16),
                        _buildHomeGuardianTextField(
                          controller: _phoneController,
                          icon: Icons.phone_outlined,
                          hintText: 'Phone',
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Next Button (Calls Scan Face)
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _navigateToScanFace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: Colors.grey,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Next (Scan Face)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontFamily: 'Comfortaa',
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),

          // 3. Status Bar and Illustration
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _buildHomeGuardianHeader()),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
