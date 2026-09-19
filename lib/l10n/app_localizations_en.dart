// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get securityAndBiometrics => 'Security and Biometrics';

  @override
  String get manageNotifications => 'Manage Notifications';

  @override
  String get languageSettings => 'Language Settings';

  @override
  String get chooseLanguage => 'Choose Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'Arabic';

  @override
  String get appTheme => 'App Theme';

  @override
  String get savedOnDeviceOnly =>
      'Language saved on this device. Only the home owner can update the home language for all devices.';

  @override
  String get languageUpdated => 'Language updated';

  @override
  String get couldNotSaveLanguage => 'Could not save language. Try again.';
}
