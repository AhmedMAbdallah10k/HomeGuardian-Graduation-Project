import 'package:flutter/material.dart';
import 'signup_page.dart';
import 'login_page.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(
        child: Column(
          children: [
            // Top title
            Padding(
              padding: const EdgeInsets.only(top: 140.0, left: 140.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'Hello!',
                  style: TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: 47,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Illustration area
            Expanded(
              child: Center(
                child: SizedBox(
                  width: media.width * 0.9,
                  child: Image.asset(
                    'assets/images/Get_Started.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 260,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Icon(Icons.image, size: 48)),
                    ),
                  ),
                ),
              ),
            ),

            // Get Started button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    // Go to Sign Up page
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const SignUpPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Already have account? Login
            GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24.0, top: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Already have account? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                    Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Comfortaa',
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
