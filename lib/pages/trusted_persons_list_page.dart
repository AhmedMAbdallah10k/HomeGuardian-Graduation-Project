import 'package:flutter/material.dart';
import 'edit_trusted_person_page.dart';
import 'new_trusted_person_page.dart';
import '../services/auth_service.dart';

class TrustedPersonsListPage extends StatefulWidget {
  const TrustedPersonsListPage({super.key});

  @override
  State<TrustedPersonsListPage> createState() => _TrustedPersonsListPageState();
}

class _TrustedPersonsListPageState extends State<TrustedPersonsListPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _persons = [];

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    setState(() => _loading = true);
    final result = await AuthService().getTrustedPersons();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _persons = List<Map<String, dynamic>>.from(
          result['trusted_persons'] ?? [],
        );
      }
    });
    if (result['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Failed to load trusted persons',
          ),
        ),
      );
    }
  }

  Future<void> _openAddPage() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const NewTrustedPersonPage()),
    );
    if (added == true) {
      _loadPersons();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
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
                        'Trusted Persons',
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
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF1F0),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(70),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(70),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _persons.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    'No trusted persons yet.\nAdd someone to receive emergency emails.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontFamily: 'Comfortaa',
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 40,
                                  left: 24,
                                  right: 24,
                                  bottom: 100,
                                ),
                                itemCount: _persons.length,
                                itemBuilder: (context, index) {
                                  final person = _persons[index];
                                  return _buildTrustedPersonItem(
                                    context,
                                    person,
                                  );
                                },
                              ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 30,
            child: ElevatedButton(
              onPressed: _openAddPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 5,
              ),
              child: const Text(
                'Add trusted person',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Comfortaa',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustedPersonItem(
    BuildContext context,
    Map<String, dynamic> person,
  ) {
    final name = person['name']?.toString() ?? 'Unknown';
    final role = person['relationship']?.toString() ?? '';
    final email = person['email']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.grey,
                  size: 40,
                ),
              ),
              Positioned(
                bottom: 2,
                left: 0,
                child: GestureDetector(
                  onTap: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => EditTrustedPersonPage(
                          personId: person['id'] as int,
                          name: name,
                          phone: person['phone']?.toString() ?? '',
                          email: email,
                          relationship: role,
                        ),
                      ),
                    );
                    if (updated == true) {
                      _loadPersons();
                    }
                  },
                  child: const Icon(
                    Icons.edit,
                    size: 22,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9E9E9E),
                    fontFamily: 'Comfortaa',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    fontFamily: 'Comfortaa',
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'Comfortaa',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
