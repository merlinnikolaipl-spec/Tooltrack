import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // CRITICAL: Initialize Firebase in background isolate
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Already initialized - ignore
  }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  Timer? _gpsTimer;
  String? _companyId;
  String? _shiftId;

  Future<void> sendGps() async {
    if (_companyId == null || _shiftId == null) return;
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(_companyId)
          .collection('timesheets')
          .doc(_shiftId)
          .collection('locations')
          .add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'accuracy': pos.accuracy,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gps_last_error');
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('gps_last_error', e.toString());
      } catch (_) {}
    }
  }

  Future<void> startTracking(String cId, String sId, int gpsMinutes) async {
    _companyId = cId;
    _shiftId = sId;
    _gpsTimer?.cancel();
    await sendGps();
    _gpsTimer = Timer.periodic(Duration(minutes: gpsMinutes), (_) => sendGps());
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final savedCompany = prefs.getString('shift_companyId');
  final savedShift  = prefs.getString('shift_shiftId');
  final savedInterval = prefs.getInt('shift_gpsInterval') ?? 5;

  if (savedCompany != null && savedShift != null) {
    await startTracking(savedCompany, savedShift, savedInterval);
  }

  service.on('startTracking').listen((event) async {
    if (event == null) return;
    final cId = event['companyId'] as String?;
    final sId = event['shiftId'] as String?;
    final gps = (event['gpsInterval'] as int?) ??
                (event['interval'] as int?) ?? 5;
    if (cId == null || sId == null) return;
    await startTracking(cId, sId, gps);
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

@pragma('vm:entry-point')
Future<bool> iosBackgroundHandler(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
