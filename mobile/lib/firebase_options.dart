import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    throw UnsupportedError('TsumoAI Firebase supports Android and iOS only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBHkjZeT0eoh1pXrPTW_89VXccG1BdF18s',
    appId: '1:1046222816103:android:1a8e2318aa0bc2b315a5c2',
    messagingSenderId: '1046222816103',
    projectId: 'tsumoai',
    storageBucket: 'tsumoai.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyACoTlhqioMje0MfWcnIeKO7Wfnj-H2NSg',
    appId: '1:1046222816103:ios:6cb8355e4b4e4d9d15a5c2',
    messagingSenderId: '1046222816103',
    projectId: 'tsumoai',
    storageBucket: 'tsumoai.firebasestorage.app',
    iosBundleId: 'com.fezzlk.tsumoai',
    iosClientId: '1046222816103-es2vkl6tvapbqlkk8g3bfmeo21ps1rvm.apps.googleusercontent.com',
  );
}
