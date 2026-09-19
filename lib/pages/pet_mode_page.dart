import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';

import 'home_page.dart';

class PetModePage extends StatefulWidget {
  const PetModePage({Key? key}) : super(key: key);

  @override
  State<PetModePage> createState() => _PetModePageState();
}

class _PetModePageState extends State<PetModePage> {
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  // Initial list of pet data
  final List<Map<String, dynamic>> pets = [
    {
      'name': TextEditingController(),
      'age': TextEditingController(),
      'gender': ValueNotifier<String?>(null),
      'pregnant': ValueNotifier<String?>(null),
      'type': TextEditingController(),
      'notes': TextEditingController(),
      'photos': <File>[], // Added for photo storage
    },
  ];

  @override
  void dispose() {
    for (var pet in pets) {
      (pet['name'] as TextEditingController).dispose();
      (pet['age'] as TextEditingController).dispose();
      (pet['type'] as TextEditingController).dispose();
      (pet['notes'] as TextEditingController).dispose();
      (pet['gender'] as ValueNotifier).dispose();
      (pet['pregnant'] as ValueNotifier).dispose();
    }
    super.dispose();
  }

  void _addPet() {
    setState(() {
      pets.add({
        'name': TextEditingController(),
        'age': TextEditingController(),
        'gender': ValueNotifier<String?>(null),
        'pregnant': ValueNotifier<String?>(null),
        'type': TextEditingController(),
        'notes': TextEditingController(),
        'photos': <File>[],
      });
    });
  }

  Future<void> _pickImage(int index) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      setState(() {
        (pets[index]['photos'] as List<File>).add(File(pickedFile.path));
      });
    }
  }

  Future<void> _savePets() async {
    setState(() => _isSaving = true);
    try {
      final token = await AuthService().getToken();

      for (var pet in pets) {
        final name = (pet['name'] as TextEditingController).text;
        final age = (pet['age'] as TextEditingController).text;
        final type = (pet['type'] as TextEditingController).text;
        final photos = pet['photos'] as List<File>;

        if (name.isEmpty) continue;

        List<String> base64Photos = [];
        for (var photo in photos) {
          final bytes = await photo.readAsBytes();
          base64Photos.add(base64Encode(bytes));
        }

        final response = await http.post(
          Uri.parse('${AuthService.baseUrl}/api/pets'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'name': name,
            'age': age,
            'breed': type,
            'photos': base64Photos,
          }),
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to save pet $name');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pets saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving pets: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Adapted TextField Builder from NannyModePage
  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
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

  // New Radio Button Builder for Gender and Pregnant options
  Widget _buildRadioOption({
    required ValueNotifier<String?> notifier,
    required String label,
    required String valueMale,
    required String valueFemale,
  }) {
    return ValueListenableBuilder<String?>(
      valueListenable: notifier,
      builder: (context, value, _) => Row(
        children: [
          const SizedBox(width: 24),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Comfortaa',
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 24),
          Row(
            children: [
              Radio<String>(
                value: valueMale,
                groupValue: value,
                onChanged: (v) => notifier.value = v,
                activeColor: Colors.black,
              ),
              Text(
                valueMale,
                style: const TextStyle(
                  fontFamily: 'Comfortaa',
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Radio<String>(
                value: valueFemale,
                groupValue: value,
                onChanged: (v) => notifier.value = v,
                activeColor: Colors.black,
              ),
              Text(
                valueFemale,
                style: const TextStyle(
                  fontFamily: 'Comfortaa',
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
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
                      'Pet Mode',
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
                      itemCount: pets.length,
                      itemBuilder: (context, idx) {
                        final pet = pets[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            children: [
                              // Pet Name
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: pet['name'],
                                  hintText: "Pet Name",
                                  icon: Icons.pets_outlined,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Age
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: pet['age'],
                                  hintText: 'Age',
                                  icon: Icons.cake_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Gender (Male/Female)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildRadioOption(
                                  notifier: pet['gender'],
                                  label: 'Gender',
                                  valueMale: 'Male',
                                  valueFemale: 'Female',
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Pregnant (Yes/No)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildRadioOption(
                                  notifier: pet['pregnant'],
                                  label: 'Pregnant',
                                  valueMale: 'Yes',
                                  valueFemale: 'No',
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Type of the pet
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: pet['type'],
                                  hintText: 'Type of the pet',
                                  icon: Icons.sort,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Additional Notes
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: pet['notes'],
                                  hintText: 'Additional Notes',
                                  icon: Icons.note_outlined,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Photo section
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pet Photos',
                                      style: TextStyle(
                                        fontFamily: 'Comfortaa',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        ...(pet['photos'] as List<File>)
                                            .map(
                                              (file) => ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.file(
                                                  file,
                                                  width: 60,
                                                  height: 60,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        GestureDetector(
                                          onTap: () => _pickImage(idx),
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[300],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.add_a_photo,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Save button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 4.0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _savePets,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Save All Pets',
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
                  // Add more button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addPet,
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
                  // Centered Scan button
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: GestureDetector(
                        onTap: () async {
                          final result = await Navigator.of(
                            context,
                          ).pushNamed('/pet_mode_scan');
                          if (result is File && mounted) {
                            setState(() {
                              // Add the scanned photo to the first pet if it exists
                              if (pets.isNotEmpty) {
                                (pets[0]['photos'] as List<File>).add(result);
                              }
                            });
                          }
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
                              'Scan Pet',
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
          // Pet icon overlapping the card (top right, always on top)
          Positioned(
            top: 50,
            right: 20,
            child: Image.asset(
              'assets/images/pets.png',
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
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                child: Text(
                  '< Back',
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
