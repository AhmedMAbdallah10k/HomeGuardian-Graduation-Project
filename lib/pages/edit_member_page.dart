import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Real edit page for a family member.
/// Loads the existing data, lets the user edit name/phone/relationship,
/// and supports deleting the member with a confirmation dialog.
class EditMemberPage extends StatefulWidget {
  final int memberId;
  final String name;
  final String relationship;
  final String phone;
  final String? photoUrl;
  final bool hasAccount;
  final bool invitePending;

  const EditMemberPage({
    super.key,
    required this.memberId,
    required this.name,
    this.relationship = '',
    this.phone = '',
    this.photoUrl,
    this.hasAccount = false,
    this.invitePending = false,
  });

  @override
  State<EditMemberPage> createState() => _EditMemberPageState();
}

class _EditMemberPageState extends State<EditMemberPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _relationshipController;

  bool _saving = false;
  bool _deleting = false;
  bool _inviteLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _phoneController = TextEditingController(text: widget.phone);
    _relationshipController = TextEditingController(text: widget.relationship);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    final newPhone = _phoneController.text.trim();
    final newRel = _relationshipController.text.trim();

    if (newName.isEmpty) {
      _toast('Name cannot be empty', isError: true);
      return;
    }

    setState(() => _saving = true);
    final result = await AuthService().updateFamilyMember(
      memberId: widget.memberId,
      name: newName != widget.name ? newName : null,
      relationship: newRel != widget.relationship ? newRel : null,
      phone: newPhone != widget.phone ? newPhone : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      _toast('Saved', isError: false);
      Navigator.of(context).pop(true);
    } else {
      _toast(result['message']?.toString() ?? 'Save failed', isError: true);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete this member?',
          style: TextStyle(
            fontFamily: 'Comfortaa',
            fontWeight: FontWeight.w700,
            color: Colors.black,
            fontSize: 18,
          ),
        ),
        content: Text(
          'This will remove ${widget.name} and all of their face recognition data. This action cannot be undone.',
          style: TextStyle(
            fontFamily: 'Comfortaa',
            color: Colors.grey.shade700,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Comfortaa', color: Colors.black),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'Comfortaa',
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final result = await AuthService().deleteFamilyMember(widget.memberId);

    if (!mounted) return;
    setState(() => _deleting = false);

    if (result['success'] == true) {
      _toast('Deleted', isError: false);
      Navigator.of(context).pop(true);
    } else {
      _toast(result['message']?.toString() ?? 'Delete failed', isError: true);
    }
  }

  Future<void> _generateInvite() async {
    setState(() => _inviteLoading = true);
    final r = await AuthService().regenerateFamilyInviteCode(widget.memberId);
    if (!mounted) return;
    setState(() => _inviteLoading = false);
    if (r['success'] == true) {
      final code = r['invite_code']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Invite code',
            style: TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.w700),
          ),
          content: SelectableText(
            code,
            style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(fontFamily: 'Comfortaa')),
            ),
          ],
        ),
      );
    } else {
      _toast(r['message']?.toString() ?? 'Could not create invite', isError: true);
    }
  }

  void _toast(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _saving || _deleting;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
                  child: Column(
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 28),
                      _buildInputField(
                        controller: _nameController,
                        hintText: 'Name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        controller: _relationshipController,
                        hintText: 'Relationship',
                        icon: Icons.people_outline,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        controller: _phoneController,
                        hintText: 'Phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      if (!widget.hasAccount) ...[
                        const SizedBox(height: 28),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mobile app login',
                                style: TextStyle(
                                  fontFamily: 'Comfortaa',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.invitePending
                                    ? 'An invite code is active. Generate a new code to replace it (the old code stops working).'
                                    : 'Generate an invite code so this person can sign in once from Log in → Family member.',
                                style: TextStyle(
                                  fontFamily: 'Comfortaa',
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _inviteLoading ? null : _generateInvite,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    side: const BorderSide(color: Colors.black, width: 1.2),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: _inviteLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text(
                                          'Show new invite code',
                                          style: TextStyle(fontFamily: 'Comfortaa'),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      _buildPrimaryButton(
                        label: _saving ? 'Saving...' : 'Save Changes',
                        onTap: disabled ? null : _save,
                        loading: _saving,
                      ),
                      const SizedBox(height: 14),
                      _buildDangerButton(
                        label: _deleting ? 'Deleting...' : 'Delete Member',
                        onTap: disabled ? null : _confirmDelete,
                        loading: _deleting,
                      ),
                      const SizedBox(height: 16),
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

  Widget _buildHeader() {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(60)),
      ),
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.center,
            child: Text(
              'Edit Member',
              style: TextStyle(
                fontSize: 26,
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
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: widget.photoUrl != null
            ? Image.network(
                widget.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback(),
              )
            : _avatarFallback(),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFFEFEFEF),
      child: Icon(Icons.person, color: Colors.grey.shade400, size: 60),
    );
  }

  Widget _buildInputField({
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: 'Comfortaa', color: Colors.black, fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400], fontFamily: 'Comfortaa'),
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildPrimaryButton({required String label, required VoidCallback? onTap, required bool loading}) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          disabledBackgroundColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Comfortaa',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildDangerButton({required String label, required VoidCallback? onTap, required bool loading}) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white60,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: Colors.red.shade200, width: 1.2),
          ),
          elevation: 0,
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.red.shade700, strokeWidth: 2),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Comfortaa',
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
      ),
    );
  }
}
