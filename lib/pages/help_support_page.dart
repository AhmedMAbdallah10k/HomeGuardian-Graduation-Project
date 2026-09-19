import 'package:flutter/material.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                      'Help and Support',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24, 
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
                      onTap: () => Navigator.of(context).pop(),
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
                    children: [
                      const SizedBox(height: 40),
                      
                      // FAQs
                      _buildSettingsItem(
                        title: 'FAQs',
                        icon: Icons.help_outline_rounded,
                        onTap: () {
                          // Navigation to be implemented
                        }
                      ),
                      _buildDivider(),

                      // quick setup guide
                      _buildSettingsItem(
                        title: 'quick setup guide',
                        icon: Icons.description_outlined,
                        onTap: () {
                           // Navigation to be implemented
                        }
                      ),
                      _buildDivider(),

                      // contact support
                      _buildSettingsItem(
                        title: 'contact support',
                        icon: Icons.contact_support_outlined, 
                        onTap: () {
                           // Navigation to be implemented
                        }
                      ),
                       _buildDivider(),

                       // privacy policy and terms
                      _buildSettingsItem(
                        title: 'privacy policy and terms',
                        icon: Icons.gavel_outlined, 
                        onTap: () {
                           // Navigation to be implemented
                        }
                      ),
                       _buildDivider(),
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

  Widget _buildSettingsItem({required String title, required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
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
             const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.only(left: 80, right: 40),
      child: Divider(color: Color(0xFFE0E0E0), thickness: 1, height: 1),
    );
  }
}
