import 'package:flutter/material.dart';
import 'manage_face_id_page.dart';

class CheckFaceIdPage extends StatelessWidget {
  const CheckFaceIdPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F4),
      body: SafeArea(
        child: Column(
          children: [
            // Header with Back Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.black),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 1. Face ID Icon from assets
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ManageFaceIdPage()),
                        );
                      },
                      child: Image.asset(
                        'assets/images/face-id.png',
                        height: 130,
                        width: 130,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // 2. Title
                  const Text(
                    'Checking Face ID',
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
                      'Please put your phone in front of\nyour face',
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
            ),
          ],
        ),
      ),
    );
  }
}
