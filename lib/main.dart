import 'admin_employee_pages.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'billing/plans.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import 'qr_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gps_foreground_service.dart';

/// Глобальный экземпляр локальных уведомлений
final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

/// MethodChannel для Android-специфичных операций
const _batteryChannel = MethodChannel('com.toolkeeper.app/battery');

Future<void> _initLocalNotifications() async {
  try {
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifs.initialize(const InitializationSettings(android: androidSettings));
    final androidImpl = _localNotifs
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'shift_reminders',
      'Напоминания о смене',
      description: 'Предупреждения о длительных сменах',
      importance: Importance.high,
    ));
    // Канал для GPS foreground service — создаём явно при старте, чтобы он
    // гарантированно существовал когда BackgroundService вызовет startForeground().
    // Без этого на Android 14+ выбрасывается CannotPostForegroundServiceNotificationException.
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'shift_gps',
      'GPS Трекинг',
      description: 'Отслеживание геопозиции во время смены',
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    ));
    await androidImpl?.requestNotificationsPermission();
  } catch (_) {}
}

Future<void> _scheduleShiftNotif(int id, Duration delay, String title, String body) async {
  try {
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _localNotifs.zonedSchedule(
      id, title, body, when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'shift_reminders', 'Напоминания о смене',
          importance: Importance.high, priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
bool iosBackgroundHandler(ServiceInstance service) {
  return true;
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: gpsServiceMain,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'shift_gps',
      initialNotificationTitle: 'ToolKeeper',
      initialNotificationContent: 'Отслеживание смены',
      foregroundServiceNotificationId: 256,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: gpsServiceMain,
      onBackground: iosBackgroundHandler,
      // This is crucial for keeping location updates running in the background on iOS.
      pausesLocationUpdatesAutomatically: false,
    ),
  );
}

/// ✅ ОДИН main()
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Офлайн-кэш Firestore (размер не ограничен)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await _initLocalNotifications();
  runApp(const MyApp());
}
