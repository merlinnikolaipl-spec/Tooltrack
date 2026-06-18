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
      'GPS tracking',
      description: 'Отслеживание местоположения во время смены',
      importance: Importance.low,
    ));
  } catch (_) {}
}

// ignore: unused_element
Future<void> _scheduleShiftNotif(int id, String title, String body, Duration delay) async {
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

// ignore: unused_element
Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: gpsServiceMain,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'shift_gps',
      initialNotificationTitle: 'GPS tracking',
      initialNotificationContent: 'Отслеживание местоположения активно',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: gpsServiceMain,
      onBackground: iosBackgroundHandler,
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToolKeeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B4EFF)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != null) {
          return CompanyProfilePage();
        }
        return LoginPage();
      },
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ToolKeeper', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
              if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: Colors.red))],
              const SizedBox(height: 24),
              _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _signIn, child: const Text('Sign In')),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyProfilePage extends StatefulWidget {
  const CompanyProfilePage({super.key});
  @override
  State<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends State<CompanyProfilePage> {
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToolKeeper'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: Center(
        child: Text('Welcome, ${user?.email ?? 'User'}'),
      ),
    );
  }
}
