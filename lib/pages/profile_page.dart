import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _birthController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _gender;
  bool _loading = true;
  String? _photoUrl;
  bool _isFamily = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final cached = Provider.of<UserProvider>(context, listen: false).user;
    if (cached != null) {
      _applyUser(cached);
    }

    final res = await AuthService().getUserProfile();
    if (!mounted) return;

    if (res['success'] == true && res['user'] is Map) {
      final map = Map<String, dynamic>.from(res['user'] as Map);
      final u = User.fromJson(map);
      if (mounted) {
        context.read<UserProvider>().setUser(u);
        _applyUser(u);
      }
    } else if (mounted && cached == null) {
      setState(() => _loading = false);
    }
  }

  void _applyUser(User u) {
    setState(() {
      _nameController.text = u.name;
      _emailController.text = u.email;
      _phoneController.text = u.phone ?? '';
      _isFamily = u.isFamilyMember;
      _photoUrl = AuthService().buildPhotoUrl(u.profileImage);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _birthController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
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
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 28,
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
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.black))
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 30),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: ClipOval(
                                      child: _buildAvatar(),
                                    ),
                                  ),
                                ),
                                if (!_isFamily)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                                        ],
                                      ),
                                      child: const Icon(Icons.edit, size: 16, color: Colors.black),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 30),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                children: [
                                  _buildProfileField(
                                    controller: _nameController,
                                    icon: Icons.person_outline,
                                    hintText: 'Name',
                                    readOnly: _isFamily,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildProfileField(
                                    controller: _emailController,
                                    icon: Icons.email_outlined,
                                    hintText: 'Email',
                                    readOnly: _isFamily,
                                  ),
                                  const SizedBox(height: 20),
                                  if (!_isFamily)
                                    Row(
                                      children: [
                                        const Text(
                                          'Gender',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Comfortaa',
                                            color: Colors.black,
                                          ),
                                        ),
                                        const Spacer(),
                                        Radio<String>(
                                          value: 'Male',
                                          groupValue: _gender,
                                          onChanged: (val) {
                                            setState(() {
                                              _gender = val;
                                            });
                                          },
                                          activeColor: Colors.black,
                                        ),
                                        const Text(
                                          'Male',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontFamily: 'Comfortaa',
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Radio<String>(
                                          value: 'Female',
                                          groupValue: _gender,
                                          onChanged: (val) {
                                            setState(() {
                                              _gender = val;
                                            });
                                          },
                                          activeColor: Colors.black,
                                        ),
                                        const Text(
                                          'Female',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontFamily: 'Comfortaa',
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (!_isFamily) const SizedBox(height: 20),
                                  if (!_isFamily)
                                    _buildProfileField(
                                      controller: _birthController,
                                      icon: Icons.calendar_today_outlined,
                                      hintText: 'Birth Date',
                                    ),
                                  if (!_isFamily) const SizedBox(height: 16),
                                  _buildProfileField(
                                    controller: _phoneController,
                                    icon: Icons.phone_android_outlined,
                                    hintText: 'Phone Number',
                                    readOnly: _isFamily,
                                  ),
                                  if (_isFamily) ...[
                                    const SizedBox(height: 20),
                                    Text(
                                      'Details come from your home enrollment. Contact the owner to update.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Comfortaa',
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final url = _photoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/boy.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person, size: 60, color: Colors.grey),
        ),
      );
    }
    return Image.asset(
      'assets/images/boy.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.person, size: 60, color: Colors.grey),
    );
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    bool readOnly = false,
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
        readOnly: readOnly,
        style: const TextStyle(
          fontFamily: 'Comfortaa',
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Comfortaa'),
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
