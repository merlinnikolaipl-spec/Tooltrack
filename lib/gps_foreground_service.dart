import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

String? _companyId;
String? _shiftId;
int _intervalMinutes = 15;
Timer? _timer;

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  await _ensureFirebase();
  await _loadPrefs();

  service.on('startTracking').listen((data) {
    _companyId = data?['companyId'] as String?;
    _shiftId = data?['shiftId'] as String?;
    final raw = data?['interval'];
    if (raw != null) _intervalMinutes = (raw as num).toInt();
    print('[GPS] startTracking: company=$_companyId shift=$_shiftId interval=$_intervalMinutes');
    // Перезапускаем таймер с новым интервалом
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _intervalMinutes), (_) {
      _pingGps();
    });
  });

  service.on('stopService').listen((_) {
    _timer?.cancel();
    _timer = null;
    service.stopSelf();
  });

  // Первый пинг — сразу при старте (prefs уже загружены)
  await _pingGps();

  // Таймер — только если startTracking ещё не запустил свой
  _timer ??= Timer.periodic(Duration(minutes: _intervalMinutes), (_) {
    _pingGps();
  });
}

Future<void> _loadPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _companyId ??= prefs.getString('shift_companyId');
    _shiftId ??= prefs.getString('shift_shiftId');
    final saved = prefs.getInt('shift_gpsInterval');
    if (saved != null) _intervalMinutes = saved;
    print('[GPS] Prefs: company=$_companyId shift=$_shiftId interval=$_intervalMinutes');
  } catch (e) {
    print('[GPS] Prefs error: $e');
  }
}

Future<void> _ensureFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    print('[GPS] Firebase error: $e');
  }
}

Future<void> _pingGps() async {
  try {
    // Читаем prefs при каждом пинге — защита от устаревших данных при повторном старте
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('shift_companyId') ?? _companyId;
    final shift = prefs.getString('shift_shiftId') ?? _shiftId;
    if (company == null || shift == null) {
      print('[GPS] Нет данных смены');
      return;
    }
    await _ensureFirebase();

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      print('[GPS] Нет разрешения: $perm');
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    );

    await FirebaseFirestore.instance
        .collection('companies').doc(company)
        .collection('timesheets').doc(shift)
        .collection('locations')
        .add({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('[GPS] Ping OK: ${pos.latitude}, ${pos.longitude}');
  } catch (e, st) {
    print('[GPS] Ping error: $e\n$st');
  }
}
