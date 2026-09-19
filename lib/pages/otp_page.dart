import 'dashboard_home_page.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import '../services/user_provider.dart';
import '../models/user.dart';

class OtpPage extends StatefulWidget {
  final String email;
  final bool isSignUp;
  const OtpPage({super.key, required this.email, required this.isSignUp});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController _otpController = TextEditingController();
  String? _errorText;
  bool _isLoading = false;
  final _authService = AuthService();

  void _verify() async {
    if (_otpController.text.length < 6) {
      setState(() => _errorText = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final result = await _authService.verifyOtp(
      widget.email,
      _otpController.text,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      if (mounted) {
        final data = result['data'];
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.setUser(User.fromJson(data['user']));
        
        // Fetch options
        final optionsRes = await _authService.getOptions();
        if (optionsRes['success']) {
          userProvider.setOptions(UserOptions.fromJson(optionsRes['options']));
        }

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const DashboardHomePage(),
            ),
            (route) => false,
          );
        }
      }
    } else {
      setState(() {
        _errorText = result['message'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double boxWidth = (MediaQuery.of(context).size.width > 1800)
        ? 1600
        : (MediaQuery.of(context).size.width > 1200 ? 1400 : 700);
    final double boxHeight = (MediaQuery.of(context).size.height > 1600)
        ? 1400
        : (MediaQuery.of(context).size.height > 1200
              ? 1000
              : (MediaQuery.of(context).size.height > 900 ? 800 : 600));
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
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
              // Right: OTP Form
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 32,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        widget.isSignUp
                            ? 'Verify Your Email'
                            : 'Login Verification',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'A 6-digit code has been sent to',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _otpController,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          letterSpacing: 16,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Enter 6-digit code',
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Comfortaa',
                          ),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: Colors.white,
                              width: 1,
                            ),
                          ),
                          errorText: _errorText,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                        ),
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
                          onPressed: _isLoading ? null : _verify,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.black)
                              : const Text(
                                  'Verify',
                                  style: TextStyle(fontSize: 18),
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
      ),
    );
  }
}
