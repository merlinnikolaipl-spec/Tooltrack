import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  StreamSubscription<Position>? posStream;
  String? _currentShiftId;
  String? _currentCompanyId;

  Future<void> _startGps(String companyId, String shiftId) async {
    if (posStream != null) return; // already running
    _currentCompanyId = companyId;
    _currentShiftId = shiftId;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}

    final LocationSettings locationSettings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: false,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );

    posStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      try {
        await FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('timesheets')
            .doc(shiftId)
            .collection('locations')
            .add({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': position.timestamp.toIso8601String(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    });
  }

  // On iOS: invoke() events are unreliable.
  // Read shiftId/companyId directly from SharedPreferences.
  // The main app saves them before calling startService().
  if (Platform.isIOS) {
    // Poll SharedPreferences every 3s until we get valid IDs, then start GPS
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (posStream != null) {
        timer.cancel();
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('shift_companyId') ?? '';
      final shiftId = prefs.getString('shift_shiftId') ?? '';
      if (companyId.isNotEmpty && shiftId.isNotEmpty) {
        timer.cancel();
        await _startGps(companyId, shiftId);
      }
    });
  }

  // Event-driven (works reliably on Android, also kept for iOS as backup)
  service.on('startTracking').listen((event) async {
    await posStream?.cancel();
    posStream = null;

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
