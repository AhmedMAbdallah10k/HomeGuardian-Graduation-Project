import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/user_provider.dart';
import 'change_password_page.dart';
import 'manage_face_id_page.dart';

class SecurityAndBiometricsPage extends StatelessWidget {
  const SecurityAndBiometricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isFamily = context.watch<UserProvider>().user?.isFamilyMember ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 90,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(60),
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: const Text(
                      'Security',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 30),

                       // List Items
                       _buildSettingsItem(
                        context,
                        icon: Icons.lock,
                        title: 'Change Password',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
                          );
                        },
                      ),
                      if (!isFamily) ...[
                        _buildDivider(),
                        _buildSettingsItem(
                          context,
                          icon: Icons.face,
                          title: 'Manage Face ID',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ManageFaceIdPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Icon(icon, size: 28, color: Colors.black),
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDivider() {
     return Padding(
       padding: const EdgeInsets.only(left: 80, right: 40), // Indented divider
       child: Divider(color: Colors.grey[400], thickness: 1),
     );
  }
}
