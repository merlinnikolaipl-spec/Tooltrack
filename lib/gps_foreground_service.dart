import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

Future<void> gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase in background isolate
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Already initialized — ignore
  }

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  StreamSubscription<Position>? posStream;

  Future<void> _startGps(String companyId, String shiftId) async {
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

    posStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position pos) async {
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
      } catch (_) {}
    });
  }

  // iOS: read companyId/shiftId from SharedPreferences immediately
  // (service.invoke is unreliable on iOS)
  if (Platform.isIOS) {
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';
    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await _startGps(companyId, shiftId);
    } else {
      // Poll every 2s until IDs appear (max 30s)
      var attempts = 0;
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        attempts++;
        final p = await SharedPreferences.getInstance();
        final cId = p.getString('shift_companyId') ?? '';
        final sId = p.getString('shift_shiftId') ?? '';
        if (cId.isNotEmpty && sId.isNotEmpty) {
          timer.cancel();
          await _startGps(cId, sId);
        } else if (attempts > 15) {
          timer.cancel();
        }
      });
    }
  }

  // Event-driven start (Android primary, iOS backup)
  service.on('startTracking').listen((event) async {
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
    if (shiftId.isEmpty || companyId.isEmpty) return;
    await _startGps(companyId, shiftId);
  });

  service.on('stopTracking').listen((_) async {
    await posStream?.cancel();
    posStream = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_shiftId');
    await prefs.remove('shift_companyId');
    await service.stopSelf();
  });
}
