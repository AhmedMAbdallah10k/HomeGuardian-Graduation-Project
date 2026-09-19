import 'package:flutter/material.dart';
import 'trusted_person_page.dart';
import 'scan_face_page.dart';
import 'home_page.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import 'dart:typed_data';

/// Register family members page with form fields.
/// [isOnboarding] is true during first-time signup; false when adding from the menu.
class RegisterFamilyMembersPage extends StatefulWidget {
  final bool isOnboarding;

  const RegisterFamilyMembersPage({super.key, this.isOnboarding = true});

  @override
  State<RegisterFamilyMembersPage> createState() =>
      _RegisterFamilyMembersPageState();
}

class _RegisterFamilyMembersPageState extends State<RegisterFamilyMembersPage> {
  // List to store multiple family member entries
  List<Map<String, TextEditingController>> familyMembers = [];
  // Store multiple selected image bytes
  List<Uint8List> _capturedPhotos = [];
  bool _isLoading = false;

  // Each photo targets a specific angle to maximize recognition accuracy
  static const int _requiredPhotos = 5;
  static const List<String> _angleLabels = [
    'Front (look straight ahead)',
    'Turn slightly LEFT',
    'Turn slightly RIGHT',
    'Tilt head UP slightly',
    'Tilt head DOWN slightly',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with one set of input fields
    _addNewPerson();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var person in familyMembers) {
      person['fullName']?.dispose();
      person['phone']?.dispose();
      person['relationship']?.dispose();
    }
    super.dispose();
  }

  void _addNewPerson() {
    // Always add one entry for the form
    familyMembers.add({
      'fullName': TextEditingController(),
      'phone': TextEditingController(),
      'relationship': TextEditingController(),
    });
  }

  Future<void> _pickImage() async {
    if (_capturedPhotos.length >= _requiredPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You have already added $_requiredPhotos photos.')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _capturedPhotos.add(bytes);
      });

      if (_capturedPhotos.length < _requiredPhotos) {
        final nextAngle = _angleLabels[_capturedPhotos.length];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo ${_capturedPhotos.length}/$_requiredPhotos saved! Next: $nextAngle'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _finishFlow() {
    if (widget.isOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const TrustedPersonPage()),
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SmartHomePage()),
        (route) => false,
      );
    }
  }

  void _goBack() {
    if (widget.isOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ScanFacePage()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleSaveMember({bool isAddingMore = false}) async {
    final name = familyMembers[0]['fullName']!.text.trim();
    final phone = familyMembers[0]['phone']!.text.trim();
    final relationship = familyMembers[0]['relationship']!.text.trim();

    if (name.isEmpty || phone.isEmpty || relationship.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (_capturedPhotos.length < _requiredPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add all $_requiredPhotos photos for better recognition.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<String> base64Photos = _capturedPhotos.map((bytes) => base64Encode(bytes)).toList();

      final result = await AuthService().addFamilyMember(
        name: name,
        relationship: relationship,
        phone: phone,
        photos: base64Photos,
      );

      if (result['success']) {
        if (!mounted) return;
        final data = result['data'];
        if (data is Map<String, dynamic>) {
          final invite = data['invite_code']?.toString();
          if (invite != null && invite.isNotEmpty) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text(
                  'Share this invite code',
                  style: TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.w600),
                ),
                content: SelectableText(
                  invite,
                  style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done', style: TextStyle(fontFamily: 'Comfortaa')),
                  ),
                ],
              ),
            );
          }
        }
        if (isAddingMore) {
          // Stay on the same page: clear inputs + photos and get ready for next member
          familyMembers[0]['fullName']!.clear();
          familyMembers[0]['phone']!.clear();
          familyMembers[0]['relationship']!.clear();
          setState(() {
            _capturedPhotos = [];
          });
          FocusScope.of(context).unfocus();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" added — ready for next member'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green[700],
            ),
          );
        } else {
          _finishFlow();
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${result['message']}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      width: double.infinity,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontFamily: 'Comfortaa',
          color: Color(0xFF333333),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[500],
            fontFamily: 'Comfortaa',
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, // slightly reduced
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), // slightly reduced
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          prefixIcon: Icon(icon, color: Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildPhotoField() {
    final allCaptured = _capturedPhotos.length >= _requiredPhotos;
    final nextAngle = allCaptured ? null : _angleLabels[_capturedPhotos.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.transparent),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _capturedPhotos.isNotEmpty
                      ? MemoryImage(_capturedPhotos.last)
                      : const AssetImage('assets/images/user.png') as ImageProvider,
                  radius: 22,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        allCaptured
                            ? '$_requiredPhotos photos added'
                            : 'Add photo ${_capturedPhotos.length + 1} of $_requiredPhotos',
                        style: TextStyle(
                          color: allCaptured ? Colors.green : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                      if (nextAngle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Next: $nextAngle',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.camera_alt, color: Colors.grey, size: 24),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Row(
            children: List.generate(_requiredPhotos, (index) {
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: index < _capturedPhotos.length ? Colors.green : Colors.grey[300]!,
                      width: 2,
                    ),
                    image: index < _capturedPhotos.length
                        ? DecorationImage(
                            image: MemoryImage(_capturedPhotos[index]),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: index >= _capturedPhotos.length
                      ? Icon(Icons.add_a_photo, color: Colors.grey[300], size: 18)
                      : null,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Dark top background
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              color: Colors.black,
            ),
          ),

          // White content card positioned lower with a large top-left radius
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Back link
                    GestureDetector(
                      onTap: _goBack,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left,
                            color: Colors.black,
                            size: 28,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Title: Register family members
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 3),
                      child: const Text(
                        'Register family members',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Photo field
                    _buildPhotoField(),
                    const SizedBox(height: 16),
                    // Input fields for family member
                    _buildInputField(
                      controller: familyMembers[0]['fullName']!,
                      hintText: 'Full Name',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: familyMembers[0]['phone']!,
                      hintText: 'Phone',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: familyMembers[0]['relationship']!,
                      hintText: 'Relationship',
                      icon: Icons.people_outline,
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 8),

                    // Add more button
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _handleSaveMember(isAddingMore: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text(
                            'Add more',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontFamily: 'Comfortaa',
                            ),
                          ),
                    ),

                    const SizedBox(height: 20),

                    // Next button
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _handleSaveMember(isAddingMore: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),

                    if (widget.isOnboarding) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          await AuthService().trackOnboardingSkip(
                            'family_members',
                          );
                          if (!mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const TrustedPersonPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          // Top header with the 3d_home image overlapping the card
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8.0,
                      bottom: 8.0,
                      left: 12,
                      right: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          '9:41',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                        SizedBox.shrink(),
                      ],
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(
                      offset: const Offset(80, -100),
                      child: SizedBox(
                        height: 300,
                        width: 300,
                        child: Image.asset(
                          'assets/images/3d_home.png',
                          height: 200,
                          width: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
