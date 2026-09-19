import 'package:flutter/material.dart';
import 'modes_page.dart';
import 'register_family_members_page.dart';
import '../services/auth_service.dart';

/// Trusted person registration page with form fields.
class TrustedPersonPage extends StatefulWidget {
  const TrustedPersonPage({super.key});

  @override
  State<TrustedPersonPage> createState() => _TrustedPersonPageState();
}

class _TrustedPersonPageState extends State<TrustedPersonPage> {
  List<Map<String, TextEditingController>> trustedPersons = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize with one set of input fields
    _addNewPerson();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var person in trustedPersons) {
      person['fullName']?.dispose();
      person['phone']?.dispose();
      person['email']?.dispose();
      person['relationship']?.dispose();
    }
    super.dispose();
  }

  void _addNewPerson() {
    // Always add one entry for the form
    trustedPersons.add({
      'fullName': TextEditingController(),
      'phone': TextEditingController(),
      'email': TextEditingController(),
      'relationship': TextEditingController(),
    });
  }

  Future<void> _handleSavePerson({bool isAddingMore = false}) async {
    final name = trustedPersons[0]['fullName']!.text.trim();
    final phone = trustedPersons[0]['phone']!.text.trim();
    final email = trustedPersons[0]['email']!.text.trim();
    final relationship = trustedPersons[0]['relationship']!.text.trim();

    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        relationship.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService().addTrustedPerson(
        name: name,
        relationship: relationship,
        phone: phone,
        email: email,
      );

      if (result['success']) {
        if (!mounted) return;
        if (isAddingMore) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const TrustedPersonPage(),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const ModesPage(),
            ),
          );
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
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) =>
                                const RegisterFamilyMembersPage(),
                          ),
                        );
                      },
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

                    // Title: Register Trusted Person
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 3),
                      child: const Text(
                        'Register Trusted Person',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    _buildInputField(
                      controller: trustedPersons[0]['fullName']!,
                      hintText: 'Full Name',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: trustedPersons[0]['phone']!,
                      hintText: 'Phone (WhatsApp number)',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: trustedPersons[0]['email']!,
                      hintText: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: trustedPersons[0]['relationship']!,
                      hintText: 'Relationship',
                      icon: Icons.people_outline,
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 8),

                    // Add more button
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _handleSavePerson(isAddingMore: true),
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
                      onPressed: _isLoading ? null : () => _handleSavePerson(isAddingMore: false),
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

                    const SizedBox(height: 16),

                    // Skip button (white background)
                    ElevatedButton(
                      onPressed: () async {
                        // Skip to Modes page
                        await AuthService().trackOnboardingSkip('trusted_persons');
                        
                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const ModesPage(),
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
