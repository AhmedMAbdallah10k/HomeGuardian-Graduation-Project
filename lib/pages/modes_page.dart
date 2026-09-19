import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_page.dart';
import 'home_alone_mode_page.dart';

class ModesPage extends StatefulWidget {
  const ModesPage({Key? key}) : super(key: key);

  @override
  State<ModesPage> createState() => _ModesPageState();
}

class _ModesPageState extends State<ModesPage> {
  // Track selected modes
  final List<bool> _selected = List.generate(5, (_) => false);
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  final List<String> _modeNames = [
    'Silver Mode',
    'Nanny Mode',
    'Nurse Mode',
    'Pet Mode',
    'Home alone Mode',
  ];

  Future<void> _handleNext() async {
    if (!_selected.contains(true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one mode to continue.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get list of selected mode names
      List<String> selectedModeNames = [];
      for (int i = 0; i < _selected.length; i++) {
        if (_selected[i]) {
          selectedModeNames.add(_modeNames[i]);
        }
      }

      // Save to backend
      final result = await _authService.updateSelectedModes(selectedModeNames);

      if (result['success'] == true) {
        if (!mounted) return;
        
        // If "Home alone Mode" is selected, navigate to its configuration page
        if (selectedModeNames.contains('Home alone Mode')) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeAloneModePage()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const SmartHomePage()),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving modes: ${result['message']}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasSelection = _selected.contains(true);

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
                  const SizedBox(height: 80),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'What brings you to HomeGuardian?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Comfortaa',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
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
                      top: 10.0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasSelection
                              ? Colors.black
                              : Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Next',
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
          // Top header with the 3d_home image overlapping the card
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      height: 180,
                      width: 180,
                      child: Image.asset(
                        'assets/images/3d_home.png',
                        fit: BoxFit.contain,
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

  Widget _buildModeCard(
    int index,
    String title,
    String subtitle,
    String assetPath,
  ) {
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
                    color: isSelected ? Colors.black : Colors.grey.shade400,
                    width: 1.5,
                  ),
                  color: isSelected ? Colors.transparent : Colors.white,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 18, color: Colors.black)
                    : null,
              ),
            ),
            const Spacer(flex: 1),
            Image.asset(assetPath, height: 60, width: 60, fit: BoxFit.contain),
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
