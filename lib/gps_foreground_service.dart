import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

const _kProjectId = 'tooltrack-ee0aa';
const _kFirebaseApiKey = 'AIzaSyB28W647o4zrAZisrQNLfrn_4CXN_jjeIg';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

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

  Future<String?> _getIdToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final token = prefs.getString('shift_idToken');
    if (token == null || token.isEmpty) {
      await prefs.setString('gps_last_error', 'NO_ID_TOKEN: Start shift first');
      return null;
    }
    return token;
  }

  Future<void> _writeLocation({
    required String companyId,
    required String shiftId,
    required String idToken,
    required double lat,
    required double lng,
    required double accuracy,
  }) async {
    final url = 'https://firestore.googleapis.com/v1/projects/$_kProjectId'
        '/databases/(default)/documents'
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
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.headers.contentType = ContentType.json;
      req.write(body);
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 400) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('gps_last_error',
            'HTTP_${resp.statusCode}: ${respBody.length > 200 ? respBody.substring(0, 200) : respBody}');
      } else {
        // Success - clear error
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('gps_last_error');
      }
    } finally {
      client.close();
    }
  }

  Future<void> sendGps() async {
    if (_companyId == null || _shiftId == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      final idToken = await _getIdToken();
      if (idToken == null) return;
      await _writeLocation(
        companyId: _companyId!,
        shiftId: _shiftId!,
        idToken: idToken,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gps_last_error', 'SEND_ERR: ${e.toString().substring(0, 150)}');
    }
  }

  // On startup - check if there's a saved shift
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
    }
  } catch (_) {}

  service.on('startTracking').listen((data) async {
    _gpsTimer?.cancel();
    _companyId = data?['companyId'] as String?;
    _shiftId = data?['shiftId'] as String?;
    _interval = (data?['interval'] as int?) ??
        (data?['gpsInterval'] as int?) ?? 5;

    // Save to prefs for recovery
    final prefs = await SharedPreferences.getInstance();
    if (_companyId != null) await prefs.setString('shift_companyId', _companyId!);
    if (_shiftId != null) await prefs.setString('shift_shiftId', _shiftId!);
    await prefs.setInt('shift_gpsInterval', _interval);

    // Send first point immediately, then periodic
    await sendGps();
    _gpsTimer = Timer.periodic(Duration(minutes: _interval), (_) => sendGps());
  });

  service.on('stopTracking').listen((_) {
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _companyId = null;
    _shiftId = null;
  });

  service.on('stopService').listen((_) {
    _gpsTimer?.cancel();
    service.stopSelf();
  });
}
