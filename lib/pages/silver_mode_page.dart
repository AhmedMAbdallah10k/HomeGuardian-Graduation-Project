import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import 'silver_mode_scan_page.dart';
import 'home_page.dart';

class SilverModePage extends StatefulWidget {
  const SilverModePage({Key? key}) : super(key: key);

  @override
  State<SilverModePage> createState() => _SilverModePageState();
}

class _SilverModePageState extends State<SilverModePage> {
  final List<Map<String, dynamic>> persons = [
    {
      'fullName': TextEditingController(),
      'age': TextEditingController(),
      'gender': ValueNotifier<String?>(null),
      'health': TextEditingController(),
      'mobility': ValueNotifier('Walk normally'),
      'relationship': TextEditingController(),
    },
  ];

  @override
  void dispose() {
    for (var person in persons) {
      (person['fullName'] as TextEditingController).dispose();
      (person['age'] as TextEditingController).dispose();
      (person['health'] as TextEditingController).dispose();
      (person['relationship'] as TextEditingController).dispose();
      (person['gender'] as ValueNotifier).dispose();
      (person['mobility'] as ValueNotifier).dispose();
    }
    super.dispose();
  }

  void _addPerson() {
    setState(() {
      persons.add({
        'fullName': TextEditingController(),
        'age': TextEditingController(),
        'gender': ValueNotifier<String?>(null),
        'health': TextEditingController(),
        'mobility': ValueNotifier('Walk normally'),
        'relationship': TextEditingController(),
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
      style: const TextStyle(
        fontSize: 16,
        fontFamily: 'Comfortaa',
        color: Colors.black,
      ),
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
          Positioned(
            top: 40,
            left: 16,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const SmartHomePage(),
                  ),
                  (route) => false,
                );
              },
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back_ios_new,
                    size: 20,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Back to home',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Comfortaa',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                      top: 20.0,
                      bottom: 16.0,
                    ),
                    child: Text(
                      'Silver Mode',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: persons.length,
                      itemBuilder: (context, idx) {
                        final person = persons[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            children: [
                              // Full Name
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: person['fullName'],
                                  hintText: 'Full Name',
                                  icon: Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Age
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: person['age'],
                                  hintText: 'Age',
                                  icon: Icons.cake_outlined,
                                  keyboardType: TextInputType.number,
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
                                      valueListenable: person['gender'],
                                      builder: (context, value, _) => Row(
                                        children: [
                                          Radio<String>(
                                            value: 'Male',
                                            groupValue: value,
                                            onChanged: (v) =>
                                                person['gender'].value = v,
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
                                            onChanged: (v) =>
                                                person['gender'].value = v,
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
                              // Health Condition
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: person['health'],
                                  hintText: 'Health Condition',
                                  icon: Icons.favorite_border,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Mobility Status (centered with extra space)
                              SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Mobility Status',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontFamily: 'Comfortaa',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  ValueListenableBuilder<String>(
                                    valueListenable: person['mobility'],
                                    builder: (context, value, _) => Container(
                                      height: 36,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: value,
                                          icon: const Icon(
                                            Icons.arrow_drop_down,
                                            size: 22,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontFamily: 'Comfortaa',
                                            fontWeight: FontWeight.w400,
                                            fontSize: 16,
                                          ),
                                          dropdownColor: Colors.white,
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'Walk normally',
                                              child: Text('Walk normally'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Need assistance',
                                              child: Text('Need assistance'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Wheelchair',
                                              child: Text('Wheelchair'),
                                            ),
                                          ],
                                          onChanged: (v) =>
                                              person['mobility'].value =
                                                  v ?? 'Walk normally',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 18),
                              const SizedBox(height: 8),
                              // Relationship
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: person['relationship'],
                                  hintText: 'Relationship',
                                  icon: Icons.groups_outlined,
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
                        onPressed: _addPerson,
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
                          // Claim the camera for Silver Mode scan
                          CameraService().setActivePreview('Silver Scan');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const SilverModeScanPage(),
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
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Comfortaa',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Grandparents icon overlapping the card (top right) - always on top
          Positioned(
            top: 50,
            right: 10,
            child: Image.asset(
              'assets/images/grandparents.png',
              width: 140,
              height: 140,
            ),
          ),
          // Back button (highest z-index, styled like NannyModePage)
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
