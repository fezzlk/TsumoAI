import 'package:flutter/foundation.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static const _webClientId =
      '1046222816103-ng2ftbh5iq3t332bedaome0nucnhqn5o.apps.googleusercontent.com';
  static const _iosClientId =
      '1046222816103-es2vkl6tvapbqlkk8g3bfmeo21ps1rvm.apps.googleusercontent.com';
  static bool _initialized = false;

  static User? get currentUser =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  static Stream<User?> authStateChanges() => Firebase.apps.isEmpty
      ? Stream<User?>.value(null)
      : FirebaseAuth.instance.authStateChanges();

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    await GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? _iosClientId
          : null,
      serverClientId: _webClientId,
    );
    _initialized = true;
  }

  static Future<User> ensureSignedIn() async {
    final existing = currentUser;
    if (existing != null) return existing;

    await initialize();
    if (kIsWeb) {
      final result = await FirebaseAuth.instance.signInWithPopup(
        GoogleAuthProvider(),
      );
      final user = result.user;
      if (user == null) throw StateError('Googleログインに失敗しました');
      return user;
    }
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

  static Future<bool> isAdmin({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      final result = await user.getIdTokenResult(forceRefresh);
      return result.claims?['admin'] == true;
    } catch (_) {
      // Developer-only UI must fail closed when claims cannot be verified.
      return false;
    }
  }

  static Future<void> signOut() async {
    if (Firebase.apps.isEmpty) return;
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) await GoogleSignIn.instance.signOut();
  }
}
