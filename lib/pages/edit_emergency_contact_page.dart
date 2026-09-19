import 'package:flutter/material.dart';

class EditEmergencyContactPage extends StatefulWidget {
  final String name;
  final String role;
  final String imagePath;

  const EditEmergencyContactPage({
    super.key,
    this.name = 'Ahmed Osama', // Default/Placeholder
    this.role = 'Neighbor',
    this.imagePath = 'assets/images/boy.png',
  });

  @override
  State<EditEmergencyContactPage> createState() => _EditEmergencyContactPageState();
}

class _EditEmergencyContactPageState extends State<EditEmergencyContactPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController(); // Using raw text for now or maybe dropdown if needed? Image shows "Relationship" as a field.
  // "Edit Permissions" is a dropdown in the image.

  String? _selectedPermission;
  final List<String> _permissions = ['Full Access', 'Limited Access', 'View Only'];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.name;
    // Initialize other controllers with dummy data or empty
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 1. Header (Black background with Title and Back button)
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
                    'Edit Emergency Contact',
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

          // 2. White Card Content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFEFF1F0),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(70)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    children: [
                      // Avatar with Pencil
                      Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            padding: const EdgeInsets.all(5),
                            child: ClipOval(
                              child: Image.asset(
                                widget.imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person, size: 60, color: Colors.grey),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                // color: Colors.black, // Optional bg for visibility? Image shows just the icon floating nicely
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit, color: Colors.black, size: 24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // Fields
                      _buildRoundedField(
                        controller: _nameController,
                        hintText: 'Edit Name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      _buildRoundedField(
                        controller: _phoneController,
                        hintText: 'Edit Phone Number',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      
                      // Permissions Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                             BoxShadow(
                               color: Colors.black.withOpacity(0.03),
                               blurRadius: 10,
                               offset: const Offset(0, 4),
                             ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPermission,
                            isExpanded: true,
                            hint: Row(
                              children: [
                                Icon(Icons.lock_outline, color: Colors.grey[400]),
                                const SizedBox(width: 12),
                                Text(
                                  'Edit Permissions',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontFamily: 'Comfortaa',
                                  ),
                                ),
                              ],
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black),
                            items: _permissions.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value, style: const TextStyle(fontFamily: 'Comfortaa')),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedPermission = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                       _buildRoundedField(
                        controller: _relationshipController,
                        hintText: 'Relationship',
                        icon: Icons.group_outlined, // Changed to match image roughly
                      ),

                      const SizedBox(height: 50),

                      // Buttons
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Save logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Comfortaa'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                           Navigator.pop(context); // Delete logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Comfortaa'),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundedField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
           BoxShadow(
             color: Colors.black.withOpacity(0.03),
             blurRadius: 10,
             offset: const Offset(0, 4),
           ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: 'Comfortaa', color: Color(0xFF333333)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400], fontFamily: 'Comfortaa'),
          prefixIcon: Icon(icon, color: Colors.grey[300]),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
        ),
      ),
    );
  }
}
