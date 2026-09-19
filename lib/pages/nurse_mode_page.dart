import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import 'home_page.dart'; // Assume this file exists
import 'nurse_mode_scan_page.dart'; // Create this file or update path

// Placeholder for the scan page if it doesn't exist yet
// class NurseModeScanPage extends StatelessWidget {
//   const NurseModeScanPage({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return const Scaffold(
//       body: Center(child: Text('Nurse Mode Scan Page')),
//     );
//   }
// }

class NurseModePage extends StatefulWidget {
  const NurseModePage({Key? key}) : super(key: key);

  @override
  State<NurseModePage> createState() => _NurseModePageState();
}

class _NurseModePageState extends State<NurseModePage> {
  // List to hold data for multiple patients (if "Add more" is used)
  final List<Map<String, dynamic>> patients = [
    {
      'name': TextEditingController(),
      'age': TextEditingController(),
      'gender': ValueNotifier<String?>(null),
      'healthCondition': TextEditingController(),
      'mobilityStatus': ValueNotifier<String?>(
        'Walk normally',
      ), // Default value
      'healthRiskLevel': ValueNotifier<String?>('Low'), // Default value
      'medicationTime': TextEditingController(),
    },
  ];

  // Dropdown options
  final List<String> _mobilityStatuses = [
    'Walk normally',
    'Limited movement',
    'Wheelchair user',
  ];
  final List<String> _healthRiskLevels = ['Low', 'Medium', 'High'];

  @override
  void dispose() {
    for (var patient in patients) {
      (patient['name'] as TextEditingController).dispose();
      (patient['age'] as TextEditingController).dispose();
      (patient['healthCondition'] as TextEditingController).dispose();
      (patient['medicationTime'] as TextEditingController).dispose();
      (patient['gender'] as ValueNotifier).dispose();
      (patient['mobilityStatus'] as ValueNotifier).dispose();
      (patient['healthRiskLevel'] as ValueNotifier).dispose();
    }
    super.dispose();
  }

  void _addPatient() {
    setState(() {
      patients.add({
        'name': TextEditingController(),
        'age': TextEditingController(),
        'gender': ValueNotifier<String?>(null),
        'healthCondition': TextEditingController(),
        'mobilityStatus': ValueNotifier<String?>('Walk normally'),
        'healthRiskLevel': ValueNotifier<String?>('Low'),
        'medicationTime': TextEditingController(),
      });
    });
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
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

  Widget _buildDropdownField({
    required ValueNotifier<String?> valueNotifier,
    required List<String> items,
    required String labelText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ValueListenableBuilder<String?>(
        valueListenable: valueNotifier,
        builder: (context, value, _) {
          return DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: Text(
                labelText,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Comfortaa',
                ),
              ),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Comfortaa',
                color: Colors.black,
              ),
              dropdownColor: Colors.white,
              onChanged: (String? newValue) {
                valueNotifier.value = newValue;
              },
              items: items.map<DropdownMenuItem<String>>((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              }).toList(),
            ),
          );
        },
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
                      'Nurse Mode',
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
                      itemCount: patients.length,
                      itemBuilder: (context, idx) {
                        final patient = patients[idx];
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
                                  controller: patient['name'],
                                  hintText: "Full Name",
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
                                  controller: patient['age'],
                                  hintText: 'Age',
                                  icon: Icons.calendar_today_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Gender (Radio buttons)
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
                                      valueListenable: patient['gender'],
                                      builder: (context, value, _) => Row(
                                        children: [
                                          Radio<String>(
                                            value: 'Male',
                                            groupValue: value,
                                            onChanged: (v) {
                                              patient['gender'].value = v;
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
                                              patient['gender'].value = v;
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
                              // Health Condition
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: patient['healthCondition'],
                                  hintText: 'Health Condition',
                                  icon: Icons.favorite_border,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Mobility Status (styled like image)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 4,
                                ),
                                child: Row(
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
                                    const SizedBox(width: 24),
                                    ValueListenableBuilder<String?>(
                                      valueListenable:
                                          patient['mobilityStatus'],
                                      builder: (context, value, _) => SizedBox(
                                        width: 170,
                                        child: Container(
                                          height: 36,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: value,
                                              icon: const Icon(
                                                Icons.arrow_drop_down,
                                                size: 22,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontFamily: 'Comfortaa',
                                                fontWeight: FontWeight.w400,
                                                fontSize: 16,
                                              ),
                                              dropdownColor: Colors.white,
                                              alignment: Alignment.center,
                                              isExpanded: true,
                                              selectedItemBuilder: (context) =>
                                                  _mobilityStatuses
                                                      .map(
                                                        (item) => Center(
                                                          child: Text(
                                                            item,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                  fontFamily:
                                                                      'Comfortaa',
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w400,
                                                                  fontSize: 16,
                                                                ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              items: _mobilityStatuses
                                                  .map(
                                                    (item) => DropdownMenuItem(
                                                      value: item,
                                                      child: Center(
                                                        child: Text(item),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) =>
                                                  patient['mobilityStatus']
                                                          .value =
                                                      v,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Health Risk Level (styled like image)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Health Risk Level',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontFamily: 'Comfortaa',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    ValueListenableBuilder<String?>(
                                      valueListenable:
                                          patient['healthRiskLevel'],
                                      builder: (context, value, _) => SizedBox(
                                        width: 170,
                                        child: Container(
                                          height: 36,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: value,
                                              icon: const Icon(
                                                Icons.arrow_drop_down,
                                                size: 22,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontFamily: 'Comfortaa',
                                                fontWeight: FontWeight.w400,
                                                fontSize: 16,
                                              ),
                                              dropdownColor: Colors.white,
                                              alignment: Alignment.center,
                                              isExpanded: true,
                                              selectedItemBuilder: (context) =>
                                                  _healthRiskLevels
                                                      .map(
                                                        (item) => Center(
                                                          child: Text(
                                                            item,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                  fontFamily:
                                                                      'Comfortaa',
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w400,
                                                                  fontSize: 16,
                                                                ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              items: _healthRiskLevels
                                                  .map(
                                                    (item) => DropdownMenuItem(
                                                      value: item,
                                                      child: Center(
                                                        child: Text(item),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) =>
                                                  patient['healthRiskLevel']
                                                          .value =
                                                      v,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Medication Time
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: _buildStyledTextField(
                                  controller: patient['medicationTime'],
                                  hintText: 'Medication Time',
                                  icon: Icons.access_time_outlined,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
                        onPressed: _addPatient,
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
                          // Claim the camera for Nurse Mode scan
                          CameraService().setActivePreview('Nurse Scan');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const NurseModeScanPage(),
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
          // Nurse icon overlapping the card (top right, always on top)
          Positioned(
            top: 50,
            right: -1,
            child: Image.asset(
              'assets/images/nurse.png', // Using the specified asset name
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
                  '<  Back',
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