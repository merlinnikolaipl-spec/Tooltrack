import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// Firebase Web API key (used for token refresh via REST)
const _kFirebaseApiKey = 'AIzaSyB28W647o4zrAZisrQNLfrn_4CXN_jjeIg';
const _kProjectId = 'tooltrack-ee0aa';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Init Firebase in background isolate
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  Timer? _gpsTimer;
  String? _companyId;
  String? _shiftId;
  int _interval = 5;
  String? _cachedIdToken;

  // Refresh idToken using refreshToken via Firebase Auth REST API
  Future<String?> _getValidIdToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final refreshToken = prefs.getString('shift_refreshToken');
    if (refreshToken == null || refreshToken.isEmpty) {
      await prefs.setString('gps_last_error', 'NO_REFRESH_TOKEN');
      return null;
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_kFirebaseApiKey'),
      );
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write('grant_type=refresh_token&refresh_token=$refreshToken');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('id_token')) {
        final newIdToken = json['id_token'] as String;
        final newRefreshToken = json['refresh_token'] as String?;
        if (newRefreshToken != null) {
          await prefs.setString('shift_refreshToken', newRefreshToken);
        }
        return newIdToken;
      } else {
        await prefs.setString('gps_last_error', 'TOKEN_REFRESH_FAIL: ${body.substring(0, 200)}');
        return null;
      }
    } catch (e) {
      await prefs.setString('gps_last_error', 'TOKEN_REFRESH_ERR: ${e.toString()}');
      return null;
    }
  }

  // Write GPS location to Firestore via REST API (no auth SDK needed)
  Future<void> _writeToFirestore({
    required String companyId,
    required String shiftId,
    required String idToken,
    required double lat,
    required double lng,
    required double accuracy,
  }) async {
    final url = 'https://firestore.googleapis.com/v1/projects/$_kProjectId/databases/(default)/documents'
        '/companies/$companyId/timesheets/$shiftId/locations';

    final now = DateTime.now().toUtc().toIso8601String();
    final body = jsonEncode({
      'fields': {
        'lat': {'doubleValue': lat},
        'lng': {'doubleValue': lng},
        'accuracy': {'doubleValue': accuracy},
        'timestamp': {'timestampValue': now},
      }
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Authorization', 'Bearer $idToken');
    req.headers.contentType = ContentType.json;
    req.write(body);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    client.close();

    if (resp.statusCode >= 400) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gps_last_error', 'FIRESTORE_ERR ${resp.statusCode}: ${respBody.substring(0, 200)}');
    } else {
      // Clear error on success
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gps_last_error');
    }
  }

  Future<void> sendGps() async {
    if (_companyId == null || _shiftId == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Get valid token
      _cachedIdToken ??= await _getValidIdToken();
      if (_cachedIdToken == null) return;

      try {
        await _writeToFirestore(
          companyId: _companyId!,
          shiftId: _shiftId!,
          idToken: _cachedIdToken!,
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
        );
      } catch (e) {
        // Token may be expired - try refreshing once
        _cachedIdToken = await _getValidIdToken();
        if (_cachedIdToken != null) {
          await _writeToFirestore(
            companyId: _companyId!,
            shiftId: _shiftId!,
            idToken: _cachedIdToken!,
            lat: pos.latitude,
            lng: pos.longitude,
            accuracy: pos.accuracy,
          );
        }
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gps_last_error', 'GPS_ERR: ${e.toString()}');
    }
  }

  // Recovery from SharedPreferences on startup
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final savedCompany = prefs.getString('shift_companyId');
    final savedShift = prefs.getString('shift_shiftId');
    final savedInterval = prefs.getInt('shift_gpsInterval') ?? 5;
    if (savedCompany != null && savedShift != null) {
      _companyId = savedCompany;
      _shiftId = savedShift;
      _interval = savedInterval;
      // Pre-fetch token
      _cachedIdToken = await _getValidIdToken();
    }
  } catch (_) {}

  service.on('startTracking').listen((data) async {
    _companyId = data?['companyId'] as String?;
    _shiftId = data?['shiftId'] as String?;
    _interval = (data?['interval'] as int?) ?? (data?['gpsInterval'] as int?) ?? 5;

    // Save to prefs
    final prefs = await SharedPreferences.getInstance();
    if (_companyId != null) await prefs.setString('shift_companyId', _companyId!);
    if (_shiftId != null) await prefs.setString('shift_shiftId', _shiftId!);
    await prefs.setInt('shift_gpsInterval', _interval);

    // Refresh token
    _cachedIdToken = await _getValidIdToken();

    _gpsTimer?.cancel();
    // Send first point immediately
    await sendGps();
    // Then periodic
    _gpsTimer = Timer.periodic(Duration(minutes: _interval), (_) => sendGps());
  });

  service.on('stopTracking').listen((_) {
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _companyId = null;
    _shiftId = null;
    _cachedIdToken = null;
  });

  service.on('stopService').listen((_) {
    _gpsTimer?.cancel();
    service.stopSelf();
  });
}
