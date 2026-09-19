import 'package:flutter/material.dart';

class AddMoreModesPage extends StatefulWidget {
  const AddMoreModesPage({Key? key}) : super(key: key);

  @override
  State<AddMoreModesPage> createState() => _AddMoreModesPageState();
}

class _AddMoreModesPageState extends State<AddMoreModesPage> {
  // Track selected modes
  final List<bool> _selected = List.generate(5, (_) => false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40), // Spacing for the curve
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      children: [
                        _buildModeCard(
                          0,
                          'Silver Mode',
                          'Keep grandparents safe',
                          'assets/images/grandparents.png',
                        ),
                        _buildModeCard(
                          1,
                          'Nanny Mode',
                          'Watch the kids',
                          'assets/images/babysitter.png',
                        ),
                        _buildModeCard(
                          2,
                          'Nurse Mode',
                          'Recovery after injury or surgery',
                          'assets/images/nurse.png',
                        ),
                        _buildModeCard(
                          3,
                          'Pet Mode',
                          'Keep pets out of trouble',
                          'assets/images/pets.png',
                        ),
                        _buildModeCard(
                          4,
                          'Home alone Mode',
                          'Secure in empty home',
                          'assets/images/house.png',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 24.0,
                      right: 24.0,
                      bottom: 40.0,
                      top: 10.0
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          // Action for "Add" button - for now just pop or show a success message
                          // User didn't specify exact behavior, but usually it adds the selected modes.
                          // For UI purpose, we just pop back.
                           Navigator.of(context).pop(); 
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Comfortaa',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Custom Header
          Positioned(
            top: 0, 
            left: 0,
            right: 0,
            height: 100,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Add more Modes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Comfortaa',
                        ),
                      ),
                    ),
                     const SizedBox(width: 40), // Balance the back button
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(int index, String title, String subtitle, String assetPath) {
    bool isSelected = _selected[index];
    return GestureDetector(
      onTap: () {
        setState(() {
          _selected[index] = !isSelected;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.grey.shade400, // Always grey border for checkbox like mockup
                    width: 1.5,
                  ),
                   // Mockup shows checkmark inside the box, so we can use standard check or just boolean toggle logic
                  color: Colors.transparent,
                ),
                 child: isSelected
                    ? const Icon(Icons.check, size: 18, color: Colors.black)
                    : null,
              ),
            ),
            const Spacer(flex: 1),
            Image.asset(
              assetPath,
              height: 60,
              width: 60,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.grey.shade400,
                fontFamily: 'Comfortaa',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black,
                fontFamily: 'Comfortaa',
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
