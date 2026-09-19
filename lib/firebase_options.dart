// Run: dart pub global activate flutterfire_cli && flutterfire configure
// Then replace this file, or paste values from Firebase Console → Project settings.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyALCD09mAzriidsmGIlpwqlVYXtkTY6BAE',
    appId: '1:661377955795:android:5aee28f74c407182bb6126',
    messagingSenderId: '661377955795',
    projectId: 'homeguardian-98387',
    storageBucket: 'homeguardian-98387.firebasestorage.app',
  );

  /// Add an iOS app in Firebase and run `flutterfire configure`, or paste values from
  /// `GoogleService-Info.plist` before building for iPhone/iPad.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_IOS_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '661377955795',
    projectId: 'homeguardian-98387',
    storageBucket: 'homeguardian-98387.firebasestorage.app',
    iosBundleId: 'com.example.flutterApplication1',
  );
}
