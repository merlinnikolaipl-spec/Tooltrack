import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// ============================================================
// GPS Service v3 Ã¢ÂÂ idToken from SharedPreferences + HTTP REST
// No dependency on Firebase Auth in background isolate
// Firestore rules: ios_debug_logs open, locations open (if true)
// ============================================================

const _projectId = 'tooltrack-ee0aa';
const _apiKey = 'AIzaSyBWM0gMgkuMr5eAtbET1OtQn08Ld3_7cnI';
const _firestoreBase =
        'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

String? _cachedToken;
String? _cachedRefreshToken;
DateTime? _tokenExpiry;
DateTime? _lastWriteTime;

// Ã¢ÂÂÃ¢ÂÂ Token management Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ

Future<String?> _getToken() async {
      // Return cached token if still valid (5 min buffer)
      if (_cachedToken != null &&
                _tokenExpiry != null &&
                DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
              return _cachedToken;
      }
      // Try to refresh
      if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
              final newToken = await _refreshToken(_cachedRefreshToken!);
              if (newToken != null) return newToken;
      }
      return _cachedToken; // return expired token as fallback (rules open anyway)
}

Future<String?> _refreshToken(String refreshToken) async {
      try {
              final resp = await http
                          .post(
                            Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
                            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                            body: 'grant_type=refresh_token&refresh_token=$refreshToken',
                          )
                          .timeout(const Duration(seconds: 10));
              if (resp.statusCode == 200) {
                        final data = jsonDecode(resp.body);
                        _cachedToken = data['id_token'] as String?;
                        _cachedRefreshToken = data['refresh_token'] as String?;
                        final expiresIn = int.tryParse(data['expires_in']?.toString() ?? '3600') ?? 3600;
                        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
                        // Save refreshed token back to prefs
                        final prefs = await SharedPreferences.getInstance();
                        if (_cachedToken != null) await prefs.setString('shift_idToken', _cachedToken!);
                        if (_cachedRefreshToken != null) await prefs.setString('shift_refreshToken', _cachedRefreshToken!);
                                  await prefs.setString('shift_tokenExpiry', DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String());
                        return _cachedToken;
              }
      } catch (_) {}
      return null;
}

Map<String, String> _authHeaders({String? token}) {
      final headers = <String, String>{'Content-Type': 'application/json'};
      final t = token ?? _cachedToken;
      if (t != null && t.isNotEmpty) headers['Authorization'] = 'Bearer $t';
      return headers;
}

// Ã¢ÂÂÃ¢ÂÂ Logging Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ

Future<void> _log(String tag, String msg, {String? err}) async {
      final now = DateTime.now().toUtc().toIso8601String();
      // 1) Always write to SharedPreferences
      try {
              final prefs = await SharedPreferences.getInstance();
              final logs = prefs.getStringList('debug_log') ?? [];
              logs.add('$now [$tag] $msg${err != null ? " ERR: $err" : ""}');
              if (logs.length > 300) logs.removeRange(0, logs.length - 300);
              await prefs.setStringList('debug_log', logs);
      } catch (_) {}

      // 2) Write to Firestore ios_debug_logs via HTTP (rules open Ã¢ÂÂ no auth needed)
      try {
              final body = jsonEncode({
                        'fields': {
                                    'tag': {'stringValue': tag},
                                    'msg': {'stringValue': msg},
                                    'err': {'stringValue': err ?? ''},
                                    'ts': {'stringValue': now},
                                    'platform': {'stringValue': Platform.operatingSystem},
                        }
              });
              await http
                          .post(
                            Uri.parse('$_firestoreBase/ios_debug_logs'),
                            headers: {'Content-Type': 'application/json'},
                            body: body,
                          )
                          .timeout(const Duration(seconds: 8));
      } catch (_) {}
}

// Ã¢ÂÂÃ¢ÂÂ GPS location write Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ

Future<void> _writeLocation(
        String companyId, String shiftId, Position pos) async {
          // Throttle: only write if gpsIntervalMinutes have elapsed
          final tPrefs = await SharedPreferences.getInstance();
          final intervalMin = tPrefs.getInt('shift_gpsInterval') ?? 60;
          final now0 = DateTime.now();
          if (_lastWriteTime != null && now0.difference(_lastWriteTime!).inMinutes < intervalMin) {
                      return;
          }
          _lastWriteTime = now0;
      final now = DateTime.now().toIso8601String();
      final body = jsonEncode({
              'fields': {
                        'lat': {'doubleValue': pos.latitude},
                        'lng': {'doubleValue': pos.longitude},
                        'accuracy': {'doubleValue': pos.accuracy},
                        'timestamp': {'timestampValue': (pos.timestamp ?? DateTime.now()).toUtc().toIso8601String()},
                        'createdAt': {'timestampValue': now},
                        'source': {'stringValue': 'http_v3'},
              }
      });
      final url =
                '$_firestoreBase/companies/$companyId/timesheets/$shiftId/locations';

      // Try 1: with auth token (proper rules)
      try {
              final token = await _getToken();
              final resp = await http
                          .post(Uri.parse(url), headers: _authHeaders(token: token), body: body)
                          .timeout(const Duration(seconds: 12));
              if (resp.statusCode == 200 || resp.statusCode == 201) {
                        await _log('GPS_WRITE', 'OK_AUTH lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)}');
                        return;
              }
              await _log('GPS_WRITE', 'AUTH_FAIL status=${resp.statusCode}',
                                 err: resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body);
      } catch (e) {
              await _log('GPS_WRITE', 'AUTH_EXCEPTION', err: e.toString());
      }

      // Try 2: without auth (rules open Ã¢ÂÂ allow create: if true)
      try {
              final resp = await http
                          .post(Uri.parse(url),
                                            headers: {'Content-Type': 'application/json'}, body: body)
                          .timeout(const Duration(seconds: 12));
              if (resp.statusCode == 200 || resp.statusCode == 201) {
                        await _log('GPS_WRITE', 'OK_NOAUTH lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)}');
              } else {
                        await _log('GPS_WRITE', 'NOAUTH_FAIL status=${resp.statusCode}',
                                             err: resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body);
              }
      } catch (e) {
              await _log('GPS_WRITE', 'NOAUTH_EXCEPTION', err: e.toString());
      }
}

// Ã¢ÂÂÃ¢ÂÂ Main service entry point Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ

@pragma('vm:entry-point')
Future<void> gpsServiceMain(ServiceInstance service) async {
      WidgetsFlutterBinding.ensureInitialized();

      await _log('SERVICE', 'v3 started ios=${Platform.isIOS}');

      // Initialize Firebase
      try {
              await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
              await _log('FIREBASE', 'initializeApp OK');
      } catch (e) {
              await _log('FIREBASE', 'initializeApp error', err: e.toString());
      }

      // Load tokens from SharedPreferences (saved by main isolate)
      try {
              final prefs = await SharedPreferences.getInstance();
              _cachedToken = prefs.getString('shift_idToken');
              _cachedRefreshToken = prefs.getString('shift_refreshToken');
              final expiryStr = prefs.getString('shift_tokenExpiry');
              if (expiryStr != null) _tokenExpiry = DateTime.tryParse(expiryStr);
              await _log('AUTH', 'token_len=${_cachedToken?.length ?? 0} has_refresh=${_cachedRefreshToken != null} expiry=$expiryStr');
      } catch (e) {
              await _log('AUTH', 'load prefs error', err: e.toString());
      }

      // Try to refresh token immediately if we have refreshToken
      if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
              final newToken = await _refreshToken(_cachedRefreshToken!);
              await _log('TOKEN_REFRESH', newToken != null ? 'OK len=${newToken.length}' : 'FAILED');
      }

      if (service is AndroidServiceInstance) {
              try { await service.setAsForegroundService(); } catch (_) {}
      }

      StreamSubscription<Position>? posStream;

      Future<void> _startGps(String companyId, String shiftId) async {
              await _log('GPS', 'startGps cid=$companyId sid=$shiftId');
              await posStream?.cancel();
              posStream = null;

              final LocationSettings locationSettings = Platform.isIOS
                          ? AppleSettings(
                              accuracy: LocationAccuracy.high,
                              activityType: ActivityType.otherNavigation,
                              distanceFilter: 0,
                              allowBackgroundLocationUpdates: true,
                              showBackgroundLocationIndicator: true,
                            )
                          : const LocationSettings(
                                          accuracy: LocationAccuracy.high,
                                          distanceFilter: 0,
                                        );

              try {
                        posStream = Geolocator.getPositionStream(
                                    locationSettings: locationSettings,
                                  ).listen(
                                    (Position pos) async {
                                                  await _log('POS',
                                                                           'lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)} acc=${pos.accuracy.toStringAsFixed(1)}');
                                                  await _writeLocation(companyId, shiftId, pos);
                                    },
                                    onError: (e) async {
                                                  await _log('POS_ERR', e.toString());
                                    },
                                    onDone: () async {
                                                  await _log('POS_DONE', 'stream closed');
                                    },
                                  );
                        await _log('GPS', 'stream listen OK');
              } catch (e) {
                        await _log('GPS', 'getPositionStream FAILED', err: e.toString());
              }
      }

      // iOS: read IDs from SharedPreferences immediately
      if (Platform.isIOS) {
              await _log('IOS', 'reading prefs');
              final prefs = await SharedPreferences.getInstance();
              final companyId = prefs.getString('shift_companyId') ?? '';
              final shiftId = prefs.getString('shift_shiftId') ?? '';
              await _log('IOS', 'cid=[$companyId] sid=[$shiftId]');

              if (companyId.isNotEmpty && shiftId.isNotEmpty) {
                        await _startGps(companyId, shiftId);
              } else {
                        await _log('IOS', 'IDs empty, polling...');
                        var attempts = 0;
                        Timer.periodic(const Duration(seconds: 2), (timer) async {
                                    attempts++;
                                    final p = await SharedPreferences.getInstance();
                                    final cId = p.getString('shift_companyId') ?? '';
                                    final sId = p.getString('shift_shiftId') ?? '';
                                    if (cId.isNotEmpty && sId.isNotEmpty) {
                                                  timer.cancel();
                                                  await _log('IOS', 'poll found ids attempt=$attempts');
                                                  await _startGps(cId, sId);
                                    } else if (attempts > 30) {
                                                  timer.cancel();
                                                  await _log('IOS', 'poll timeout after $attempts attempts');
                                    }
                        });
              }
      }

      // Event-driven start (Android primary, iOS backup)
      service.on('startTracking').listen((event) async {
              await _log('EVENT', 'startTracking received');
              final prefs = await SharedPreferences.getInstance();
              final companyId = event?['companyId'] as String? ?? prefs.getString('shift_companyId') ?? '';
              final shiftId = event?['shiftId'] as String? ?? prefs.getString('shift_shiftId') ?? '';
              final idToken = event?['idToken'] as String?;
              final refreshToken = event?['refreshToken'] as String?;

              if (companyId.isNotEmpty) await prefs.setString('shift_companyId', companyId);
              if (shiftId.isNotEmpty) await prefs.setString('shift_shiftId', shiftId);

              // Update tokens if passed via event
              if (idToken != null && idToken.isNotEmpty) {
                        _cachedToken = idToken;
                        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
                        await prefs.setString('shift_idToken', idToken);
              }
              if (refreshToken != null && refreshToken.isNotEmpty) {
                        _cachedRefreshToken = refreshToken;
                        await prefs.setString('shift_refreshToken', refreshToken);
              }

              if (shiftId.isEmpty || companyId.isEmpty) {
                        await _log('EVENT', 'startTracking IDs empty abort');
                        return;
              }
              await _startGps(companyId, shiftId);
      });

      service.on('stopTracking').listen((_) async {
              await _log('EVENT', 'stopTracking received');
              await posStream?.cancel();
              posStream = null;
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('shift_companyId');
              await prefs.remove('shift_shiftId');
              await service.stopSelf();
      });

      await _log('SERVICE', 'setup complete');
}
