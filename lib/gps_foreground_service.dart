import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// ============================================================
// DIAGNOSTIC v2 — Firestore rules now open (allow write: if true)
// Logs everything to ios_debug_logs via HTTP REST (no auth needed)
// Also tries Firebase SDK and reports exact errors
// ============================================================

const _projectId = 'tooltrack-ee0aa';
const _firestoreBase =
    'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

// Write a log entry via raw HTTP REST — no auth required (rules open)
Future<void> _log(String tag, String msg, {String? err}) async {
  final now = DateTime.now().toIso8601String();
  // 1) Write to SharedPreferences (always works, no network)
  try {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('debug_log') ?? [];
    logs.add('[$tag] $msg ${err != null ? "ERR: $err" : ""}');
    if (logs.length > 200) logs.removeRange(0, logs.length - 200);
    await prefs.setStringList('debug_log', logs);
  } catch (_) {}

  // 2) Write to Firestore via HTTP REST (no auth needed — rules open)
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
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    // HTTP also failed — only SharedPreferences has the log
  }
}

// Write GPS location via HTTP REST (no auth — rules open for locations)
Future<void> _httpWriteLocation(
    String companyId, String shiftId, Position pos) async {
  try {
    final now = DateTime.now().toIso8601String();
    final body = jsonEncode({
      'fields': {
        'latitude': {'doubleValue': pos.latitude},
        'longitude': {'doubleValue': pos.longitude},
        'accuracy': {'doubleValue': pos.accuracy},
        'timestamp': {'stringValue': pos.timestamp.toIso8601String()},
        'createdAt': {'stringValue': now},
        'source': {'stringValue': 'http_no_auth'},
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
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      await _log('HTTP_WRITE', 'OK status=${resp.statusCode}');
    } else {
      await _log('HTTP_WRITE', 'FAIL status=${resp.statusCode}',
          err: resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body);
    }
  } catch (e) {
    await _log('HTTP_WRITE', 'EXCEPTION', err: e.toString());
  }
}

Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  await _log('SERVICE', 'gpsServiceMain started ios=' + Platform.isIOS.toString());

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await _log('FIREBASE', 'initializeApp OK');
  } catch (e) {
    await _log('FIREBASE', 'initializeApp error', err: e.toString());
  }

  // Check Firebase Auth current user
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      await _log('AUTH', 'user=${user.email} token_len=${token?.length ?? 0}');
    } else {
      await _log('AUTH', 'currentUser is NULL — no auth in background isolate');
    }
  } catch (e) {
    await _log('AUTH', 'getIdToken error', err: e.toString());
  }

  if (service is AndroidServiceInstance) {
    try {
      await service.setAsForegroundService();
    } catch (_) {}
  }

  StreamSubscription<Position>? posStream;

  Future<void> _startGps(String companyId, String shiftId) async {
    await _log('GPS', '_startGps cid=$companyId sid=$shiftId');
    await posStream?.cancel();
    posStream = null;

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
          await _log('POSITION',
              'lat=${pos.latitude.toStringAsFixed(5)} lng=${pos.longitude.toStringAsFixed(5)} acc=${pos.accuracy.toStringAsFixed(1)}');

          // Try 1: Firebase SDK write
          bool sdkOk = false;
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
            sdkOk = true;
            await _log('SDK_WRITE', 'OK');
          } catch (e) {
            await _log('SDK_WRITE', 'FAILED', err: e.toString());
          }

          // Try 2: HTTP REST write (no auth — rules open)
          if (!sdkOk) {
            await _httpWriteLocation(companyId, shiftId, pos);
          }
        },
        onError: (e) async {
          await _log('STREAM_ERR', e.toString());
        },
        onDone: () async {
          await _log('STREAM_DONE', 'stream closed');
        },
      );
      await _log('GPS', 'getPositionStream listen OK');
    } catch (e) {
      await _log('GPS', 'getPositionStream FAILED', err: e.toString());
    }
  }

  // iOS: read IDs from SharedPreferences immediately
  if (Platform.isIOS) {
    await _log('IOS', 'iOS branch reading prefs');
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';
    await _log('IOS', 'prefs cid=[$companyId] sid=[$shiftId]');

    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await _startGps(companyId, shiftId);
    } else {
      await _log('IOS', 'IDs empty, starting poll');
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
        } else if (attempts > 15) {
          timer.cancel();
          await _log('IOS', 'poll timeout $attempts attempts ids still empty');
        }
      });
    }
  }

  // Event-driven (Android primary, iOS backup)
  service.on('startTracking').listen((event) async {
    await _log('EVENT', 'startTracking received');
    final prefs = await SharedPreferences.getInstance();
    final companyId = event?['companyId'] as String? ??
        prefs.getString('shift_companyId') ?? '';
    final shiftId = event?['shiftId'] as String? ??
        prefs.getString('shift_shiftId') ?? '';
    if (companyId.isNotEmpty) await prefs.setString('shift_companyId', companyId);
    if (shiftId.isNotEmpty) await prefs.setString('shift_shiftId', shiftId);
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
    await prefs.remove('shift_shiftId');
    await prefs.remove('shift_companyId');
    await service.stopSelf();
  });

  await _log('SERVICE', 'gpsServiceMain setup complete');
}
