import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// ============================================================
// DIAGNOSTIC VERSION - logs everything to ios_debug_logs
// ============================================================

const _projectId = 'tooltrack-ee0aa';
const _firestoreBase =
    'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

// Write a log entry via raw HTTP REST (no SDK required)
Future<void> _httpLog(String tag, String msg, {String? err}) async {
  try {
    final now = DateTime.now().toIso8601String();
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
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // If HTTP also fails, at least write to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('debug_log') ?? [];
      logs.add('${DateTime.now().toIso8601String()} [$tag] $msg ${err ?? ''}');
      if (logs.length > 100) logs.removeRange(0, logs.length - 100);
      await prefs.setStringList('debug_log', logs);
    } catch (_) {}
  }
}

Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  await _httpLog('SERVICE', 'gpsServiceMain started');

  // Initialize Firebase
  String firebaseStatus = 'ok';
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await _httpLog('FIREBASE', 'initializeApp success');
  } catch (e) {
    firebaseStatus = e.toString();
    await _httpLog('FIREBASE', 'initializeApp error', err: e.toString());
  }

  if (service is AndroidServiceInstance) {
    try {
      await service.setAsForegroundService();
      await _httpLog('SERVICE', 'setAsForegroundService OK');
    } catch (e) {
      await _httpLog('SERVICE', 'setAsForegroundService error', err: e.toString());
    }
  }

  StreamSubscription<Position>? posStream;

  Future<void> _startGps(String companyId, String shiftId) async {
    await _httpLog('GPS', 'startGps called cid=$companyId sid=$shiftId');

    await posStream?.cancel();
    posStream = null;

    // Test Firestore write via SDK
    try {
      await FirebaseFirestore.instance
          .collection('ios_debug_logs')
          .add({'tag': 'SDK_TEST', 'msg': 'SDK write from _startGps', 'ts': DateTime.now().toIso8601String()});
      await _httpLog('SDK_TEST', 'SDK write from _startGps SUCCESS');
    } catch (e) {
      await _httpLog('SDK_TEST', 'SDK write FAILED', err: e.toString());
    }

    final LocationSettings locationSettings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );

    try {
      posStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) async {
          await _httpLog('POSITION',
              'lat=${pos.latitude} lng=${pos.longitude} acc=${pos.accuracy}');

          // Write GPS to Firestore via SDK
          try {
            await FirebaseFirestore.instance
                .collection('companies')
                .doc(companyId)
                .collection('timesheets')
                .doc(shiftId)
                .collection('locations')
                .add({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'accuracy': pos.accuracy,
              'timestamp': pos.timestamp.toIso8601String(),
              'createdAt': FieldValue.serverTimestamp(),
            });
            await _httpLog('WRITE', 'SDK write to locations OK');
          } catch (e) {
            await _httpLog('WRITE', 'SDK write to locations FAILED', err: e.toString());

            // Fallback: write via HTTP REST
            try {
              final now = DateTime.now().toIso8601String();
              final body = jsonEncode({
                'fields': {
                  'latitude': {'doubleValue': pos.latitude},
                  'longitude': {'doubleValue': pos.longitude},
                  'accuracy': {'doubleValue': pos.accuracy},
                  'timestamp': {'stringValue': now},
                  'source': {'stringValue': 'http_fallback'},
                }
              });
              final resp = await http
                  .post(
                    Uri.parse(
                        '$_firestoreBase/companies/$companyId/timesheets/$shiftId/locations'),
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  )
                  .timeout(const Duration(seconds: 15));
              await _httpLog('HTTP_FALLBACK',
                  'status=${resp.statusCode} body=${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
            } catch (e2) {
              await _httpLog('HTTP_FALLBACK', 'HTTP write FAILED', err: e2.toString());
            }
          }
        },
        onError: (e) async {
          await _httpLog('STREAM_ERROR', 'posStream error', err: e.toString());
        },
        onDone: () async {
          await _httpLog('STREAM_DONE', 'posStream done/closed');
        },
      );
      await _httpLog('GPS', 'getPositionStream listen() called OK');
    } catch (e) {
      await _httpLog('GPS', 'getPositionStream FAILED', err: e.toString());
    }
  }

  // iOS: read IDs from SharedPreferences immediately
  if (Platform.isIOS) {
    await _httpLog('IOS', 'iOS branch: reading prefs');
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';
    await _httpLog('IOS', 'prefs: cid=$companyId sid=$shiftId');

    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await _startGps(companyId, shiftId);
    } else {
      await _httpLog('IOS', 'IDs empty, starting poll timer');
      var attempts = 0;
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        attempts++;
        final p = await SharedPreferences.getInstance();
        final cId = p.getString('shift_companyId') ?? '';
        final sId = p.getString('shift_shiftId') ?? '';
        if (cId.isNotEmpty && sId.isNotEmpty) {
          timer.cancel();
          await _httpLog('IOS', 'poll found ids attempt=$attempts');
          await _startGps(cId, sId);
        } else if (attempts > 15) {
          timer.cancel();
          await _httpLog('IOS', 'poll timeout after $attempts attempts, ids still empty');
        }
      });
    }
  }

  // Event-driven start (Android primary, iOS backup)
  service.on('startTracking').listen((event) async {
    await _httpLog('EVENT', 'startTracking event received');
    final prefs = await SharedPreferences.getInstance();
    final companyId = event?['companyId'] as String? ??
        prefs.getString('shift_companyId') ?? '';
    final shiftId = event?['shiftId'] as String? ??
        prefs.getString('shift_shiftId') ?? '';
    if (companyId.isNotEmpty) {
      await prefs.setString('shift_companyId', companyId);
    }
    if (shiftId.isNotEmpty) {
      await prefs.setString('shift_shiftId', shiftId);
    }
    if (shiftId.isEmpty || companyId.isEmpty) {
      await _httpLog('EVENT', 'startTracking: IDs empty, abort');
      return;
    }
    await _startGps(companyId, shiftId);
  });

  service.on('stopTracking').listen((_) async {
    await _httpLog('EVENT', 'stopTracking received');
    await posStream?.cancel();
    posStream = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_shiftId');
    await prefs.remove('shift_companyId');
    await service.stopSelf();
  });

  await _httpLog('SERVICE', 'gpsServiceMain setup complete');
}
