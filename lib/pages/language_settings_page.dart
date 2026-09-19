import 'package:flutter/material.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../services/app_locale.dart';
import '../services/auth_service.dart';
import '../services/user_provider.dart';

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  static const _codes = ['en', 'ar'];
  late String _code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code = normalizeLanguageCode(appLocaleNotifier.value.languageCode);
  }

  String _labelForCode(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context)!;
    return code == 'ar' ? l10n.arabic : l10n.english;
  }

  Future<void> _onLanguageSelected(String newCode) async {
    if (newCode == _code || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    final prev = _code;
    setState(() {
      _code = newCode;
      _busy = true;
    });

    final user = context.read<UserProvider>().user;
    final isFamily = user?.isFamilyMember ?? false;
    final canUseServer = user != null && !isFamily;

    await setAppLanguageCode(newCode);

    if (!mounted) return;

    if (canUseServer) {
      final auth = AuthService();
      final res = await auth.updateUserOptions({'language': newCode});
      if (!mounted) return;
      if (res['success'] == true && res['options'] != null) {
        context.read<UserProvider>().setOptions(
              UserOptions.fromJson(res['options'] as Map<String, dynamic>),
            );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.languageUpdated)),
        );
      } else {
        await setAppLanguageCode(prev);
        if (mounted) {
          setState(() => _code = prev);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['message']?.toString() ?? l10n.couldNotSaveLanguage,
              ),
            ),
          );
        }
      }
    } else {
      if (isFamily) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.savedOnDeviceOnly)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.languageUpdated)),
        );
      }
    }

    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      l10n.languageSettings,
                      style: const TextStyle(
                        fontSize: 24,
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
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F5F4),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(70)),
                ),
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _code,
                            isExpanded: true,
                            hint: Row(
                              children: [
                                Icon(Icons.language, color: Colors.grey[400]),
                                const SizedBox(width: 12),
                                Text(
                                  l10n.chooseLanguage,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontFamily: 'Comfortaa',
                                  ),
                                ),
                              ],
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.black,
                            ),
                            selectedItemBuilder: (BuildContext ctx) {
                              return _codes.map((c) {
                                return Row(
                                  children: [
                                    Icon(Icons.language,
                                        color: Colors.grey[700]),
                                    const SizedBox(width: 12),
                                    Text(
                                      _labelForCode(context, c),
                                      style: TextStyle(
                                        fontFamily: 'Comfortaa',
                                        fontSize: 16,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList();
                            },
                            items: _codes.map((c) {
                              return DropdownMenuItem<String>(
                                value: c,
                                child: Row(
                                  children: [
                                    const Icon(Icons.language,
                                        color: Colors.black54),
                                    const SizedBox(width: 12),
                                    Text(
                                      _labelForCode(context, c),
                                      style: const TextStyle(
                                        fontFamily: 'Comfortaa',
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v != null) _onLanguageSelected(v);
                                  },
                          ),
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
    );
  }
}
