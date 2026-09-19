import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import 'home_page.dart';
import 'nanny_mode_scan_page.dart';

class NannyModePage extends StatefulWidget {
  const NannyModePage({Key? key}) : super(key: key);

  @override
  State<NannyModePage> createState() => _NannyModePageState();
}

class _NannyModePageState extends State<NannyModePage> {
  final List<Map<String, dynamic>> children = [
    {
      'name': TextEditingController(),
      'birthDate': TextEditingController(),
      'gender': ValueNotifier<String?>(null),
      'health': TextEditingController(),
    },
  ];

  @override
  void dispose() {
    for (var child in children) {
      (child['name'] as TextEditingController).dispose();
      (child['birthDate'] as TextEditingController).dispose();
      (child['health'] as TextEditingController).dispose();
      (child['gender'] as ValueNotifier).dispose();
    }
    super.dispose();
  }

  void _addChild() {
    setState(() {
      children.add({
        'name': TextEditingController(),
        'birthDate': TextEditingController(),
        'gender': ValueNotifier<String?>(null),
        'health': TextEditingController(),
      });
    });
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16, fontFamily: 'Comfortaa', color: Colors.black),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey[400], fontFamily: 'Comfortaa'),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
        ),
        prefixIcon: Icon(icon, color: Colors.grey[600]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // White/Light Gray Content Card (with large curved corner)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F0F0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(70),
                  topRight: Radius.circular(0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  // Title left-aligned inside the card
                  const Padding(
                    padding: EdgeInsets.only(
                      left: 32.0,
                      top: 16.0,
                      bottom: 16.0,
                    ),
                    child: Text(
                      'Nanny Mode',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  // ...existing code...
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: children.length,
                      itemBuilder: (context, idx) {
                        final child = children[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            children: [
                              // Child's Name
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: child['name'],
                                  hintText: "Child's Name",
                                  icon: Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Birth Date
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: child['birthDate'],
                                  hintText: 'Birth Date',
                                  icon: Icons.cake_outlined,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Gender (mutually exclusive)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 36.0,
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Gender',
                                      style: TextStyle(
                                        fontFamily: 'Comfortaa',
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    ValueListenableBuilder<String?>(
                                      valueListenable: child['gender'],
                                      builder: (context, value, _) => Row(
                                        children: [
                                          Radio<String>(
                                            value: 'Male',
                                            groupValue: value,
                                            onChanged: (v) {
                                              child['gender'].value = v;
                                            },
                                            activeColor: Colors.black,
                                          ),
                                          const Text(
                                            'Male',
                                            style: TextStyle(
                                              fontFamily: 'Comfortaa',
                                              color: Colors.black,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Radio<String>(
                                            value: 'Female',
                                            groupValue: value,
                                            onChanged: (v) {
                                              child['gender'].value = v;
                                            },
                                            activeColor: Colors.black,
                                          ),
                                          const Text(
                                            'Female',
                                            style: TextStyle(
                                              fontFamily: 'Comfortaa',
                                              color: Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Health Information
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: child['health'],
                                  hintText: 'Health Information',
                                  icon: Icons.favorite_border,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addChild,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Add more',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Comfortaa',
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Centered Scan face button
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: GestureDetector(
                        onTap: () {
                          // Claim the camera for Nanny Mode scan
                          CameraService().setActivePreview('Nanny Scan');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const NannyModeScanPage(),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/face-id.png',
                              width: 40,
                              height: 40,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Scan face',
                              style: TextStyle(
                                fontFamily: 'Comfortaa',
                                color: Colors.black,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Nanny icon overlapping the card (top right, always on top)
          Positioned(
            top: 50,
            right: -1,
            child: Image.asset(
              'assets/images/babysitter.png',
              width: 150,
              height: 150,
            ),
          ),
          // Back button (highest z-index)
          Positioned(
            top: 126,
            left: 38,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const SmartHomePage(),
                  ),
                  (route) => false,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                child: Text(
                  '<  Back',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Comfortaa',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
