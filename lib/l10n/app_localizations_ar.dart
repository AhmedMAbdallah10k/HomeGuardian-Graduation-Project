// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get settings => 'الإعدادات';

  @override
  String get securityAndBiometrics => 'الأمان والقياسات الحيوية';

  @override
  String get manageNotifications => 'إدارة الإشعارات';

  @override
  String get languageSettings => 'إعدادات اللغة';

  @override
  String get chooseLanguage => 'اختر اللغة';

  @override
  String get english => 'الإنجليزية';

  @override
  String get arabic => 'العربية';

  @override
  String get appTheme => 'مظهر التطبيق';

  @override
  String get savedOnDeviceOnly =>
      'تم حفظ اللغة على هذا الجهاز فقط. يمكن لمالك المنزل فقط تحديث لغة المنزل لجميع الأجهزة.';

  @override
  String get languageUpdated => 'تم تحديث اللغة';

  @override
  String get couldNotSaveLanguage => 'تعذّر حفظ اللغة. حاول مرة أخرى.';
}
