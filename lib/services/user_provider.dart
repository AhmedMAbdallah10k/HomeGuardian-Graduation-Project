import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import 'app_locale.dart';

class UserProvider with ChangeNotifier {
  User? _user;
  UserOptions? _options;

  User? get user => _user;
  UserOptions? get options => _options;
  bool get isAuthenticated => _user != null;

  /// Pop-up banners while using the app (WebSocket). Independent of FCM/email.
  bool get inAppAlertsEnabled => _options?.inAppAlertsEnabled ?? true;

  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  void setOptions(UserOptions options) {
    _options = options;
    notifyListeners();
    unawaited(initAppLanguageFromServerIfNeeded(options.language));
  }

  void clear() {
    _user = null;
    _options = null;
    notifyListeners();
  }
}
