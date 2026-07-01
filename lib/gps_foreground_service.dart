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

// GPS Service v6 - added full diagnostic logging to find write bug

const _projectId = 'tooltrack-ee0aa';
const _apiKey = 'AIzaSyBWM0gMgkuMr5eAtbET1OtQn08Ld3_7cnI';

String? _cachedToken;
String? _cachedRefreshToken;
DateTime? _tokenExpiry;
DateTime? _lastWriteTime;

Future<void> _log(String tag, String msg, {String err = ''}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final url = 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/ios_debug_logs';
    final body = jsonEncode({
      'fields': {
        'ts': {'stringValue': DateTime.now().toIso8601String()},
        'platform': {'stringValue': 'ios'},
        'tag': {'stringValue': tag},
        'msg': {'stringValue': msg},
        'err': {'stringValue': err},
      }
    });
    await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body);
  } catch (_) {}
}

Future<String?> _getToken() async {
  // Return cached token if still valid (5min margin)
  if (_cachedToken != null && _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
    return _cachedToken;
  }
  // Try to refresh using cached refresh token
  if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
    final newToken = await _refreshToken(_cachedRefreshToken!);
    if (newToken != null) {
      _cachedToken = newToken;
      return _cachedToken;
    }
  }
  // Try reading from SharedPreferences (main isolate may have updated)
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final freshRefresh = prefs.getString('shift_refreshToken');
    if (freshRefresh != null && freshRefresh != _cachedRefreshToken) {
      _cachedRefreshToken = freshRefresh;
      await _log('AUTH', 'reloaded refreshToken from prefs');
    }
    if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
      final newToken = await _refreshToken(_cachedRefreshToken!);
      if (newToken != null) {
        _cachedToken = newToken;
        return _cachedToken;
      }
    }
  } catch (e) {
    await _log('AUTH', 'load prefs error', err: e.toString());
  }
  return _cachedToken;
}

Future<String?> _refreshToken(String refreshToken) async {
  try {
    final url = 'https://securetoken.googleapis.com/v1/token?key=$_apiKey';
    final resp = await http.post(Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token&refresh_token=$refreshToken');
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final newToken = data['id_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (newToken != null) {
        _cachedToken = newToken;
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
        if (newRefresh != null) _cachedRefreshToken = newRefresh;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('shift_idToken', newToken);
        if (newRefresh != null) await prefs.setString('shift_refreshToken', newRefresh);
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
        await _log('AUTH', 'token refreshed OK');
        return newToken;
      }
    } else {
      await _log('AUTH', 'refresh FAILED status=${resp.statusCode}', err: resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length));
    }
  } catch (e) {
    await _log('AUTH', 'refresh exception', err: e.toString());
  }
  return null;
}
Future<void> _writeLocation(
    String companyId, String shiftId, Position pos) async {
  final tPrefs = await SharedPreferences.getInstance();
  await tPrefs.reload();
  final intervalMin = tPrefs.getInt('shift_gpsInterval') ?? 60;
  final now0 = DateTime.now();

  // v6: log every attempt for diagnostics
  if (_lastWriteTime != null) {
    final elapsedMin = now0.difference(_lastWriteTime!).inMinutes;
    if (elapsedMin < intervalMin) {
      // Skip silently - interval not passed yet
      return;
    }
  }

  await _log('GPS_WRITE', 'attempt companyId=${companyId.isNotEmpty ? "ok" : "EMPTY"} shiftId=${shiftId.isNotEmpty ? "ok" : "EMPTY"} intervalMin=$intervalMin');

  if (companyId.isEmpty || shiftId.isEmpty) {
    await _log('GPS_WRITE', 'ABORT empty IDs');
    return;
  }

  final token = await _getToken();
  if (token == null || token.isEmpty) {
    await _log('GPS_WRITE', 'NO TOKEN - cachedToken null, cachedRefresh=${_cachedRefreshToken != null ? "exists" : "null"}');
    return;
  }

  await _log('GPS_WRITE', 'got token ok, writing to Firestore');

  final now = DateTime.now();
  final posTs = (pos.timestamp ?? now).toIso8601String();
  final url = 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/companies/$companyId/timesheets/$shiftId/locations';
  final body = jsonEncode({
    'fields': {
      'lat': {'doubleValue': pos.latitude},
      'lng': {'doubleValue': pos.longitude},
      'acc': {'doubleValue': pos.accuracy},
      'ts': {'stringValue': posTs},
      'source': {'stringValue': 'gps_service_v6'},
    }
  });

  try {
    final resp = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body,
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      _lastWriteTime = now0;
      await _log('GPS_WRITE', 'OK lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)} status=${resp.statusCode}');
    } else if (resp.statusCode == 401 || resp.statusCode == 403) {
      await _log('GPS_WRITE', 'AUTH_FAIL status=${resp.statusCode} - refreshing token');
      // Force refresh
      _cachedToken = null;
      _tokenExpiry = null;
      final newToken = await _getToken();
      if (newToken != null) {
        // Retry once
        final resp2 = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $newToken'},
          body: body,
        );
        if (resp2.statusCode == 200 || resp2.statusCode == 201) {
          _lastWriteTime = now0;
          await _log('GPS_WRITE', 'OK after retry status=${resp2.statusCode}');
        } else {
          await _log('GPS_WRITE', 'FAIL after retry status=${resp2.statusCode}', err: resp2.body.substring(0, resp2.body.length > 300 ? 300 : resp2.body.length));
        }
      }
    } else {
      await _log('GPS_WRITE', 'HTTP_ERR status=${resp.statusCode}', err: resp.body.substring(0, resp.body.length > 300 ? 300 : resp.body.length));
    }
  } catch (e) {
    await _log('GPS_WRITE', 'EXCEPTION', err: e.toString());
  }
}
@pragma('vm:entry-point')
Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _log('FIREBASE', 'initializeApp OK');
  } catch (e) {
    await _log('FIREBASE', 'initializeApp error', err: e.toString());
  }

  // Load tokens from SharedPreferences on startup
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final savedToken = prefs.getString('shift_idToken');
    final savedRefresh = prefs.getString('shift_refreshToken');
    final savedExpiry = prefs.getString('shift_tokenExpiry');
    final savedCompany = prefs.getString('shift_companyId') ?? '';
    final savedShift = prefs.getString('shift_shiftId') ?? '';

    if (savedToken != null && savedToken.isNotEmpty) {
      _cachedToken = savedToken;
    }
    if (savedRefresh != null && savedRefresh.isNotEmpty) {
      _cachedRefreshToken = savedRefresh;
    }
    if (savedExpiry != null) {
      try {
        _tokenExpiry = DateTime.parse(savedExpiry);
      } catch (_) {
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 30));
      }
    }
    await _log('SERVICE', 'v6 started ios=${Platform.isIOS} token=${savedToken != null && savedToken.isNotEmpty ? "ok" : "null"} refresh=${savedRefresh != null && savedRefresh.isNotEmpty ? "ok" : "null"} companyId=${savedCompany.isNotEmpty ? "ok" : "EMPTY"} shiftId=${savedShift.isNotEmpty ? "ok" : "EMPTY"}');
  } catch (e) {
    await _log('SERVICE', 'v6 prefs load error', err: e.toString());
  }

  Future<void> startGps(String companyId, String shiftId) async {
    await posStream?.cancel();
    posStream = null;
    await _log('GPS', 'startGps companyId=${companyId.isNotEmpty ? "ok" : "EMPTY"} shiftId=${shiftId.isNotEmpty ? "ok" : "EMPTY"}');

    final locationSettings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
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
      );
      await _log('GPS', 'stream started OK');
    } catch (e) {
      await _log('GPS', 'getPositionStream FAILED', err: e.toString());
    }
  }
  // iOS: read companyId/shiftId from prefs immediately, or poll
  if (Platform.isIOS) {
    await _log('IOS', 'reading prefs for IDs');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';

    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await _log('IOS', 'IDs found immediately, starting GPS');
      await startGps(companyId, shiftId);
    } else {
      await _log('IOS', 'IDs empty, polling every 2s up to 30 attempts...');
      int attempts = 0;
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        attempts++;
        final p = await SharedPreferences.getInstance();
        await p.reload();
        final cId = p.getString('shift_companyId') ?? '';
        final sId = p.getString('shift_shiftId') ?? '';
        if (cId.isNotEmpty && sId.isNotEmpty) {
          timer.cancel();
          await _log('IOS', 'IDs found after $attempts poll attempts');
          await startGps(cId, sId);
        } else if (attempts >= 30) {
          timer.cancel();
          await _log('IOS', 'poll timeout after $attempts attempts - no IDs found');
        }
      });
    }
  }

  // Event-driven start (Android primary, iOS backup)
  service.on('startTracking').listen((event) async {
    await _log('EVENT', 'startTracking received');
    final prefs = await SharedPreferences.getInstance();

    final companyId = (event?['companyId'] as String?) ?? prefs.getString('shift_companyId') ?? '';
    final shiftId = (event?['shiftId'] as String?) ?? prefs.getString('shift_shiftId') ?? '';
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

    await _log('EVENT', 'startTracking companyId=${companyId.isNotEmpty ? "ok" : "EMPTY"} shiftId=${shiftId.isNotEmpty ? "ok" : "EMPTY"} token=${idToken != null && idToken.isNotEmpty ? "ok" : "null"}');

    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await startGps(companyId, shiftId);
    } else {
      await _log('EVENT', 'startTracking IDs empty abort');
    }
  });

  service.on('stopTracking').listen((event) async {
    await _log('EVENT', 'stopTracking received');
    await posStream?.cancel();
    posStream = null;
  });
}

StreamSubscription<Position>? posStream;
