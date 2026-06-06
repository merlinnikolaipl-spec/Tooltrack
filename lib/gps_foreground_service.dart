import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const _kApiKey = 'AIzaSyB28W647o4zrAZisrQNLfrn_4CXN_jjeIg';
const _kProjectId = 'tooltrack-ee0aa';
const _kRefreshUrl = 'https://securetoken.googleapis.com/v1/token?key=${_kApiKey}';

String? _cachedIdToken;
DateTime? _tokenFetchedAt;

Future<String?> _refreshIdToken(String refreshToken) async {
  try {
    final resp = await http.post(
      Uri.parse(_kRefreshUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=refresh_token&refresh_token=$refreshToken',
    );
    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data['id_token'] as String?;
    }
  } catch (_) {}
  return null;
}

Future<String?> _getValidToken(SharedPreferences prefs) async {
  final now = DateTime.now();
  if (_cachedIdToken != null && _tokenFetchedAt != null) {
    final age = now.difference(_tokenFetchedAt!).inMinutes;
    if (age < 55) return _cachedIdToken;
  }
  final refreshToken = prefs.getString('shift_refreshToken') ?? '';
  if (refreshToken.isNotEmpty) {
    final newToken = await _refreshIdToken(refreshToken);
    if (newToken != null) {
      _cachedIdToken = newToken;
      _tokenFetchedAt = now;
      await prefs.setString('shift_idToken', newToken);
      return newToken;
    }
  }
  final stored = prefs.getString('shift_idToken') ?? '';
  if (stored.isNotEmpty) {
    _cachedIdToken = stored;
    _tokenFetchedAt = now;
    return stored;
  }
  return null;
}

@pragma('vm:entry-point')
void gpsServiceMain() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterBackgroundService().on('startTracking').listen((event) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';

    if (companyId.isEmpty || shiftId.isEmpty) {
      await prefs.setString('gps_last_error', 'NO_SHIFT_DATA');
      return;
    }

    final intervalSec = (event?['gpsInterval'] ?? event?['interval'] ?? 30) as int;

    await _sendGpsPoint(prefs, companyId, shiftId);

    Timer.periodic(Duration(seconds: intervalSec), (_) async {
      await _sendGpsPoint(prefs, companyId, shiftId);
    });
  });

  FlutterBackgroundService().on('stopTracking').listen((event) async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
  });

  FlutterBackgroundService().on('updateToken').listen((event) async {
    final newToken = event?['idToken'] as String?;
    final newRefresh = event?['refreshToken'] as String?;
    if (newToken != null && newToken.isNotEmpty) {
      _cachedIdToken = newToken;
      _tokenFetchedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shift_idToken', newToken);
    }
    if (newRefresh != null && newRefresh.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shift_refreshToken', newRefresh);
    }
  });
}

Future<void> _sendGpsPoint(
  SharedPreferences prefs,
  String companyId,
  String shiftId,
) async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await prefs.setString('gps_last_error', 'GPS_DISABLED');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await prefs.setString('gps_last_error', 'NO_PERMISSION');
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );

    final idToken = await _getValidToken(prefs);
    if (idToken == null || idToken.isEmpty) {
      await prefs.setString('gps_last_error', 'NO_ID_TOKEN');
      return;
    }

    await _writeLocation(
      idToken: idToken,
      companyId: companyId,
      shiftId: shiftId,
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
    );

    await prefs.setString('gps_last_error', 'OK');
  } catch (e) {
    await prefs.setString('gps_last_error', 'GPS_ERR:$e');
  }
}

Future<void> _writeLocation({
  required String idToken,
  required String companyId,
  required String shiftId,
  required double lat,
  required double lng,
  required double accuracy,
}) async {
  final url = 'https://firestore.googleapis.com/v1/projects/$_kProjectId'
      '/databases/(default)/documents'
      '/companies/$companyId/timesheets/$shiftId/locations';

  final ts = DateTime.now().toIso8601String();
  final body = json.encode({
    'fields': {
      'lat': {'doubleValue': lat},
      'lng': {'doubleValue': lng},
      'accuracy': {'doubleValue': accuracy},
      'timestamp': {'stringValue': ts},
    }
  });

  final resp = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    },
    body: body,
  );

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    final prefs = await SharedPreferences.getInstance();
    final errMsg = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
    await prefs.setString('gps_last_error', 'HTTP_${resp.statusCode}:$errMsg');
  }
}
