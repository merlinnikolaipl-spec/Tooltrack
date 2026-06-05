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

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  Timer? _gpsTimer;

  final prefs = await SharedPreferences.getInstance();
  final companyId = prefs.getString('shift_companyId');
  final shiftId   = prefs.getString('shift_shiftId');
  final interval  = prefs.getInt('shift_gpsInterval') ?? 5;

  Future<void> tryStartTimer(String cId, String sId, int gpsInterval) async {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(Duration(minutes: gpsInterval), (_) async {
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) return;

        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        await FirebaseFirestore.instance
            .collection('companies')
            .doc(cId)
            .collection('timesheets')
            .doc(sId)
            .collection('locations')
            .add({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // silent
      }
    });
  }

  if (companyId != null && shiftId != null) {
    await tryStartTimer(companyId, shiftId, interval);
  }

  service.on('startTracking').listen((event) async {
    if (event == null) return;
    final cId = event['companyId'] as String?;
    final sId = event['shiftId'] as String?;
    final gps = (event['gpsInterval'] as int?) ?? 5;
    if (cId == null || sId == null) return;
    await tryStartTimer(cId, sId, gps);
  });

  service.on('stopTracking').listen((_) {
    _gpsTimer?.cancel();
    _gpsTimer = null;
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
