import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// ─── Entry point for BOTH foreground and background isolates ───────────────

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // On Android — keep as foreground service
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // Listen for startTracking (foreground use only — saves to prefs)
  service.on('startTracking').listen((data) async {
    final companyId = data?['companyId'] as String?;
    final shiftId   = data?['shiftId']   as String?;
    final interval  = data?['interval']  as int?;
    if (companyId != null && shiftId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shift_companyId', companyId);
      await prefs.setString('shift_shiftId', shiftId);
      if (interval != null) await prefs.setInt('shift_gpsInterval', interval);
      print('[GPS] startTracking saved: company=${companyId} shift=${shiftId} interval=${interval}');
    }
  });

  service.on('stopService').listen((_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_companyId');
    await prefs.remove('shift_shiftId');
    service.stopSelf();
  });

  // Do an immediate ping when the service starts
  await _pingGps();
}

// ─── onBackground for iOS BGTask — called periodically by the OS ──────────

@pragma('vm:entry-point')
Future<bool> iosBackgroundHandler(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await _pingGps();
  return true;
}

// ─── Core GPS ping logic ────────────────────────────────────────────────────

Future<void> _pingGps() async {
  try {
    // 1. Read shift data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('shift_companyId');
    final shift   = prefs.getString('shift_shiftId');

    if (company == null || company.isEmpty || shift == null || shift.isEmpty) {
      print('[GPS] No active shift in prefs — skipping ping');
      return;
    }

    print('[GPS] Pinging for company=${company} shift=${shift}');

    // 2. Ensure Firebase is initialised in this isolate
    await _ensureFirebase();

    // 3. Check location permission
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      print('[GPS] Permission denied: ${perm}');
      return;
    }

    // 4. Check location service enabled
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      print('[GPS] Location service disabled');
      return;
    }

    // 5. Get position — short timeout for BGTask budget
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    );

    // 6. Write to Firestore
    await FirebaseFirestore.instance
        .collection('companies')
        .doc(company)
        .collection('timesheets')
        .doc(shift)
        .collection('locations')
        .add({
      'lat':       pos.latitude,
      'lng':       pos.longitude,
      'accuracy':  pos.accuracy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('[GPS] Ping OK: ${pos.latitude}, ${pos.longitude}');
  } catch (e, st) {
    print('[GPS] Ping error: ${e}\n${st}');
  }
}

// ─── Firebase init helper ────────────────────────────────────────────────────

Future<void> _ensureFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes:     Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    print('[GPS] Firebase init error: ${e}');
  }
}
