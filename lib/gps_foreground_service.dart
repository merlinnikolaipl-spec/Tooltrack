import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// Called by main app to flush queued iOS GPS positions to Firestore
Future<void> flushIosGpsQueue() async {
  if (!Platform.isIOS) return;
  final prefs = await SharedPreferences.getInstance();
  final queue = prefs.getStringList('gps_queue') ?? [];
  if (queue.isEmpty) return;
  final companyId = prefs.getString('shift_companyId') ?? '';
  final shiftId = prefs.getString('shift_shiftId') ?? '';
  if (companyId.isEmpty || shiftId.isEmpty) return;

  final uploaded = <String>[];
  for (final item in queue) {
    try {
      final map = jsonDecode(item) as Map<String, dynamic>;
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('timesheets')
          .doc(shiftId)
          .collection('locations')
          .add({
        'latitude': map['lat'],
        'longitude': map['lng'],
        'accuracy': map['acc'],
        'timestamp': map['ts'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      uploaded.add(item);
    } catch (_) {}
  }
  if (uploaded.isNotEmpty) {
    final remaining = queue.where((e) => !uploaded.contains(e)).toList();
    await prefs.setStringList('gps_queue', remaining);
  }
}

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  StreamSubscription<Position>? posStream;
  Timer? flushTimer;

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
  }

  Future<void> _startGps(String companyId, String shiftId) async {
    await posStream?.cancel();
    posStream = null;
    flushTimer?.cancel();

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
      if (Platform.isIOS) {
        // On iOS: queue to SharedPreferences, flush timer handles Firestore write
        final prefs = await SharedPreferences.getInstance();
        final queue = prefs.getStringList('gps_queue') ?? [];
        queue.add(jsonEncode({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'acc': pos.accuracy,
          'ts': pos.timestamp.toIso8601String(),
        }));
        // Keep max 200 positions in queue
        if (queue.length > 200) queue.removeRange(0, queue.length - 200);
        await prefs.setStringList('gps_queue', queue);
      } else {
        // Android: write directly to Firestore
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
      }
    });

    if (Platform.isIOS) {
      // Flush queued positions to Firestore every 30s while service is alive
      flushTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        final prefs = await SharedPreferences.getInstance();
        final queue = prefs.getStringList('gps_queue') ?? [];
        if (queue.isEmpty) return;
        final uploaded = <String>[];
        for (final item in queue) {
          try {
            final map = jsonDecode(item) as Map<String, dynamic>;
            await FirebaseFirestore.instance
                .collection('companies')
                .doc(companyId)
                .collection('timesheets')
                .doc(shiftId)
                .collection('locations')
                .add({
              'latitude': map['lat'],
              'longitude': map['lng'],
              'accuracy': map['acc'],
              'timestamp': map['ts'],
              'createdAt': FieldValue.serverTimestamp(),
            });
            uploaded.add(item);
          } catch (_) {}
        }
        if (uploaded.isNotEmpty) {
          final remaining = queue.where((e) => !uploaded.contains(e)).toList();
          await prefs.setStringList('gps_queue', remaining);
        }
      });
    }
  }

  // iOS: start GPS immediately from SharedPreferences (invoke is unreliable on iOS)
  if (Platform.isIOS) {
    await _initFirebase();
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString('shift_companyId') ?? '';
    final shiftId = prefs.getString('shift_shiftId') ?? '';
    if (companyId.isNotEmpty && shiftId.isNotEmpty) {
      await _startGps(companyId, shiftId);
    } else {
      // Fallback: poll until IDs are available (max 30s)
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

  // Event-driven (Android + iOS backup)
  service.on('startTracking').listen((event) async {
    await _initFirebase();
    final prefs = await SharedPreferences.getInstance();
    final companyId = event?['companyId'] as String? ?? prefs.getString('shift_companyId') ?? '';
    final shiftId = event?['shiftId'] as String? ?? prefs.getString('shift_shiftId') ?? '';
    if (companyId.isNotEmpty) await prefs.setString('shift_companyId', companyId);
    if (shiftId.isNotEmpty) await prefs.setString('shift_shiftId', shiftId);
    if (shiftId.isEmpty || companyId.isEmpty) return;
    await _startGps(companyId, shiftId);
  });

  service.on('stopTracking').listen((_) async {
    flushTimer?.cancel();
    await posStream?.cancel();
    posStream = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shift_shiftId');
    await prefs.remove('shift_companyId');
    await prefs.remove('gps_queue');
    await service.stopSelf();
  });
}
