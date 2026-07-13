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

// GPS Service v9 - Android GPS fix (no Platform.isIOS startup check)
// noauth write first (rules allow it), token write as fallback; timestampValue UTC fix

const _projectId = 'tooltrack-ee0aa';

String? _cachedToken;
String? _cachedRefreshToken;
DateTime? _tokenExpiry;
DateTime? _lastWriteTime;
int _gpsIntervalMin = 1;

Future<void> _log(String tag, String msg, {String err = ''}) async {
  try {
    final ts = DateTime.now().toIso8601String();
    final body = jsonEncode({
      'fields': {
        'tag': {'stringValue': tag},
        'msg': {'stringValue': msg},
        'err': {'stringValue': err},
        'ts': {'stringValue': ts},
        'platform': {'stringValue': Platform.isAndroid ? 'android' : 'ios'},
      }
    });
    await http.post(
      Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/ios_debug_logs'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 5));
  } catch (_) {}
}

Future<String?> _getToken() async {
  if (_cachedToken != null && _cachedToken!.isNotEmpty) {
    if (_tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }
  }
  if (_cachedRefreshToken == null || _cachedRefreshToken!.isEmpty) return null;
  try {
    final resp = await http.post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=AIzaSyAcYwlq7T3rFgTp1EZjxBCJ2uIJpg5tJQY'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'grant_type': 'refresh_token', 'refresh_token': _cachedRefreshToken}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      _cachedToken = data['id_token'] as String?;
      final expiresIn = int.tryParse(data['expires_in']?.toString() ?? '3600') ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
      if (data['refresh_token'] != null) _cachedRefreshToken = data['refresh_token'] as String;
      return _cachedToken;
    }
    await _log('AUTH', 'refresh failed status=${resp.statusCode}');
    return null;
  } catch (e) {
    await _log('AUTH', 'refresh exception', err: e.toString());
    return null;
  }
}

Future<void> _writeLocation(String companyId, String shiftId, Position pos) async {
  final now = DateTime.now();
  if (_lastWriteTime != null) {
    final elapsedMin = now.difference(_lastWriteTime!).inMinutes;
    if (elapsedMin < _gpsIntervalMin) return;
  }

  await _log('GPS_WRITE', 'v7 attempt cid=${companyId.isNotEmpty ? "ok" : "EMPTY"} sid=${shiftId.isNotEmpty ? "ok" : "EMPTY"} interval=$_gpsIntervalMin elapsed=${_lastWriteTime != null ? now.difference(_lastWriteTime!).inSeconds : -1}s');

  if (companyId.isEmpty || shiftId.isEmpty) {
    await _log('GPS_WRITE', 'v7 ABORT empty IDs');
    return;
  }

  _lastWriteTime = now;

  final posTs = (pos.timestamp ?? now).toUtc().toIso8601String();
  final url = 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/companies/$companyId/timesheets/$shiftId/locations';
  final body = jsonEncode({
    'fields': {
      'lat': {'doubleValue': pos.latitude},
      'lng': {'doubleValue': pos.longitude},
      'accuracy': {'doubleValue': pos.accuracy},
      'createdAt': {'timestampValue': posTs},
      'source': {'stringValue': 'gps_v8'},
    }
  });

  try {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      await _log('GPS_WRITE', 'v7 OK_NOAUTH lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)}');
      return;
    }
    await _log('GPS_WRITE', 'v7 noauth status=${resp.statusCode} trying token');
  } catch (e) {
    await _log('GPS_WRITE', 'v7 noauth exception', err: e.toString());
  }

  final token = await _getToken();
  if (token == null || token.isEmpty) {
    await _log('GPS_WRITE', 'v7 NO TOKEN');
    return;
  }

  try {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: body,
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      await _log('GPS_WRITE', 'v7 OK_AUTH lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)}');
    } else {
      await _log('GPS_WRITE', 'v7 AUTH_FAIL status=${resp.statusCode}', err: resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body);
    }
  } catch (e) {
    await _log('GPS_WRITE', 'v7 auth exception', err: e.toString());
  }
}

@pragma('vm:entry-point')
Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _log('FIREBASE', 'v7 initializeApp OK');
  } catch (e) {
    await _log('FIREBASE', 'v7 initializeApp error', err: e.toString());
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _cachedToken = prefs.getString('shift_idToken');
    _cachedRefreshToken = prefs.getString('shift_refreshToken');
    final expiryStr = prefs.getString('shift_tokenExpiry');
    if (expiryStr != null) _tokenExpiry = DateTime.tryParse(expiryStr);
    _gpsIntervalMin = prefs.getInt('shift_gpsInterval') ?? 1;

    final savedCompany = prefs.getString('shift_companyId') ?? '';
    final savedShift = prefs.getString('shift_shiftId') ?? '';

    await _log('SERVICE', 'v7 started token=${_cachedToken != null && _cachedToken!.isNotEmpty ? "ok" : "null"} refresh=${_cachedRefreshToken != null ? "ok" : "null"} cid=${savedCompany.isNotEmpty ? "ok" : "EMPTY"} sid=${savedShift.isNotEmpty ? "ok" : "EMPTY"} interval=$_gpsIntervalMin');

    if (savedCompany.isNotEmpty && savedShift.isNotEmpty) {
      await _log('SERVICE', 'v9 IDs found on startup, starting GPS');
      await _startGps(savedCompany, savedShift);
    } else {
      await _log('SERVICE', 'v9 IDs empty on startup, waiting for startTracking event');
      int attempts = 0;
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        attempts++;
        final p = await SharedPreferences.getInstance();
        await p.reload();
        final cId = p.getString('shift_companyId') ?? '';
        final sId = p.getString('shift_shiftId') ?? '';
        if (cId.isNotEmpty && sId.isNotEmpty) {
          timer.cancel();
          await _log('SERVICE', 'v9 IDs found after ${attempts} poll attempts');
          await _startGps(cId, sId);
        } else if (attempts >= 30) {
          timer.cancel();
          await _log('SERVICE', 'v9 poll timeout after ${attempts} attempts');
        }
      });
    }
  } catch (e) {
    await _log('SERVICE', 'v7 startup error', err: e.toString());
  }

  service.on('startTracking').listen((event) async {
    await _log('EVENT', 'v7 startTracking received');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final companyId = (event?['companyId'] as String?) ?? prefs.getString('shift_companyId') ?? '';
      final shiftId = (event?['shiftId'] as String?) ?? prefs.getString('shift_shiftId') ?? '';
      final idToken = event?['idToken'] as String?;
      final refreshToken = event?['refreshToken'] as String?;
      if (idToken != null && idToken.isNotEmpty) {
        _cachedToken = idToken;
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
        await prefs.setString('shift_idToken', idToken);
      }
      if (refreshToken != null && refreshToken.isNotEmpty) {
        _cachedRefreshToken = refreshToken;
        await prefs.setString('shift_refreshToken', refreshToken);
      }
      if (companyId.isNotEmpty) await prefs.setString('shift_companyId', companyId);
      if (shiftId.isNotEmpty) await prefs.setString('shift_shiftId', shiftId);
      _gpsIntervalMin = prefs.getInt('shift_gpsInterval') ?? 1;
      await _log('EVENT', 'v7 startTracking cid=${companyId.isNotEmpty ? "ok" : "EMPTY"} sid=${shiftId.isNotEmpty ? "ok" : "EMPTY"} token=${idToken != null && idToken!.isNotEmpty ? "ok" : "null"} interval=$_gpsIntervalMin');
      if (companyId.isNotEmpty && shiftId.isNotEmpty) {
        await _startGps(companyId, shiftId);
      } else {
        await _log('EVENT', 'v7 startTracking IDs empty abort');
      }
    } catch (e) {
      await _log('EVENT', 'v7 startTracking error', err: e.toString());
    }
  });

  service.on('stopTracking').listen((_) async {
    await _log('EVENT', 'v7 stopTracking received');
    await _posStream?.cancel();
    _posStream = null;
  });
}

StreamSubscription<Position>? _posStream;

Future<void> _startGps(String companyId, String shiftId) async {
  await _posStream?.cancel();
  _posStream = null;
  _lastWriteTime = null;

  await _log('GPS', 'v7 startGps cid=${companyId.isNotEmpty ? "ok" : "EMPTY"} sid=${shiftId.isNotEmpty ? "ok" : "EMPTY"}');

  final locationSettings = Platform.isIOS
      ? AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.otherNavigation,
          distanceFilter: 0,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        )
      : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);

  try {
    _posStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) async {
        // POS logging removed (v8) - was causing Firestore quota exhaustion
        await _writeLocation(companyId, shiftId, pos);
      },
      onError: (e) async { await _log('POS_ERR', e.toString()); },
    );
    await _log('GPS', 'v7 stream started OK');
  } catch (e) {
    await _log('GPS', 'v7 getPositionStream FAILED', err: e.toString());
  }
}
