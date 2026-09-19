import 'package:flutter/material.dart';
import 'edit_emergency_contact_page.dart';
import 'add_more_from_page.dart';

class EmergencyContactPage extends StatelessWidget {
  const EmergencyContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              // 1. Header Area (Dark)
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
                        'Emergency Contact',
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
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. White Card Content
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(
                      0xFFEFF1F0,
                    ), // Keep the light greyish background
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(70),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(70),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.only(
                        top: 40,
                        left: 24,
                        right: 24,
                        bottom: 100,
                      ),
                      children: [
                        _buildTrustedPersonItem(
                          context,
                          'Ahmed Osama',
                          'Neighbor',
                          'assets/images/boy.png',
                        ),
                        _buildTrustedPersonItem(
                          context,
                          'Shahd Wagdy',
                          'Cousin',
                          'assets/images/girl.png',
                        ),
                        _buildTrustedPersonItem(
                          context,
                          'Ahmed Abdallah',
                          'Cousin',
                          'assets/images/boy.png',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 3. Bottom Button "Add More"
          Positioned(
            left: 24,
            right: 24,
            bottom: 30, // Bottom margin
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddMoreFromPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 5,
              ),
              child: const Text(
                'Add More',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Comfortaa',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustedPersonItem(
    BuildContext context,
    String name,
    String role,
    String assetPath,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          // Avatar with Edit Icon
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5.0), // White border effect
                  child: ClipOval(
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: const Icon(
                          Icons.person,
                          color: Colors.grey,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                left: 0,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => EditEmergencyContactPage(
                          name: name,
                          role: role,
                          imagePath: assetPath,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(
                      2,
                    ), // tiny background for contrast if needed or just blank
                    child: const Icon(
                      Icons.edit,
                      size: 22,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Text Info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF9E9E9E), // Grey text for Name
                  fontFamily: 'Comfortaa',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                role,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black, // Dark text for Role
                  fontFamily: 'Comfortaa',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
