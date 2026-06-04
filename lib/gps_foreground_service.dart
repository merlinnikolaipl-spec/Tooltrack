import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// ─── Entry point for FOREGROUND (app on screen) ───────────────────────────

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  Timer? _gpsTimer;

  // Read prefs that were saved BEFORE startService() was called
  final prefs = await SharedPreferences.getInstance();
  final companyId = prefs.getString('shift_companyId');
  final shiftId   = prefs.getString('shift_shiftId');
  final interval  = prefs.getInt('shift_gpsInterval') ?? 5;

  if (companyId != null && companyId.isNotEmpty &&
      shiftId   != null && shiftId.isNotEmpty) {
    print('[GPS] Service started: company=$companyId shift=$shiftId interval=$interval min');

    // Ping immediately on service start
    await _pingGps();

    // Then repeat every interval minutes
    _gpsTimer = Timer.periodic(Duration(minutes: interval), (_) async {
      await _pingGps();
    });
  } else {
    print('[GPS] No shift in prefs at service start — waiting for startTracking event');
  }

  // Also listen for startTracking (in case called after service start)
  service.on('startTracking').listen((data) async {
    final cId = data?['companyId'] as String?;
    final sId = data?['shiftId']   as String?;
    final inv = (data?['interval'] as int?) ?? 5;

    if (cId != null && sId != null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('shift_companyId', cId);
      await p.setString('shift_shiftId',   sId);
      await p.setInt   ('shift_gpsInterval', inv);
      print('[GPS] startTracking event: company=$cId shift=$sId interval=$inv min');

      _gpsTimer?.cancel();
      await _pingGps();
      _gpsTimer = Timer.periodic(Duration(minutes: inv), (_) async {
        await _pingGps();
      });
    }
  });

  service.on('stopService').listen((_) async {
    _gpsTimer?.cancel();
    _gpsTimer = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('shift_companyId');
    await p.remove('shift_shiftId');
    await p.remove('shift_gpsInterval');
    service.stopSelf();
  });
}

// ─── onBackground for iOS BGTask — one-shot call by iOS ──────────────────

@pragma('vm:entry-point')
Future<bool> iosBackgroundHandler(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await _pingGps();
  return true;
}

// ─── Core GPS ping ────────────────────────────────────────────────────────

Future<void> _pingGps() async {
  try {
    final prefs   = await SharedPreferences.getInstance();
    final company = prefs.getString('shift_companyId');
    final shift   = prefs.getString('shift_shiftId');

    if (company == null || company.isEmpty || shift == null || shift.isEmpty) {
      print('[GPS] No active shift in prefs — skipping ping');
      return;
    }

    print('[GPS] Pinging for company=$company shift=$shift');

    await _ensureFirebase();

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      print('[GPS] Permission denied: $perm');
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      print('[GPS] Location service disabled');
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20),
    );

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
    print('[GPS] Ping error: $e\n$st');
  }
}

// ─── Firebase init helper ─────────────────────────────────────────────────

Future<void> _ensureFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    print('[GPS] Firebase init error: $e');
  }
}
