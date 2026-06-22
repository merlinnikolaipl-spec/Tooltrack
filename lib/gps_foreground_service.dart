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

  StreamSubscription<Position>? posStream;

  service.on('startTracking').listen((event) async {
    await posStream?.cancel();
    posStream = null;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // already initialized
    }

    final prefs = await SharedPreferences.getInstance();
    final shiftIdFromEvent = event?['shiftId'] as String?;
    if (shiftIdFromEvent != null) {
      await prefs.setString('shift_shiftId', shiftIdFromEvent);
    }
    final companyId = event?['companyId'] as String? ??
        prefs.getString('shift_companyId') ?? '';
    final shiftId = shiftIdFromEvent ??
        prefs.getString('shift_shiftId') ?? '';

    if (shiftId.isEmpty || companyId.isEmpty) return;

    // AppleSettings with allowBackgroundLocationUpdates is required for iOS background GPS
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
      } catch (e) {
        // write error - silently continue
      }
    });
  });

  service.on('stopTracking').listen((_) async {
    await posStream?.cancel();
    posStream = null;
    await service.stopSelf();
  });
}
