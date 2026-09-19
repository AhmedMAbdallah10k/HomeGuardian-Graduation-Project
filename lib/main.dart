import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/user_provider.dart';
import 'services/camera_service.dart';
import 'services/push_notification_service.dart';
import 'services/app_locale.dart';
import 'services/auth_service.dart';
import 'services/event_notifier.dart';
import 'services/in_app_alert_service.dart';
import 'widgets/auth_wrapper.dart';
import 'pages/start_page.dart';
import 'pages/pet_mode_page.dart';
import 'pages/pet_mode_scan_page.dart';
import 'pages/home_alone_mode_page.dart';

// Global notifier for theme mode - preserved from new UI design
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.bootstrapNetworkFromPrefs();
  await loadAppLocaleFromPrefs();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService.init();
  } catch (e) {
    debugPrint(
      'Firebase / push init failed — configure firebase_options.dart '
      'and android/app/google-services.json: $e',
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => EventNotifier()),
      ],
      child: const SmartHomeApp(),
    ),
  );
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, currentMode, child) {
            return MaterialApp(
              navigatorKey: rootNavigatorKey,
              title: 'Smart Home Management',
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              themeMode: currentMode,
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: Colors.black,
                scaffoldBackgroundColor: const Color(0xFFF5F5F5),
                fontFamily: 'Comfortaa', // HomeGuardian signature font
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primaryColor: Colors.white,
                scaffoldBackgroundColor: const Color(0xFF121212),
                fontFamily: 'Comfortaa',
              ),
              // CHANGE THIS LINE: true for Dashboard, false for Mobile App
              home: const AuthWrapper(isDashboard: true),
              routes: {
                '/pet_mode': (context) => const PetModePage(),
                '/pet_mode_scan': (context) => const PetModeScanPage(),
                '/home_alone_mode': (context) => const HomeAloneModePage(),
                '/start': (context) => const StartPage(),
              },
            );
          },
        );
      },
    );
  }
}
