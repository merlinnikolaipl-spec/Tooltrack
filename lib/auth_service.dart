import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// ===============================
/// AUTH SERVICE (Email + Google)
/// - Android/iOS: google_sign_in
/// - Windows: OAuth in browser via flutter_web_auth_2 + localhost redirect
/// ===============================
class AuthService {
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  // ==========================================================
  // ✅ ВСТАВЬ СЮДА СВОЙ OAuth Desktop Client (Windows)
  // Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client IDs → Desktop app
  // ==========================================================
  static const String windowsClientId = '242560270718-ene4r0ekee3o2i0ut1in1k84q6mtorbc.apps.googleusercontent.com';
  static const String windowsClientSecret = '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';

  // localhost callback (ВАЖНО: без webview, чтобы не требовать доп. настройки WebView2)
  static const String _winRedirectUri = 'http://localhost:43823/';
  static const String _winCallbackUrlScheme = 'http://localhost:43823';

  /// Email register
  static Future<UserCredential> registerEmail(String email, String password) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    }

  /// Email login
  static Future<UserCredential> loginEmail(String email, String password) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Logout (везде)
  static Future<void> logout() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  /// Google login (маршрутизация по платформам)
  static Future<void> loginGoogle() async {
    if (isWindows) {
      await loginGoogleWindows();
    } else {
      await loginGoogleMobile();
    }
  }

  /// Google login for Android/iOS
  static Future<void> loginGoogleMobile() async {
    final googleSignIn = GoogleSignIn(scopes: const ['email']);
    try {
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) return;

      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      throw Exception('Google login (mobile) failed: $e');
    }
  }

  /// Google login for Windows (OAuth code -> token -> Firebase credential)
  static Future<void> loginGoogleWindows() async {
    if (windowsClientId.startsWith('PASTE_HERE')) {
      throw Exception(
        'Не вставлен OAuth Desktop Client.\n'
        'Открой lib/auth_service.dart и вставь windowsClientId / windowsClientSecret (локально, не в чат).',
      );
    }

    try {
      // 1) open Google auth page
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'response_type': 'code',
        'client_id': windowsClientId,
        'redirect_uri': _winRedirectUri,
        'scope': 'openid email profile',
        'access_type': 'offline',
        'prompt': 'select_account',
      });

      // IMPORTANT: useWebview:false => callbackUrlScheme must be http://localhost:PORT
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: _winCallbackUrlScheme,
        options: const FlutterWebAuth2Options(useWebview: false),
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw Exception('Google OAuth не вернул code.');
      }

      // 2) exchange code for tokens
      final tokenUrl = Uri.https('oauth2.googleapis.com', '/token');
      final tokenResp = await http.post(tokenUrl, headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      }, body: {
        'code': code,
        'client_id': windowsClientId,
        'client_secret': windowsClientSecret, // desktop client secret
        'redirect_uri': _winRedirectUri,
        'grant_type': 'authorization_code',
      });

      if (tokenResp.statusCode < 200 || tokenResp.statusCode >= 300) {
        throw Exception(
          'Token exchange failed (${tokenResp.statusCode}).\n${tokenResp.body}',
        );
      }

      final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final idToken = (tokenJson['id_token'] ?? '').toString();
      final accessToken = (tokenJson['access_token'] ?? '').toString();

      if (idToken.isEmpty) {
        throw Exception('Google token endpoint не вернул id_token.');
      }

      // 3) sign into Firebase using Google credential
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken.isEmpty ? null : accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      throw Exception('Google login (Windows) failed: $e');
    }
  }
}
