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

// GPS Service v5 — based on v3 (working) + 401 retry

const _projectId = 'tooltrack-ee0aa';
const _apiKey = 'AIzaSyBWM0gMgkuMr5eAtbET1OtQn08Ld3_7cnI';

String? _cachedToken;
String? _cachedRefreshToken;
DateTime? _tokenExpiry;
DateTime? _lastWriteTime;

Future<String?> _getToken() async {
  // Return cached token if still valid (5min margin)
  if (_cachedToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
    return _cachedToken;
  }
  // Try to refresh using cached refresh token
  if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
    final newToken = await _refreshToken(_cachedRefreshToken!);
    if (newToken != null) return newToken;
  }
  // Try reading from SharedPreferences (main isolate may have updated)
  try {
    final prefs = await SharedPreferences.getInstance();
    final freshRefresh = prefs.getString('shift_refreshToken');
    final freshId = prefs.getString('shift_idToken');
    if (freshRefresh != null && freshRefresh.isNotEmpty) {
      if (freshRefresh != _cachedRefreshToken) {
        _cachedRefreshToken = freshRefresh;
        await _log('AUTH', 'reloaded refreshToken from prefs');
      }
      if (freshId != null && freshId.isNotEmpty) {
        _cachedToken = freshId;
        final freshExpiry = prefs.getString('shift_tokenExpiry');
        if (freshExpiry != null) _tokenExpiry = DateTime.tryParse(freshExpiry);
      }
      final newToken = await _refreshToken(_cachedRefreshToken!);
      if (newToken != null) return newToken;
    }
  } catch (e) {
    await _log('AUTH', 'load prefs error', err: e.toString());
  }
  return _cachedToken;
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
      // Save refreshed tokens back to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (_cachedToken != null) await prefs.setString('shift_idToken', _cachedToken!);
      if (_cachedRefreshToken != null) await prefs.setString('shift_refreshToken', _cachedRefreshToken!);
      await prefs.setString('shift_tokenExpiry', _tokenExpiry.toString());
      return _cachedToken;
    } else {
      final errSnip = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
      await _log('AUTH', 'refresh failed status=${resp.statusCode}', err: errSnip);
    }
  } catch (e) {
    await _log('AUTH', 'refresh exception', err: e.toString());
  }
  return null;
}

Map<String, String> _authHeaders({String? token}) {
  final headers = <String, String>{'Content-Type': 'application/json'};
  final t = token ?? _cachedToken;
  if (t != null && t.isNotEmpty) headers['Authorization'] = 'Bearer $t';
  return headers;
}

Future<void> _log(String tag, String msg, {String? err}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  try {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('debug_log') ?? [];
    logs.add('$now [$tag] $msg${err != null ? " ERR: $err" : ""}');
    if (logs.length > 300) logs.removeRange(0, logs.length - 300);
    await prefs.setStringList('debug_log', logs);
  } catch (_) {}
  try {
    final body = jsonEncode({
      'fields': {
        'tag': {'stringValue': tag},
        'msg': {'stringValue': msg},
        'err': {'stringValue': err ?? ''},
        'platform': {'stringValue': 'ios'},
        'ts': {'stringValue': now},
      }
    });
    await http
        .post(
          Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/ios_debug_logs'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 5));
  } catch (_) {}
}

Future<void> _writeLocation(
    String companyId, String shiftId, Position pos) async {
  final tPrefs = await SharedPreferences.getInstance();
  final intervalMin = tPrefs.getInt('shift_gpsInterval') ?? 60;
  final now0 = DateTime.now();
  if (_lastWriteTime != null &&
      now0.difference(_lastWriteTime!).inMinutes < intervalMin) {
    return;
  }
  _lastWriteTime = now0;

  final token = await _getToken();
  if (token == null || token.isEmpty) {
    await _log('GPS_WRITE', 'no token available, skip write');
    return;
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final posTs = (pos.timestamp ?? DateTime.now()).toUtc().toIso8601String();
  final body = jsonEncode({
    'fields': {
      'lat': {'doubleValue': pos.latitude},
      'lng': {'doubleValue': pos.longitude},
      'accuracy': {'doubleValue': pos.accuracy},
      'timestamp': {
        'timestampValue': posTs,
      },
      'createdAt': {
        'timestampValue': now,
      },
      'source': {'stringValue': 'gps_service'},
    }
  });

  final url =
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/companies/$companyId/timesheets/$shiftId/locations';

  Future<int> doPost(String tk) async {
    try {
      final r = await http
          .post(Uri.parse(url), headers: _authHeaders(token: tk), body: body)
          .timeout(const Duration(seconds: 10));
      return r.statusCode;
    } catch (_) {
      return -1;
    }
  }

  final status = await doPost(token);

  if (status == 200 || status == 201) {
    await _log('GPS_WRITE',
        'OK lat=${pos.latitude.toStringAsFixed(5)} acc=${pos.accuracy.toStringAsFixed(1)}');
    return;
  }

  if (status == 401 || status == 403) {
    await _log('GPS_WRITE', 'AUTH_FAIL status=$status forcing refresh');
    // Force refresh
    _tokenExpiry = DateTime.now().subtract(const Duration(hours: 2));
    _cachedToken = null;
    final freshToken = await _getToken();
    if (freshToken == null || freshToken.isEmpty) {
      await _log('GPS_WRITE', 'FAIL no token after refresh');
      return;
    }
    final status2 = await doPost(freshToken);
    if (status2 == 200 || status2 == 201) {
      await _log('GPS_WRITE',
          'OK after retry lat=${pos.latitude.toStringAsFixed(5)}');
    } else {
      await _log('GPS_WRITE', 'FAIL after retry status=$status2');
    }
    return;
  }

  await _log('GPS_WRITE', 'FAIL status=$status');
}

@pragma('vm:entry-point')
Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _log('SERVICE', 'v5 started ios=${Platform.isIOS}');
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _log('FIREBASE', 'initializeApp OK');
  } catch (e) {
    await _log('FIREBASE', 'initializeApp error', err: e.toString());
  }
  // Load tokens from SharedPreferences on startup
  try {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('shift_idToken');
    _cachedRefreshToken = prefs.getString('shift_refreshToken');
    final expiryStr = prefs.getString('shift_tokenExpiry');
    if (expiryStr != null) _tokenExpiry = DateTime.tryParse(expiryStr);
    await _log('AUTH', 'token_len=${_cachedToken?.length ?? 0} has_refresh=${_cachedRefreshToken?.isNotEmpty ?? false}');
  } catch (e) {
    await _log('AUTH', 'load prefs error', err: e.toString());
  }

  if (service is AndroidServiceInstance) {
    try { await service.setAsForegroundService(); } catch (_) {}
  }

  StreamSubscription<Position>? posStream;

  Future<void> startGps(String companyId, String shiftId) async {
    await posStream?.cancel();
    posStream = null;
    final locationSettings = Platform.isIOS
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
        onError: (e) async { await _log('POS_ERR', e.toString()); },
        onDone: () async { await _log('POS_DONE', 'stream closed'); },
      );
      await _log('GPS', 'stream listen OK');
    } catch (e) {
      await _log('GPS', 'getPositionStream FAILED', err: e.toString());
    }
  }

  // iOS: read companyId/shiftId from prefs immediately, or poll
  if (Platform.isIOS) {
    await _log('IOS', 'reading prefs');
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';
    await _log('IOS', 'cid=[$companyId] sid=[$shiftId]');
    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await startGps(companyId, shiftId);
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
          await startGps(cId, sId);
        } else if (attempts >= 30) {
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

    await _log('EVENT', 'startTracking cid=$companyId sid=$shiftId');
    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await startGps(companyId, shiftId);
    } else {
      await _log('EVENT', 'startTracking IDs empty abort');
    }
  });

  service.on('stopTracking').listen((_) async {
    await _log('EVENT', 'stopTracking received');
    await posStream?.cancel();
    posStream = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_companyId');
    await prefs.remove('shift_shiftId');
    service.stopSelf();
  });

  service.on('stopService').listen((_) async {
    await _log('EVENT', 'stopService received');
    await posStream?.cancel();
    posStream = null;
    service.stopSelf();
  });

  await _log('SERVICE', 'setup complete');
}
