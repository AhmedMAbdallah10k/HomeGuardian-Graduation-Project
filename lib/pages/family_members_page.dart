import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'edit_member_page.dart';
import 'register_family_members_page.dart';

/// Real, data-driven Family Members page.
/// Fetches the user's enrolled family members and their live At-Home / Away status,
/// supports navigating to an Edit page, and adding new members.
class FamilyMembersPage extends StatefulWidget {
  const FamilyMembersPage({super.key});

  @override
  State<FamilyMembersPage> createState() => _FamilyMembersPageState();
}

class _FamilyMembersPageState extends State<FamilyMembersPage> {
  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic> _statusByName = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = AuthService();
    final results = await Future.wait([
      auth.getFamilyMembers(),
      auth.getFamilyStatus(),
    ]);

    if (!mounted) return;

    final membersResult = results[0];
    final statusResult = results[1];

    // Build a quick lookup: name -> status data
    final Map<String, dynamic> statusByName = {};
    final List statusList = (statusResult['data'] is List)
        ? statusResult['data']
        : (statusResult['members'] is List ? statusResult['members'] : []);
    for (final entry in statusList) {
      if (entry is Map && entry['name'] is String) {
        statusByName[entry['name'] as String] = entry;
      }
    }

    setState(() {
      _members = List<Map<String, dynamic>>.from(membersResult['members'] ?? []);
      _statusByName = statusByName;
      _isLoading = false;
      _error = (membersResult['success'] == true) ? null : membersResult['message']?.toString();
    });
  }

  Future<void> _openAddMember() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegisterFamilyMembersPage(isOnboarding: false),
      ),
    );
    if (mounted) _loadAll();
  }

  Future<void> _openMember(Map<String, dynamic> member) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditMemberPage(
          memberId: member['id'] as int,
          name: (member['name'] ?? '').toString(),
          relationship: (member['relationship'] ?? '').toString(),
          phone: (member['phone'] ?? '').toString(),
          photoUrl: AuthService().buildPhotoUrl(member['photo_path']?.toString()),
          hasAccount: member['has_account'] == true,
          invitePending: member['invite_pending'] == true,
        ),
      ),
    );
    if (mounted) _loadAll();
  }

  bool _isAtHome(String name) {
    final s = _statusByName[name];
    if (s == null) return false;
    final status = (s['status'] ?? '').toString();
    return status == 'At Home';
  }

  String _statusLabel(String name) {
    final s = _statusByName[name];
    if (s == null) return 'Status unknown';
    final status = (s['status'] ?? '').toString();
    if (status == 'At Home') return 'At Home';
    final lastSeen = s['last_seen'];
    if (lastSeen == null) return 'Not seen yet';
    return 'Away';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
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
              'Family Members',
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
    );
  }

  Widget _buildBody() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5F4),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
      ),
      child: RefreshIndicator(
        onRefresh: _loadAll,
        color: Colors.black,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: CircularProgressIndicator(color: Colors.black),
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) _buildErrorBanner(_error!),
                    _buildAvatarRow(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('All Members'),
                    const SizedBox(height: 12),
                    if (_members.isEmpty)
                      _buildEmptyState()
                    else ...[
                      for (final m in _members) ...[
                        _buildMemberCard(m),
                        const SizedBox(height: 10),
                      ],
                    ],
                    const SizedBox(height: 8),
                    _buildAddMemberCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade700,
                fontFamily: 'Comfortaa',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarRow() {
    final display = _members.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (final m in display) ...[
              _buildAvatarChip(m),
              const SizedBox(width: 18),
            ],
            _buildAddAvatarChip(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarChip(Map<String, dynamic> member) {
    final name = (member['name'] ?? '').toString();
    final photoUrl = AuthService().buildPhotoUrl(member['photo_path']?.toString());
    final atHome = _isAtHome(name);

    return GestureDetector(
      onTap: () => _openMember(member),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          width: 72,
                          height: 72,
                          errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                        )
                      : _avatarPlaceholder(),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: atHome ? Colors.green : Colors.grey.shade400,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 76,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Comfortaa',
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: const Color(0xFFEFEFEF),
      child: Icon(Icons.person, color: Colors.grey.shade400, size: 36),
    );
  }

  Widget _buildAddAvatarChip() {
    return GestureDetector(
      onTap: _openAddMember,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1.5,
                style: BorderStyle.solid,
              ),
            ),
            child: Icon(Icons.add, color: Colors.grey.shade500, size: 28),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            width: 76,
            child: Text(
              'Add',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Comfortaa',
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontFamily: 'Comfortaa',
          fontSize: 12,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    final name = (member['name'] ?? '').toString();
    final relationship = (member['relationship'] ?? '').toString();
    final photoUrl = AuthService().buildPhotoUrl(member['photo_path']?.toString());
    final atHome = _isAtHome(name);
    final statusText = _statusLabel(name);

    return GestureDetector(
      onTap: () => _openMember(member),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFEFEFEF),
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 56,
                            height: 56,
                            errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                          )
                        : _avatarPlaceholder(),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: atHome ? Colors.green : Colors.grey.shade400,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Comfortaa',
                      fontSize: 15,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    relationship.isNotEmpty ? relationship : '—',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontFamily: 'Comfortaa',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: atHome ? Colors.green : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: atHome ? Colors.green.shade700 : Colors.grey.shade500,
                          fontFamily: 'Comfortaa',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMemberCard() {
    return GestureDetector(
      onTap: _openAddMember,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Add Family Member',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Comfortaa',
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, color: Colors.grey.shade300, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No family members yet',
            style: TextStyle(
              color: Colors.black,
              fontFamily: 'Comfortaa',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add the people you live with so the\nsystem can recognize them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontFamily: 'Comfortaa',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
