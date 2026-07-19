import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static const _webClientId =
      '1046222816103-ng2ftbh5iq3t332bedaome0nucnhqn5o.apps.googleusercontent.com';
  static const _iosClientId =
      '1046222816103-es2vkl6tvapbqlkk8g3bfmeo21ps1rvm.apps.googleusercontent.com';
  static bool _initialized = false;

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  static Future<void> initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? _iosClientId : null,
      serverClientId: _webClientId,
    );
    _initialized = true;
  }

  static Future<User> ensureSignedIn() async {
    final existing = currentUser;
    if (existing != null) return existing;

    await initialize();
    final account = await GoogleSignIn.instance.authenticate();
    final googleAuth = account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in did not return an ID token.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw StateError('Firebase sign-in failed.');
    return user;
  }

  static Future<String> idToken({bool interactive = false}) async {
    final user = interactive ? await ensureSignedIn() : currentUser;
    if (user == null) throw StateError('Google login is required.');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Firebase ID token is unavailable.');
    return token;
  }

  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }
}
