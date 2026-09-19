import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class AddEmergencyContactPage extends StatefulWidget {
  const AddEmergencyContactPage({super.key});

  @override
  State<AddEmergencyContactPage> createState() => _AddEmergencyContactPageState();
}

class _AddEmergencyContactPageState extends State<AddEmergencyContactPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();
  File? _selectedImageFile;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }
  
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImageFile = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 1. Header Area
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
                    'New Emergency Contact', // Updated Title
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20, // Slightly smaller to fit
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
                      _buildPhotoField(),
                      const SizedBox(height: 30),

                      _buildRoundedField(
                        controller: _nameController,
                        hintText: 'Full Name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      _buildRoundedField(
                        controller: _phoneController,
                        hintText: 'Phone',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      _buildRoundedField(
                        controller: _relationshipController,
                        hintText: 'Relationship',
                        icon: Icons.people_outline,
                      ),

                      const SizedBox(height: 50),

                      // Save Button
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

  Widget _buildPhotoField() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[200],
              backgroundImage: _selectedImageFile != null
                  ? FileImage(_selectedImageFile!)
                  : const AssetImage('assets/images/user.png'),
              radius: 22,
            ),
            const SizedBox(width: 16),
            const Text(
              'Add 3 photos at least',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontFamily: 'Comfortaa',
              ),
            ),
            const Spacer(),
            const Icon(Icons.camera_alt, color: Colors.grey, size: 24),
          ],
        ),
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
