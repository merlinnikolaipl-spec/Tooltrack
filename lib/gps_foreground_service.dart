import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) {
  service.on('startTracking').listen((event) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Firebase already initialized
    }

    final prefs = await SharedPreferences.getInstance();
    final shiftIdFromEvent = event?['shiftId'] as String?;
    if (shiftIdFromEvent != null) {
      await prefs.setString('shift_shiftId', shiftIdFromEvent);
    }
    final companyId = event?['companyId'] as String? ?? prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';

    if (shiftId.isEmpty || companyId.isEmpty) return;

    StreamSubscription<Position>? posStream;
    posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
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
      } catch (e) {
        // ignore
      }
    });

    service.on('stopTracking').listen((_) async {
      await posStream?.cancel();
      await service.stopSelf();
    });
  });
}
