import 'package:flutter/material.dart';

class UnlockAppPage extends StatelessWidget {
  const UnlockAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F4),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 140),
                // 1. Face ID Icon from assets
                Center(
                  child: Image.asset(
                    'assets/images/face-id.png',
                    height: 130,
                    width: 130,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 48),
                // 2. Title
                const Text(
                  'Login with Face ID',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.black,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 16),
                // 3. Subtitle
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 50.0),
                  child: Text(
                    'Please put your phone in front of\nyour face to login',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.black87,
                      height: 1.5,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ),
              ],
            ),
            // 4. Positioned Illustration at the bottom using your asset
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/images/Get_Started.png',
                fit: BoxFit.contain,
                height: 380,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 380,
                  alignment: Alignment.bottomCenter,
                  child: const Icon(
                    Icons.person_outline,
                    size: 100,
                    color: Colors.black12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
