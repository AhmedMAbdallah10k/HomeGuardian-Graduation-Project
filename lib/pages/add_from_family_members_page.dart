import 'package:flutter/material.dart';

class AddFromFamilyMembersPage extends StatefulWidget {
  const AddFromFamilyMembersPage({super.key});

  @override
  State<AddFromFamilyMembersPage> createState() => _AddFromFamilyMembersPageState();
}

class _AddFromFamilyMembersPageState extends State<AddFromFamilyMembersPage> {
  // Mock data representing family members from FamilyMembersPage/HomePage
  final List<Map<String, dynamic>> _familyMembers = [
    {'name': 'Ahmed', 'role': 'Nighbour', 'image': 'assets/images/boy.png', 'selected': false},
    {'name': 'Arwa', 'role': 'Nighbour', 'image': 'assets/images/girl.png', 'selected': false},
    {'name': 'Shahd', 'role': 'Nighbour', 'image': 'assets/images/woman.png', 'selected': false},
  ];

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
                        'Family Members',
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
                        child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. White Card Content
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF1F0), // Keep the light greyish background
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                  ),
                  child: ClipRRect(
                     borderRadius: const BorderRadius.only(topLeft: Radius.circular(70)),
                     child: ListView.builder(
                      padding: const EdgeInsets.only(top: 40, left: 24, right: 24, bottom: 100),
                      itemCount: _familyMembers.length,
                      itemBuilder: (context, index) {
                        return _buildFamilyMemberItem(index);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 3. Bottom Button "Add"
          Positioned(
            left: 24,
            right: 24,
            bottom: 30, // Bottom margin
            child: ElevatedButton(
              onPressed: () {
                // Handle Add action (e.g., return selected members or just pop for now)
                Navigator.of(context).pop();
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
                'Add',
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

  Widget _buildFamilyMemberItem(int index) {
    final member = _familyMembers[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(5.0),
              child: ClipOval(
                child: Image.asset(
                  member['image'],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: const Icon(Icons.person, color: Colors.grey, size: 40),
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Text Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9E9E9E), // Grey text for Name
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  member['role'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black, // Dark text for Role
                    fontFamily: 'Comfortaa',
                  ),
                ),
              ],
            ),
          ),
          // Checkbox instead of Edit Icon
          // Custom Checkbox
          GestureDetector(
            onTap: () {
              setState(() {
                member['selected'] = !member['selected'];
              });
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.grey.shade400,
                  width: 1.5,
                ),
                color: Colors.transparent,
              ),
              child: member['selected']
                  ? const Icon(Icons.check, size: 18, color: Colors.black)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
