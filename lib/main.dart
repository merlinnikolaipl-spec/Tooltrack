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

/// ÐÐ»Ð¾Ð±Ð°Ð»ÑÐ½ÑÐ¹ ÑÐºÐ·ÐµÐ¼Ð¿Ð»ÑÑ Ð»Ð¾ÐºÐ°Ð»ÑÐ½ÑÑ ÑÐ²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ð¹
final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

/// MethodChannel Ð´Ð»Ñ Android-ÑÐ¿ÐµÑÐ¸ÑÐ¸ÑÐ½ÑÑ Ð¾Ð¿ÐµÑÐ°ÑÐ¸Ð¹
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
      'ÐÐ°Ð¿Ð¾Ð¼Ð¸Ð½Ð°Ð½Ð¸Ñ Ð¾ ÑÐ¼ÐµÐ½Ðµ',
      description: 'ÐÑÐµÐ´ÑÐ¿ÑÐµÐ¶Ð´ÐµÐ½Ð¸Ñ Ð¾ Ð´Ð»Ð¸ÑÐµÐ»ÑÐ½ÑÑ ÑÐ¼ÐµÐ½Ð°Ñ',
      importance: Importance.high,
    ));
    // ÐÐ°Ð½Ð°Ð» Ð´Ð»Ñ GPS foreground service â ÑÐ¾Ð·Ð´Ð°ÑÐ¼ ÑÐ²Ð½Ð¾ Ð¿ÑÐ¸ ÑÑÐ°ÑÑÐµ, ÑÑÐ¾Ð±Ñ Ð¾Ð½
    // Ð³Ð°ÑÐ°Ð½ÑÐ¸ÑÐ¾Ð²Ð°Ð½Ð½Ð¾ ÑÑÑÐµÑÑÐ²Ð¾Ð²Ð°Ð» ÐºÐ¾Ð³Ð´Ð° BackgroundService Ð²ÑÐ·Ð¾Ð²ÐµÑ startForeground().
    // ÐÐµÐ· ÑÑÐ¾Ð³Ð¾ Ð½Ð° Android 14+ Ð²ÑÐ±ÑÐ°ÑÑÐ²Ð°ÐµÑÑÑ CannotPostForegroundServiceNotificationException.
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'shift_gps',
      'GPS Ð¢ÑÐµÐºÐ¸Ð½Ð³',
      description: 'ÐÑÑÐ»ÐµÐ¶Ð¸Ð²Ð°Ð½Ð¸Ðµ Ð³ÐµÐ¾Ð¿Ð¾Ð·Ð¸ÑÐ¸Ð¸ Ð²Ð¾ Ð²ÑÐµÐ¼Ñ ÑÐ¼ÐµÐ½Ñ',
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
          'shift_reminders', 'ÐÐ°Ð¿Ð¾Ð¼Ð¸Ð½Ð°Ð½Ð¸Ñ Ð¾ ÑÐ¼ÐµÐ½Ðµ',
          importance: Importance.high, priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  } catch (_) {}
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
      initialNotificationContent: 'ÐÑÑÐ»ÐµÐ¶Ð¸Ð²Ð°Ð½Ð¸Ðµ ÑÐ¼ÐµÐ½Ñ',
      foregroundServiceNotificationId: 256,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
            iosConfiguration: IosConfiguration(autoStart: false, onForeground: gpsServiceMain, onBackground: iosBackgroundHandler),
  );
}

/// â ÐÐÐÐ main()
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ÐÑÐ»Ð°Ð¹Ð½-ÐºÑÑ Firestore (ÑÐ°Ð·Ð¼ÐµÑ Ð½Ðµ Ð¾Ð³ÑÐ°Ð½Ð¸ÑÐµÐ½)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await _initLocalNotifications();
  runApp(const MyApp());
}

/// ===================
/// SIMPLE LANG
/// ===================
enum AppLang { ru, uk, pl, en, de, fr, es, it, pt, cs, ro, nl, tr, ar, hi, ko, ja, zh, id, vi, tl }

/// Human-readable names for all supported languages
const Map<AppLang, String> kLangNames = {
  AppLang.ru: 'Ð ÑÑÑÐºÐ¸Ð¹',
  AppLang.uk: 'Ð£ÐºÑÐ°ÑÐ½ÑÑÐºÐ°',
  AppLang.pl: 'Polski',
  AppLang.en: 'English',
  AppLang.de: 'Deutsch',
  AppLang.fr: 'FranÃ§ais',
  AppLang.es: 'EspaÃ±ol',
  AppLang.it: 'Italiano',
  AppLang.pt: 'PortuguÃªs',
  AppLang.cs: 'ÄeÅ¡tina',
  AppLang.ro: 'RomÃ¢nÄ',
  AppLang.nl: 'Nederlands',
  AppLang.tr: 'TÃ¼rkÃ§e',
  AppLang.ar: 'Ø§ÙØ¹Ø±Ø¨ÙØ©',
  AppLang.hi: 'à¤¹à¤¿à¤¨à¥à¤¦à¥',
  AppLang.ko: 'íêµ­ì´',
  AppLang.ja: 'æ¥æ¬èª',
  AppLang.zh: 'ä¸­æ',
  AppLang.id: 'Indonesia',
  AppLang.vi: 'Tiáº¿ng Viá»t',
  AppLang.tl: 'Filipino',
};

class I18n {
  final AppLang lang;
  const I18n(this.lang);

  static const _dict = <AppLang, Map<String, String>>{
    AppLang.ru: {
      'appTitle': 'ToolKeeper',
      'login': 'ÐÑÐ¾Ð´',
      'register': 'Ð ÐµÐ³Ð¸ÑÑÑÐ°ÑÐ¸Ñ',
      'email': 'Email',
      'password': 'ÐÐ°ÑÐ¾Ð»Ñ',
      'enter': 'ÐÐ¾Ð¹ÑÐ¸',
      'haveAccount': 'Ð£Ð¶Ðµ ÐµÑÑÑ Ð°ÐºÐºÐ°ÑÐ½Ñ',
      'needAccount': 'Ð ÐµÐ³Ð¸ÑÑÑÐ°ÑÐ¸Ñ',
      'or': 'ÐÐÐ',
      'google': 'ÐÐ¾Ð¹ÑÐ¸ ÑÐµÑÐµÐ· Google',
      'continue': 'ÐÑÐ¾Ð´Ð¾Ð»Ð¶Ð¸ÑÑ',
      'switchAcc': 'Ð¡Ð¼ÐµÐ½Ð¸ÑÑ Ð°ÐºÐºÐ°ÑÐ½Ñ',
      'logout': 'ÐÑÐ¹ÑÐ¸',
      'people': 'ÐÑÐ´Ð¸',
      'tools': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑ',
      'tool': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'inv': 'ÐÐ½Ð². â',
      'issue': 'ÐÑÐ´Ð°ÑÐ°',
      'profile': 'ÐÑÐ¾ÑÐ¸Ð»Ñ',
      'add': 'ÐÐ¾Ð±Ð°Ð²Ð¸ÑÑ',
      'cancel': 'ÐÑÐ¼ÐµÐ½Ð°',
      'save': 'Ð¡Ð¾ÑÑÐ°Ð½Ð¸ÑÑ',
      'delete': 'Ð£Ð´Ð°Ð»Ð¸ÑÑ',
      'noPeople': 'ÐÑÐ´ÐµÐ¹ Ð¿Ð¾ÐºÐ° Ð½ÐµÑ. ÐÐ°Ð¶Ð¼Ð¸ +',
      'noTools': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð² Ð¿Ð¾ÐºÐ° Ð½ÐµÑ. ÐÐ°Ð¶Ð¼Ð¸ +',
      'history': 'ÐÑÑÐ¾ÑÐ¸Ñ',
      'reports': 'ÐÑÑÑÑÑ',
      'issueTool': 'ÐÑÐ´Ð°ÑÑ',
      'returnTool': 'ÐÐµÑÐ½ÑÑÑ',
      'issueTitle': 'ÐÑÐ´Ð°ÑÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'returnTitle': 'ÐÑÐ¸Ð½ÑÑÑ Ð²Ð¾Ð·Ð²ÑÐ°Ñ',
      'person': 'Ð§ÐµÐ»Ð¾Ð²ÐµÐº',
      'toolInv': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ (Ð¸Ð½Ð². â)',
      'historyEmpty': 'ÐÑÑÐ¾ÑÐ¸Ñ Ð¿ÑÑÑÐ°Ñ',
      'reportsPeople': 'Ð£ ÐºÐ¾Ð³Ð¾ ÑÑÐ¾ Ð½Ð° ÑÑÐºÐ°Ñ (Ð¿Ð¾ Ð»ÑÐ´ÑÐ¼)',
      'reportsTools': 'ÐÐ´Ðµ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ (Ð¿Ð¾ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°Ð¼)',
      'reportFilterHint': 'Ð¤Ð¸Ð»ÑÑÑ Ð¾ÑÑÐµÑÐ°...',
      'onHandsTotal': 'Ð¡ÐµÐ¹ÑÐ°Ñ Ð½Ð° ÑÑÐºÐ°Ñ Ð²ÑÐµÐ³Ð¾: {n} ÐµÐ´.',
      'toolsCountLabel': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð²: {n}',
      'whoLabel': 'Ð£ ÐºÐ¾Ð³Ð¾: {name}',
      'noneIssued': 'Ð¡ÐµÐ¹ÑÐ°Ñ Ð½Ð¸ Ñ ÐºÐ¾Ð³Ð¾ Ð½Ð¸ÑÐµÐ³Ð¾ Ð½Ðµ Ð²ÑÐ´Ð°Ð½Ð¾.',
      'noneIssued2': 'Ð¡ÐµÐ¹ÑÐ°Ñ Ð½ÐµÑ Ð²ÑÐ´Ð°Ð½Ð½Ð¾Ð³Ð¾ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°.',
      'issued': 'ÐÐ«ÐÐÐÐ',
      'returned': 'ÐÐÐÐÐ ÐÐ¢',
      'addPerson': 'ÐÐ¾Ð±Ð°Ð²Ð¸ÑÑ ÑÐµÐ»Ð¾Ð²ÐµÐºÐ°',
      'firstName': 'ÐÐ¼Ñ',
      'lastName': 'Ð¤Ð°Ð¼Ð¸Ð»Ð¸Ñ',
      'position': 'ÐÐ¾Ð»Ð¶Ð½Ð¾ÑÑÑ',
      'addTool': 'ÐÐ¾Ð±Ð°Ð²Ð¸ÑÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'toolNameHint': 'ÐÐ°Ð·Ð²Ð°Ð½Ð¸Ðµ (Ð½Ð°Ð¿ÑÐ¸Ð¼ÐµÑ: ÐÐµÑÑÐ¾ÑÐ°ÑÐ¾Ñ)',
      'invHint': 'ÐÐ½Ð²ÐµÐ½ÑÐ°ÑÐ½ÑÐ¹ Ð½Ð¾Ð¼ÐµÑ (Ð½Ð°Ð¿ÑÐ¸Ð¼ÐµÑ: SIM-001)',
      'needPeopleFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð´Ð¾Ð±Ð°Ð²Ñ Ð»ÑÐ´ÐµÐ¹',
      'needToolsFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð´Ð¾Ð±Ð°Ð²Ñ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ',
      'noFreeTool': 'ÐÐµÑ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½Ð¾Ð³Ð¾ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°',
      'noReturnTool': 'ÐÐµÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ° Ð´Ð»Ñ Ð²Ð¾Ð·Ð²ÑÐ°ÑÐ°',
      'lang': 'Ð¯Ð·ÑÐº',
      'chooseLang': 'ÐÑÐ±ÐµÑÐ¸ ÑÐ·ÑÐº',
      'sessionTitle': 'ÐÑÐ¾Ð´',
      'alreadyIn': 'ÐÑ ÑÐ¶Ðµ Ð²Ð¾ÑÐ»Ð¸ ÐºÐ°Ðº:',
      'enterEmailPass': 'ÐÐ²ÐµÐ´Ð¸ÑÐµ email Ð¸ Ð¿Ð°ÑÐ¾Ð»Ñ',

      // Firms
      'welcome': 'ÐÐ¾Ð±ÑÐ¾ Ð¿Ð¾Ð¶Ð°Ð»Ð¾Ð²Ð°ÑÑ',
      'chooseRole': 'ÐÑÐ¾ Ð²Ñ?',
      'owner': 'ÐÐ»Ð°Ð´ÐµÐ»ÐµÑ ÑÐ¸ÑÐ¼Ñ',
      'employee': 'Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº',
      'createCompany': 'Ð¡Ð¾Ð·Ð´Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ',
      'joinCompany': 'ÐÐ¾Ð¹ÑÐ¸ Ð² ÑÐ¸ÑÐ¼Ñ Ð¿Ð¾ ÐºÐ¾Ð´Ñ',
      'companyName': 'ÐÐ°Ð·Ð²Ð°Ð½Ð¸Ðµ ÑÐ¸ÑÐ¼Ñ (Ð½Ð°Ð¿ÑÐ¸Ð¼ÐµÑ: SIMKA)',
      'inviteCode': 'ÐÐ¾Ð´ Ð¿ÑÐ¸Ð³Ð»Ð°ÑÐµÐ½Ð¸Ñ',
      'yourInviteCode': 'ÐÐ°Ñ ÐºÐ¾Ð´ Ð¿ÑÐ¸Ð³Ð»Ð°ÑÐµÐ½Ð¸Ñ',
      'copyCodeHint': 'Ð¡ÐºÐ¾Ð¿Ð¸ÑÑÐ¹ÑÐµ Ð¸ Ð¾ÑÐ¿ÑÐ°Ð²ÑÑÐµ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÑ',
      'pendingTitle': 'ÐÐ¶Ð¸Ð´Ð°Ð½Ð¸Ðµ Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ¶Ð´ÐµÐ½Ð¸Ñ',
      'pendingText': 'ÐÑ Ð¾ÑÐ¿ÑÐ°Ð²Ð¸Ð»Ð¸ Ð·Ð°ÑÐ²ÐºÑ. ÐÐ»Ð°Ð´ÐµÐ»ÐµÑ ÑÐ¸ÑÐ¼Ñ Ð´Ð¾Ð»Ð¶ÐµÐ½ Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ´Ð¸ÑÑ Ð´Ð¾ÑÑÑÐ¿.',
      'requests': 'ÐÐ°ÑÐ²ÐºÐ¸ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¾Ð²',
      'approve': 'ÐÐ¾Ð´ÑÐ²ÐµÑÐ´Ð¸ÑÑ',
      'decline': 'ÐÑÐºÐ»Ð¾Ð½Ð¸ÑÑ',
      'noRequests': 'ÐÐ¾ÐºÐ° Ð½ÐµÑ Ð·Ð°ÑÐ²Ð¾Ðº.',
      'profileForm': 'ÐÐ½ÐºÐµÑÐ° ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°',
      'birthDate': 'ÐÐ°ÑÐ° ÑÐ¾Ð¶Ð´ÐµÐ½Ð¸Ñ (YYYY-MM-DD)',
      'phone': 'Ð¢ÐµÐ»ÐµÑÐ¾Ð½ (Ð¼ÐµÐ¶Ð´ÑÐ½Ð°ÑÐ¾Ð´Ð½ÑÐ¹ ÑÐ¾ÑÐ¼Ð°Ñ, Ð½Ð°Ð¿ÑÐ¸Ð¼ÐµÑ +48...)',
      'shoeSize': 'Ð Ð°Ð·Ð¼ÐµÑ Ð¾Ð±ÑÐ²Ð¸',
      'clothesSize': 'Ð Ð°Ð·Ð¼ÐµÑ Ð¾Ð´ÐµÐ¶Ð´Ñ',
      'saveProfile': 'Ð¡Ð¾ÑÑÐ°Ð½Ð¸ÑÑ Ð°Ð½ÐºÐµÑÑ',
      'needProfile': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð·Ð°Ð¿Ð¾Ð»Ð½Ð¸ÑÐµ Ð°Ð½ÐºÐµÑÑ',
      'company': 'Ð¤Ð¸ÑÐ¼Ð°',
      'role': 'Ð Ð¾Ð»Ñ',
      'admin': 'ÐÐ´Ð¼Ð¸Ð½',
      'worker': 'Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº',
      'onlyAdmin': 'ÐÐ¾ÑÑÑÐ¿Ð½Ð¾ ÑÐ¾Ð»ÑÐºÐ¾ Ð²Ð»Ð°Ð´ÐµÐ»ÑÑÑ/Ð°Ð´Ð¼Ð¸Ð½Ñ',
      'codeNotFound': 'ÐÐ¾Ð´ Ð½Ðµ Ð½Ð°Ð¹Ð´ÐµÐ½',

      // Company management
      'leaveCompany': 'Ð¡Ð¼ÐµÐ½Ð¸ÑÑ ÑÐ¸ÑÐ¼Ñ / Ð²ÑÐ¹ÑÐ¸ Ð¸Ð· ÑÐ¸ÑÐ¼Ñ',
      'editCompany': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ',
      'renameCompany': 'ÐÐµÑÐµÐ¸Ð¼ÐµÐ½Ð¾Ð²Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ',
      'newCompanyName': 'ÐÐ¾Ð²Ð¾Ðµ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ðµ',
      'deleteCompany': 'Ð£Ð´Ð°Ð»Ð¸ÑÑ ÑÐ¸ÑÐ¼Ñ Ð¿Ð¾Ð»Ð½Ð¾ÑÑÑÑ',
      'deleteCompanyTitle': 'Ð£Ð´Ð°Ð»Ð¸ÑÑ ÑÐ¸ÑÐ¼Ñ?',
      'deleteCompanyText':
          'Ð¤Ð¸ÑÐ¼Ð° Ð±ÑÐ´ÐµÑ ÑÐ´Ð°Ð»ÐµÐ½Ð° Ð¿Ð¾Ð»Ð½Ð¾ÑÑÑÑ: Ð»ÑÐ´Ð¸, Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ, Ð²ÑÐ´Ð°ÑÐ¸, ÑÑÐ°ÑÑÐ½Ð¸ÐºÐ¸ Ð¸ ÐºÐ¾Ð´.\n\nÐÐµÐ¹ÑÑÐ²Ð¸Ðµ Ð½ÐµÐ¾Ð±ÑÐ°ÑÐ¸Ð¼Ð¾.',
      'archivedCompany': 'Ð¤Ð¸ÑÐ¼Ð° ÑÐ´Ð°Ð»ÐµÐ½Ð° (Ð°ÑÑÐ¸Ð²).',

      // Employees list
      'employees': 'Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¸',
      'noEmployees': 'ÐÐ¾ÐºÐ° Ð½ÐµÑ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¾Ð².',
      'editMyProfile': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ Ð¼Ð¾Ð¹ Ð¿ÑÐ¾ÑÐ¸Ð»Ñ',
      'linkPassword': 'ÐÑÐ¾Ð´ Ð½Ð° ÐÐ: Ð¿ÑÐ¸Ð²ÑÐ·Ð°ÑÑ/ÑÐ¼ÐµÐ½Ð¸ÑÑ Ð¿Ð°ÑÐ¾Ð»Ñ',
      'setPassword': 'Ð£ÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÑ Ð¿Ð°ÑÐ¾Ð»Ñ',
      'changePassword': 'Ð¡Ð¼ÐµÐ½Ð¸ÑÑ Ð¿Ð°ÑÐ¾Ð»Ñ',
      'newPassword': 'ÐÐ¾Ð²ÑÐ¹ Ð¿Ð°ÑÐ¾Ð»Ñ (Ð¼Ð¸Ð½Ð¸Ð¼ÑÐ¼ 6 ÑÐ¸Ð¼Ð²Ð¾Ð»Ð¾Ð²)',
      'repeatPassword': 'ÐÐ¾Ð²ÑÐ¾ÑÐ¸ÑÐµ Ð¿Ð°ÑÐ¾Ð»Ñ',
      'passwordsNotMatch': 'ÐÐ°ÑÐ¾Ð»Ð¸ Ð½Ðµ ÑÐ¾Ð²Ð¿Ð°Ð´Ð°ÑÑ',
      'needReLogin': 'ÐÑÐ¶Ð½Ð¾ Ð¿ÐµÑÐµÐ»Ð¾Ð³Ð¸Ð½Ð¸ÑÑÑÑ (Google) Ð¸ Ð¿Ð¾Ð²ÑÐ¾ÑÐ¸ÑÑ',
      'sendReset': 'ÐÑÐ¿ÑÐ°Ð²Ð¸ÑÑ ÑÐ±ÑÐ¾Ñ Ð¿Ð°ÑÐ¾Ð»Ñ Ð½Ð° email',
      'done': 'ÐÐ¾ÑÐ¾Ð²Ð¾',

      // Errors / Fix
      'fixAccess':
          'ÐÐ¾ÑÐ¾Ð¶Ðµ, Ñ Ð°ÐºÐºÐ°ÑÐ½ÑÐ° Ð½ÐµÑ Ð´Ð¾ÑÑÑÐ¿Ð° Ðº ÑÐ¸ÑÐ¼Ðµ (PERMISSION_DENIED) Ð¸Ð»Ð¸ activeCompanyId ÑÐºÐ°Ð·ÑÐ²Ð°ÐµÑ Ð½Ðµ ÑÑÐ´Ð°.\n'
              'Ð¯ ÑÐ±ÑÐ¾ÑÐ¸Ð» activeCompanyId, ÑÑÐ¾Ð±Ñ ÑÑ Ð¼Ð¾Ð³ Ð²ÑÐ±ÑÐ°ÑÑ/ÑÐ¾Ð·Ð´Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ Ð·Ð°Ð½Ð¾Ð²Ð¾.',
      'errUserRead': 'ÐÑÐ¸Ð±ÐºÐ° ÑÑÐµÐ½Ð¸Ñ Ð¿ÑÐ¾ÑÐ¸Ð»Ñ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ',
      'errCompanyRead': 'ÐÑÐ¸Ð±ÐºÐ° ÑÑÐµÐ½Ð¸Ñ ÑÐ¸ÑÐ¼Ñ',
      'errMemberRead': 'ÐÑÐ¸Ð±ÐºÐ° ÑÑÐµÐ½Ð¸Ñ ÑÑÐ°ÑÑÐ½Ð¸ÐºÐ° ÑÐ¸ÑÐ¼Ñ',
      'noAccessCompany': 'ÐÐµÑ Ð´Ð¾ÑÑÑÐ¿Ð° Ðº ÑÐ¸ÑÐ¼Ðµ',
      'removedFromCompany': 'ÐÐ°Ñ ÑÐ´Ð°Ð»Ð¸Ð»Ð¸ Ð¸Ð· ÑÐ¸ÑÐ¼Ñ. ÐÐ²ÐµÐ´Ð¸ÑÐµ ÐºÐ¾Ð´ Ð·Ð°Ð½Ð¾Ð²Ð¾ Ð¸ Ð´Ð¾Ð¶Ð´Ð¸ÑÐµÑÑ Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ¶Ð´ÐµÐ½Ð¸Ñ.',
      'selectModeFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð²ÑÐ±ÐµÑÐ¸ÑÐµ: ÐÐ«ÐÐÐ¢Ð¬ Ð¸Ð»Ð¸ ÐÐÐ ÐÐ£Ð¢Ð¬',
      'selectPersonForReturnFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð²ÑÐ±ÐµÑÐ¸ÑÐµ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ° Ð´Ð»Ñ ÐÐÐÐÐ ÐÐ¢Ð',
      'noRightsIssueReturn': 'ÐÐµÑ Ð¿ÑÐ°Ð² Ð½Ð° Ð²ÑÐ´Ð°ÑÑ/Ð²Ð¾Ð·Ð²ÑÐ°Ñ',
      'selectPersonAndTool': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ° Ð¸ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'searchEmployee': 'ÐÐ¾Ð¸ÑÐº ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°...',
      'searchTool': 'ÐÐ¾Ð¸ÑÐº Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°...',
      'issueUpper': 'ÐÐ«ÐÐÐ¢Ð¬',
      'returnUpper': 'ÐÐÐ ÐÐ£Ð¢Ð¬',
      'invShort': 'ÐÐ½Ð²',
      'invNumber': 'ÐÐ½Ð². Ð½Ð¾Ð¼ÐµÑ',
      'noName': 'ÐÐµÐ· Ð¸Ð¼ÐµÐ½Ð¸',
      'noTitle': 'ÐÐµÐ· Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ',
      'noFreeTools': 'ÐÐµÑ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½ÑÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð²',
      'noToolsOnHands': 'ÐÐµÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ° Ð½Ð° ÑÑÐºÐ°Ñ',
      'whoSelectEmployee': 'ÐÐ¾Ð¼Ñ Ð²ÑÐ´Ð°ÐµÐ¼?',
      'whoField': 'ÐÐ¢Ð (ÐÑÐ±Ð¾Ñ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°)',
      'whatSelectEmployeeTool': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ° Ð¸ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'whatSelectFreeTool': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½ÑÐ¹ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'whatFieldOnHands': 'Ð§Ð¢Ð (ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ ÑÑÐ¾Ð³Ð¾ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°)',
      'whatFieldFree': 'Ð§Ð¢Ð (Ð¡Ð²Ð¾Ð±Ð¾Ð´Ð½ÑÐ¹ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ)',
      'confirmIssue': 'ÐÐ¾Ð´ÑÐ²ÐµÑÐ´Ð¸ÑÑ Ð²ÑÐ´Ð°ÑÑ',
      'confirmReturn': 'ÐÐ¾Ð´ÑÐ²ÐµÑÐ´Ð¸ÑÑ Ð²Ð¾Ð·Ð²ÑÐ°Ñ',
    'issueTab': 'ÐÑÐ´Ð°ÑÐ°',
    'returnTab': 'ÐÐ¾Ð·Ð²ÑÐ°Ñ',
    'role_owner': 'ÐÐ»Ð°Ð´ÐµÐ»ÐµÑ',
    'role_admin': 'ÐÐ´Ð¼Ð¸Ð½',
      'role_foreman': 'ÐÑÐ¾ÑÐ°Ð±',
    'role_employee': 'Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº',
    'searchByNameOrPhone': 'ÐÐ¾Ð¸ÑÐº Ð¿Ð¾ Ð¸Ð¼ÐµÐ½Ð¸ Ð¸Ð»Ð¸ ÑÐµÐ»ÐµÑÐ¾Ð½Ñ...',
    'searchSite': 'ÐÐ¾Ð¸ÑÐº Ð¿Ð¾ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ Ð¸Ð»Ð¸ Ð°Ð´ÑÐµÑÑ...',
    'editProfile': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ Ð¿ÑÐ¾ÑÐ¸Ð»Ñ',
    'setRole': 'ÐÐ°Ð·Ð½Ð°ÑÐ¸ÑÑ ÑÐ¾Ð»Ñ',
      'langRu': 'Ð ÑÑÑÐºÐ¸Ð¹',
      'langUk': 'Ð£ÐºÑÐ°ÑÐ½ÑÑÐºÐ°',
      'langPl': 'Polski',
      'langEn': 'English',
      'searchByNameOrInv': 'ÐÐ¾Ð¸ÑÐº Ð¿Ð¾ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ Ð¸Ð»Ð¸ â...',
      'searchByToolOrLastName': 'ÐÐ¾Ð¸ÑÐº Ð¿Ð¾ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ Ð¸Ð»Ð¸ ÑÐ°Ð¼Ð¸Ð»Ð¸Ð¸...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Ð¡ÑÐ°ÑÑÑ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°',
      'empStatusActive': 'ÐÐºÑÐ¸Ð²ÐµÐ½',
      'empStatusFired': 'Ð£Ð²Ð¾Ð»ÐµÐ½',
      'toolStatus': 'Ð¡ÑÐ°ÑÑÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°',
      'toolStatusActive': 'Ð Ð°Ð±Ð¾ÑÐ¸Ð¹',
      'toolStatusRepair': 'Ð ÑÐµÐ¼Ð¾Ð½ÑÐµ',
      'toolStatusDisposed': 'Ð¡Ð¿Ð¸ÑÐ°Ð½',
      'markToolActive': 'Ð¡Ð´ÐµÐ»Ð°ÑÑ ÑÐ°Ð±Ð¾ÑÐ¸Ð¼',
      'markToolRepair': 'ÐÑÐ¿ÑÐ°Ð²Ð¸ÑÑ Ð² ÑÐµÐ¼Ð¾Ð½Ñ',
      'markToolDisposed': 'Ð¡Ð¿Ð¸ÑÐ°ÑÑ (ÑÑÐ¸Ð»Ð¸Ð·Ð°ÑÐ¸Ñ)',
      'statusNote': 'ÐÐ¾Ð¼Ð¼ÐµÐ½ÑÐ°ÑÐ¸Ð¹',
      'reportsByTool': 'ÐÐ¾ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ',
      'reportsByPerson': 'ÐÐ¾ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÑ',
      'selectTool': 'ÐÑÐ±ÐµÑÐ¸ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'selectPerson': 'ÐÑÐ±ÐµÑÐ¸ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°',
      'selectToolFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð²ÑÐ±ÐµÑÐ¸ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'selectPersonFirst': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð²ÑÐ±ÐµÑÐ¸ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°',
      'warehouse': 'Ð¡ÐºÐ»Ð°Ð´',
      'where': 'ÐÐ´Ðµ',
      'issuedAt': 'ÐÑÐ´Ð°Ð½Ð¾',
      'noData': 'ÐÐµÑ Ð´Ð°Ð½Ð½ÑÑ',
      'noIssued': 'ÐÐ¸ÑÐµÐ³Ð¾ Ð½Ðµ Ð²ÑÐ´Ð°Ð½Ð¾',

      'tariffLimitsTitle': 'Ð¢Ð°ÑÐ¸Ñ Ð¸ Ð»Ð¸Ð¼Ð¸ÑÑ',
      'subscriptionTitle': 'ÐÐ¾Ð´Ð¿Ð¸ÑÐºÐ°',
      'subscriptionStatusLabel': 'Ð¡ÑÐ°ÑÑÑ',
      'subscriptionModeLabel': 'Ð ÐµÐ¶Ð¸Ð¼',
      'subscriptionValidUntilLabel': 'ÐÐµÐ¹ÑÑÐ²ÑÐµÑ Ð´Ð¾',
      'subscriptionTest': 'Ð¢ÐµÑÑÐ¾Ð²ÑÐ¹ ÑÐµÐ¶Ð¸Ð¼',
      'subscriptionLive': 'ÐÐ»Ð°ÑÐ½ÑÐ¹ ÑÐµÐ¶Ð¸Ð¼',
      'subscriptionActive': 'ÐÐºÑÐ¸Ð²Ð½Ð°',
      'subscriptionInactive': 'ÐÐµ Ð°ÐºÑÐ¸Ð²Ð½Ð°',
      'buyRenew': 'ÐÑÐ¿Ð¸ÑÑ / ÐÑÐ¾Ð´Ð»Ð¸ÑÑ',
      'buyRenewSoon': 'ÐÐ¿Ð»Ð°ÑÐ° ÑÐºÐ¾ÑÐ¾ Ð±ÑÐ´ÐµÑ Ð´Ð¾ÑÑÑÐ¿Ð½Ð°. ÐÐ¾ÐºÐ° Ð´Ð»Ñ Ð¿Ð¾ÐºÑÐ¿ÐºÐ¸/Ð¿ÑÐ¾Ð´Ð»ÐµÐ½Ð¸Ñ ÑÐ²ÑÐ¶Ð¸ÑÐµÑÑ Ñ Ð¿Ð¾Ð´Ð´ÐµÑÐ¶ÐºÐ¾Ð¹.',
      'planLabel': 'Ð¢Ð°ÑÐ¸Ñ',
      'perMonth': 'Ð¼ÐµÑÑÑ',
      'peopleLimitLabel': 'ÐÐ¸Ð¼Ð¸Ñ Ð»ÑÐ´ÐµÐ¹',
      'usedActiveLabel': 'ÐÑÐ¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°Ð½Ð¾ (Ð°ÐºÑÐ¸Ð²Ð½ÑÐµ)',
      'inactiveNotCountedNote': 'Ð£Ð²Ð¾Ð»ÐµÐ½Ð½ÑÐµ/Ð½ÐµÐ°ÐºÑÐ¸Ð²Ð½ÑÐµ Ð½Ðµ ÑÑÐ¸ÑÐ°ÑÑÑÑ Ð² Ð»Ð¸Ð¼Ð¸Ñ.',
      'billingModeLabel': 'Ð ÐµÐ¶Ð¸Ð¼ Ð¾Ð¿Ð»Ð°ÑÑ',
      'billingTest': 'Ð¢ÐÐ¡Ð¢',
      'billingLive': 'ÐÐÐÐÐÐ',
      'changePlan': 'ÐÐ·Ð¼ÐµÐ½Ð¸ÑÑ ÑÐ°ÑÐ¸Ñ',
      'planChangeOnlyOwner': 'Ð¢Ð¾Ð»ÑÐºÐ¾ Ð²Ð»Ð°Ð´ÐµÐ»ÐµÑ (owner) Ð¼Ð¾Ð¶ÐµÑ Ð¼ÐµÐ½ÑÑÑ ÑÐ°ÑÐ¸Ñ.',
      'selectPlan': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ ÑÐ°ÑÐ¸Ñ',
      'ok': 'OK',
      'planSaved': 'Ð¢Ð°ÑÐ¸Ñ ÑÐ¾ÑÑÐ°Ð½ÑÐ½',
      'gpsNotInPlan': 'GPS-ÑÑÐµÐºÐ¸Ð½Ð³ Ð´Ð¾ÑÑÑÐ¿ÐµÐ½ Ñ ÑÐ°ÑÐ¸ÑÐ° ÐÑÐ¾ Ð¸ Ð²ÑÑÐµ',
      'gpsIncluded': 'GPS â',
      'gpsNotIncluded': 'GPS â',
      'supportTitle': 'ÐÐ¾Ð´Ð´ÐµÑÐ¶ÐºÐ°',
      'supportDesc': 'ÐÐ¾ Ð²Ð¾Ð¿ÑÐ¾ÑÐ°Ð¼ ÑÐ°Ð±Ð¾ÑÑ Ð¿ÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ñ Ð²Ñ Ð¼Ð¾Ð¶ÐµÑÐµ ÑÐ²ÑÐ·Ð°ÑÑÑÑ Ñ Ð½Ð°Ð¼Ð¸:',
      'versionLabel': 'ÐÐµÑÑÐ¸Ñ',
      'emailLabel': 'Email',
      'telegramLabel': 'Telegram',
      'myShift': 'ÐÐ¾Ñ ÑÐ¼ÐµÐ½Ð°',
      'startShift': 'ÐÐ°ÑÐ°ÑÑ ÑÐ¼ÐµÐ½Ñ',
      'endShift': 'ÐÐ°Ð²ÐµÑÑÐ¸ÑÑ ÑÐ¼ÐµÐ½Ñ',
      'currentShift': 'Ð¢ÐµÐºÑÑÐ°Ñ ÑÐ¼ÐµÐ½Ð°',
      'shiftStarted': 'Ð¡Ð¼ÐµÐ½Ð° Ð½Ð°ÑÐ°Ð»Ð°ÑÑ!',
      'shiftEnded': 'Ð¡Ð¼ÐµÐ½Ð° Ð·Ð°Ð²ÐµÑÑÐµÐ½Ð°!',
      'shiftActive': 'Ð¡Ð¼ÐµÐ½Ð° Ð°ÐºÑÐ¸Ð²Ð½Ð°',
      'shiftStart': 'ÐÐ°ÑÐ°Ð»Ð¾',
      'shiftEnd': 'ÐÐ¾Ð½ÐµÑ',
      'selectSite': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ Ð¾Ð±ÑÐµÐºÑ',
      'noSites': 'ÐÐ±ÑÐµÐºÑÑ Ð½Ðµ Ð´Ð¾Ð±Ð°Ð²Ð»ÐµÐ½Ñ. ÐÐ¾Ð¿ÑÐ¾ÑÐ¸ÑÐµ Ð°Ð´Ð¼Ð¸Ð½Ð¸ÑÑÑÐ°ÑÐ¾ÑÐ°.',
      'writeReport': 'ÐÑÑÑÑ Ð·Ð° ÑÐ¼ÐµÐ½Ñ',
      'whatDone': 'Ð§ÑÐ¾ Ð±ÑÐ»Ð¾ ÑÐ´ÐµÐ»Ð°Ð½Ð¾',
      'workReport': 'ÐÑÑÑÑ',
      'timesheets': 'Ð¢Ð°Ð±ÐµÐ»Ñ ÑÐ¼ÐµÐ½',
      'myTimesheets': 'ÐÐ¾Ð¸ ÑÐ¼ÐµÐ½Ñ',
      'allTimesheets': 'ÐÑÐµ ÑÐ¼ÐµÐ½Ñ',
      'totalHours': 'ÐÑÐ¾Ð³Ð¾ ÑÐ°ÑÐ¾Ð²',
      'shiftsCount': 'Ð¡Ð¼ÐµÐ½',
      'manageSites': 'Ð£Ð¿ÑÐ°Ð²Ð»ÐµÐ½Ð¸Ðµ Ð¾Ð±ÑÐµÐºÑÐ°Ð¼Ð¸',
      'sites': 'ÐÐ±ÑÐµÐºÑÑ',
      'addSite': 'ÐÐ¾Ð±Ð°Ð²Ð¸ÑÑ Ð¾Ð±ÑÐµÐºÑ',
      'editSite': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ Ð¾Ð±ÑÐµÐºÑ',
      'siteName': 'ÐÐ°Ð·Ð²Ð°Ð½Ð¸Ðµ Ð¾Ð±ÑÐµÐºÑÐ°',
      'siteAddress': 'ÐÐ´ÑÐµÑ',
      'siteRadius': 'Ð Ð°Ð´Ð¸ÑÑ ÑÐµÐº-Ð¸Ð½Ð° (Ð¼)',
      'gpsInterval': 'ÐÐ½ÑÐµÑÐ²Ð°Ð» GPS (Ð¼Ð¸Ð½)',
      'gpsPermissionDenied': 'GPS Ð½ÐµÐ´Ð¾ÑÑÑÐ¿ÐµÐ½ â ÑÐ¼ÐµÐ½Ð° Ð½Ð°ÑÐ°ÑÐ° Ð±ÐµÐ· Ð¿ÑÐ¾Ð²ÐµÑÐºÐ¸ ÐºÐ¾Ð¾ÑÐ´Ð¸Ð½Ð°Ñ',
      'gpsWarningTitle': 'ÐÑ Ð²Ð½Ðµ Ð·Ð¾Ð½Ñ Ð¾Ð±ÑÐµÐºÑÐ°',
      'gpsWarningText': 'ÐÐ°ÑÐµ Ð¼ÐµÑÑÐ¾Ð¿Ð¾Ð»Ð¾Ð¶ÐµÐ½Ð¸Ðµ Ð½Ðµ ÑÐ¾Ð²Ð¿Ð°Ð´Ð°ÐµÑ Ñ Ð°Ð´ÑÐµÑÐ¾Ð¼ Ð¾Ð±ÑÐµÐºÑÐ°.',
      'distance': 'Ð Ð°ÑÑÑÐ¾ÑÐ½Ð¸Ðµ',
      'startAnyway': 'ÐÐ°ÑÐ°ÑÑ Ð²ÑÑ ÑÐ°Ð²Ð½Ð¾',
      'allTime': 'ÐÑÑ Ð²ÑÐµÐ¼Ñ',
      'allSites': 'ÐÑÐµ Ð¾Ð±ÑÐµÐºÑÑ',
      'allPeople': 'ÐÑÐµ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¸',
      'exportPdf': 'Ð­ÐºÑÐ¿Ð¾ÑÑ PDF',
      'exportXlsx': 'Ð­ÐºÑÐ¿Ð¾ÑÑ Excel',
      'shiftTypeHourly': 'ÐÐ¾ ÑÐ°ÑÐ°Ð¼',
      'shiftTypeAccord': 'ÐÐºÐºÐ¾ÑÐ´',
      'chooseShiftType': 'Ð¢Ð¸Ð¿ ÑÐ¼ÐµÐ½Ñ',
      'shiftType': 'Ð¢Ð¸Ð¿ ÑÐ°Ð±Ð¾ÑÑ',
      'reportRequired': 'ÐÐ°Ð¿Ð¾Ð»Ð½Ð¸ÑÐµ Ð¾ÑÑÑÑ â ÑÑÐ¾ Ð±ÑÐ»Ð¾ ÑÐ´ÐµÐ»Ð°Ð½Ð¾',
      'viewSites': 'ÐÑÐµ Ð¾Ð±ÑÐµÐºÑÑ',
      'navigateTo': 'ÐÐ°ÑÑÑÑÑ',
      'linkUser': 'ÐÑÐ¸Ð²ÑÐ·Ð°ÑÑ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ',
      'linkedUser': 'ÐÑÐ¸Ð²ÑÐ·Ð°Ð½ Ðº',
      'unlinkUser': 'ÐÑÐ²ÑÐ·Ð°ÑÑ',
      'selectUserToLink': 'ÐÑÐ±ÐµÑÐ¸ÑÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ',
      'notLinked': 'ÐÐºÐºÐ°ÑÐ½Ñ Ð½Ðµ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½ Ðº Ð°Ð½ÐºÐµÑÐµ. ÐÐ±ÑÐ°ÑÐ¸ÑÐµÑÑ Ðº Ð°Ð´Ð¼Ð¸Ð½Ð¸ÑÑÑÐ°ÑÐ¾ÑÑ.',
      'personTypePerson': 'Ð§ÐµÐ»Ð¾Ð²ÐµÐº',
      'personTypeObject': 'ÐÐ±ÑÐµÐºÑ',
      'noObjects': 'ÐÐ±ÑÐµÐºÑÐ¾Ð² Ð¿Ð¾ÐºÐ° Ð½ÐµÑ. ÐÐ°Ð¶Ð¼Ð¸ +',
      'objectCompleted': 'ÐÐ°Ð²ÐµÑÑÑÐ½',
      'markObjectCompleted': 'ÐÐ°Ð²ÐµÑÑÐ¸ÑÑ Ð¾Ð±ÑÐµÐºÑ',
      'personTab': 'ÐÑÐ´Ð¸',
      'objectTab': 'ÐÐ±ÑÐµÐºÑÑ',
      'cannotCompleteHasTools': 'ÐÐµÐ»ÑÐ·Ñ Ð·Ð°Ð²ÐµÑÑÐ¸ÑÑ: Ð½Ð° Ð¾Ð±ÑÐµÐºÑÐµ {n} Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð²',
      'cannotFireHasTools': 'ÐÐµÐ»ÑÐ·Ñ ÑÐ²Ð¾Ð»Ð¸ÑÑ: Ñ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ° {n} Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð²',
      'addObject': 'ÐÐ¾Ð±Ð°Ð²Ð¸ÑÑ Ð¾Ð±ÑÐµÐºÑ',
      'shiftReminder10hTitle': 'Ð¡Ð¼ÐµÐ½Ð° Ð¸Ð´ÑÑ 10 ÑÐ°ÑÐ¾Ð²',
      'shiftReminder10hBody': 'Ð¡Ð¼ÐµÐ½Ð° Ð°ÐºÑÐ¸Ð²Ð½Ð° Ð±Ð¾Ð»ÑÑÐµ 10 ÑÐ°ÑÐ¾Ð². ÐÐµ Ð·Ð°Ð±ÑÐ´ÑÑÐµ Ð·Ð°ÐºÑÑÑÑ.',
      'shiftReminder12hTitle': 'â ï¸ Ð¡Ð¼ÐµÐ½Ð° 12 ÑÐ°ÑÐ¾Ð²!',
      'shiftReminder12hBody': 'ÐÐ½Ð¸Ð¼Ð°Ð½Ð¸Ðµ: ÑÐ¼ÐµÐ½Ð° Ð¸Ð´ÑÑ Ð±Ð¾Ð»ÑÑÐµ 12 ÑÐ°ÑÐ¾Ð². ÐÐ°ÐºÑÐ¾Ð¹ÑÐµ ÑÐ¼ÐµÐ½Ñ.',
      'offlineBanner': 'ÐÐµÑ Ð¿Ð¾Ð´ÐºÐ»ÑÑÐµÐ½Ð¸Ñ â¢ Ð´Ð°Ð½Ð½ÑÐµ Ð¸Ð· ÐºÑÑÐ°',
      'alreadyHaveActiveShift': 'Ð£ Ð²Ð°Ñ ÑÐ¶Ðµ ÐµÑÑÑ Ð°ÐºÑÐ¸Ð²Ð½Ð°Ñ ÑÐ¼ÐµÐ½Ð°. ÐÐ°ÐºÑÐ¾Ð¹ÑÐµ ÐµÑ Ð¿ÐµÑÐµÐ´ Ð½Ð°ÑÐ°Ð»Ð¾Ð¼ Ð½Ð¾Ð²Ð¾Ð¹.',
      'forceCloseShift': 'ÐÑÐ¸Ð½ÑÐ´Ð¸ÑÐµÐ»ÑÐ½Ð¾ Ð·Ð°ÐºÑÑÑÑ',
      'forceCloseShiftHint': 'Ð¡Ð¼ÐµÐ½Ð° Ð±ÑÐ´ÐµÑ Ð·Ð°ÐºÑÑÑÐ° Ð¿ÑÑÐ¼Ð¾ ÑÐµÐ¹ÑÐ°Ñ. ÐÑ Ð¼Ð¾Ð¶ÐµÑÐµ Ð´Ð¾Ð±Ð°Ð²Ð¸ÑÑ Ð¾ÑÑÑÑ.',
      'shiftClosed': 'Ð¡Ð¼ÐµÐ½Ð° Ð·Ð°ÐºÑÑÑÐ°.',
      'archive': 'ÐÑÑÐ¸Ð²',
      'noArchive': 'ÐÑÑÐ¸Ð² Ð¿ÑÑÑ',
      'notifications': 'Ð£Ð²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ñ',
      'noNotifications': 'ÐÐµÑ Ð½Ð¾Ð²ÑÑ ÑÐ²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ð¹',
      'newMemberRequest': 'ÐÐ¾Ð²Ð°Ñ Ð·Ð°ÑÐ²ÐºÐ° Ð½Ð° Ð²ÑÑÑÐ¿Ð»ÐµÐ½Ð¸Ðµ',
      'markAllRead': 'ÐÑÐ¼ÐµÑÐ¸ÑÑ Ð²ÑÐµ Ð¿ÑÐ¾ÑÐ¸ÑÐ°Ð½Ð½ÑÐ¼Ð¸',
      'pendingRequests': 'ÐÐ°ÑÐ²ÐºÐ¸',
      'copyTool': 'ÐÐ¾Ð¿Ð¸ÑÐ¾Ð²Ð°ÑÑ',
      'toolCopied': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ ÑÐºÐ¾Ð¿Ð¸ÑÐ¾Ð²Ð°Ð½',
      'sortNameAZ': 'ÐÐ°Ð·Ð²Ð°Ð½Ð¸Ðµ Ð-Ð¯',
      'sortCountDesc': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð±Ð¾Ð»ÑÑÐ¸Ðµ Ð³ÑÑÐ¿Ð¿Ñ',
      'sortDateDesc': 'Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð½Ð¾Ð²ÑÐµ',
      'darkTheme': 'Ð¢ÑÐ¼Ð½Ð°Ñ ÑÐµÐ¼Ð°',
      'lightTheme': 'Ð¡Ð²ÐµÑÐ»Ð°Ñ ÑÐµÐ¼Ð°',
      'systemTheme': 'Ð¡Ð¸ÑÑÐµÐ¼Ð½Ð°Ñ ÑÐµÐ¼Ð°',
      'printQr': 'Ð Ð°ÑÐ¿ÐµÑÐ°ÑÐ°ÑÑ QR',
      'saveAsPng': 'Ð¡Ð¾ÑÑÐ°Ð½Ð¸ÑÑ PNG',
      'thermalLabel': 'Ð¢ÐµÑÐ¼Ð¾-ÑÑÐ¸ÐºÐµÑÐºÐ°',
      'printAllQr': 'ÐÑÐµ QR Ð½Ð° Ð»Ð¸ÑÑ',
      'noResults': 'ÐÐ¸ÑÐµÐ³Ð¾ Ð½Ðµ Ð½Ð°Ð¹Ð´ÐµÐ½Ð¾',
      'actPdf': 'ÐÐºÑ PDF',
      'nakladnayaPdf': 'ÐÐ°ÐºÐ»Ð°Ð´Ð½Ð°Ñ PDF',
      'yes': 'ÐÐ°',
      'no': 'ÐÐµÑ',
      'name': 'ÐÐ¼Ñ',
      'toolName': 'ÐÐ°Ð·Ð²Ð°Ð½Ð¸Ðµ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°',
      'editTool': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'editEmployee': 'Ð ÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°',
      'cannotSetToolStatusOnHands': 'ÐÐµÐ»ÑÐ·Ñ Ð¸Ð·Ð¼ÐµÐ½Ð¸ÑÑ ÑÑÐ°ÑÑÑ: Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½Ñ Ð½Ð° ÑÑÐºÐ°Ñ',
      'gpsTrack': 'GPS-ÑÑÐµÐº',
      'noGpsData': 'ÐÐµÑ GPS-Ð´Ð°Ð½Ð½ÑÑ',
},
    AppLang.uk: {
      'appTitle': 'ToolKeeper',
      'login': 'ÐÑÑÐ´',
      'register': 'Ð ÐµÑÑÑÑÐ°ÑÑÑ',
      'enter': 'Ð£Ð²ÑÐ¹ÑÐ¸',
      'logout': 'ÐÐ¸Ð¹ÑÐ¸',
      'people': 'ÐÑÐ´Ð¸',
      'tools': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¸',
      'tool': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'inv': 'ÐÐ½Ð². â',
      'issue': 'ÐÐ¸Ð´Ð°ÑÐ°',
      'profile': 'ÐÑÐ¾ÑÑÐ»Ñ',
      'chooseLang': 'ÐÐ±ÐµÑÐ¸ Ð¼Ð¾Ð²Ñ',
      'chooseCompany': 'ÐÐ±ÐµÑÑÑÑ Ð²Ð°ÑÑ ÑÑÑÐ¼Ñ',
      'searchingCompany': 'Ð¨ÑÐºÐ°Ñ Ð²Ð°ÑÑ ÑÑÑÐ¼Ñ...',
      'companyNotFound': 'Ð¤ÑÑÐ¼Ñ Ð½Ðµ Ð·Ð½Ð°Ð¹Ð´ÐµÐ½Ð¾',
      'companyDeleted': 'Ð¤ÑÑÐ¼Ñ Ð²Ð¸Ð´Ð°Ð»ÐµÐ½Ð¾',
      'noAccessCompany': 'ÐÐµÐ¼Ð°Ñ Ð´Ð¾ÑÑÑÐ¿Ñ Ð´Ð¾ ÑÑÑÐ¼Ð¸',
      'removedFromCompany': 'ÐÐ°Ñ Ð²Ð¸Ð´Ð°Ð»Ð¸Ð»Ð¸ Ð· ÑÑÑÐ¼Ð¸. ÐÐ²ÐµÐ´ÑÑÑ ÐºÐ¾Ð´ ÑÐµ ÑÐ°Ð· Ñ Ð´Ð¾ÑÐµÐºÐ°Ð¹ÑÐµÑÑ Ð¿ÑÐ´ÑÐ²ÐµÑÐ´Ð¶ÐµÐ½Ð½Ñ.',
      'leaveCompany': 'ÐÐ¸Ð¹ÑÐ¸ / Ð¾Ð±ÑÐ°ÑÐ¸ ÑÐ½ÑÑ ÑÑÑÐ¼Ñ',
      'createCompany': 'Ð¡ÑÐ²Ð¾ÑÐ¸ÑÐ¸ ÑÑÑÐ¼Ñ',
      'enterInviteCode': 'ÐÐ²ÐµÐ´ÑÑÑ ÐºÐ¾Ð´ Ð·Ð°Ð¿ÑÐ¾ÑÐµÐ½Ð½Ñ',
      'joinCompany': 'ÐÑÐ¸ÑÐ´Ð½Ð°ÑÐ¸ÑÑ',
      'or': 'ÐÐÐ',
      'companyName': 'ÐÐ°Ð·Ð²Ð° ÑÑÑÐ¼Ð¸',
      'create': 'Ð¡ÑÐ²Ð¾ÑÐ¸ÑÐ¸',
      'myCompany': 'ÐÐ¾Ñ ÑÑÑÐ¼Ð°',
      'myProfile': 'ÐÑÐ¹ Ð¿ÑÐ¾ÑÑÐ»Ñ',
      'role': 'Ð Ð¾Ð»Ñ',
      'role_owner': 'ÐÐ»Ð°ÑÐ½Ð¸Ðº',
      'role_admin': 'ÐÐ´Ð¼ÑÐ½ÑÑÑÑÐ°ÑÐ¾Ñ',
      'role_foreman': 'ÐÑÐ¾ÑÐ°Ð±',
      'role_employee': 'ÐÑÐ°ÑÑÐ²Ð½Ð¸Ðº',
      'editRoles': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ ÑÐ¾Ð»Ñ',
      'save': 'ÐÐ±ÐµÑÐµÐ³ÑÐ¸',
      'cancel': 'Ð¡ÐºÐ°ÑÑÐ²Ð°ÑÐ¸',
      'inviteCode': 'ÐÐ¾Ð´ Ð·Ð°Ð¿ÑÐ¾ÑÐµÐ½Ð½Ñ',
      'copy': 'ÐÐ¾Ð¿ÑÑÐ²Ð°ÑÐ¸',
      'copied': 'Ð¡ÐºÐ¾Ð¿ÑÐ¹Ð¾Ð²Ð°Ð½Ð¾',
      'share': 'ÐÐ¾Ð´ÑÐ»Ð¸ÑÐ¸ÑÑ',
      'pendingRequests': 'ÐÐ°ÑÐ²ÐºÐ¸ Ð½Ð° Ð²ÑÑÑÐ¿',
      'accept': 'ÐÑÐ¸Ð¹Ð½ÑÑÐ¸',
      'deny': 'ÐÑÐ´ÑÐ¸Ð»Ð¸ÑÐ¸',
      'noRequests': 'ÐÐµÐ¼Ð°Ñ Ð·Ð°ÑÐ²Ð¾Ðº',
      'members': 'Ð£ÑÐ°ÑÐ½Ð¸ÐºÐ¸',
      'noMembers': 'ÐÐµÐ¼Ð°Ñ ÑÑÐ°ÑÐ½Ð¸ÐºÑÐ²',
      'addEmployee': 'ÐÐ¾Ð´Ð°ÑÐ¸ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'employeeFirstName': "ÐÐ¼'Ñ",
      'employeeLastName': 'ÐÑÑÐ·Ð²Ð¸ÑÐµ',
      'employeePosition': 'ÐÐ¾ÑÐ°Ð´Ð°',
      'phone': 'Ð¢ÐµÐ»ÐµÑÐ¾Ð½',
      'add': 'ÐÐ¾Ð´Ð°ÑÐ¸',
      'editEmployee': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'deleteEmployee': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'delete': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸',
      'deleteConfirm': 'Ð¢Ð¾ÑÐ½Ð¾ Ð²Ð¸Ð´Ð°Ð»Ð¸ÑÐ¸?',
      'searchEmployee': 'ÐÐ¾ÑÑÐº Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°...',
      'noEmployees': 'ÐÐµÐ¼Ð°Ñ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÑÐ²',
      'addTool': 'ÐÐ¾Ð´Ð°ÑÐ¸ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'toolName': 'ÐÐ°Ð·Ð²Ð° ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑ',
      'toolInv': 'ÐÐ½Ð². Ð½Ð¾Ð¼ÐµÑ',
      'addToolBtn': 'ÐÐ¾Ð´Ð°ÑÐ¸',
      'editTool': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'deleteTool': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'searchTool': 'ÐÐ¾ÑÑÐº ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑ...',
      'noTools': 'ÐÐµÐ¼Ð°Ñ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²',
      'issueTitle': 'ÐÐ¸Ð´Ð°ÑÐ° / ÐÐ¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'issueTo': 'ÐÐ¸Ð´Ð°ÑÐ¸',
      'returnFrom': 'ÐÐ¾Ð²ÐµÑÐ½ÑÑÐ¸',
      'selectEmployee': 'ÐÐ±ÐµÑÑÑÑ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'selectTool': 'ÐÐ±ÐµÑÑÑÑ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'issued': 'ÐÐ¸Ð´Ð°Ð½Ð¾',
      'returned': 'ÐÐ¾Ð²ÐµÑÐ½ÐµÐ½Ð¾',
      'history': 'ÐÑÑÐ¾ÑÑÑ',
      'searchHistory': 'ÐÐ¾ÑÑÐº Ð¿Ð¾ ÑÑÑÐ¾ÑÑÑ...',
      'noMoves': 'ÐÐµÐ¼Ð°Ñ Ð·Ð°Ð¿Ð¸ÑÑÐ²',
      'moveIssue': 'ÐÐ¸Ð´Ð°ÑÐ°',
      'moveReturn': 'ÐÐ¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'onHands': 'ÐÐ° ÑÑÐºÐ°Ñ',
      'freeTools': 'ÐÑÐ»ÑÐ½Ñ',
      'total': 'ÐÑÑÐ¾Ð³Ð¾',
      'toolsCount': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²',
      'pcs': 'ÑÑ.',
      'report': 'ÐÐ²ÑÑ',
      'filter': 'Ð¤ÑÐ»ÑÑÑ',
      'reset': 'Ð¡ÐºÐ¸Ð½ÑÑÐ¸',
      'export': 'ÐÐºÑÐ¿Ð¾ÑÑ',
      'exportCsv': 'ÐÐºÑÐ¿Ð¾ÑÑ CSV',
      'exportPdf': 'ÐÐºÑÐ¿Ð¾ÑÑ PDF',
      'exportDone': 'ÐÐºÑÐ¿Ð¾ÑÑ Ð³Ð¾ÑÐ¾Ð²Ð¸Ð¹',
      'loading': 'ÐÐ°Ð²Ð°Ð½ÑÐ°Ð¶ÐµÐ½Ð½Ñ...',
      'error': 'ÐÐ¾Ð¼Ð¸Ð»ÐºÐ°',
      'ok': 'ÐÐ',
      'yes': 'Ð¢Ð°Ðº',
      'no': 'ÐÑ',
      'langRu': 'Ð ÑÑÑÐºÐ¸Ð¹',
      'langUk': 'Ð£ÐºÑÐ°ÑÐ½ÑÑÐºÐ°',
      'langPl': 'Polski',
      'langEn': 'English',
      'selectModeFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð²Ð¸Ð±ÐµÑÑÑÑ: ÐÐÐÐÐ¢Ð Ð°Ð±Ð¾ ÐÐÐÐÐ ÐÐ£Ð¢Ð',
      'selectPersonForReturnFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð²Ð¸Ð±ÐµÑÑÑÑ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ° Ð´Ð»Ñ ÐÐÐÐÐ ÐÐÐÐÐ¯',
      'noRightsIssueReturn': 'ÐÐµÐ¼Ð°Ñ Ð¿ÑÐ°Ð² Ð½Ð° Ð²Ð¸Ð´Ð°ÑÑ/Ð¿Ð¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'selectPersonAndTool': 'ÐÐ±ÐµÑÑÑÑ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ° ÑÐ° ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
      'issueUpper': 'ÐÐÐÐÐ¢Ð',
      'returnUpper': 'ÐÐÐÐÐ ÐÐ£Ð¢Ð',
      'invShort': 'ÐÐ½Ð²',
      'invNumber': 'ÐÐ½Ð². Ð½Ð¾Ð¼ÐµÑ',
      'noName': 'ÐÐµÐ· ÑÐ¼ÐµÐ½Ñ',
      'noTitle': 'ÐÐµÐ· Ð½Ð°Ð·Ð²Ð¸',
      'noFreeTools': 'ÐÐµÐ¼Ð°Ñ Ð²ÑÐ»ÑÐ½Ð¸Ñ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²',
      'noToolsOnHands': 'ÐÐµÐ¼Ð°Ñ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ² Ð½Ð° ÑÑÐºÐ°Ñ',
      'whoSelectEmployee': 'ÐÐ¾Ð¼Ñ Ð²Ð¸Ð´Ð°ÑÐ¸',
      'whoField': 'ÐÐ¢Ð (ÐÐ¸Ð±ÑÑ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÐ°)',
      'whatSelectEmployeeTool': 'Ð©Ð¾ Ð²Ð¸Ð´Ð°ÑÐ¸',
      'whatSelectFreeTool': 'Ð©Ð¾ Ð¿Ð¾Ð²ÐµÑÐ½ÑÑÐ¸',
      'whatFieldOnHands': 'Ð§Ð¢Ð (ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ ÑÑÐ¾Ð³Ð¾ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÐ°)',
      'whatFieldFree': 'Ð§Ð¢Ð (ÐÑÐ»ÑÐ½Ð¸Ð¹ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ)',
      'confirmReturn': 'ÐÐ¾Ð²ÐµÑÐ½ÑÑÐ¸',
      'confirmIssue': 'ÐÐ¸Ð´Ð°ÑÐ¸',
      'restoreCompanyError': 'ÐÐµ Ð²Ð´Ð°Ð»Ð¾ÑÑ Ð²ÑÐ´Ð½Ð¾Ð²Ð¸ÑÐ¸ Ð²Ð¸Ð±ÑÑ ÑÑÑÐ¼Ð¸',
      'restoredCompanyId': 'Ð¯ Ð²ÑÐ´Ð½Ð¾Ð²Ð¸Ð² activeCompanyId Ð· Ð²Ð°ÑÐ¾Ð³Ð¾ Ð¿ÑÐ¾ÑÑÐ»Ñ',
      'resetActiveCompanyId': 'Ð¯ ÑÐºÐ¸Ð½ÑÐ² activeCompanyId, ÑÐ¾Ð± Ð²Ð¸ Ð¼Ð¾Ð³Ð»Ð¸ Ð²Ð¸Ð±ÑÐ°ÑÐ¸/ÑÑÐ²Ð¾ÑÐ¸ÑÐ¸ ÑÑÑÐ¼Ñ Ð·Ð°Ð½Ð¾Ð²Ð¾.',
      'errUserRead': 'ÐÐ¾Ð¼Ð¸Ð»ÐºÐ° ÑÐ¸ÑÐ°Ð½Ð½Ñ Ð¿ÑÐ¾ÑÑÐ»Ñ ÐºÐ¾ÑÐ¸ÑÑÑÐ²Ð°ÑÐ°',
      'errCompanyRead': 'ÐÐ¾Ð¼Ð¸Ð»ÐºÐ° ÑÐ¸ÑÐ°Ð½Ð½Ñ ÑÑÑÐ¼Ð¸',
      'errMemberRead': 'ÐÐ¾Ð¼Ð¸Ð»ÐºÐ° ÑÐ¸ÑÐ°Ð½Ð½Ñ ÑÑÐ°ÑÐ½Ð¸ÐºÐ° ÑÑÑÐ¼Ð¸',
    'addPerson': 'ÐÐ¾Ð´Ð°ÑÐ¸ Ð»ÑÐ´Ð¸Ð½Ñ',
    'alreadyIn': 'ÐÐ¶Ðµ Ñ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'approve': 'ÐÑÐ´ÑÐ²ÐµÑÐ´Ð¸ÑÐ¸',
    'archivedCompany': 'ÐÐ¾Ð¼Ð¿Ð°Ð½ÑÑ Ð°ÑÑÑÐ²Ð¾Ð²Ð°Ð½Ð¾',
    'askAdminIssueReturn': 'ÐÐ¾Ð¿ÑÐ¾ÑÑÑÑ Ð°Ð´Ð¼ÑÐ½Ð° Ð²Ð¸Ð´Ð°ÑÐ¸/Ð¿ÑÐ¸Ð¹Ð½ÑÑÐ¸',
    'deleteCompanyConfirm': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ Ð¿Ð¾Ð²Ð½ÑÑÑÑ?',
    'deleteCompanyWarn': 'ÐÑÐ´Ðµ Ð²Ð¸Ð´Ð°Ð»ÐµÐ½Ð¾ Ð²ÑÑ Ð´Ð°Ð½Ñ. ÐÑÑ Ð½Ðµ Ð¼Ð¾Ð¶Ð½Ð° ÑÐºÐ°ÑÑÐ²Ð°ÑÐ¸.',
    'issueTab': 'ÐÐ¸Ð´Ð°ÑÐ°',
    'returnTab': 'ÐÐ¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
    'searchByNameOrPhone': 'ÐÐ¾ÑÑÐº Ð·Ð° ÑÐ¼âÑÐ¼ Ð°Ð±Ð¾ ÑÐµÐ»ÐµÑÐ¾Ð½Ð¾Ð¼...',
    'selectToolFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð²Ð¸Ð±ÐµÑÑÑÑ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ',
    'birthDate': 'ÐÐ°ÑÐ° Ð½Ð°ÑÐ¾Ð´Ð¶ÐµÐ½Ð½Ñ',
    'changePassword': 'ÐÐ¼ÑÐ½Ð¸ÑÐ¸ / Ð²ÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÐ¸ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'chooseRole': 'ÐÐ¸Ð±ÐµÑÑÑÑ ÑÐ¾Ð»Ñ',
    'clothesSize': 'Ð Ð¾Ð·Ð¼ÑÑ Ð¾Ð´ÑÐ³Ñ',
    'codeNotFound': 'ÐÐ¾Ð´ Ð½Ðµ Ð·Ð½Ð°Ð¹Ð´ÐµÐ½Ð¾',
    'company': 'ÐÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'continue': 'ÐÑÐ¾Ð´Ð¾Ð²Ð¶Ð¸ÑÐ¸',
    'copyCodeHint': 'Ð¡ÐºÐ¾Ð¿ÑÑÐ¹ÑÐµ ÑÐ° Ð½Ð°Ð´ÑÑÐ»ÑÑÑ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÑ',
    'decline': 'ÐÑÐ´ÑÐ¸Ð»Ð¸ÑÐ¸',
    'deleteCompany': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'deleteCompanyText': 'ÐÐ¸Ð´Ð°Ð»Ð¸ÑÐ¸ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ Ð¿Ð¾Ð²Ð½ÑÑÑÑ',
    'deleteCompanyTitle': 'ÐÐ¸Ð´Ð°Ð»ÐµÐ½Ð½Ñ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'done': 'ÐÐ¾ÑÐ¾Ð²Ð¾',
    'editCompany': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'editMyProfile': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ Ð¼ÑÐ¹ Ð¿ÑÐ¾ÑÑÐ»Ñ',
    'editProfile': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ Ð¿ÑÐ¾ÑÑÐ»Ñ',
    'employeeRequests': 'ÐÐ°ÑÐ²ÐºÐ¸ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÑÐ²',
    'enterPassword': 'ÐÐ²ÐµÐ´ÑÑÑ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'enterPhone': 'ÐÐ²ÐµÐ´ÑÑÑ ÑÐµÐ»ÐµÑÐ¾Ð½',
    'firstName': 'ÐÐ¼âÑ',
    'invHint': 'ÐÐ½Ð²ÐµÐ½ÑÐ°ÑÐ½Ð¸Ð¹ Ð½Ð¾Ð¼ÐµÑ (Ð½Ð°Ð¿Ñ. SKDW-001)',
    'join': 'ÐÑÐ¸ÑÐ´Ð½Ð°ÑÐ¸ÑÑ',
    'lastName': 'ÐÑÑÐ·Ð²Ð¸ÑÐµ',
    'loginPc': 'ÐÑÑÐ´ Ð½Ð° ÐÐ: Ð¿ÑÐ¸Ð²âÑÐ·Ð°ÑÐ¸/Ð·Ð¼ÑÐ½Ð¸ÑÐ¸ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'name': 'ÐÐ°Ð·Ð²Ð°',
    'noCompany': 'ÐÐ¾Ð¼Ð¿Ð°Ð½ÑÑ Ð½Ðµ Ð²Ð¸Ð±ÑÐ°Ð½Ð¾',
    'noRights': 'ÐÐµÐ¼Ð°Ñ Ð¿ÑÐ°Ð²',
    'password': 'ÐÐ°ÑÐ¾Ð»Ñ',
    'position': 'ÐÐ¾ÑÐ°Ð´Ð°',
    'reports': 'ÐÐ²ÑÑÐ¸',
    'reportsPeople': 'Ð£ ÐºÐ¾Ð³Ð¾ ÑÐ¾ (Ð¿Ð¾ Ð»ÑÐ´ÑÑ)',
    'reportsTools': 'ÐÐµ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ (Ð¿Ð¾ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°Ñ)',
    'reportFilterHint': 'Ð¤ÑÐ»ÑÑÑ Ð·Ð²ÑÑÑ...',
    'onHandsTotal': 'ÐÐ°ÑÐ°Ð· Ð½Ð° ÑÑÐºÐ°Ñ Ð²ÑÑÐ¾Ð³Ð¾: {n} Ð¾Ð´.',
    'toolsCountLabel': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²: {n}',
    'whoLabel': 'Ð£ ÐºÐ¾Ð³Ð¾: {name}',
    'requests': 'ÐÐ°ÑÐ²ÐºÐ¸',
    'saveProfile': 'ÐÐ±ÐµÑÐµÐ³ÑÐ¸ Ð¿ÑÐ¾ÑÑÐ»Ñ',
    'sendReset': 'ÐÐ°Ð´ÑÑÐ»Ð°ÑÐ¸ Ð¿Ð¾ÑÐ¸Ð»Ð°Ð½Ð½Ñ Ð´Ð»Ñ ÑÐºÐ¸Ð´Ð°Ð½Ð½Ñ',
    'sessionTitle': 'Ð¡ÐµÑÑÑ',
    'setPassword': 'ÐÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÐ¸ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'setRole': 'ÐÑÐ¸Ð·Ð½Ð°ÑÐ¸ÑÐ¸ ÑÐ¾Ð»Ñ',
    'shoeSize': 'Ð Ð¾Ð·Ð¼ÑÑ Ð²Ð·ÑÑÑÑ',
    'switchAcc': 'ÐÐ¼ÑÐ½Ð¸ÑÐ¸ Ð°ÐºÐ°ÑÐ½Ñ',
    'toolNameHint': 'ÐÐ°Ð·Ð²Ð° (Ð½Ð°Ð¿Ñ. ÐÐ¾Ð»Ð³Ð°ÑÐºÐ°)',
    'welcome': 'ÐÐ°ÑÐºÐ°Ð²Ð¾ Ð¿ÑÐ¾ÑÐ¸Ð¼Ð¾',
    'yourInviteCode': 'ÐÐ°Ñ ÐºÐ¾Ð´ Ð·Ð°Ð¿ÑÐ¾ÑÐµÐ½Ð½Ñ',
    'repeatPassword': 'ÐÐ¾Ð²ÑÐ¾ÑÑÑÑ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'email': 'ÐÐ». Ð¿Ð¾ÑÑÐ°',
    'employee': 'ÐÑÐ°ÑÑÐ²Ð½Ð¸Ðº',
    'employees': 'Ð¡Ð¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÐ¸',
    'enterEmailPass': 'ÐÐ²ÐµÐ´ÑÑÑ email Ñ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'google': 'Google',
    'haveAccount': 'ÐÐ¶Ðµ Ñ Ð°ÐºÐ°ÑÐ½Ñ?',
    'historyEmpty': 'ÐÑÑÐ¾ÑÑÑ ÑÐµ Ð½ÐµÐ¼Ð°Ñ',
    'linkPassword': 'ÐÑÐ¸Ð²âÑÐ·Ð°ÑÐ¸/Ð²ÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÐ¸ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'needAccount': 'ÐÐ¾ÑÑÑÐ±ÐµÐ½ Ð°ÐºÐ°ÑÐ½Ñ',
    'needProfile': 'ÐÐ°Ð¿Ð¾Ð²Ð½ÑÑÑ Ð¿ÑÐ¾ÑÑÐ»Ñ',
    'needReLogin': 'Ð£Ð²ÑÐ¹Ð´ÑÑÑ Ð·Ð½Ð¾Ð²Ñ',
    'newCompanyName': 'ÐÐ¾Ð²Ð° Ð½Ð°Ð·Ð²Ð° ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
    'newPassword': 'ÐÐ¾Ð²Ð¸Ð¹ Ð¿Ð°ÑÐ¾Ð»Ñ',
    'noPeople': 'ÐÐ¾ÐºÐ¸ ÑÐ¾ Ð½ÐµÐ¼Ð°Ñ Ð»ÑÐ´ÐµÐ¹',
    'noneIssued': 'ÐÑÑÐ¾Ð³Ð¾ Ð½Ðµ Ð²Ð¸Ð´Ð°Ð½Ð¾',
    'noneIssued2': 'ÐÐµÐ¼Ð°Ñ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ² Ð½Ð° ÑÑÐºÐ°Ñ',
    'onlyAdmin': 'ÐÐ¸ÑÐµ Ð²Ð»Ð°ÑÐ½Ð¸Ðº/Ð°Ð´Ð¼ÑÐ½',
    'owner': 'ÐÐ»Ð°ÑÐ½Ð¸Ðº',
    'passwordsNotMatch': 'ÐÐ°ÑÐ¾Ð»Ñ Ð½Ðµ ÑÐ¿ÑÐ²Ð¿Ð°Ð´Ð°ÑÑÑ',
    'pendingText': 'ÐÐ°ÑÐ° Ð·Ð°ÑÐ²ÐºÐ° Ð¾ÑÑÐºÑÑ Ð¿ÑÐ´ÑÐ²ÐµÑÐ´Ð¶ÐµÐ½Ð½Ñ',
    'pendingTitle': 'ÐÑÑÐºÑÑ',
    'profileForm': 'Ð¤Ð¾ÑÐ¼Ð° Ð¿ÑÐ¾ÑÑÐ»Ñ',
    'renameCompany': 'ÐÐµÑÐµÐ¹Ð¼ÐµÐ½ÑÐ²Ð°ÑÐ¸ ÐºÐ¾Ð¼Ð¿Ð°Ð½ÑÑ',
      'searchByNameOrInv': 'ÐÐ¾ÑÑÐº Ð·Ð° Ð½Ð°Ð·Ð²Ð¾Ñ Ð°Ð±Ð¾ â...',
      'searchByToolOrLastName': 'ÐÐ¾ÑÑÐº Ð·Ð° ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð¼ Ð°Ð±Ð¾ Ð¿ÑÑÐ·Ð²Ð¸ÑÐµÐ¼...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Ð¡ÑÐ°ÑÑÑ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'empStatusActive': 'ÐÐºÑÐ¸Ð²Ð½Ð¸Ð¹',
      'empStatusFired': 'ÐÐ²ÑÐ»ÑÐ½ÐµÐ½Ð¸Ð¹',
      'toolStatus': 'Ð¡ÑÐ°ÑÑÑ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑ',
      'toolStatusActive': 'Ð Ð¾Ð±Ð¾ÑÐ¸Ð¹',
      'toolStatusRepair': 'Ð ÑÐµÐ¼Ð¾Ð½ÑÑ',
      'toolStatusDisposed': 'Ð¡Ð¿Ð¸ÑÐ°Ð½Ð¾',
      'markToolActive': 'ÐÑÐ¾Ð±Ð¸ÑÐ¸ ÑÐ¾Ð±Ð¾ÑÐ¸Ð¼',
      'markToolRepair': 'ÐÑÐ´Ð¿ÑÐ°Ð²Ð¸ÑÐ¸ Ð² ÑÐµÐ¼Ð¾Ð½Ñ',
      'markToolDisposed': 'Ð¡Ð¿Ð¸ÑÐ°ÑÐ¸ (ÑÑÐ¸Ð»ÑÐ·Ð°ÑÑÑ)',
      'statusNote': 'ÐÐ¾Ð¼ÐµÐ½ÑÐ°Ñ',
      'reportsByTool': 'ÐÐ° ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð¼',
      'reportsByPerson': 'ÐÐ° Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ¾Ð¼',
      'selectPerson': 'ÐÐ±ÐµÑÐ¸ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'selectPersonFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð¾Ð±ÐµÑÐ¸ Ð¿ÑÐ°ÑÑÐ²Ð½Ð¸ÐºÐ°',
      'warehouse': 'Ð¡ÐºÐ»Ð°Ð´',
      'where': 'ÐÐµ',
      'issuedAt': 'ÐÐ¸Ð´Ð°Ð½Ð¾',
      'noData': 'ÐÐµÐ¼Ð°Ñ Ð´Ð°Ð½Ð¸Ñ',
      'noIssued': 'ÐÑÑÐ¾Ð³Ð¾ Ð½Ðµ Ð²Ð¸Ð´Ð°Ð½Ð¾',
      'subscriptionTitle': 'ÐÑÐ´Ð¿Ð¸ÑÐºÐ°',
      'subscriptionStatusLabel': 'Ð¡ÑÐ°ÑÑÑ',
      'subscriptionModeLabel': 'Ð ÐµÐ¶Ð¸Ð¼',
      'subscriptionValidUntilLabel': 'ÐÑÑ Ð´Ð¾',
      'subscriptionTest': 'Ð¢ÐµÑÑÐ¾Ð²Ð¸Ð¹ ÑÐµÐ¶Ð¸Ð¼',
      'subscriptionLive': 'ÐÐ»Ð°ÑÐ½Ð¸Ð¹ ÑÐµÐ¶Ð¸Ð¼',
      'subscriptionActive': 'ÐÐºÑÐ¸Ð²Ð½Ð°',
      'subscriptionInactive': 'ÐÐµ Ð°ÐºÑÐ¸Ð²Ð½Ð°',
      'buyRenew': 'ÐÑÐ¿Ð¸ÑÐ¸ / ÐÐ¾Ð´Ð¾Ð²Ð¶Ð¸ÑÐ¸',
      'buyRenewSoon': 'ÐÐ¿Ð»Ð°ÑÐ° ÑÐºÐ¾ÑÐ¾ Ð±ÑÐ´Ðµ Ð´Ð¾ÑÑÑÐ¿Ð½Ð°. ÐÐ¾ÐºÐ¸ ÑÐ¾ Ð´Ð»Ñ ÐºÑÐ¿ÑÐ²Ð»Ñ/Ð¿ÑÐ¾Ð´Ð¾Ð²Ð¶ÐµÐ½Ð½Ñ Ð·Ð²ÐµÑÐ½ÑÑÑÑÑ Ð² Ð¿ÑÐ´ÑÑÐ¸Ð¼ÐºÑ.',
      'admin': 'ÐÐ´Ð¼ÑÐ½',
      'billingLive': 'LIVE',
      'billingTest': 'Ð¢ÐÐ¡Ð¢',
      'billingModeLabel': 'Ð ÐµÐ¶Ð¸Ð¼ Ð¾Ð¿Ð»Ð°ÑÐ¸',
      'changePlan': 'ÐÐ¼ÑÐ½Ð¸ÑÐ¸ ÑÐ°ÑÐ¸Ñ',
      'emailLabel': 'Email',
      'needPeopleFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð´Ð¾Ð´Ð°Ð¹ÑÐµ Ð»ÑÐ´ÐµÐ¹',
      'needToolsFirst': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð´Ð¾Ð´Ð°Ð¹ÑÐµ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¸',
      'noFreeTool': 'ÐÐµÐ¼Ð°Ñ Ð²ÑÐ»ÑÐ½Ð¾Ð³Ð¾ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°',
      'noReturnTool': 'ÐÐµÐ¼Ð°Ñ ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÐ° Ð´Ð»Ñ Ð¿Ð¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'peopleLimitLabel': 'ÐÑÐ¼ÑÑ Ð»ÑÐ´ÐµÐ¹',
      'perMonth': 'Ð¼ÑÑ.',
      'person': 'ÐÑÐ¾Ð±Ð°',
      'planChangeOnlyOwner': 'ÐÐ¸ÑÐµ Ð²Ð»Ð°ÑÐ½Ð¸Ðº Ð¼Ð¾Ð¶Ðµ Ð·Ð¼ÑÐ½Ð¸ÑÐ¸ ÑÐ°ÑÐ¸Ñ.',
      'planLabel': 'Ð¢Ð°ÑÐ¸Ñ',
      'planSaved': 'Ð¢Ð°ÑÐ¸Ñ Ð·Ð±ÐµÑÐµÐ¶ÐµÐ½Ð¾',
      'gpsNotInPlan': 'GPS-ÑÑÐµÐºÑÐ½Ð³ Ð´Ð¾ÑÑÑÐ¿Ð½Ð¸Ð¹ Ð· ÑÐ°ÑÐ¸ÑÑ ÐÑÐ¾ Ñ Ð²Ð¸ÑÐµ',
      'gpsIncluded': 'GPS â',
      'gpsNotIncluded': 'GPS â',
      'returnTitle': 'ÐÑÐ´ÑÐ²ÐµÑÐ´Ð¸ÑÐ¸ Ð¿Ð¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'returnTool': 'ÐÐ¾Ð²ÐµÑÐ½ÐµÐ½Ð½Ñ',
      'selectPlan': 'ÐÐ¸Ð±ÐµÑÑÑÑ ÑÐ°ÑÐ¸Ñ',
      'supportDesc': 'Ð Ð¿Ð¸ÑÐ°Ð½Ñ ÑÐ¾Ð±Ð¾ÑÐ¸ Ð·Ð°ÑÑÐ¾ÑÑÐ½ÐºÑ Ð²Ð¸ Ð¼Ð¾Ð¶ÐµÑÐµ Ð·Ð²âÑÐ·Ð°ÑÐ¸ÑÑ Ð· Ð½Ð°Ð¼Ð¸:',
      'supportTitle': 'ÐÑÐ´ÑÑÐ¸Ð¼ÐºÐ°',
      'tariffLimitsTitle': 'Ð¢Ð°ÑÐ¸Ñ Ñ Ð»ÑÐ¼ÑÑÐ¸',
      'telegramLabel': 'Telegram',
      'usedActiveLabel': 'ÐÐ¸ÐºÐ¾ÑÐ¸ÑÑÐ°Ð½Ð¾ (Ð°ÐºÑÐ¸Ð²Ð½Ñ)',
      'inactiveNotCountedNote': 'ÐÐ²ÑÐ»ÑÐ½ÐµÐ½Ñ/Ð½ÐµÐ°ÐºÑÐ¸Ð²Ð½Ñ Ð½Ðµ ÑÐ°ÑÑÑÑÑÑÑ Ð² Ð»ÑÐ¼ÑÑ.',
      'versionLabel': 'ÐÐµÑÑÑÑ',
      'worker': 'ÐÑÐ°ÑÑÐ²Ð½Ð¸Ðº',
      'myShift': 'ÐÐ¾Ñ Ð·Ð¼ÑÐ½Ð°',
      'startShift': 'ÐÐ¾ÑÐ°ÑÐ¸ Ð·Ð¼ÑÐ½Ñ',
      'endShift': 'ÐÐ°Ð²ÐµÑÑÐ¸ÑÐ¸ Ð·Ð¼ÑÐ½Ñ',
      'currentShift': 'ÐÐ¾ÑÐ¾ÑÐ½Ð° Ð·Ð¼ÑÐ½Ð°',
      'shiftStarted': 'ÐÐ¼ÑÐ½Ñ ÑÐ¾Ð·Ð¿Ð¾ÑÐ°ÑÐ¾!',
      'shiftEnded': 'ÐÐ¼ÑÐ½Ñ Ð·Ð°Ð²ÐµÑÑÐµÐ½Ð¾!',
      'shiftActive': 'ÐÐ¼ÑÐ½Ð° Ð°ÐºÑÐ¸Ð²Ð½Ð°',
      'shiftStart': 'ÐÐ¾ÑÐ°ÑÐ¾Ðº',
      'shiftEnd': 'ÐÑÐ½ÐµÑÑ',
      'selectSite': 'ÐÐ±ÐµÑÑÑÑ Ð¾Ð±\'ÑÐºÑ',
      'noSites': 'ÐÐ±\'ÑÐºÑÐ¸ Ð½Ðµ Ð´Ð¾Ð´Ð°Ð½Ñ. ÐÐ²ÐµÑÐ½ÑÑÑÑÑ Ð´Ð¾ Ð°Ð´Ð¼ÑÐ½ÑÑÑÑÐ°ÑÐ¾ÑÐ°.',
      'writeReport': 'ÐÐ²ÑÑ Ð·Ð° Ð·Ð¼ÑÐ½Ñ',
      'whatDone': 'Ð©Ð¾ Ð·ÑÐ¾Ð±Ð»ÐµÐ½Ð¾',
      'workReport': 'ÐÐ²ÑÑ',
      'timesheets': 'Ð¢Ð°Ð±ÐµÐ»Ñ Ð·Ð¼ÑÐ½',
      'myTimesheets': 'ÐÐ¾Ñ Ð·Ð¼ÑÐ½Ð¸',
      'allTimesheets': 'ÐÑÑ Ð·Ð¼ÑÐ½Ð¸',
      'totalHours': 'ÐÑÑÐ¾Ð³Ð¾ Ð³Ð¾Ð´Ð¸Ð½',
      'shiftsCount': 'ÐÐ¼ÑÐ½',
      'manageSites': 'Ð£Ð¿ÑÐ°Ð²Ð»ÑÐ½Ð½Ñ Ð¾Ð±\'ÑÐºÑÐ°Ð¼Ð¸',
      'sites': 'ÐÐ±\'ÑÐºÑÐ¸',
      'addSite': 'ÐÐ¾Ð´Ð°ÑÐ¸ Ð¾Ð±\'ÑÐºÑ',
      'editSite': 'Ð ÐµÐ´Ð°Ð³ÑÐ²Ð°ÑÐ¸ Ð¾Ð±\'ÑÐºÑ',
      'siteName': 'ÐÐ°Ð·Ð²Ð° Ð¾Ð±\'ÑÐºÑÑ',
      'siteAddress': 'ÐÐ´ÑÐµÑÐ°',
      'siteRadius': 'Ð Ð°Ð´ÑÑÑ ÑÐµÐº-ÑÐ½Ñ (Ð¼)',
      'gpsInterval': 'ÐÐ½ÑÐµÑÐ²Ð°Ð» GPS (ÑÐ²)',
      'gpsPermissionDenied': 'GPS Ð½ÐµÐ´Ð¾ÑÑÑÐ¿Ð½Ð¸Ð¹ â Ð·Ð¼ÑÐ½Ñ ÑÐ¾Ð·Ð¿Ð¾ÑÐ°ÑÐ¾ Ð±ÐµÐ· Ð¿ÐµÑÐµÐ²ÑÑÐºÐ¸ ÐºÐ¾Ð¾ÑÐ´Ð¸Ð½Ð°Ñ',
      'gpsWarningTitle': 'ÐÐ¸ Ð¿Ð¾Ð·Ð° Ð·Ð¾Ð½Ð¾Ñ Ð¾Ð±\'ÑÐºÑÑ',
      'gpsWarningText': 'ÐÐ°ÑÐµ Ð¼ÑÑÑÐµÐ·Ð½Ð°ÑÐ¾Ð´Ð¶ÐµÐ½Ð½Ñ Ð½Ðµ Ð·Ð±ÑÐ³Ð°ÑÑÑÑÑ Ð· Ð°Ð´ÑÐµÑÐ¾Ñ Ð¾Ð±\'ÑÐºÑÑ.',
      'distance': 'ÐÑÐ´ÑÑÐ°Ð½Ñ',
      'startAnyway': 'ÐÐ¾ÑÐ°ÑÐ¸ Ð²ÑÐµ Ð¾Ð´Ð½Ð¾',
      'allTime': 'ÐÐµÑÑ ÑÐ°Ñ',
      'allSites': 'ÐÑÑ Ð¾Ð±\'ÑÐºÑÐ¸',
      'allPeople': 'ÐÑÑ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÐ¸',
      'exportXlsx': 'ÐÐºÑÐ¿Ð¾ÑÑ Excel',
      'actPdf': 'ÐÐºÑ PDF',
      'nakladnayaPdf': 'ÐÐ°ÐºÐ»Ð°Ð´Ð½Ð° PDF',
      'gpsTrack': 'GPS-ÑÑÐµÐº',
      'noGpsData': 'ÐÐµÐ¼Ð°Ñ GPS-Ð´Ð°Ð½Ð¸Ñ',
      'shiftTypeHourly': 'ÐÐ¾Ð³Ð¾Ð´Ð¸Ð½Ð½Ð¾',
      'shiftTypeAccord': 'ÐÐºÐ¾ÑÐ´',
      'chooseShiftType': 'Ð¢Ð¸Ð¿ Ð·Ð¼ÑÐ½Ð¸',
      'shiftType': 'Ð¢Ð¸Ð¿ ÑÐ¾Ð±Ð¾ÑÐ¸',
      'reportRequired': 'ÐÐ°Ð¿Ð¾Ð²Ð½ÑÑÑ Ð·Ð²ÑÑ â ÑÐ¾ Ð±ÑÐ»Ð¾ Ð·ÑÐ¾Ð±Ð»ÐµÐ½Ð¾',
      'viewSites': 'ÐÑÑ Ð¾Ð±\'ÑÐºÑÐ¸',
      'navigateTo': 'ÐÐ°ÑÑÑÑÑ',
      'linkUser': 'ÐÑÐ¸Ð²\'ÑÐ·Ð°ÑÐ¸ ÐºÐ¾ÑÐ¸ÑÑÑÐ²Ð°ÑÐ°',
      'linkedUser': 'ÐÑÐ¸Ð²\'ÑÐ·Ð°Ð½Ð¸Ð¹ Ð´Ð¾',
      'unlinkUser': 'ÐÑÐ´Ð²\'ÑÐ·Ð°ÑÐ¸',
      'selectUserToLink': 'ÐÐ±ÐµÑÑÑÑ ÐºÐ¾ÑÐ¸ÑÑÑÐ²Ð°ÑÐ°',
      'notLinked': 'ÐÐºÐ°ÑÐ½Ñ Ð½Ðµ Ð¿ÑÐ¸Ð²\'ÑÐ·Ð°Ð½Ð¸Ð¹ Ð´Ð¾ Ð°Ð½ÐºÐµÑÐ¸. ÐÐ²ÐµÑÐ½ÑÑÑÑÑ Ð´Ð¾ Ð°Ð´Ð¼ÑÐ½ÑÑÑÑÐ°ÑÐ¾ÑÐ°.',
      'personTypePerson': 'ÐÑÐ´Ð¸Ð½Ð°',
      'personTypeObject': 'ÐÐ±\'ÑÐºÑ',
      'noObjects': 'ÐÐ±\'ÑÐºÑÑÐ² Ð¿Ð¾ÐºÐ¸ Ð½ÐµÐ¼Ð°Ñ. ÐÐ°ÑÐ¸ÑÐ½ÑÑÑ +',
      'objectCompleted': 'ÐÐ°Ð²ÐµÑÑÐµÐ½Ð¸Ð¹',
      'markObjectCompleted': 'ÐÐ°Ð²ÐµÑÑÐ¸ÑÐ¸ Ð¾Ð±\'ÑÐºÑ',
      'personTab': 'ÐÑÐ´Ð¸',
      'objectTab': 'ÐÐ±\'ÑÐºÑÐ¸',
      'cannotCompleteHasTools': 'ÐÐµ Ð¼Ð¾Ð¶Ð½Ð° Ð·Ð°Ð²ÐµÑÑÐ¸ÑÐ¸: Ð½Ð° Ð¾Ð±\'ÑÐºÑÑ {n} ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²',
      'cannotFireHasTools': 'ÐÐµ Ð¼Ð¾Ð¶Ð½Ð° Ð·Ð²ÑÐ»ÑÐ½Ð¸ÑÐ¸: Ñ ÑÐ¿ÑÐ²ÑÐ¾Ð±ÑÑÐ½Ð¸ÐºÐ° {n} ÑÐ½ÑÑÑÑÐ¼ÐµÐ½ÑÑÐ²',
      'addObject': 'ÐÐ¾Ð´Ð°ÑÐ¸ Ð¾Ð±\'ÑÐºÑ',
      'shiftReminder10hTitle': 'ÐÐ¼ÑÐ½Ð° ÑÑÐ¸Ð²Ð°Ñ 10 Ð³Ð¾Ð´Ð¸Ð½',
      'shiftReminder10hBody': 'ÐÐ¼ÑÐ½Ð° Ð°ÐºÑÐ¸Ð²Ð½Ð° Ð±ÑÐ»ÑÑÐµ 10 Ð³Ð¾Ð´Ð¸Ð½. ÐÐµ Ð·Ð°Ð±ÑÐ´ÑÑÐµ Ð·Ð°ÐºÑÐ¸ÑÐ¸.',
      'shiftReminder12hTitle': 'â ï¸ ÐÐ¼ÑÐ½Ð° 12 Ð³Ð¾Ð´Ð¸Ð½!',
      'shiftReminder12hBody': 'Ð£Ð²Ð°Ð³Ð°: Ð·Ð¼ÑÐ½Ð° ÑÑÐ¸Ð²Ð°Ñ Ð±ÑÐ»ÑÑÐµ 12 Ð³Ð¾Ð´Ð¸Ð½. ÐÐ°ÐºÑÐ¸Ð¹ÑÐµ Ð·Ð¼ÑÐ½Ñ.',
      'offlineBanner': 'ÐÐµÐ¼Ð°Ñ Ð¿ÑÐ´ÐºÐ»ÑÑÐµÐ½Ð½Ñ â¢ Ð´Ð°Ð½Ñ Ð· ÐºÐµÑÑ',
      'alreadyHaveActiveShift': 'Ð£ Ð²Ð°Ñ Ð²Ð¶Ðµ Ñ Ð°ÐºÑÐ¸Ð²Ð½Ð° Ð·Ð¼ÑÐ½Ð°. ÐÐ°ÐºÑÐ¸Ð¹ÑÐµ ÑÑ Ð¿ÐµÑÐµÐ´ Ð¿Ð¾ÑÐ°ÑÐºÐ¾Ð¼ Ð½Ð¾Ð²Ð¾Ñ.',
      'forceCloseShift': 'ÐÑÐ¸Ð¼ÑÑÐ¾Ð²Ð¾ Ð·Ð°ÐºÑÐ¸ÑÐ¸',
      'forceCloseShiftHint': 'ÐÐ¼ÑÐ½Ñ Ð±ÑÐ´Ðµ Ð·Ð°ÐºÑÐ¸ÑÐ¾ Ð·Ð°ÑÐ°Ð·. ÐÐ¸ Ð¼Ð¾Ð¶ÐµÑÐµ Ð´Ð¾Ð´Ð°ÑÐ¸ Ð·Ð²ÑÑ.',
      'shiftClosed': 'ÐÐ¼ÑÐ½Ñ Ð·Ð°ÐºÑÐ¸ÑÐ¾.',
      'archive': 'ÐÑÑÑÐ²',
      'noArchive': 'ÐÑÑÑÐ² Ð¿Ð¾ÑÐ¾Ð¶Ð½ÑÐ¹',
      'notifications': 'Ð¡Ð¿Ð¾Ð²ÑÑÐµÐ½Ð½Ñ',
      'noNotifications': 'ÐÐµÐ¼Ð°Ñ Ð½Ð¾Ð²Ð¸Ñ ÑÐ¿Ð¾Ð²ÑÑÐµÐ½Ñ',
      'newMemberRequest': 'ÐÐ¾Ð²Ð° Ð·Ð°ÑÐ²ÐºÐ° Ð½Ð° Ð²ÑÑÑÐ¿',
      'markAllRead': 'ÐÐ¾Ð·Ð½Ð°ÑÐ¸ÑÐ¸ Ð²ÑÑ ÑÐº Ð¿ÑÐ¾ÑÐ¸ÑÐ°Ð½Ñ',
      'copyTool': 'ÐÐ¾Ð¿ÑÑÐ²Ð°ÑÐ¸',
      'toolCopied': 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ ÑÐºÐ¾Ð¿ÑÐ¹Ð¾Ð²Ð°Ð½Ð¾',
      'sortNameAZ': 'ÐÐ°Ð·Ð²Ð° Ð-Ð¯',
      'sortCountDesc': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð²ÐµÐ»Ð¸ÐºÑ Ð³ÑÑÐ¿Ð¸',
      'sortDateDesc': 'Ð¡Ð¿Ð¾ÑÐ°ÑÐºÑ Ð½Ð¾Ð²Ñ',
      'darkTheme': 'Ð¢ÐµÐ¼Ð½Ð° ÑÐµÐ¼Ð°',
      'lightTheme': 'Ð¡Ð²ÑÑÐ»Ð° ÑÐµÐ¼Ð°',
      'systemTheme': 'Ð¡Ð¸ÑÑÐµÐ¼Ð½Ð° ÑÐµÐ¼Ð°',
      'printQr': 'ÐÐ°Ð´ÑÑÐºÑÐ²Ð°ÑÐ¸ QR',
      'saveAsPng': 'ÐÐ±ÐµÑÐµÐ³ÑÐ¸ PNG',
      'thermalLabel': 'Ð¢ÐµÑÐ¼Ð¾-ÐµÑÐ¸ÐºÐµÑÐºÐ°',
      'printAllQr': 'Ð£ÑÑ QR Ð½Ð° Ð°ÑÐºÑÑ',
      'noResults': 'ÐÑÑÐ¾Ð³Ð¾ Ð½Ðµ Ð·Ð½Ð°Ð¹Ð´ÐµÐ½Ð¾',
    },
    AppLang.pl: {
      'appTitle': 'ToolKeeper',
      'login': 'Logowanie',
      'register': 'Rejestracja',
      'enter': 'Zaloguj',
      'logout': 'Wyloguj',
      'people': 'Ludzie',
      'tools': 'NarzÄdzia',
      'tool': 'NarzÄdzie',
      'inv': 'Nr inw.',
      'issue': 'Wydanie',
      'profile': 'Profil',
      'chooseLang': 'Wybierz jÄzyk',
      'chooseCompany': 'Wybierz firmÄ',
      'searchingCompany': 'Szukam Twojej firmy...',
      'companyNotFound': 'Nie znaleziono firmy',
      'companyDeleted': 'Firma zostaÅa usuniÄta',
      'noAccessCompany': 'Brak dostÄpu do firmy',
      'removedFromCompany': 'ZostaÅeÅ usuniÄty z firmy. Wpisz kod ponownie i poczekaj na akceptacjÄ.',
      'leaveCompany': 'WyjdÅº / wybierz innÄ firmÄ',
      'createCompany': 'UtwÃ³rz firmÄ',
      'enterInviteCode': 'Wpisz kod zaproszenia',
      'joinCompany': 'DoÅÄcz',
      'or': 'LUB',
      'companyName': 'Nazwa firmy',
      'create': 'UtwÃ³rz',
      'myCompany': 'Moja firma',
      'myProfile': 'MÃ³j profil',
      'role': 'Rola',
      'role_owner': 'WÅaÅciciel',
      'role_admin': 'Administrator',
      'role_foreman': 'Brygadzista',
      'role_employee': 'Pracownik',
      'editRoles': 'Edytuj role',
      'save': 'Zapisz',
      'cancel': 'Anuluj',
      'inviteCode': 'Kod zaproszenia',
      'copy': 'Kopiuj',
      'copied': 'Skopiowano',
      'share': 'UdostÄpnij',
      'pendingRequests': 'ProÅby o doÅÄczenie',
      'accept': 'Akceptuj',
      'deny': 'OdrzuÄ',
      'noRequests': 'Brak prÃ³Åb',
      'members': 'CzÅonkowie',
      'noMembers': 'Brak czÅonkÃ³w',
      'addEmployee': 'Dodaj pracownika',
      'employeeFirstName': 'ImiÄ',
      'employeeLastName': 'Nazwisko',
      'employeePosition': 'Stanowisko',
      'phone': 'Telefon',
      'add': 'Dodaj',
      'editEmployee': 'Edytuj pracownika',
      'deleteEmployee': 'UsuÅ pracownika',
      'delete': 'UsuÅ',
      'deleteConfirm': 'Na pewno usunÄÄ?',
      'searchEmployee': 'Szukaj pracownika...',
      'noEmployees': 'Brak pracownikÃ³w',
      'addTool': 'Dodaj narzÄdzie',
      'toolName': 'Nazwa narzÄdzia',
      'toolInv': 'Nr inw.',
      'addToolBtn': 'Dodaj',
      'editTool': 'Edytuj narzÄdzie',
      'deleteTool': 'UsuÅ narzÄdzie',
      'searchTool': 'Szukaj narzÄdzia...',
      'noTools': 'Brak narzÄdzi',
      'issueTitle': 'Wydanie / Zwrot',
      'issueTo': 'WydaÄ',
      'returnFrom': 'ZwrÃ³ciÄ',
      'selectEmployee': 'Wybierz pracownika',
      'selectTool': 'Wybierz narzÄdzie',
      'issued': 'Wydano',
      'returned': 'ZwrÃ³cono',
      'history': 'Historia',
      'searchHistory': 'Szukaj w historii...',
      'noMoves': 'Brak wpisÃ³w',
      'moveIssue': 'Wydanie',
      'moveReturn': 'Zwrot',
      'onHands': 'Na rÄkach',
      'freeTools': 'Wolne',
      'total': 'Razem',
      'toolsCount': 'NarzÄdzi',
      'pcs': 'szt.',
      'report': 'Raport',
      'filter': 'Filtr',
      'reset': 'Reset',
      'export': 'Eksport',
      'exportCsv': 'Eksport CSV',
      'exportPdf': 'Eksport PDF',
      'exportDone': 'Eksport gotowy',
      'loading': 'Åadowanie...',
      'error': 'BÅÄd',
      'ok': 'OK',
      'yes': 'Tak',
      'no': 'Nie',
      'langRu': 'Ð ÑÑÑÐºÐ¸Ð¹',
      'langUk': 'Ð£ÐºÑÐ°ÑÐ½ÑÑÐºÐ°',
      'langPl': 'Polski',
      'langEn': 'English',
      'selectModeFirst': 'Najpierw wybierz: WYDANIE albo ZWROT',
      'selectPersonForReturnFirst': 'Najpierw wybierz pracownika do ZWROTU',
      'noRightsIssueReturn': 'Brak uprawnieÅ do wydania/zwrotu',
      'selectPersonAndTool': 'Wybierz pracownika i narzÄdzie',
      'issueUpper': 'WYDAÄ',
      'returnUpper': 'ZWRÃCIÄ',
      'invShort': 'Inw',
      'invNumber': 'Nr inw.',
      'noName': 'Bez imienia',
      'noTitle': 'Bez nazwy',
      'noFreeTools': 'Brak wolnych narzÄdzi',
      'noToolsOnHands': 'Brak narzÄdzi na rÄkach',
      'whoSelectEmployee': 'Komu wydaÄ',
      'whoField': 'KTO (WybÃ³r pracownika)',
      'whatSelectEmployeeTool': 'Co wydaÄ',
      'whatSelectFreeTool': 'Co zwrÃ³ciÄ',
      'whatFieldOnHands': 'CO (NarzÄdzie tego pracownika)',
      'whatFieldFree': 'CO (Wolne narzÄdzie)',
      'confirmReturn': 'ZwrÃ³Ä',
      'confirmIssue': 'Wydaj',
      'restoreCompanyError': 'Nie udaÅo siÄ przywrÃ³ciÄ wyboru firmy',
      'restoredCompanyId': 'PrzywrÃ³ciÅam activeCompanyId z Twojego profilu',
      'resetActiveCompanyId': 'ZresetowaÅam activeCompanyId, abyÅ mÃ³gÅ wybraÄ/utworzyÄ firmÄ ponownie.',
      'errUserRead': 'BÅÄd odczytu profilu uÅ¼ytkownika',
      'errCompanyRead': 'BÅÄd odczytu firmy',
      'errMemberRead': 'BÅÄd odczytu czÅonka firmy',
    'addPerson': 'Dodaj osobÄ',
    'alreadyIn': 'JuÅ¼ w firmie',
    'approve': 'ZatwierdÅº',
    'archivedCompany': 'Firma zarchiwizowana',
    'askAdminIssueReturn': 'PoproÅ admina o wydanie/zwrot',
    'deleteCompanyConfirm': 'UsunÄÄ firmÄ caÅkowicie?',
    'deleteCompanyWarn': 'To usunie wszystkie dane. Tego nie da siÄ cofnÄÄ.',
    'issueTab': 'Wydanie',
    'returnTab': 'Zwrot',
    'searchByNameOrPhone': 'Szukaj po imieniu lub telefonie...',
    'selectToolFirst': 'Najpierw wybierz narzÄdzie',
    'birthDate': 'Data urodzenia',
    'changePassword': 'ZmieÅ / ustaw hasÅo',
    'chooseRole': 'Wybierz rolÄ',
    'clothesSize': 'Rozmiar odzieÅ¼y',
    'codeNotFound': 'Nie znaleziono kodu',
    'company': 'Firma',
    'continue': 'Kontynuuj',
    'copyCodeHint': 'Skopiuj i wyÅlij pracownikowi',
    'decline': 'OdrzuÄ',
    'deleteCompany': 'UsuÅ firmÄ',
    'deleteCompanyText': 'UsuÅ firmÄ caÅkowicie',
    'deleteCompanyTitle': 'Usuwanie firmy',
    'done': 'Gotowe',
    'editCompany': 'Edytuj firmÄ',
    'editMyProfile': 'Edytuj mÃ³j profil',
    'editProfile': 'Edytuj profil',
    'employeeRequests': 'Wnioski pracownikÃ³w',
    'enterPassword': 'Wpisz hasÅo',
    'enterPhone': 'Wpisz telefon',
    'firstName': 'ImiÄ',
    'invHint': 'Numer inwentarzowy (np. SKDW-001)',
    'join': 'DoÅÄcz',
    'lastName': 'Nazwisko',
    'loginPc': 'Logowanie PC: powiÄÅ¼/zmieÅ hasÅo',
    'name': 'Nazwa',
    'noCompany': 'Nie wybrano firmy',
    'noRights': 'Brak uprawnieÅ',
    'password': 'HasÅo',
    'position': 'Stanowisko',
    'reports': 'Raporty',
    'reportsPeople': 'Kto ma co (wg osÃ³b)',
    'reportsTools': 'Gdzie jest narzÄdzie (wg narzÄdzi)',
    'reportFilterHint': 'Filtr raportu...',
    'onHandsTotal': 'Na rÄkach ÅÄcznie: {n} szt.',
    'toolsCountLabel': 'NarzÄdzia: {n}',
    'whoLabel': 'U kogo: {name}',
    'requests': 'Wnioski',
    'saveProfile': 'Zapisz profil',
    'sendReset': 'WyÅlij link resetu',
    'sessionTitle': 'Sesja',
    'setPassword': 'Ustaw hasÅo',
    'setRole': 'Ustaw rolÄ',
    'shoeSize': 'Rozmiar buta',
    'switchAcc': 'ZmieÅ konto',
    'toolNameHint': 'Nazwa (np. Szlifierka)',
    'welcome': 'Witamy',
    'yourInviteCode': 'TwÃ³j kod zaproszenia',
    'repeatPassword': 'PowtÃ³rz hasÅo',
    'email': 'Email',
    'employee': 'Pracownik',
    'employees': 'Pracownicy',
    'enterEmailPass': 'Wpisz email i hasÅo',
    'google': 'Google',
    'haveAccount': 'Masz juÅ¼ konto?',
    'historyEmpty': 'Brak historii',
    'linkPassword': 'PowiÄÅ¼/ustaw hasÅo',
    'needAccount': 'Potrzebne konto',
    'needProfile': 'UzupeÅnij profil',
    'needReLogin': 'Zaloguj siÄ ponownie',
    'newCompanyName': 'Nowa nazwa firmy',
    'newPassword': 'Nowe hasÅo',
    'noPeople': 'Brak osÃ³b',
    'noneIssued': 'Nic nie wydano',
    'noneIssued2': 'Brak narzÄdzi na rÄkach',
    'onlyAdmin': 'Tylko wÅaÅciciel/admin',
    'owner': 'WÅaÅciciel',
    'passwordsNotMatch': 'HasÅa nie pasujÄ',
    'pendingText': 'Twoja proÅba czeka na akceptacjÄ',
    'pendingTitle': 'Oczekuje',
    'profileForm': 'Formularz profilu',
    'renameCompany': 'ZmieÅ nazwÄ firmy',
      'searchByNameOrInv': 'Szukaj po nazwie lub nr...',
      'searchByToolOrLastName': 'Szukaj po narzÄdziu lub nazwisku...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Status pracownika',
      'empStatusActive': 'Aktywny',
      'empStatusFired': 'Zwolniony',
      'toolStatus': 'Status narzÄdzia',
      'toolStatusActive': 'Sprawne',
      'toolStatusRepair': 'W naprawie',
      'toolStatusDisposed': 'Zlikwidowane',
      'markToolActive': 'Oznacz jako sprawne',
      'markToolRepair': 'WyÅlij do naprawy',
      'markToolDisposed': 'Spisz (utylizacja)',
      'statusNote': 'Komentarz',
      'reportsByTool': 'Po narzÄdziu',
      'reportsByPerson': 'Po pracowniku',
      'selectPerson': 'Wybierz pracownika',
      'selectPersonFirst': 'Najpierw wybierz pracownika',
      'warehouse': 'Magazyn',
      'where': 'Gdzie',
      'issuedAt': 'Wydano',
      'noData': 'Brak danych',
      'noIssued': 'Nic nie wydano',
      'subscriptionTitle': 'Subskrypcja',
      'subscriptionStatusLabel': 'Status',
      'subscriptionModeLabel': 'Tryb',
      'subscriptionValidUntilLabel': 'WaÅ¼na do',
      'subscriptionTest': 'Tryb testowy',
      'subscriptionLive': 'Tryb pÅatny',
      'subscriptionActive': 'Aktywna',
      'subscriptionInactive': 'Nieaktywna',
      'buyRenew': 'Kup / PrzedÅuÅ¼',
      'buyRenewSoon': 'PÅatnoÅci bÄdÄ dostÄpne wkrÃ³tce. Na razie, aby kupiÄ/przedÅuÅ¼yÄ, skontaktuj siÄ z pomocÄ.',
      'admin': 'Admin',
      'billingLive': 'LIVE',
      'billingTest': 'TEST',
      'billingModeLabel': 'Tryb pÅatnoÅci',
      'changePlan': 'ZmieÅ plan',
      'emailLabel': 'Email',
      'lang': 'JÄzyk',
      'needToolsFirst': 'Najpierw dodaj narzÄdzia',
      'noFreeTool': 'Brak wolnego narzÄdzia',
      'noReturnTool': 'Brak narzÄdzia do zwrotu',
      'peopleLimitLabel': 'Limit osÃ³b',
      'perMonth': 'mies.',
      'person': 'Osoba',
      'planChangeOnlyOwner': 'Tylko wÅaÅciciel moÅ¼e zmieniÄ plan.',
      'planLabel': 'Plan',
      'planSaved': 'Plan zapisany',
      'gpsNotInPlan': 'Åledzenie GPS dostÄpne od planu Pro i wyÅ¼ej',
      'gpsIncluded': 'GPS â',
      'gpsNotIncluded': 'GPS â',
      'returnTitle': 'PotwierdÅº zwrot',
      'returnTool': 'Zwrot',
      'selectPlan': 'Wybierz plan',
      'supportDesc': 'W sprawie dziaÅania aplikacji moÅ¼esz siÄ z nami skontaktowaÄ:',
      'supportTitle': 'Wsparcie',
      'tariffLimitsTitle': 'Taryf i limity',
      'telegramLabel': 'Telegram',
      'usedActiveLabel': 'UÅ¼yto (aktywni)',
      'inactiveNotCountedNote': 'Zwolnieni/nieaktywni nie sÄ wliczani do limitu.',
      'versionLabel': 'Wersja',
      'worker': 'Pracownik',
      'myShift': 'Moja zmiana',
      'startShift': 'Rozpocznij zmianÄ',
      'endShift': 'ZakoÅcz zmianÄ',
      'currentShift': 'Aktualna zmiana',
      'shiftStarted': 'Zmiana rozpoczÄta!',
      'shiftEnded': 'Zmiana zakoÅczona!',
      'shiftActive': 'Zmiana aktywna',
      'shiftStart': 'PoczÄtek',
      'shiftEnd': 'Koniec',
      'selectSite': 'Wybierz obiekt',
      'noSites': 'Brak obiektÃ³w. Skontaktuj siÄ z administratorem.',
      'writeReport': 'Raport ze zmiany',
      'whatDone': 'Co zostaÅo zrobione',
      'workReport': 'Raport',
      'timesheets': 'Grafik zmian',
      'myTimesheets': 'Moje zmiany',
      'allTimesheets': 'Wszystkie zmiany',
      'totalHours': 'ÅÄcznie godzin',
      'shiftsCount': 'Zmian',
      'manageSites': 'ZarzÄdzanie obiektami',
      'sites': 'Obiekty',
      'addSite': 'Dodaj obiekt',
      'editSite': 'Edytuj obiekt',
      'siteName': 'Nazwa obiektu',
      'siteAddress': 'Adres',
      'siteRadius': 'PromieÅ meldowania (m)',
      'gpsInterval': 'InterwaÅ GPS (min)',
      'gpsPermissionDenied': 'GPS niedostÄpny â zmiana rozpoczÄta bez weryfikacji lokalizacji',
      'gpsWarningTitle': 'JesteÅ poza strefÄ obiektu',
      'gpsWarningText': 'Twoja lokalizacja nie zgadza siÄ z adresem obiektu.',
      'distance': 'OdlegÅoÅÄ',
      'startAnyway': 'Rozpocznij mimo to',
      'allTime': 'CaÅy czas',
      'allSites': 'Wszystkie obiekty',
      'allPeople': 'Wszyscy pracownicy',
      'exportXlsx': 'Eksport Excel',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'WZ PDF',
      'cannotSetToolStatusOnHands': 'Nie moÅ¼na zmieniÄ statusu: narzÄdzie jest wydane',
      'gpsTrack': 'Ålad GPS',
      'noGpsData': 'Brak danych GPS',
      'shiftTypeHourly': 'Godzinowy',
      'shiftTypeAccord': 'Akordowy',
      'chooseShiftType': 'Typ zmiany',
      'shiftType': 'Typ pracy',
      'reportRequired': 'UzupeÅnij raport â co zostaÅo zrobione',
      'viewSites': 'Wszystkie obiekty',
      'navigateTo': 'Trasa',
      'linkUser': 'PoÅÄcz uÅ¼ytkownika',
      'linkedUser': 'PoÅÄczony z',
      'unlinkUser': 'RozÅÄcz',
      'selectUserToLink': 'Wybierz uÅ¼ytkownika',
      'notLinked': 'Konto nie jest poÅÄczone z profilem. Skontaktuj siÄ z administratorem.',
      'personTypePerson': 'Osoba',
      'personTypeObject': 'Obiekt',
      'noObjects': 'Brak obiektÃ³w. NaciÅnij +',
      'objectCompleted': 'ZakoÅczony',
      'markObjectCompleted': 'ZakoÅcz obiekt',
      'personTab': 'Osoby',
      'objectTab': 'Obiekty',
      'cannotCompleteHasTools': 'Nie moÅ¼na zakoÅczyÄ: {n} narzÄdzi na obiekcie',
      'cannotFireHasTools': 'Nie moÅ¼na zwolniÄ: pracownik ma {n} narzÄdzi',
      'addObject': 'Dodaj obiekt',
      'shiftReminder10hTitle': 'Zmiana trwa 10 godzin',
      'shiftReminder10hBody': 'Zmiana aktywna ponad 10 godzin. PamiÄtaj o zamkniÄciu.',
      'shiftReminder12hTitle': 'â ï¸ Zmiana 12 godzin!',
      'shiftReminder12hBody': 'Uwaga: zmiana trwa ponad 12 godzin. Zamknij zmianÄ.',
      'offlineBanner': 'Brak poÅÄczenia â¢ dane z cache',
      'alreadyHaveActiveShift': 'Masz juÅ¼ aktywnÄ zmianÄ. Zamknij jÄ przed rozpoczÄciem nowej.',
      'forceCloseShift': 'WymuÅ zamkniÄcie',
      'forceCloseShiftHint': 'Zmiana zostanie zamkniÄta teraz. MoÅ¼esz dodaÄ raport.',
      'shiftClosed': 'Zmiana zamkniÄta.',
      'archive': 'Archiwum',
      'noArchive': 'Archiwum puste',
      'notifications': 'Powiadomienia',
      'noNotifications': 'Brak nowych powiadomieÅ',
      'newMemberRequest': 'Nowe zgÅoszenie doÅÄczenia',
      'markAllRead': 'Oznacz wszystkie jako przeczytane',
      'copyTool': 'Kopiuj',
      'toolCopied': 'NarzÄdzie skopiowane',
      'sortNameAZ': 'Nazwa A-Z',
      'sortCountDesc': 'DuÅ¼e grupy najpierw',
      'sortDateDesc': 'Najnowsze najpierw',
      'darkTheme': 'Ciemny motyw',
      'lightTheme': 'Jasny motyw',
      'systemTheme': 'Motyw systemowy',
      'printQr': 'Drukuj QR',
      'saveAsPng': 'Zapisz PNG',
      'thermalLabel': 'Etykieta termiczna',
      'printAllQr': 'Wszystkie QR na arkusz',
      'noResults': 'Nic nie znaleziono',
    },
    AppLang.en: {
      'appTitle': 'ToolKeeper',
      'login': 'Login',
      'register': 'Register',
      'enter': 'Sign in',
      'logout': 'Sign out',
      'people': 'People',
      'tools': 'Tools',
      'tool': 'Tool',
      'inv': 'Inv. #',
      'issue': 'Issue',
      'profile': 'Profile',
      'chooseLang': 'Choose language',
      'chooseCompany': 'Choose your company',
      'searchingCompany': 'Searching your company...',
      'companyNotFound': 'Company not found',
      'companyDeleted': 'Company deleted',
      'noAccessCompany': 'No access to the company',
      'removedFromCompany': 'You were removed from the company. Enter the code again and wait for approval.',
      'leaveCompany': 'Leave / choose another company',
      'createCompany': 'Create company',
      'enterInviteCode': 'Enter invite code',
      'joinCompany': 'Join',
      'or': 'OR',
      'companyName': 'Company name',
      'create': 'Create',
      'myCompany': 'My company',
      'myProfile': 'My profile',
      'role': 'Role',
      'role_owner': 'Owner',
      'role_admin': 'Admin',
      'role_foreman': 'Foreman',
      'role_employee': 'Employee',
      'editRoles': 'Edit roles',
      'save': 'Save',
      'cancel': 'Cancel',
      'inviteCode': 'Invite code',
      'copy': 'Copy',
      'copied': 'Copied',
      'share': 'Share',
      'pendingRequests': 'Join requests',
      'accept': 'Accept',
      'deny': 'Deny',
      'noRequests': 'No requests',
      'members': 'Members',
      'noMembers': 'No members',
      'addEmployee': 'Add employee',
      'employeeFirstName': 'First name',
      'employeeLastName': 'Last name',
      'employeePosition': 'Position',
      'phone': 'Phone',
      'add': 'Add',
      'editEmployee': 'Edit employee',
      'deleteEmployee': 'Delete employee',
      'delete': 'Delete',
      'deleteConfirm': 'Delete for sure?',
      'searchEmployee': 'Search employee...',
      'noEmployees': 'No employees',
      'addTool': 'Add tool',
      'toolName': 'Tool name',
      'toolInv': 'Inv. no.',
      'addToolBtn': 'Add',
      'editTool': 'Edit tool',
      'deleteTool': 'Delete tool',
      'searchTool': 'Search tool...',
      'noTools': 'No tools',
      'issueTitle': 'Issue / Return',
      'issueTo': 'Issue',
      'returnFrom': 'Return',
      'selectEmployee': 'Select employee',
      'selectTool': 'Select tool',
      'issued': 'Issued',
      'returned': 'Returned',
      'history': 'History',
      'searchHistory': 'Search in history...',
      'noMoves': 'No records',
      'moveIssue': 'Issue',
      'moveReturn': 'Return',
      'onHands': 'On hands',
      'freeTools': 'Free',
      'total': 'Total',
      'toolsCount': 'Tools',
      'pcs': 'pcs.',
      'report': 'Report',
      'filter': 'Filter',
      'reset': 'Reset',
      'export': 'Export',
      'exportCsv': 'Export CSV',
      'exportPdf': 'Export PDF',
      'exportDone': 'Export ready',
      'loading': 'Loading...',
      'error': 'Error',
      'ok': 'OK',
      'yes': 'Yes',
      'no': 'No',
      'langRu': 'Ð ÑÑÑÐºÐ¸Ð¹',
      'langUk': 'Ð£ÐºÑÐ°ÑÐ½ÑÑÐºÐ°',
      'langPl': 'Polski',
      'langEn': 'English',
      'selectModeFirst': 'First select: ISSUE or RETURN',
      'selectPersonForReturnFirst': 'First select an employee for RETURN',
      'noRightsIssueReturn': 'No rights to issue/return',
      'selectPersonAndTool': 'Select employee and tool',
      'issueUpper': 'ISSUE',
      'returnUpper': 'RETURN',
      'invShort': 'Inv',
      'invNumber': 'Inv. no.',
      'noName': 'No name',
      'noTitle': 'No title',
      'noFreeTools': 'No free tools',
      'noToolsOnHands': 'No tools on hands',
      'whoSelectEmployee': 'Issue to',
      'whoField': 'WHO (Select employee)',
      'whatSelectEmployeeTool': 'What to issue',
      'whatSelectFreeTool': 'What to return',
      'whatFieldOnHands': 'WHAT (This employee\'s tool)',
      'whatFieldFree': 'WHAT (Free tool)',
      'confirmReturn': 'Return',
      'confirmIssue': 'Issue',
      'restoreCompanyError': 'Failed to restore company selection',
      'restoredCompanyId': 'I restored activeCompanyId from your profile',
      'resetActiveCompanyId': 'I reset activeCompanyId so you can choose/create the company again.',
      'errUserRead': 'Error reading user profile',
      'errCompanyRead': 'Error reading company',
      'errMemberRead': 'Error reading company member',
    'addPerson': 'Add person',
    'alreadyIn': 'Already in company',
    'approve': 'Approve',
    'archivedCompany': 'Company archived',
    'askAdminIssueReturn': 'Ask admin to issue/return',
    'deleteCompanyConfirm': 'Delete company permanently?',
    'deleteCompanyWarn': 'This will delete all data. Action cannot be undone.',
    'issueTab': 'Issue',
    'returnTab': 'Return',
    'searchByNameOrPhone': 'Search by name or phone...',
    'selectToolFirst': 'Select a tool first',
    'birthDate': 'Birth date',
    'changePassword': 'Change / set password',
    'chooseRole': 'Choose role',
    'clothesSize': 'Clothes size',
    'codeNotFound': 'Code not found',
    'company': 'Company',
    'continue': 'Continue',
    'copyCodeHint': 'Copy and send to employee',
    'decline': 'Decline',
    'deleteCompany': 'Delete company',
    'deleteCompanyText': 'Delete company permanently',
    'deleteCompanyTitle': 'Delete company',
    'done': 'Done',
    'editCompany': 'Edit company',
    'editMyProfile': 'Edit my profile',
    'editProfile': 'Edit profile',
    'firstName': 'First name',
    'invHint': 'Inventory number (e.g. SKDW-001)',
    'lastName': 'Last name',
    'password': 'Password',
    'position': 'Position',
    'reports': 'Reports',
    'reportsPeople': 'Who has what (by people)',
    'reportsTools': 'Where is tool (by tools)',
    'reportFilterHint': 'Report filter...',
    'onHandsTotal': 'Total on hands now: {n} pcs.',
    'toolsCountLabel': 'Tools: {n}',
    'whoLabel': 'Who: {name}',
    'requests': 'Requests',
    'saveProfile': 'Save profile',
    'sendReset': 'Send reset link',
    'sessionTitle': 'Session',
    'setPassword': 'Set password',
    'setRole': 'Set role',
    'shoeSize': 'Shoe size',
    'switchAcc': 'Switch account',
    'toolNameHint': 'Name (e.g. Grinder)',
    'welcome': 'Welcome',
    'yourInviteCode': 'Your invite code',
    'repeatPassword': 'Repeat password',
    'email': 'Email',
    'employee': 'Employee',
    'employees': 'Employees',
    'enterEmailPass': 'Enter email and password',
    'google': 'Google',
    'haveAccount': 'Already have an account?',
    'historyEmpty': 'No history yet',
    'linkPassword': 'Link/set password',
    'needAccount': 'Need an account',
    'needProfile': 'Please fill in profile',
    'needReLogin': 'Please sign in again',
    'newCompanyName': 'New company name',
    'newPassword': 'New password',
    'noPeople': 'No people yet',
    'noneIssued': 'Nothing issued',
    'noneIssued2': 'No tools on hands',
    'onlyAdmin': 'Only owner/admin',
    'owner': 'Owner',
    'passwordsNotMatch': 'Passwords do not match',
    'pendingText': 'Your request is pending approval',
    'pendingTitle': 'Pending',
    'profileForm': 'Profile form',
    'renameCompany': 'Rename company',
      'searchByNameOrInv': 'Search by name or No...',
      'searchByToolOrLastName': 'Search by tool or last name...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Employee status',
      'empStatusActive': 'Active',
      'empStatusFired': 'Fired',
      'toolStatus': 'Tool status',
      'toolStatusActive': 'Active',
      'toolStatusRepair': 'In repair',
      'toolStatusDisposed': 'Disposed',
      'markToolActive': 'Mark as active',
      'markToolRepair': 'Send to repair',
      'markToolDisposed': 'Write off (dispose)',
      'statusNote': 'Note',
      'reportsByTool': 'By tool',
      'reportsByPerson': 'By employee',
      'selectPerson': 'Select employee',
      'selectPersonFirst': 'Select an employee first',
      'warehouse': 'Warehouse',
      'where': 'Where',
      'issuedAt': 'Issued',
      'noData': 'No data',
      'noIssued': 'Nothing issued',
      'subscriptionTitle': 'Subscription',
      'subscriptionStatusLabel': 'Status',
      'subscriptionModeLabel': 'Mode',
      'subscriptionValidUntilLabel': 'Valid until',
      'subscriptionTest': 'Test mode',
      'subscriptionLive': 'Paid mode',
      'subscriptionActive': 'Active',
      'subscriptionInactive': 'Inactive',
      'buyRenew': 'Buy / Renew',
      'buyRenewSoon': 'Payments will be available soon. For now, contact support to buy/renew.',
      'admin': 'Admin',
      'billingLive': 'LIVE',
      'billingTest': 'TEST',
      'billingModeLabel': 'Payment mode',
      'changePlan': 'Change plan',
      'emailLabel': 'Email',
      'employeeRequests': 'Employee requests',
      'enterPassword': 'Enter password',
      'enterPhone': 'Enter phone',
      'fixAccess': "It looks like this account has no access to the company (PERMISSION_DENIED) or activeCompanyId points to the wrong company.\n" + 'Go to Profile â select a company / enter invite code, or ask the owner for access.',
      'join': 'Join',
      'lang': 'Language',
      'loginPc': 'PC login: link/change password',
      'name': 'Name',
      'needPeopleFirst': 'Add people first',
      'needToolsFirst': 'Add tools first',
      'noCompany': 'No company selected',
      'noFreeTool': 'No free tool available',
      'noReturnTool': 'No tool to return',
      'noRights': 'No rights',
      'peopleLimitLabel': 'People limit',
      'perMonth': 'month',
      'person': 'Person',
      'planChangeOnlyOwner': 'Only the owner can change the plan.',
      'planLabel': 'Plan',
      'planSaved': 'Plan saved',
      'gpsNotInPlan': 'GPS tracking available from Pro plan and above',
      'gpsIncluded': 'GPS â',
      'gpsNotIncluded': 'GPS â',
      'returnTitle': 'Confirm return',
      'returnTool': 'Return',
      'selectPlan': 'Choose a plan',
      'supportDesc': 'For questions about the app, you can contact us:',
      'supportTitle': 'Support',
      'tariffLimitsTitle': 'Tariff and limits',
      'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Used (active)',
      'inactiveNotCountedNote': 'Fired/inactive are not counted toward the limit.',
      'versionLabel': 'Version',
      'worker': 'Employee',
      'myShift': 'My shift',
      'startShift': 'Start shift',
      'endShift': 'End shift',
      'currentShift': 'Current shift',
      'shiftStarted': 'Shift started!',
      'shiftEnded': 'Shift ended!',
      'shiftActive': 'Shift active',
      'shiftStart': 'Start',
      'shiftEnd': 'End',
      'selectSite': 'Select site',
      'noSites': 'No sites added. Contact your administrator.',
      'writeReport': 'Shift report',
      'whatDone': 'What was done',
      'workReport': 'Report',
      'timesheets': 'Timesheets',
      'myTimesheets': 'My shifts',
      'allTimesheets': 'All shifts',
      'totalHours': 'Total hours',
      'shiftsCount': 'Shifts',
      'manageSites': 'Manage sites',
      'sites': 'Sites',
      'addSite': 'Add site',
      'editSite': 'Edit site',
      'siteName': 'Site name',
      'siteAddress': 'Address',
      'siteRadius': 'Check-in radius (m)',
      'gpsInterval': 'GPS interval (min)',
      'gpsPermissionDenied': 'GPS unavailable â shift started without location check',
      'gpsWarningTitle': 'Outside site zone',
      'gpsWarningText': 'Your location does not match the site address.',
      'distance': 'Distance',
      'startAnyway': 'Start anyway',
      'allTime': 'All time',
      'allSites': 'All sites',
      'allPeople': 'All people',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Act PDF',
      'nakladnayaPdf': 'Invoice PDF',
      'cannotSetToolStatusOnHands': 'Cannot change status: tool is currently issued',
      'gpsTrack': 'GPS track',
      'noGpsData': 'No GPS data',
      'shiftTypeHourly': 'Hourly',
      'shiftTypeAccord': 'Fixed price',
      'chooseShiftType': 'Shift type',
      'shiftType': 'Work type',
      'reportRequired': 'Fill in the report â what was done',
      'viewSites': 'All sites',
      'navigateTo': 'Navigate',
      'linkUser': 'Link user',
      'linkedUser': 'Linked to',
      'unlinkUser': 'Unlink',
      'selectUserToLink': 'Select user to link',
      'notLinked': 'Account is not linked to a profile. Contact your administrator.',
      'personTypePerson': 'Person',
      'personTypeObject': 'Object',
      'noObjects': 'No objects yet. Tap +',
      'objectCompleted': 'Completed',
      'markObjectCompleted': 'Mark as completed',
      'personTab': 'People',
      'objectTab': 'Objects',
      'cannotCompleteHasTools': 'Cannot complete: {n} tools on object',
      'cannotFireHasTools': 'Cannot fire: employee has {n} tools',
      'addObject': 'Add object',
      'shiftReminder10hTitle': 'Shift is 10 hours long',
      'shiftReminder10hBody': 'Shift has been active for over 10 hours. Don\'t forget to close it.',
      'shiftReminder12hTitle': 'â ï¸ Shift 12 hours!',
      'shiftReminder12hBody': 'Warning: shift has been running for over 12 hours. Close the shift.',
      'offlineBanner': 'No connection â¢ data from cache',
      'alreadyHaveActiveShift': 'You already have an active shift. Close it before starting a new one.',
      'forceCloseShift': 'Force close',
      'forceCloseShiftHint': 'The shift will be closed now. You can add a report.',
      'shiftClosed': 'Shift closed.',
      'archive': 'Archive',
      'noArchive': 'Archive is empty',
      'notifications': 'Notifications',
      'noNotifications': 'No new notifications',
      'newMemberRequest': 'New join request',
      'markAllRead': 'Mark all as read',
      'copyTool': 'Copy',
      'toolCopied': 'Tool copied',
      'sortNameAZ': 'Name A-Z',
      'sortCountDesc': 'Large groups first',
      'sortDateDesc': 'Newest first',
      'darkTheme': 'Dark theme',
      'lightTheme': 'Light theme',
      'systemTheme': 'System theme',
      'printQr': 'Print QR',
      'saveAsPng': 'Save PNG',
      'thermalLabel': 'Thermal label',
      'printAllQr': 'All QR to sheet',
      'noResults': 'Nothing found',
    },

    AppLang.de: {
      'appTitle': 'ToolKeeper', 'login': 'Anmelden', 'register': 'Registrieren', 'enter': 'Einloggen',
      'logout': 'Abmelden', 'people': 'Personen', 'tools': 'Werkzeuge', 'tool': 'Werkzeug',
      'inv': 'Inv.-Nr.', 'issue': 'Ausgabe', 'profile': 'Profil', 'chooseLang': 'Sprache wÃ¤hlen',
      'companyNotFound': 'Firma nicht gefunden', 'noAccessCompany': 'Kein Zugang zur Firma',
      'leaveCompany': 'Verlassen / andere Firma wÃ¤hlen', 'createCompany': 'Firma erstellen',
      'joinCompany': 'Beitreten', 'or': 'ODER', 'companyName': 'Firmenname',
      'create': 'Erstellen', 'myCompany': 'Meine Firma', 'myProfile': 'Mein Profil',
      'role': 'Rolle', 'role_owner': 'EigentÃ¼mer', 'role_admin': 'Administrator',
      'role_foreman': 'Vorarbeiter', 'role_employee': 'Mitarbeiter',
      'save': 'Speichern', 'cancel': 'Abbrechen', 'copy': 'Kopieren', 'copied': 'Kopiert',
      'accept': 'Annehmen', 'deny': 'Ablehnen', 'noRequests': 'Keine Anfragen',
      'members': 'Mitglieder', 'phone': 'Telefon', 'add': 'HinzufÃ¼gen', 'delete': 'LÃ¶schen',
      'deleteConfirm': 'Wirklich lÃ¶schen?', 'searchEmployee': 'Mitarbeiter suchen...',
      'noEmployees': 'Keine Mitarbeiter', 'toolName': 'Werkzeugname', 'toolInv': 'Inv.-Nr.',
      'searchTool': 'Werkzeug suchen...', 'noTools': 'Keine Werkzeuge',
      'selectEmployee': 'Mitarbeiter auswÃ¤hlen', 'selectTool': 'Werkzeug auswÃ¤hlen',
      'issued': 'Ausgegeben', 'returned': 'ZurÃ¼ckgegeben', 'history': 'Verlauf',
      'noMoves': 'Keine EintrÃ¤ge', 'moveIssue': 'Ausgabe', 'moveReturn': 'RÃ¼ckgabe',
      'onHands': 'In HÃ¤nden', 'freeTools': 'Frei', 'total': 'Gesamt', 'toolsCount': 'Werkzeuge',
      'pcs': 'Stk.', 'report': 'Bericht', 'filter': 'Filter', 'reset': 'ZurÃ¼cksetzen',
      'export': 'Export', 'exportCsv': 'CSV exportieren', 'exportPdf': 'PDF exportieren',
      'exportDone': 'Export fertig', 'loading': 'Laden...', 'error': 'Fehler',
      'ok': 'OK', 'yes': 'Ja', 'no': 'Nein',
      'issueUpper': 'AUSGEBEN', 'returnUpper': 'ZURÃCKGEBEN', 'invShort': 'Inv',
      'invNumber': 'Inv.-Nr.', 'noName': 'Kein Name', 'noTitle': 'Kein Titel',
      'noFreeTools': 'Keine freien Werkzeuge', 'noToolsOnHands': 'Keine Werkzeuge in HÃ¤nden',
      'whoSelectEmployee': 'Ausgabe an', 'whoField': 'WER', 'whatSelectEmployeeTool': 'Was ausgeben',
      'whatSelectFreeTool': 'Was zurÃ¼ckgeben', 'whatFieldOnHands': 'WAS (In HÃ¤nden)',
      'whatFieldFree': 'WAS (Freies Werkzeug)', 'confirmReturn': 'ZurÃ¼ckgeben', 'confirmIssue': 'Ausgeben',
      'errUserRead': 'Fehler Benutzerprofil', 'errCompanyRead': 'Fehler Firma',
      'addPerson': 'Person hinzufÃ¼gen', 'approve': 'Genehmigen',
      'issueTab': 'Ausgabe', 'returnTab': 'RÃ¼ckgabe',
      'searchByNameOrPhone': 'Suche nach Name oder Telefon...',
      'birthDate': 'Geburtsdatum', 'clothesSize': 'KleidergrÃ¶Ãe', 'company': 'Firma',
      'continue': 'Weiter', 'decline': 'Ablehnen', 'done': 'Fertig',
      'firstName': 'Vorname', 'invHint': 'Inventarnummer (z.B. SKDW-001)', 'lastName': 'Nachname',
      'password': 'Passwort', 'position': 'Position', 'reports': 'Berichte', 'welcome': 'Willkommen',
      'email': 'E-Mail', 'employee': 'Mitarbeiter', 'employees': 'Mitarbeiter',
      'owner': 'EigentÃ¼mer', 'admin': 'Admin', 'worker': 'Mitarbeiter',
      'employeeStatus': 'Mitarbeiterstatus', 'empStatusActive': 'Aktiv', 'empStatusFired': 'Entlassen',
      'toolStatus': 'Werkzeugstatus', 'toolStatusActive': 'Aktiv', 'toolStatusRepair': 'In Reparatur',
      'toolStatusDisposed': 'Ausgesondert', 'markToolActive': 'Als aktiv markieren',
      'markToolRepair': 'Zur Reparatur senden', 'markToolDisposed': 'Aussondern',
      'statusNote': 'Notiz', 'reportsByTool': 'Nach Werkzeug', 'reportsByPerson': 'Nach Mitarbeiter',
      'selectPerson': 'Mitarbeiter auswÃ¤hlen', 'selectPersonFirst': 'Zuerst Mitarbeiter auswÃ¤hlen',
      'selectToolFirst': 'Zuerst Werkzeug auswÃ¤hlen',
      'warehouse': 'Lager', 'where': 'Wo', 'issuedAt': 'Ausgegeben am',
      'noData': 'Keine Daten', 'noIssued': 'Nichts ausgegeben',
      'subscriptionTitle': 'Abonnement', 'subscriptionStatusLabel': 'Status',
      'subscriptionModeLabel': 'Modus', 'subscriptionValidUntilLabel': 'GÃ¼ltig bis',
      'subscriptionTest': 'Testmodus', 'subscriptionLive': 'Bezahlmodus',
      'subscriptionActive': 'Aktiv', 'subscriptionInactive': 'Inaktiv',
      'buyRenew': 'Kaufen / VerlÃ¤ngern',
      'buyRenewSoon': 'Zahlung bald verfÃ¼gbar. Bitte Support kontaktieren.',
      'admin2': 'Admin', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'billingModeLabel': 'Zahlungsmodus', 'emailLabel': 'E-Mail',
      'needPeopleFirst': 'Zuerst Personen hinzufÃ¼gen', 'needToolsFirst': 'Zuerst Werkzeuge hinzufÃ¼gen',
      'noFreeTool': 'Kein freies Werkzeug', 'noReturnTool': 'Kein Werkzeug zur RÃ¼ckgabe',
      'peopleLimitLabel': 'Personenlimit', 'perMonth': 'Monat', 'person': 'Person',
      'planChangeOnlyOwner': 'Nur der EigentÃ¼mer kann den Plan Ã¤ndern.',
      'planLabel': 'Plan', 'planSaved': 'Plan gespeichert', 'gpsNotInPlan': 'GPS-Tracking ab Plan Pro verfÃ¼gbar', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'returnTitle': 'RÃ¼ckgabe bestÃ¤tigen', 'returnTool': 'ZurÃ¼ckgeben',
      'selectPlan': 'Plan auswÃ¤hlen', 'supportTitle': 'Support',
      'supportDesc': 'Bei Fragen zur App kontaktieren Sie uns:',
      'tariffLimitsTitle': 'Tarif und Limits', 'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Verwendet (aktiv)',
      'inactiveNotCountedNote': 'Entlassene/Inaktive zÃ¤hlen nicht zum Limit.',
      'versionLabel': 'Version', 'lang': 'Sprache', 'noCompany': 'Keine Firma ausgewÃ¤hlt',
      'noRights': 'Keine Rechte', 'join': 'Beitreten', 'name': 'Name',
      'onHandsTotal': 'Aktuell in HÃ¤nden: {n} Stk.', 'toolsCountLabel': 'Werkzeuge: {n}',
      'whoLabel': 'Wer: {name}', 'reportFilterHint': 'Berichtsfilter...',
      'reportsPeople': 'Wer hat was (nach Personen)',
      'reportsTools': 'Wo ist das Werkzeug (nach Werkzeug)',
      'searchByNameOrInv': 'Suche nach Name oder Nr...',
      'searchByToolOrLastName': 'Suche nach Werkzeug oder Nachname...',
      'saveProfile': 'Profil speichern', 'setRole': 'Rolle festlegen', 'shoeSize': 'SchuhgrÃ¶Ãe',
      'switchAcc': 'Konto wechseln', 'yourInviteCode': 'Ihr Einladungscode',
      'repeatPassword': 'Passwort wiederholen', 'haveAccount': 'Bereits ein Konto?',
      'historyEmpty': 'Noch kein Verlauf', 'needAccount': 'Konto benÃ¶tigt',
      'newCompanyName': 'Neuer Firmenname', 'newPassword': 'Neues Passwort',
      'noPeople': 'Noch keine Personen', 'noneIssued': 'Nichts ausgegeben',
      'noneIssued2': 'Keine Werkzeuge in HÃ¤nden',
      'onlyAdmin': 'Nur EigentÃ¼mer/Admin', 'passwordsNotMatch': 'PasswÃ¶rter stimmen nicht Ã¼berein',
      'profileForm': 'Profilformular', 'renameCompany': 'Firma umbenennen',
      'changePlan': 'Plan Ã¤ndern', 'enterEmailPass': 'E-Mail und Passwort eingeben',
      'google': 'Google', 'linkPassword': 'Passwort verknÃ¼pfen',
      'needProfile': 'Bitte Profil ausfÃ¼llen', 'needReLogin': 'Bitte erneut anmelden',
      'pendingText': 'Ihre Anfrage wartet auf Genehmigung', 'pendingTitle': 'Ausstehend',
      'sendReset': 'Reset-Link senden', 'sessionTitle': 'Sitzung', 'setPassword': 'Passwort festlegen',
      'toolNameHint': 'Name (z.B. Schleifer)', 'editProfile': 'Profil bearbeiten',
      'editMyProfile': 'Mein Profil bearbeiten', 'editCompany': 'Firma bearbeiten',
      'chooseRole': 'Rolle wÃ¤hlen', 'codeNotFound': 'Code nicht gefunden',
      'copyCodeHint': 'Kopieren und an Mitarbeiter senden',
      'deleteCompany': 'Firma lÃ¶schen', 'deleteCompanyTitle': 'Firma lÃ¶schen',
      'deleteCompanyText': 'Firma vollstÃ¤ndig lÃ¶schen',
      'inviteCode': 'Einladungscode', 'requests': 'Anfragen',
      'alreadyIn': 'Bereits in Firma', 'archivedCompany': 'Firma archiviert',
      'issueTo': 'Ausgeben', 'returnFrom': 'ZurÃ¼ckgeben',
      'selectModeFirst': 'Zuerst wÃ¤hlen: AUSGABE oder RÃCKGABE',
      'selectPersonForReturnFirst': 'Zuerst Mitarbeiter fÃ¼r RÃ¼ckgabe auswÃ¤hlen',
      'noRightsIssueReturn': 'Keine Rechte zur Ausgabe/RÃ¼ckgabe',
      'selectPersonAndTool': 'Mitarbeiter und Werkzeug auswÃ¤hlen',
      'addTool': 'Werkzeug hinzufÃ¼gen', 'addEmployee': 'Mitarbeiter hinzufÃ¼gen',
      'editTool': 'Werkzeug bearbeiten', 'editEmployee': 'Mitarbeiter bearbeiten',
      'deleteTool': 'Werkzeug lÃ¶schen', 'deleteEmployee': 'Mitarbeiter lÃ¶schen',
      'issueTitle': 'Ausgabe / RÃ¼ckgabe', 'searchHistory': 'Verlauf durchsuchen...',
      'alreadyIn2': 'Bereits vorhanden', 'enterInviteCode': 'Einladungscode eingeben',
      'employeeFirstName': 'Vorname', 'employeeLastName': 'Nachname',
      'employeePosition': 'Position', 'addToolBtn': 'HinzufÃ¼gen',
      'pendingRequests': 'Beitrittsanfragen', 'noMembers': 'Keine Mitglieder',
      'editRoles': 'Rollen bearbeiten', 'share': 'Teilen',
      'chooseCompany': 'Firma auswÃ¤hlen', 'searchingCompany': 'Firma wird gesucht...',
      'companyDeleted': 'Firma gelÃ¶scht',
      'removedFromCompany': 'Sie wurden entfernt. Geben Sie den Code erneut ein.',
      'enterPhone': 'Telefon eingeben', 'enterPassword': 'Passwort eingeben',
      'employeeRequests': 'Mitarbeiteranfragen', 'loginPc': 'PC-Login: Passwort verknÃ¼pfen',
      'myShift': 'Meine Schicht', 'startShift': 'Schicht beginnen', 'endShift': 'Schicht beenden',
      'currentShift': 'Aktuelle Schicht', 'shiftStarted': 'Schicht gestartet!', 'shiftEnded': 'Schicht beendet!',
      'selectSite': 'Baustelle auswÃ¤hlen', 'noSites': 'Keine Baustellen. Administrator kontaktieren.',
      'writeReport': 'Schichtbericht', 'whatDone': 'Was wurde gemacht', 'timesheets': 'Schichtprotokoll',
      'manageSites': 'Baustellen verwalten', 'sites': 'Baustellen', 'addSite': 'Baustelle hinzufÃ¼gen',
      'editSite': 'Baustelle bearbeiten', 'siteName': 'Name der Baustelle', 'siteAddress': 'Adresse',
      'siteRadius': 'Check-in Radius (m)', 'gpsInterval': 'GPS-Intervall (Min)',
      'allTime': 'Gesamte Zeit',
      'allSites': 'Alle Baustellen',
      'allPeople': 'Alle Mitarbeiter',
      'exportXlsx': 'Excel exportieren',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'Lieferschein PDF',
      'cannotSetToolStatusOnHands': 'Status kann nicht geÃ¤ndert werden: Werkzeug ist vergeben',
      'gpsTrack': 'GPS-Spur',
      'noGpsData': 'Keine GPS-Daten',
      'shiftActive': 'Schicht aktiv',
      'shiftStart': 'Beginn',
      'shiftEnd': 'Ende',
      'totalHours': 'Gesamtstunden',
      'shiftsCount': 'Schichten',
      'workReport': 'Bericht',
      'myTimesheets': 'Meine Schichten',
      'allTimesheets': 'Alle Schichten',
      'gpsPermissionDenied': 'GPS nicht verfÃ¼gbar â Schicht ohne StandortprÃ¼fung gestartet',
      'gpsWarningTitle': 'AuÃerhalb der Baustelle',
      'gpsWarningText': 'Ihr Standort stimmt nicht mit der Baustellenadresse Ã¼berein.',
      'distance': 'Entfernung',
      'startAnyway': 'Trotzdem starten',
      'shiftTypeHourly': 'StÃ¼ndlich',
      'shiftTypeAccord': 'Festpreis',
      'chooseShiftType': 'Schichttyp',
      'shiftType': 'Arbeitstyp',
      'reportRequired': 'Bericht ausfÃ¼llen â was wurde gemacht',
      'viewSites': 'Alle Baustellen',
      'navigateTo': 'Navigation',
      'linkUser': 'Benutzer verknÃ¼pfen',
      'linkedUser': 'VerknÃ¼pft mit',
      'unlinkUser': 'VerknÃ¼pfung lÃ¶sen',
      'selectUserToLink': 'Benutzer auswÃ¤hlen',
      'notLinked': 'Konto ist nicht mit einem Profil verknÃ¼pft. Administrator kontaktieren.',
      'personTypePerson': 'Person',
      'personTypeObject': 'Objekt',
      'noObjects': 'Noch keine Objekte. + drÃ¼cken',
      'objectCompleted': 'Abgeschlossen',
      'markObjectCompleted': 'Als abgeschlossen markieren',
      'personTab': 'Personen',
      'objectTab': 'Objekte',
      'cannotCompleteHasTools': 'Kann nicht abschlieÃen: {n} Werkzeuge am Objekt',
      'cannotFireHasTools': 'Kann nicht entlassen: Mitarbeiter hat {n} Werkzeuge',
      'addObject': 'Objekt hinzufÃ¼gen',
      'shiftReminder10hTitle': 'Schicht dauert 10 Stunden',
      'shiftReminder10hBody': 'Schicht ist seit Ã¼ber 10 Stunden aktiv. Nicht vergessen zu schlieÃen.',
      'shiftReminder12hTitle': 'â ï¸ Schicht 12 Stunden!',
      'shiftReminder12hBody': 'Warnung: Schicht lÃ¤uft seit Ã¼ber 12 Stunden. Schicht schlieÃen.',
      'offlineBanner': 'Keine Verbindung â¢ Daten aus Cache',
      'alreadyHaveActiveShift': 'Sie haben bereits eine aktive Schicht. SchlieÃen Sie sie zuerst.',
      'forceCloseShift': 'Erzwungen schlieÃen',
      'forceCloseShiftHint': 'Die Schicht wird jetzt geschlossen. Sie kÃ¶nnen einen Bericht hinzufÃ¼gen.',
      'shiftClosed': 'Schicht geschlossen.',
      'archive': 'Archiv',
      'noArchive': 'Archiv ist leer',
      'notifications': 'Benachrichtigungen',
      'noNotifications': 'Keine neuen Benachrichtigungen',
      'newMemberRequest': 'Neuer Beitrittsantrag',
      'markAllRead': 'Alle als gelesen markieren',
      'copyTool': 'Kopieren',
      'toolCopied': 'Werkzeug kopiert',
      'sortNameAZ': 'Name A-Z',
      'sortCountDesc': 'GroÃe Gruppen zuerst',
      'sortDateDesc': 'Neueste zuerst',
      'darkTheme': 'Dunkles Design',
      'lightTheme': 'Helles Design',
      'systemTheme': 'Systemdesign',
      'printQr': 'QR drucken',
      'saveAsPng': 'Als PNG speichern',
      'thermalLabel': 'Thermoetikett',
      'printAllQr': 'Alle QR auf Blatt',
      'noResults': 'Nichts gefunden',
    },

    AppLang.fr: {
      'appTitle': 'ToolKeeper', 'login': 'Connexion', 'register': 'Inscription', 'enter': 'Se connecter',
      'logout': 'DÃ©connexion', 'people': 'Personnes', 'tools': 'Outils', 'tool': 'Outil',
      'inv': 'NÂ° inv.', 'issue': 'Ãmission', 'profile': 'Profil', 'chooseLang': 'Choisir la langue',
      'companyNotFound': 'Entreprise introuvable', 'noAccessCompany': 'Pas d accÃ¨s Ã  l entreprise',
      'leaveCompany': 'Quitter / autre entreprise', 'createCompany': 'CrÃ©er une entreprise',
      'joinCompany': 'Rejoindre', 'or': 'OU', 'companyName': 'Nom de l entreprise',
      'role': 'RÃ´le', 'role_owner': 'PropriÃ©taire', 'role_admin': 'Administrateur',
      'role_foreman': 'ContremaÃ®tre', 'role_employee': 'EmployÃ©',
      'save': 'Enregistrer', 'cancel': 'Annuler', 'add': 'Ajouter', 'delete': 'Supprimer',
      'noEmployees': 'Pas d employÃ©s', 'noTools': 'Pas d outils',
      'issued': 'Ãmis', 'returned': 'RetournÃ©', 'history': 'Historique',
      'total': 'Total', 'pcs': 'pcs', 'loading': 'Chargement...', 'error': 'Erreur', 'ok': 'OK',
      'issueUpper': 'ÃMETTRE', 'returnUpper': 'RETOURNER', 'noName': 'Sans nom',
      'confirmReturn': 'Retourner', 'confirmIssue': 'Ãmettre',
      'issueTab': 'Ãmission', 'returnTab': 'Retour',
      'searchByNameOrPhone': 'Rechercher par nom ou tÃ©lÃ©phone...',
      'birthDate': 'Date de naissance', 'clothesSize': 'Taille', 'company': 'Entreprise',
      'continue': 'Continuer', 'done': 'TerminÃ©', 'firstName': 'PrÃ©nom', 'lastName': 'Nom',
      'password': 'Mot de passe', 'position': 'Poste', 'reports': 'Rapports', 'welcome': 'Bienvenue',
      'email': 'E-mail', 'employee': 'EmployÃ©', 'employees': 'EmployÃ©s',
      'owner': 'PropriÃ©taire', 'admin': 'Admin', 'worker': 'EmployÃ©',
      'employeeStatus': 'Statut employÃ©', 'empStatusActive': 'Actif', 'empStatusFired': 'LicenciÃ©',
      'toolStatus': 'Statut outil', 'toolStatusActive': 'Actif', 'toolStatusRepair': 'En rÃ©paration',
      'toolStatusDisposed': 'Mis au rebut', 'statusNote': 'Note',
      'warehouse': 'EntrepÃ´t', 'where': 'OÃ¹', 'issuedAt': 'Ãmis le', 'noData': 'Pas de donnÃ©es',
      'subscriptionTitle': 'Abonnement', 'subscriptionActive': 'Actif', 'subscriptionInactive': 'Inactif',
      'buyRenew': 'Acheter / Renouveler', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Ajouter des personnes d abord', 'needToolsFirst': 'Ajouter des outils d abord',
      'noFreeTool': 'Pas d outil libre', 'person': 'Personne', 'returnTool': 'Retourner',
      'versionLabel': 'Version', 'lang': 'Langue', 'selectPerson': 'SÃ©lectionner un employÃ©',
      'onHandsTotal': 'En main: {n} pcs.', 'toolsCountLabel': 'Outils: {n}', 'whoLabel': 'Qui: {name}',
      'reportFilterHint': 'Filtre rapport...', 'reportsPeople': 'Qui a quoi (par personnes)',
      'reportsTools': 'OÃ¹ est l outil (par outils)', 'searchByNameOrInv': 'Recherche par nom ou nÂ°...',
      'noReturnTool': 'Pas d outil Ã  retourner', 'noCompany': 'Pas d entreprise sÃ©lectionnÃ©e',
      'saveProfile': 'Enregistrer le profil', 'setRole': 'DÃ©finir le rÃ´le', 'shoeSize': 'Pointure',
      'yourInviteCode': 'Votre code d invitation', 'repeatPassword': 'RÃ©pÃ©ter le mot de passe',
      'haveAccount': 'DÃ©jÃ  un compte?', 'historyEmpty': 'Pas encore d historique',
      'needAccount': 'Compte requis', 'newCompanyName': 'Nouveau nom d entreprise',
      'newPassword': 'Nouveau mot de passe', 'noPeople': 'Pas encore de personnes',
      'noneIssued': 'Rien Ã©mis', 'noneIssued2': 'Pas d outils en main',
      'onlyAdmin': 'Seulement propriÃ©taire/admin', 'passwordsNotMatch': 'Mots de passe diffÃ©rents',
      'profileForm': 'Formulaire de profil', 'renameCompany': 'Renommer l entreprise',
      'changePlan': 'Changer de plan', 'planLabel': 'Plan', 'planSaved': 'Plan enregistrÃ©', 'gpsNotInPlan': 'Suivi GPS disponible Ã  partir du plan Pro', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Limite de personnes', 'perMonth': 'mois',
      'planChangeOnlyOwner': 'Seul le propriÃ©taire peut changer le plan.',
      'selectPlan': 'Choisir un plan', 'supportTitle': 'Support',
      'supportDesc': 'Pour toute question, contactez-nous:',
      'tariffLimitsTitle': 'Tarif et limites', 'telegramLabel': 'Telegram',
      'usedActiveLabel': 'UtilisÃ© (actifs)', 'inactiveNotCountedNote': 'LicenciÃ©s/inactifs non comptÃ©s.',
      'enterEmailPass': 'Entrer e-mail et mot de passe', 'google': 'Google',
      'linkPassword': 'Lier/dÃ©finir le mot de passe', 'needProfile': 'Veuillez complÃ©ter le profil',
      'needReLogin': 'Reconnectez-vous', 'pendingText': 'Votre demande est en attente',
      'pendingTitle': 'En attente', 'sendReset': 'Envoyer le lien', 'sessionTitle': 'Session',
      'setPassword': 'DÃ©finir le mot de passe', 'toolNameHint': 'Nom (ex. Meuleuse)',
      'editProfile': 'Modifier le profil', 'editMyProfile': 'Modifier mon profil',
      'editCompany': 'Modifier l entreprise', 'chooseRole': 'Choisir un rÃ´le',
      'codeNotFound': 'Code introuvable', 'copyCodeHint': 'Copier et envoyer Ã  l employÃ©',
      'deleteCompany': 'Supprimer l entreprise', 'inviteCode': 'Code d invitation',
      'requests': 'Demandes', 'approve': 'Approuver', 'addPerson': 'Ajouter une personne',
      'decline': 'Refuser', 'noIssued': 'Rien Ã©mis',
      'selectToolFirst': 'SÃ©lectionner d abord un outil',
      'selectPersonFirst': 'SÃ©lectionner d abord un employÃ©',
      'reportsByTool': 'Par outil', 'reportsByPerson': 'Par employÃ©',
      'markToolActive': 'Marquer comme actif', 'markToolRepair': 'Envoyer en rÃ©paration',
      'markToolDisposed': 'Mettre au rebut', 'alreadyIn': 'DÃ©jÃ  dans l entreprise',
      'archivedCompany': 'Entreprise archivÃ©e', 'noCompany2': 'Pas d entreprise',
      'subscriptionStatusLabel': 'Statut', 'subscriptionValidUntilLabel': 'Valide jusqu au',
      'subscriptionTest': 'Mode test', 'subscriptionLive': 'Mode payant',
      'buyRenewSoon': 'Paiement bientÃ´t disponible. Contacter le support.',
      'billingModeLabel': 'Mode de paiement', 'emailLabel': 'E-mail',
      'name': 'Nom', 'join': 'Rejoindre', 'noRights': 'Pas de droits',
      'returnTitle': 'Confirmer le retour', 'switchAcc': 'Changer de compte',
      'addTool': 'Ajouter un outil', 'addEmployee': 'Ajouter un employÃ©',
      'issueTo': 'Ãmettre Ã ', 'returnFrom': 'Retourner de',
      'searchByToolOrLastName': 'Recherche par outil ou nom...',
      'myShift': 'Mon quart', 'startShift': 'Commencer le quart', 'endShift': 'Terminer le quart',
      'currentShift': 'Quart en cours', 'shiftStarted': 'Quart dÃ©marrÃ©!', 'shiftEnded': 'Quart terminÃ©!',
      'selectSite': 'SÃ©lectionner le site', 'noSites': 'Aucun site. Contacter l\'administrateur.',
      'writeReport': 'Rapport de quart', 'whatDone': 'Ce qui a Ã©tÃ© fait', 'timesheets': 'Feuilles de temps',
      'manageSites': 'GÃ©rer les sites', 'sites': 'Sites', 'addSite': 'Ajouter un site',
      'editSite': 'Modifier le site', 'siteName': 'Nom du site', 'siteAddress': 'Adresse',
      'siteRadius': 'Rayon d\'enregistrement (m)', 'gpsInterval': 'Intervalle GPS (min)',
      'allTime': 'Toute la pÃ©riode',
      'allSites': 'Tous les sites',
      'allPeople': 'Tous les employÃ©s',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Acte PDF',
      'nakladnayaPdf': 'Bon de livraison PDF',
      'gpsTrack': 'Trace GPS',
      'noGpsData': 'Pas de donnÃ©es GPS',
      'shiftActive': 'Quart actif',
      'shiftStart': 'DÃ©but',
      'shiftEnd': 'Fin',
      'totalHours': 'Total heures',
      'shiftsCount': 'Quarts',
      'workReport': 'Rapport',
      'myTimesheets': 'Mes quarts',
      'allTimesheets': 'Tous les quarts',
      'gpsPermissionDenied': 'GPS indisponible â quart dÃ©marrÃ© sans vÃ©rification de localisation',
      'gpsWarningTitle': 'Hors de la zone du site',
      'gpsWarningText': 'Votre position ne correspond pas Ã  l\'adresse du site.',
      'distance': 'Distance',
      'startAnyway': 'DÃ©marrer quand mÃªme',
      'shiftTypeHourly': 'Horaire',
      'shiftTypeAccord': 'Prix fixe',
      'chooseShiftType': 'Type de quart',
      'shiftType': 'Type de travail',
      'reportRequired': 'Remplir le rapport â ce qui a Ã©tÃ© fait',
      'viewSites': 'Tous les sites',
      'navigateTo': 'ItinÃ©raire',
      'linkUser': 'Lier l\'utilisateur',
      'linkedUser': 'LiÃ© Ã ',
      'unlinkUser': 'DÃ©lier',
      'selectUserToLink': 'SÃ©lectionner l\'utilisateur',
      'notLinked': 'Compte non liÃ© Ã  un profil. Contacter l\'administrateur.',
      'personTypePerson': 'Personne',
      'personTypeObject': 'Objet',
      'noObjects': 'Pas encore d\'objets. Appuyer sur +',
      'objectCompleted': 'TerminÃ©',
      'markObjectCompleted': 'Marquer comme terminÃ©',
      'personTab': 'Personnes',
      'objectTab': 'Objets',
      'cannotCompleteHasTools': 'Impossible de terminer : {n} outils sur l\'objet',
      'cannotFireHasTools': 'Impossible de licencier : l\'employÃ© a {n} outils',
      'addObject': 'Ajouter un objet',
      'shiftReminder10hTitle': 'Le quart dure 10 heures',
      'shiftReminder10hBody': 'Le quart est actif depuis plus de 10 heures. N\'oubliez pas de le fermer.',
      'shiftReminder12hTitle': 'â ï¸ Quart 12 heures !',
      'shiftReminder12hBody': 'Attention : le quart dure depuis plus de 12 heures. Fermez le quart.',
      'offlineBanner': 'Pas de connexion â¢ donnÃ©es du cache',
      'alreadyHaveActiveShift': 'Vous avez dÃ©jÃ  un quart actif. Fermez-le avant d\'en commencer un nouveau.',
      'forceCloseShift': 'Forcer la fermeture',
      'forceCloseShiftHint': 'Le quart sera fermÃ© maintenant. Vous pouvez ajouter un rapport.',
      'shiftClosed': 'Quart fermÃ©.',
      'archive': 'Archive',
      'noArchive': 'L\'archive est vide',
      'notifications': 'Notifications',
      'noNotifications': 'Pas de nouvelles notifications',
      'newMemberRequest': 'Nouvelle demande d\'adhÃ©sion',
      'markAllRead': 'Tout marquer comme lu',
      'copyTool': 'Copier',
      'toolCopied': 'Outil copiÃ©',
      'sortNameAZ': 'Nom A-Z',
      'sortCountDesc': 'Grands groupes d\'abord',
      'sortDateDesc': 'Les plus rÃ©cents d\'abord',
      'darkTheme': 'ThÃ¨me sombre',
      'lightTheme': 'ThÃ¨me clair',
      'systemTheme': 'ThÃ¨me systÃ¨me',
      'printQr': 'Imprimer QR',
      'saveAsPng': 'Enregistrer PNG',
      'thermalLabel': 'Ãtiquette thermique',
      'printAllQr': 'Tous les QR sur feuille',
      'noResults': 'Aucun rÃ©sultat',
    },

    AppLang.es: {
      'appTitle': 'ToolKeeper', 'login': 'Iniciar sesiÃ³n', 'register': 'Registrarse', 'enter': 'Entrar',
      'logout': 'Cerrar sesiÃ³n', 'people': 'Personas', 'tools': 'Herramientas', 'tool': 'Herramienta',
      'inv': 'NÂ° inv.', 'issue': 'Entrega', 'profile': 'Perfil', 'chooseLang': 'Elegir idioma',
      'companyNotFound': 'Empresa no encontrada', 'noAccessCompany': 'Sin acceso a la empresa',
      'leaveCompany': 'Salir / elegir otra empresa', 'createCompany': 'Crear empresa',
      'joinCompany': 'Unirse', 'or': 'O', 'companyName': 'Nombre de empresa',
      'role': 'Rol', 'role_owner': 'Propietario', 'role_admin': 'Administrador',
      'role_foreman': 'Capataz', 'role_employee': 'Empleado',
      'save': 'Guardar', 'cancel': 'Cancelar', 'add': 'Agregar', 'delete': 'Eliminar',
      'noEmployees': 'Sin empleados', 'noTools': 'Sin herramientas',
      'issued': 'Entregado', 'returned': 'Devuelto', 'history': 'Historial',
      'total': 'Total', 'pcs': 'uds.', 'loading': 'Cargando...', 'error': 'Error', 'ok': 'OK',
      'issueUpper': 'ENTREGAR', 'returnUpper': 'DEVOLVER', 'noName': 'Sin nombre',
      'confirmReturn': 'Devolver', 'confirmIssue': 'Entregar',
      'issueTab': 'Entrega', 'returnTab': 'DevoluciÃ³n',
      'searchByNameOrPhone': 'Buscar por nombre o telÃ©fono...',
      'birthDate': 'Fecha de nacimiento', 'clothesSize': 'Talla de ropa', 'company': 'Empresa',
      'continue': 'Continuar', 'done': 'Listo', 'firstName': 'Nombre', 'lastName': 'Apellido',
      'password': 'ContraseÃ±a', 'position': 'Cargo', 'reports': 'Informes', 'welcome': 'Bienvenido',
      'email': 'Correo electrÃ³nico', 'employee': 'Empleado', 'employees': 'Empleados',
      'owner': 'Propietario', 'admin': 'Admin', 'worker': 'Empleado',
      'employeeStatus': 'Estado del empleado', 'empStatusActive': 'Activo', 'empStatusFired': 'Despedido',
      'toolStatus': 'Estado de herramienta', 'toolStatusActive': 'Activo', 'toolStatusRepair': 'En reparaciÃ³n',
      'toolStatusDisposed': 'Dado de baja', 'statusNote': 'Nota',
      'warehouse': 'AlmacÃ©n', 'where': 'DÃ³nde', 'issuedAt': 'Entregado', 'noData': 'Sin datos',
      'subscriptionTitle': 'SuscripciÃ³n', 'subscriptionActive': 'Activa', 'subscriptionInactive': 'Inactiva',
      'buyRenew': 'Comprar / Renovar', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Agregar personas primero', 'needToolsFirst': 'Agregar herramientas primero',
      'noFreeTool': 'Sin herramienta libre', 'person': 'Persona', 'returnTool': 'Devolver',
      'versionLabel': 'VersiÃ³n', 'lang': 'Idioma', 'selectPerson': 'Seleccionar empleado',
      'onHandsTotal': 'En mano: {n} uds.', 'toolsCountLabel': 'Herramientas: {n}', 'whoLabel': 'QuiÃ©n: {name}',
      'noReturnTool': 'Sin herramienta para devolver', 'noCompany': 'Sin empresa seleccionada',
      'reportFilterHint': 'Filtro...', 'reportsPeople': 'QuiÃ©n tiene quÃ© (por personas)',
      'reportsTools': 'DÃ³nde estÃ¡ la herramienta', 'searchByNameOrInv': 'Buscar por nombre o nÂ°...',
      'saveProfile': 'Guardar perfil', 'setRole': 'Establecer rol', 'shoeSize': 'Talla de zapato',
      'yourInviteCode': 'Su cÃ³digo de invitaciÃ³n', 'repeatPassword': 'Repetir contraseÃ±a',
      'haveAccount': 'Ya tiene cuenta?', 'historyEmpty': 'Sin historial aÃºn',
      'newPassword': 'Nueva contraseÃ±a', 'noPeople': 'Sin personas aÃºn', 'noneIssued': 'Nada entregado',
      'noneIssued2': 'Sin herramientas en mano', 'onlyAdmin': 'Solo propietario/admin',
      'passwordsNotMatch': 'Las contraseÃ±as no coinciden',
      'profileForm': 'Formulario de perfil', 'changePlan': 'Cambiar plan',
      'planLabel': 'Plan', 'planSaved': 'Plan guardado', 'gpsNotInPlan': 'Seguimiento GPS disponible desde el plan Pro', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â', 'peopleLimitLabel': 'LÃ­mite de personas',
      'perMonth': 'mes', 'planChangeOnlyOwner': 'Solo el propietario puede cambiar el plan.',
      'selectPlan': 'Elegir plan', 'supportTitle': 'Soporte',
      'supportDesc': 'Para preguntas, contÃ¡ctenos:', 'tariffLimitsTitle': 'Tarifa y lÃ­mites',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Usado (activos)',
      'inactiveNotCountedNote': 'Despedidos/inactivos no cuentan en el lÃ­mite.',
      'enterEmailPass': 'Ingresar correo y contraseÃ±a', 'google': 'Google',
      'linkPassword': 'Vincular/establecer contraseÃ±a', 'needProfile': 'Complete el perfil',
      'needReLogin': 'Inicie sesiÃ³n nuevamente', 'pendingText': 'Su solicitud espera aprobaciÃ³n',
      'pendingTitle': 'Pendiente', 'sendReset': 'Enviar enlace', 'sessionTitle': 'SesiÃ³n',
      'setPassword': 'Establecer contraseÃ±a', 'toolNameHint': 'Nombre (ej. Amoladora)',
      'editProfile': 'Editar perfil', 'editMyProfile': 'Editar mi perfil',
      'editCompany': 'Editar empresa', 'chooseRole': 'Elegir rol',
      'codeNotFound': 'CÃ³digo no encontrado', 'copyCodeHint': 'Copiar y enviar al empleado',
      'deleteCompany': 'Eliminar empresa', 'inviteCode': 'CÃ³digo de invitaciÃ³n',
      'requests': 'Solicitudes', 'approve': 'Aprobar', 'addPerson': 'Agregar persona',
      'decline': 'Rechazar', 'noIssued': 'Nada entregado',
      'selectToolFirst': 'Primero seleccione herramienta',
      'selectPersonFirst': 'Primero seleccione empleado',
      'reportsByTool': 'Por herramienta', 'reportsByPerson': 'Por empleado',
      'markToolActive': 'Marcar como activo', 'markToolRepair': 'Enviar a reparaciÃ³n',
      'markToolDisposed': 'Dar de baja', 'alreadyIn': 'Ya en empresa',
      'archivedCompany': 'Empresa archivada',
      'subscriptionStatusLabel': 'Estado', 'subscriptionValidUntilLabel': 'VÃ¡lida hasta',
      'subscriptionTest': 'Modo prueba', 'subscriptionLive': 'Modo pago',
      'buyRenewSoon': 'Pago pronto disponible. Contactar soporte.',
      'billingModeLabel': 'Modo de pago', 'emailLabel': 'Correo',
      'name': 'Nombre', 'join': 'Unirse', 'noRights': 'Sin derechos',
      'returnTitle': 'Confirmar devoluciÃ³n', 'needAccount': 'Necesita cuenta',
      'newCompanyName': 'Nuevo nombre de empresa', 'renameCompany': 'Renombrar empresa',
      'addTool': 'Agregar herramienta', 'addEmployee': 'Agregar empleado',
      'searchByToolOrLastName': 'Buscar por herramienta o apellido...',
      'switchAcc': 'Cambiar cuenta',
      'myShift': 'Mi turno', 'startShift': 'Iniciar turno', 'endShift': 'Terminar turno',
      'currentShift': 'Turno actual', 'shiftStarted': 'Â¡Turno iniciado!', 'shiftEnded': 'Â¡Turno terminado!',
      'selectSite': 'Seleccionar sitio', 'noSites': 'Sin sitios. Contacte al administrador.',
      'writeReport': 'Informe del turno', 'whatDone': 'QuÃ© se hizo', 'timesheets': 'Registro de turnos',
      'manageSites': 'Gestionar sitios', 'sites': 'Sitios', 'addSite': 'Agregar sitio',
      'editSite': 'Editar sitio', 'siteName': 'Nombre del sitio', 'siteAddress': 'DirecciÃ³n',
      'siteRadius': 'Radio de entrada (m)', 'gpsInterval': 'Intervalo GPS (min)',
      'allTime': 'Todo el perÃ­odo',
      'allSites': 'Todos los sitios',
      'allPeople': 'Todos los empleados',
      'exportPdf': 'Exportar PDF',
      'exportXlsx': 'Exportar Excel',
      'actPdf': 'Acta PDF',
      'nakladnayaPdf': 'AlbarÃ¡n PDF',
      'gpsTrack': 'Rastreo GPS',
      'noGpsData': 'Sin datos GPS',
      'shiftActive': 'Turno activo',
      'shiftStart': 'Inicio',
      'shiftEnd': 'Fin',
      'totalHours': 'Total horas',
      'shiftsCount': 'Turnos',
      'workReport': 'Informe',
      'myTimesheets': 'Mis turnos',
      'allTimesheets': 'Todos los turnos',
      'gpsPermissionDenied': 'GPS no disponible â turno iniciado sin verificaciÃ³n de ubicaciÃ³n',
      'gpsWarningTitle': 'Fuera de la zona del sitio',
      'gpsWarningText': 'Su ubicaciÃ³n no coincide con la direcciÃ³n del sitio.',
      'distance': 'Distancia',
      'startAnyway': 'Iniciar de todas formas',
      'shiftTypeHourly': 'Por horas',
      'shiftTypeAccord': 'Precio fijo',
      'chooseShiftType': 'Tipo de turno',
      'shiftType': 'Tipo de trabajo',
      'reportRequired': 'Completar el informe â quÃ© se hizo',
      'viewSites': 'Todos los sitios',
      'navigateTo': 'Navegar',
      'linkUser': 'Vincular usuario',
      'linkedUser': 'Vinculado a',
      'unlinkUser': 'Desvincular',
      'selectUserToLink': 'Seleccionar usuario',
      'notLinked': 'Cuenta no vinculada a un perfil. Contacte al administrador.',
      'personTypePerson': 'Persona',
      'personTypeObject': 'Objeto',
      'noObjects': 'AÃºn no hay objetos. Pulse +',
      'objectCompleted': 'Completado',
      'markObjectCompleted': 'Marcar como completado',
      'personTab': 'Personas',
      'objectTab': 'Objetos',
      'cannotCompleteHasTools': 'No se puede completar: {n} herramientas en el objeto',
      'cannotFireHasTools': 'No se puede despedir: el empleado tiene {n} herramientas',
      'addObject': 'Agregar objeto',
      'shiftReminder10hTitle': 'El turno dura 10 horas',
      'shiftReminder10hBody': 'El turno estÃ¡ activo mÃ¡s de 10 horas. No olvide cerrarlo.',
      'shiftReminder12hTitle': 'â ï¸ Â¡Turno 12 horas!',
      'shiftReminder12hBody': 'Advertencia: el turno lleva mÃ¡s de 12 horas. Cierre el turno.',
      'offlineBanner': 'Sin conexiÃ³n â¢ datos del cachÃ©',
      'alreadyHaveActiveShift': 'Ya tiene un turno activo. CiÃ©rrelo antes de iniciar uno nuevo.',
      'forceCloseShift': 'Forzar cierre',
      'forceCloseShiftHint': 'El turno se cerrarÃ¡ ahora. Puede agregar un informe.',
      'shiftClosed': 'Turno cerrado.',
      'archive': 'Archivo',
      'noArchive': 'El archivo estÃ¡ vacÃ­o',
      'notifications': 'Notificaciones',
      'noNotifications': 'No hay nuevas notificaciones',
      'newMemberRequest': 'Nueva solicitud de uniÃ³n',
      'markAllRead': 'Marcar todo como leÃ­do',
      'copyTool': 'Copiar',
      'toolCopied': 'Herramienta copiada',
      'sortNameAZ': 'Nombre A-Z',
      'sortCountDesc': 'Grupos grandes primero',
      'sortDateDesc': 'MÃ¡s recientes primero',
      'darkTheme': 'Tema oscuro',
      'lightTheme': 'Tema claro',
      'systemTheme': 'Tema del sistema',
      'printQr': 'Imprimir QR',
      'saveAsPng': 'Guardar PNG',
      'thermalLabel': 'Etiqueta tÃ©rmica',
      'printAllQr': 'Todos los QR en hoja',
      'noResults': 'Sin resultados',
    },

    AppLang.it: {
      'appTitle': 'ToolKeeper', 'login': 'Accesso', 'register': 'Registrazione', 'enter': 'Accedi',
      'logout': 'Esci', 'people': 'Persone', 'tools': 'Strumenti', 'tool': 'Strumento',
      'inv': 'NÂ° inv.', 'issue': 'Emissione', 'profile': 'Profilo', 'chooseLang': 'Scegli lingua',
      'companyNotFound': 'Azienda non trovata', 'noAccessCompany': 'Nessun accesso all azienda',
      'leaveCompany': 'Esci / scegli altra azienda', 'createCompany': 'Crea azienda',
      'joinCompany': 'Unisciti', 'or': 'O', 'companyName': 'Nome azienda',
      'role': 'Ruolo', 'role_owner': 'Proprietario', 'role_admin': 'Amministratore',
      'role_foreman': 'Caposquadra', 'role_employee': 'Dipendente',
      'save': 'Salva', 'cancel': 'Annulla', 'add': 'Aggiungi', 'delete': 'Elimina',
      'noEmployees': 'Nessun dipendente', 'noTools': 'Nessuno strumento',
      'issued': 'Emesso', 'returned': 'Restituito', 'history': 'Cronologia',
      'total': 'Totale', 'pcs': 'pz.', 'loading': 'Caricamento...', 'error': 'Errore', 'ok': 'OK',
      'issueUpper': 'EMETTERE', 'returnUpper': 'RESTITUIRE', 'noName': 'Senza nome',
      'confirmReturn': 'Restituire', 'confirmIssue': 'Emettere',
      'issueTab': 'Emissione', 'returnTab': 'Reso',
      'searchByNameOrPhone': 'Cerca per nome o telefono...',
      'birthDate': 'Data di nascita', 'clothesSize': 'Taglia abiti', 'company': 'Azienda',
      'continue': 'Continua', 'done': 'Fatto', 'firstName': 'Nome', 'lastName': 'Cognome',
      'password': 'Password', 'position': 'Posizione', 'reports': 'Rapporti', 'welcome': 'Benvenuto',
      'email': 'Email', 'employee': 'Dipendente', 'employees': 'Dipendenti',
      'owner': 'Proprietario', 'admin': 'Admin', 'worker': 'Dipendente',
      'employeeStatus': 'Stato dipendente', 'empStatusActive': 'Attivo', 'empStatusFired': 'Licenziato',
      'toolStatus': 'Stato strumento', 'toolStatusActive': 'Attivo', 'toolStatusRepair': 'In riparazione',
      'toolStatusDisposed': 'Dismesso', 'statusNote': 'Nota',
      'warehouse': 'Magazzino', 'where': 'Dove', 'issuedAt': 'Emesso il', 'noData': 'Nessun dato',
      'subscriptionTitle': 'Abbonamento', 'subscriptionActive': 'Attivo', 'subscriptionInactive': 'Inattivo',
      'buyRenew': 'Acquista / Rinnova', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Aggiungi prima persone', 'needToolsFirst': 'Aggiungi prima strumenti',
      'noFreeTool': 'Nessuno strumento libero', 'person': 'Persona', 'returnTool': 'Restituire',
      'versionLabel': 'Versione', 'lang': 'Lingua', 'selectPerson': 'Seleziona dipendente',
      'onHandsTotal': 'In mano: {n} pz.', 'toolsCountLabel': 'Strumenti: {n}', 'whoLabel': 'Chi: {name}',
      'noReturnTool': 'Nessuno strumento da restituire', 'noCompany': 'Nessuna azienda selezionata',
      'reportFilterHint': 'Filtro...', 'reportsPeople': 'Chi ha cosa (per persone)',
      'reportsTools': 'Dove Ã¨ lo strumento', 'searchByNameOrInv': 'Cerca per nome o nÂ°...',
      'saveProfile': 'Salva profilo', 'setRole': 'Imposta ruolo', 'shoeSize': 'Numero scarpe',
      'yourInviteCode': 'Il tuo codice invito', 'repeatPassword': 'Ripeti password',
      'haveAccount': 'Hai giÃ  un account?', 'historyEmpty': 'Ancora nessuna cronologia',
      'newPassword': 'Nuova password', 'noPeople': 'Ancora nessuna persona',
      'noneIssued': 'Niente emesso', 'noneIssued2': 'Nessuno strumento in mano',
      'onlyAdmin': 'Solo proprietario/admin', 'passwordsNotMatch': 'Le password non corrispondono',
      'profileForm': 'Modulo profilo', 'changePlan': 'Cambia piano',
      'planLabel': 'Piano', 'planSaved': 'Piano salvato', 'gpsNotInPlan': 'Tracciamento GPS disponibile dal piano Pro in su', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â', 'peopleLimitLabel': 'Limite persone',
      'perMonth': 'mese', 'planChangeOnlyOwner': 'Solo il proprietario puÃ² cambiare il piano.',
      'selectPlan': 'Scegli piano', 'supportTitle': 'Supporto',
      'supportDesc': 'Per domande contattaci:', 'tariffLimitsTitle': 'Tariffe e limiti',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Utilizzato (attivi)',
      'inactiveNotCountedNote': 'Licenziati/inattivi non contati nel limite.',
      'enterEmailPass': 'Inserisci email e password', 'google': 'Google',
      'linkPassword': 'Collega/imposta password', 'needProfile': 'Compila il profilo',
      'needReLogin': 'Accedi nuovamente', 'pendingText': 'Richiesta in attesa di approvazione',
      'pendingTitle': 'In attesa', 'sendReset': 'Invia link', 'sessionTitle': 'Sessione',
      'setPassword': 'Imposta password', 'toolNameHint': 'Nome (es. Smerigliatrice)',
      'editProfile': 'Modifica profilo', 'editMyProfile': 'Modifica il mio profilo',
      'editCompany': 'Modifica azienda', 'chooseRole': 'Scegli ruolo',
      'codeNotFound': 'Codice non trovato', 'copyCodeHint': 'Copia e invia al dipendente',
      'deleteCompany': 'Elimina azienda', 'inviteCode': 'Codice invito',
      'requests': 'Richieste', 'approve': 'Approva', 'addPerson': 'Aggiungi persona',
      'decline': 'Rifiuta', 'noIssued': 'Niente emesso',
      'selectToolFirst': 'Seleziona prima uno strumento',
      'selectPersonFirst': 'Seleziona prima un dipendente',
      'reportsByTool': 'Per strumento', 'reportsByPerson': 'Per dipendente',
      'markToolActive': 'Segna come attivo', 'markToolRepair': 'Invia in riparazione',
      'markToolDisposed': 'Dismetti', 'alreadyIn': 'GiÃ  in azienda',
      'archivedCompany': 'Azienda archiviata',
      'subscriptionStatusLabel': 'Stato', 'subscriptionValidUntilLabel': 'Valido fino al',
      'subscriptionTest': 'ModalitÃ  test', 'subscriptionLive': 'ModalitÃ  a pagamento',
      'buyRenewSoon': 'Pagamento presto disponibile. Contatta il supporto.',
      'billingModeLabel': 'ModalitÃ  pagamento', 'emailLabel': 'Email',
      'name': 'Nome', 'join': 'Unisciti', 'noRights': 'Nessun diritto',
      'returnTitle': 'Conferma reso', 'needAccount': 'Account necessario',
      'newCompanyName': 'Nuovo nome azienda', 'renameCompany': 'Rinomina azienda',
      'addTool': 'Aggiungi strumento', 'addEmployee': 'Aggiungi dipendente',
      'searchByToolOrLastName': 'Cerca per strumento o cognome...',
      'switchAcc': 'Cambia account',
      'myShift': 'Il mio turno', 'startShift': 'Inizia turno', 'endShift': 'Termina turno',
      'currentShift': 'Turno attuale', 'shiftStarted': 'Turno iniziato!', 'shiftEnded': 'Turno terminato!',
      'selectSite': 'Seleziona cantiere', 'noSites': 'Nessun cantiere. Contatta l\'amministratore.',
      'writeReport': 'Rapporto turno', 'whatDone': 'Cosa Ã¨ stato fatto', 'timesheets': 'Registro turni',
      'manageSites': 'Gestisci cantieri', 'sites': 'Cantieri', 'addSite': 'Aggiungi cantiere',
      'editSite': 'Modifica cantiere', 'siteName': 'Nome cantiere', 'siteAddress': 'Indirizzo',
      'siteRadius': 'Raggio check-in (m)', 'gpsInterval': 'Intervallo GPS (min)',
      'allTime': 'Tutto il periodo',
      'allSites': 'Tutti i cantieri',
      'allPeople': 'Tutti i dipendenti',
      'exportPdf': 'Esporta PDF',
      'exportXlsx': 'Esporta Excel',
      'actPdf': 'Atto PDF',
      'nakladnayaPdf': 'Bolla consegna PDF',
      'gpsTrack': 'Traccia GPS',
      'noGpsData': 'Nessun dato GPS',
      'shiftActive': 'Turno attivo',
      'shiftStart': 'Inizio',
      'shiftEnd': 'Fine',
      'totalHours': 'Ore totali',
      'shiftsCount': 'Turni',
      'workReport': 'Rapporto',
      'myTimesheets': 'I miei turni',
      'allTimesheets': 'Tutti i turni',
      'gpsPermissionDenied': 'GPS non disponibile â turno iniziato senza verifica posizione',
      'gpsWarningTitle': 'Fuori dalla zona del sito',
      'gpsWarningText': 'La tua posizione non corrisponde all\'indirizzo del sito.',
      'distance': 'Distanza',
      'startAnyway': 'Inizia comunque',
      'shiftTypeHourly': 'A ore',
      'shiftTypeAccord': 'Prezzo fisso',
      'chooseShiftType': 'Tipo di turno',
      'shiftType': 'Tipo di lavoro',
      'reportRequired': 'Compila il rapporto â cosa Ã¨ stato fatto',
      'viewSites': 'Tutti i siti',
      'navigateTo': 'Naviga',
      'linkUser': 'Collega utente',
      'linkedUser': 'Collegato a',
      'unlinkUser': 'Scollega',
      'selectUserToLink': 'Seleziona utente',
      'notLinked': 'Account non collegato a un profilo. Contattare l\'amministratore.',
      'personTypePerson': 'Persona',
      'personTypeObject': 'Oggetto',
      'noObjects': 'Nessun oggetto ancora. Premi +',
      'objectCompleted': 'Completato',
      'markObjectCompleted': 'Segna come completato',
      'personTab': 'Persone',
      'objectTab': 'Oggetti',
      'cannotCompleteHasTools': 'Impossibile completare: {n} strumenti sull\'oggetto',
      'cannotFireHasTools': 'Impossibile licenziare: il dipendente ha {n} strumenti',
      'addObject': 'Aggiungi oggetto',
      'shiftReminder10hTitle': 'Il turno dura 10 ore',
      'shiftReminder10hBody': 'Il turno Ã¨ attivo da oltre 10 ore. Non dimenticare di chiuderlo.',
      'shiftReminder12hTitle': 'â ï¸ Turno 12 ore!',
      'shiftReminder12hBody': 'Attenzione: il turno Ã¨ in corso da oltre 12 ore. Chiudi il turno.',
      'offlineBanner': 'Nessuna connessione â¢ dati dalla cache',
      'alreadyHaveActiveShift': 'Hai giÃ  un turno attivo. Chiudilo prima di iniziarne uno nuovo.',
      'forceCloseShift': 'Forza chiusura',
      'forceCloseShiftHint': 'Il turno verrÃ  chiuso ora. Puoi aggiungere un rapporto.',
      'shiftClosed': 'Turno chiuso.',
      'archive': 'Archivio',
      'noArchive': 'L\'archivio Ã¨ vuoto',
      'notifications': 'Notifiche',
      'noNotifications': 'Nessuna nuova notifica',
      'newMemberRequest': 'Nuova richiesta di adesione',
      'markAllRead': 'Segna tutto come letto',
      'copyTool': 'Copia',
      'toolCopied': 'Strumento copiato',
      'sortNameAZ': 'Nome A-Z',
      'sortCountDesc': 'Gruppi grandi prima',
      'sortDateDesc': 'PiÃ¹ recenti prima',
      'darkTheme': 'Tema scuro',
      'lightTheme': 'Tema chiaro',
      'systemTheme': 'Tema di sistema',
      'printQr': 'Stampa QR',
      'saveAsPng': 'Salva PNG',
      'thermalLabel': 'Etichetta termica',
      'printAllQr': 'Tutti i QR su foglio',
      'noResults': 'Nessun risultato',
    },

    AppLang.pt: {
      'appTitle': 'ToolKeeper', 'login': 'Entrar', 'register': 'Registrar', 'enter': 'Fazer login',
      'logout': 'Sair', 'people': 'Pessoas', 'tools': 'Ferramentas', 'tool': 'Ferramenta',
      'inv': 'NÂ° inv.', 'issue': 'EmissÃ£o', 'profile': 'Perfil', 'chooseLang': 'Escolher idioma',
      'companyNotFound': 'Empresa nÃ£o encontrada', 'noAccessCompany': 'Sem acesso Ã  empresa',
      'leaveCompany': 'Sair / escolher outra empresa', 'createCompany': 'Criar empresa',
      'joinCompany': 'Entrar', 'or': 'OU', 'companyName': 'Nome da empresa',
      'role': 'FunÃ§Ã£o', 'role_owner': 'ProprietÃ¡rio', 'role_admin': 'Administrador',
      'role_foreman': 'Mestre de obras', 'role_employee': 'FuncionÃ¡rio',
      'save': 'Salvar', 'cancel': 'Cancelar', 'add': 'Adicionar', 'delete': 'Excluir',
      'noEmployees': 'Sem funcionÃ¡rios', 'noTools': 'Sem ferramentas',
      'issued': 'Emitido', 'returned': 'Devolvido', 'history': 'HistÃ³rico',
      'total': 'Total', 'pcs': 'pcs.', 'loading': 'Carregando...', 'error': 'Erro', 'ok': 'OK',
      'issueUpper': 'EMITIR', 'returnUpper': 'DEVOLVER', 'noName': 'Sem nome',
      'confirmReturn': 'Devolver', 'confirmIssue': 'Emitir',
      'issueTab': 'EmissÃ£o', 'returnTab': 'DevoluÃ§Ã£o',
      'searchByNameOrPhone': 'Buscar por nome ou telefone...',
      'birthDate': 'Data de nascimento', 'clothesSize': 'Tamanho de roupa', 'company': 'Empresa',
      'continue': 'Continuar', 'done': 'Pronto', 'firstName': 'Nome', 'lastName': 'Sobrenome',
      'password': 'Senha', 'position': 'Cargo', 'reports': 'RelatÃ³rios', 'welcome': 'Bem-vindo',
      'email': 'E-mail', 'employee': 'FuncionÃ¡rio', 'employees': 'FuncionÃ¡rios',
      'owner': 'ProprietÃ¡rio', 'admin': 'Admin', 'worker': 'FuncionÃ¡rio',
      'employeeStatus': 'Status do funcionÃ¡rio', 'empStatusActive': 'Ativo', 'empStatusFired': 'Demitido',
      'toolStatus': 'Status da ferramenta', 'toolStatusActive': 'Ativo', 'toolStatusRepair': 'Em reparo',
      'toolStatusDisposed': 'Descartado', 'statusNote': 'Nota',
      'warehouse': 'ArmazÃ©m', 'where': 'Onde', 'issuedAt': 'Emitido em', 'noData': 'Sem dados',
      'subscriptionTitle': 'Assinatura', 'subscriptionActive': 'Ativa', 'subscriptionInactive': 'Inativa',
      'buyRenew': 'Comprar / Renovar', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Adicionar pessoas primeiro', 'needToolsFirst': 'Adicionar ferramentas primeiro',
      'noFreeTool': 'Sem ferramenta livre', 'person': 'Pessoa', 'returnTool': 'Devolver',
      'versionLabel': 'VersÃ£o', 'lang': 'Idioma', 'selectPerson': 'Selecionar funcionÃ¡rio',
      'onHandsTotal': 'Em mÃ£os: {n} pcs.', 'toolsCountLabel': 'Ferramentas: {n}', 'whoLabel': 'Quem: {name}',
      'noReturnTool': 'Sem ferramenta para devolver', 'noCompany': 'Sem empresa selecionada',
      'reportFilterHint': 'Filtro...', 'reportsPeople': 'Quem tem o quÃª (por pessoas)',
      'reportsTools': 'Onde estÃ¡ a ferramenta', 'searchByNameOrInv': 'Buscar por nome ou nÂ°...',
      'saveProfile': 'Salvar perfil', 'setRole': 'Definir funÃ§Ã£o', 'shoeSize': 'NÃºmero do sapato',
      'yourInviteCode': 'Seu cÃ³digo de convite', 'repeatPassword': 'Repetir senha',
      'haveAccount': 'JÃ¡ tem conta?', 'historyEmpty': 'Ainda sem histÃ³rico',
      'newPassword': 'Nova senha', 'noPeople': 'Ainda sem pessoas',
      'noneIssued': 'Nada emitido', 'noneIssued2': 'Sem ferramentas em mÃ£os',
      'onlyAdmin': 'Somente proprietÃ¡rio/admin', 'passwordsNotMatch': 'As senhas nÃ£o correspondem',
      'profileForm': 'FormulÃ¡rio de perfil', 'changePlan': 'Alterar plano',
      'planLabel': 'Plano', 'planSaved': 'Plano salvo', 'gpsNotInPlan': 'Rastreamento GPS disponÃ­vel a partir do plano Pro', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â', 'peopleLimitLabel': 'Limite de pessoas',
      'perMonth': 'mÃªs', 'planChangeOnlyOwner': 'Somente o proprietÃ¡rio pode alterar o plano.',
      'selectPlan': 'Escolher plano', 'supportTitle': 'Suporte',
      'supportDesc': 'Para dÃºvidas, entre em contato:', 'tariffLimitsTitle': 'Tarifa e limites',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Usado (ativos)',
      'inactiveNotCountedNote': 'Demitidos/inativos nÃ£o contam no limite.',
      'enterEmailPass': 'Digite e-mail e senha', 'google': 'Google',
      'linkPassword': 'Vincular/definir senha', 'needProfile': 'Complete o perfil',
      'needReLogin': 'FaÃ§a login novamente', 'pendingText': 'SolicitaÃ§Ã£o aguarda aprovaÃ§Ã£o',
      'pendingTitle': 'Pendente', 'sendReset': 'Enviar link', 'sessionTitle': 'SessÃ£o',
      'setPassword': 'Definir senha', 'toolNameHint': 'Nome (ex. Esmerilhadeira)',
      'editProfile': 'Editar perfil', 'editMyProfile': 'Editar meu perfil',
      'editCompany': 'Editar empresa', 'chooseRole': 'Escolher funÃ§Ã£o',
      'codeNotFound': 'CÃ³digo nÃ£o encontrado', 'copyCodeHint': 'Copiar e enviar ao funcionÃ¡rio',
      'deleteCompany': 'Excluir empresa', 'inviteCode': 'CÃ³digo de convite',
      'requests': 'SolicitaÃ§Ãµes', 'approve': 'Aprovar', 'addPerson': 'Adicionar pessoa',
      'decline': 'Recusar', 'noIssued': 'Nada emitido',
      'selectToolFirst': 'Primeiro selecione ferramenta',
      'selectPersonFirst': 'Primeiro selecione funcionÃ¡rio',
      'reportsByTool': 'Por ferramenta', 'reportsByPerson': 'Por funcionÃ¡rio',
      'markToolActive': 'Marcar como ativo', 'markToolRepair': 'Enviar para reparo',
      'markToolDisposed': 'Descartar', 'alreadyIn': 'JÃ¡ na empresa',
      'archivedCompany': 'Empresa arquivada',
      'subscriptionStatusLabel': 'Status', 'subscriptionValidUntilLabel': 'VÃ¡lida atÃ©',
      'subscriptionTest': 'Modo teste', 'subscriptionLive': 'Modo pago',
      'buyRenewSoon': 'Pagamento em breve. Contate o suporte.',
      'billingModeLabel': 'Modo de pagamento', 'emailLabel': 'E-mail',
      'name': 'Nome', 'join': 'Entrar', 'noRights': 'Sem direitos',
      'returnTitle': 'Confirmar devoluÃ§Ã£o', 'needAccount': 'Conta necessÃ¡ria',
      'newCompanyName': 'Novo nome da empresa', 'renameCompany': 'Renomear empresa',
      'addTool': 'Adicionar ferramenta', 'addEmployee': 'Adicionar funcionÃ¡rio',
      'searchByToolOrLastName': 'Buscar por ferramenta ou sobrenome...',
      'switchAcc': 'Trocar conta',
      'myShift': 'Meu turno', 'startShift': 'Iniciar turno', 'endShift': 'Encerrar turno',
      'currentShift': 'Turno atual', 'shiftStarted': 'Turno iniciado!', 'shiftEnded': 'Turno encerrado!',
      'selectSite': 'Selecionar obra', 'noSites': 'Sem obras. Contate o administrador.',
      'writeReport': 'RelatÃ³rio do turno', 'whatDone': 'O que foi feito', 'timesheets': 'Registro de turnos',
      'manageSites': 'Gerenciar obras', 'sites': 'Obras', 'addSite': 'Adicionar obra',
      'editSite': 'Editar obra', 'siteName': 'Nome da obra', 'siteAddress': 'EndereÃ§o',
      'siteRadius': 'Raio de check-in (m)', 'gpsInterval': 'Intervalo GPS (min)',
      'allTime': 'Todo o perÃ­odo',
      'allSites': 'Todas as obras',
      'allPeople': 'Todos os funcionÃ¡rios',
      'exportPdf': 'Exportar PDF',
      'exportXlsx': 'Exportar Excel',
      'actPdf': 'Ato PDF',
      'nakladnayaPdf': 'Guia de entrega PDF',
      'gpsTrack': 'Rastreio GPS',
      'noGpsData': 'Sem dados GPS',
      'shiftActive': 'Turno ativo',
      'shiftStart': 'InÃ­cio',
      'shiftEnd': 'Fim',
      'totalHours': 'Total de horas',
      'shiftsCount': 'Turnos',
      'workReport': 'RelatÃ³rio',
      'myTimesheets': 'Meus turnos',
      'allTimesheets': 'Todos os turnos',
      'gpsPermissionDenied': 'GPS indisponÃ­vel â turno iniciado sem verificaÃ§Ã£o de localizaÃ§Ã£o',
      'gpsWarningTitle': 'Fora da zona do local',
      'gpsWarningText': 'Sua localizaÃ§Ã£o nÃ£o corresponde ao endereÃ§o do local.',
      'distance': 'DistÃ¢ncia',
      'startAnyway': 'Iniciar mesmo assim',
      'shiftTypeHourly': 'Por hora',
      'shiftTypeAccord': 'PreÃ§o fixo',
      'chooseShiftType': 'Tipo de turno',
      'shiftType': 'Tipo de trabalho',
      'reportRequired': 'Preencha o relatÃ³rio â o que foi feito',
      'viewSites': 'Todos os locais',
      'navigateTo': 'Navegar',
      'linkUser': 'Vincular usuÃ¡rio',
      'linkedUser': 'Vinculado a',
      'unlinkUser': 'Desvincular',
      'selectUserToLink': 'Selecionar usuÃ¡rio',
      'notLinked': 'Conta nÃ£o vinculada a um perfil. Contate o administrador.',
      'personTypePerson': 'Pessoa',
      'personTypeObject': 'Objeto',
      'noObjects': 'Ainda sem objetos. Toque em +',
      'objectCompleted': 'ConcluÃ­do',
      'markObjectCompleted': 'Marcar como concluÃ­do',
      'personTab': 'Pessoas',
      'objectTab': 'Objetos',
      'cannotCompleteHasTools': 'NÃ£o Ã© possÃ­vel concluir: {n} ferramentas no objeto',
      'cannotFireHasTools': 'NÃ£o Ã© possÃ­vel demitir: funcionÃ¡rio tem {n} ferramentas',
      'addObject': 'Adicionar objeto',
      'shiftReminder10hTitle': 'O turno dura 10 horas',
      'shiftReminder10hBody': 'O turno estÃ¡ ativo hÃ¡ mais de 10 horas. NÃ£o se esqueÃ§a de fechÃ¡-lo.',
      'shiftReminder12hTitle': 'â ï¸ Turno 12 horas!',
      'shiftReminder12hBody': 'AtenÃ§Ã£o: o turno estÃ¡ em andamento hÃ¡ mais de 12 horas. Feche o turno.',
      'offlineBanner': 'Sem conexÃ£o â¢ dados do cache',
      'alreadyHaveActiveShift': 'VocÃª jÃ¡ tem um turno ativo. Feche-o antes de iniciar um novo.',
      'forceCloseShift': 'ForÃ§ar fechamento',
      'forceCloseShiftHint': 'O turno serÃ¡ fechado agora. VocÃª pode adicionar um relatÃ³rio.',
      'shiftClosed': 'Turno encerrado.',
      'archive': 'Arquivo',
      'noArchive': 'O arquivo estÃ¡ vazio',
      'notifications': 'NotificaÃ§Ãµes',
      'noNotifications': 'Sem novas notificaÃ§Ãµes',
      'newMemberRequest': 'Nova solicitaÃ§Ã£o de adesÃ£o',
      'markAllRead': 'Marcar tudo como lido',
      'copyTool': 'Copiar',
      'toolCopied': 'Ferramenta copiada',
      'sortNameAZ': 'Nome A-Z',
      'sortCountDesc': 'Grupos grandes primeiro',
      'sortDateDesc': 'Mais recentes primeiro',
      'darkTheme': 'Tema escuro',
      'lightTheme': 'Tema claro',
      'systemTheme': 'Tema do sistema',
      'printQr': 'Imprimir QR',
      'saveAsPng': 'Guardar PNG',
      'thermalLabel': 'Etiqueta tÃ©rmica',
      'printAllQr': 'Todos os QR na folha',
      'noResults': 'Sem resultados',
    },

    AppLang.cs: {
      'appTitle': 'ToolKeeper', 'login': 'PÅihlÃ¡Å¡enÃ­', 'register': 'Registrace', 'enter': 'PÅihlÃ¡sit se',
      'logout': 'OdhlÃ¡sit', 'people': 'LidÃ©', 'tools': 'NÃ¡stroje', 'tool': 'NÃ¡stroj',
      'inv': 'Inv. Ä.', 'issue': 'VÃ½dej', 'profile': 'Profil', 'chooseLang': 'Vyberte jazyk',
      'companyNotFound': 'Firma nenalezena', 'noAccessCompany': 'Å½Ã¡dnÃ½ pÅÃ­stup k firmÄ',
      'leaveCompany': 'Opustit / vybrat jinou firmu', 'createCompany': 'VytvoÅit firmu',
      'joinCompany': 'PÅipojit se', 'or': 'NEBO', 'companyName': 'NÃ¡zev firmy',
      'role': 'Role', 'role_owner': 'Majitel', 'role_admin': 'AdministrÃ¡tor',
      'role_foreman': 'VedoucÃ­', 'role_employee': 'ZamÄstnanec',
      'save': 'UloÅ¾it', 'cancel': 'ZruÅ¡it', 'add': 'PÅidat', 'delete': 'Smazat',
      'noEmployees': 'Å½Ã¡dnÃ­ zamÄstnanci', 'noTools': 'Å½Ã¡dnÃ© nÃ¡stroje',
      'issued': 'VydÃ¡no', 'returned': 'VrÃ¡ceno', 'history': 'Historie',
      'total': 'Celkem', 'pcs': 'ks.', 'loading': 'NaÄÃ­tÃ¡nÃ­...', 'error': 'Chyba', 'ok': 'OK',
      'issueUpper': 'VYDAT', 'returnUpper': 'VRÃTIT', 'noName': 'Bez jmÃ©na',
      'confirmReturn': 'VrÃ¡tit', 'confirmIssue': 'Vydat',
      'issueTab': 'VÃ½dej', 'returnTab': 'VrÃ¡cenÃ­',
      'searchByNameOrPhone': 'Hledat podle jmÃ©na nebo telefonu...',
      'birthDate': 'Datum narozenÃ­', 'clothesSize': 'Velikost obleÄenÃ­', 'company': 'Firma',
      'continue': 'PokraÄovat', 'done': 'Hotovo', 'firstName': 'JmÃ©no', 'lastName': 'PÅÃ­jmenÃ­',
      'password': 'Heslo', 'position': 'Pozice', 'reports': 'ZprÃ¡vy', 'welcome': 'VÃ­tejte',
      'email': 'E-mail', 'employee': 'ZamÄstnanec', 'employees': 'ZamÄstnanci',
      'owner': 'Majitel', 'admin': 'Admin', 'worker': 'ZamÄstnanec',
      'employeeStatus': 'Stav zamÄstnance', 'empStatusActive': 'AktivnÃ­', 'empStatusFired': 'PropuÅ¡tÄn',
      'toolStatus': 'Stav nÃ¡stroje', 'toolStatusActive': 'AktivnÃ­', 'toolStatusRepair': 'V opravÄ',
      'toolStatusDisposed': 'VyÅazen', 'statusNote': 'PoznÃ¡mka',
      'warehouse': 'Sklad', 'where': 'Kde', 'issuedAt': 'VydÃ¡no', 'noData': 'Å½Ã¡dnÃ¡ data',
      'subscriptionTitle': 'PÅedplatnÃ©', 'subscriptionActive': 'AktivnÃ­', 'subscriptionInactive': 'NeaktivnÃ­',
      'buyRenew': 'Koupit / ProdlouÅ¾it', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Nejprve pÅidejte lidi', 'needToolsFirst': 'Nejprve pÅidejte nÃ¡stroje',
      'noFreeTool': 'Å½Ã¡dnÃ½ volnÃ½ nÃ¡stroj', 'person': 'Osoba', 'returnTool': 'VrÃ¡tit',
      'versionLabel': 'Verze', 'lang': 'Jazyk', 'selectPerson': 'Vyberte zamÄstnance',
      'onHandsTotal': 'V rukou: {n} ks.', 'toolsCountLabel': 'NÃ¡strojÅ¯: {n}', 'whoLabel': 'U koho: {name}',
      'noReturnTool': 'Å½Ã¡dnÃ½ nÃ¡stroj k vrÃ¡cenÃ­', 'noCompany': 'Å½Ã¡dnÃ¡ firma vybrÃ¡na',
      'reportFilterHint': 'Filtr...', 'reportsPeople': 'Kdo mÃ¡ co (podle osob)',
      'reportsTools': 'Kde je nÃ¡stroj', 'searchByNameOrInv': 'Hledat podle nÃ¡zvu nebo Ä...',
      'saveProfile': 'UloÅ¾it profil', 'setRole': 'Nastavit roli', 'shoeSize': 'Velikost bot',
      'yourInviteCode': 'VÃ¡Å¡ pozvÃ¡nkovÃ½ kÃ³d', 'repeatPassword': 'Opakovat heslo',
      'haveAccount': 'JiÅ¾ mÃ¡te ÃºÄet?', 'historyEmpty': 'ZatÃ­m Å¾Ã¡dnÃ¡ historie',
      'newPassword': 'NovÃ© heslo', 'noPeople': 'ZatÃ­m Å¾Ã¡dnÃ­ lidÃ©', 'noneIssued': 'Nic nevydÃ¡no',
      'noneIssued2': 'Å½Ã¡dnÃ© nÃ¡stroje v rukou', 'onlyAdmin': 'Pouze majitel/admin',
      'passwordsNotMatch': 'Hesla se neshodujÃ­', 'profileForm': 'FormulÃ¡Å profilu',
      'changePlan': 'ZmÄnit plÃ¡n', 'planLabel': 'PlÃ¡n', 'planSaved': 'PlÃ¡n uloÅ¾en', 'gpsNotInPlan': 'GPS sledovÃ¡nÃ­ dostupnÃ© od plÃ¡nu Pro a vÃ½Å¡e', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Limit osob', 'perMonth': 'mÄs.',
      'planChangeOnlyOwner': 'Pouze majitel mÅ¯Å¾e zmÄnit plÃ¡n.',
      'selectPlan': 'Vybrat plÃ¡n', 'supportTitle': 'Podpora',
      'supportDesc': 'S dotazy nÃ¡s kontaktujte:', 'tariffLimitsTitle': 'Tarif a limity',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'PouÅ¾ito (aktivnÃ­)',
      'inactiveNotCountedNote': 'PropuÅ¡tÄnÃ­/neaktivnÃ­ se nepoÄÃ­tajÃ­ do limitu.',
      'enterEmailPass': 'Zadejte e-mail a heslo', 'google': 'Google',
      'needProfile': 'VyplÅte prosÃ­m profil', 'needReLogin': 'PÅihlaste se znovu',
      'pendingText': 'VaÅ¡e Å¾Ã¡dost ÄekÃ¡ na schvÃ¡lenÃ­', 'pendingTitle': 'ÄekÃ¡',
      'sendReset': 'Odeslat odkaz', 'sessionTitle': 'Relace', 'setPassword': 'Nastavit heslo',
      'toolNameHint': 'NÃ¡zev (napÅ. Bruska)', 'editProfile': 'Upravit profil',
      'editMyProfile': 'Upravit mÅ¯j profil', 'editCompany': 'Upravit firmu',
      'chooseRole': 'Vybrat roli', 'codeNotFound': 'KÃ³d nenalezen',
      'copyCodeHint': 'ZkopÃ­rujte a poÅ¡lete zamÄstnanci', 'deleteCompany': 'Smazat firmu',
      'inviteCode': 'PozvÃ¡nkovÃ½ kÃ³d', 'requests': 'Å½Ã¡dosti', 'approve': 'SchvÃ¡lit',
      'addPerson': 'PÅidat osobu', 'decline': 'OdmÃ­tnout', 'noIssued': 'Nic nevydÃ¡no',
      'selectToolFirst': 'Nejprve vyberte nÃ¡stroj', 'selectPersonFirst': 'Nejprve vyberte zamÄstnance',
      'reportsByTool': 'Podle nÃ¡stroje', 'reportsByPerson': 'Podle zamÄstnance',
      'markToolActive': 'OznaÄit jako aktivnÃ­', 'markToolRepair': 'Odeslat k opravÄ',
      'markToolDisposed': 'VyÅadit', 'alreadyIn': 'JiÅ¾ ve firmÄ', 'archivedCompany': 'Firma archivovÃ¡na',
      'subscriptionStatusLabel': 'Stav', 'subscriptionValidUntilLabel': 'PlatÃ­ do',
      'subscriptionTest': 'TestovacÃ­ reÅ¾im', 'subscriptionLive': 'PlacenÃ½ reÅ¾im',
      'buyRenewSoon': 'Platba brzy dostupnÃ¡. Kontaktujte podporu.',
      'billingModeLabel': 'PlatebnÃ­ reÅ¾im', 'emailLabel': 'E-mail',
      'name': 'NÃ¡zev', 'join': 'PÅipojit se', 'noRights': 'Å½Ã¡dnÃ¡ prÃ¡va',
      'returnTitle': 'Potvrdit vrÃ¡cenÃ­', 'needAccount': 'PotÅebujete ÃºÄet',
      'newCompanyName': 'NovÃ½ nÃ¡zev firmy', 'renameCompany': 'PÅejmenovat firmu',
      'addTool': 'PÅidat nÃ¡stroj', 'addEmployee': 'PÅidat zamÄstnance',
      'searchByToolOrLastName': 'Hledat podle nÃ¡stroje nebo pÅÃ­jmenÃ­...',
      'linkPassword': 'Propojit/nastavit heslo', 'switchAcc': 'ZmÄnit ÃºÄet',
      'myShift': 'Moje smÄna', 'startShift': 'ZaÄÃ­t smÄnu', 'endShift': 'UkonÄit smÄnu',
      'currentShift': 'AktuÃ¡lnÃ­ smÄna', 'shiftStarted': 'SmÄna zahÃ¡jena!', 'shiftEnded': 'SmÄna ukonÄena!',
      'selectSite': 'Vybrat pracoviÅ¡tÄ', 'noSites': 'Å½Ã¡dnÃ¡ pracoviÅ¡tÄ. Kontaktujte sprÃ¡vce.',
      'writeReport': 'ZprÃ¡va ze smÄny', 'whatDone': 'Co bylo udÄlÃ¡no', 'timesheets': 'DochÃ¡zka',
      'manageSites': 'SprÃ¡va pracoviÅ¡Å¥', 'sites': 'PracoviÅ¡tÄ', 'addSite': 'PÅidat pracoviÅ¡tÄ',
      'editSite': 'Upravit pracoviÅ¡tÄ', 'siteName': 'NÃ¡zev pracoviÅ¡tÄ', 'siteAddress': 'Adresa',
      'siteRadius': 'RÃ¡dius check-in (m)', 'gpsInterval': 'Interval GPS (min)',
      'allTime': 'CelÃ© obdobÃ­',
      'allSites': 'VÅ¡echna pracoviÅ¡tÄ',
      'allPeople': 'VÅ¡ichni zamÄstnanci',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'DodacÃ­ list PDF',
      'gpsTrack': 'GPS trasa',
      'noGpsData': 'Å½Ã¡dnÃ¡ GPS data',
      'shiftActive': 'SmÄna aktivnÃ­',
      'shiftStart': 'ZaÄÃ¡tek',
      'shiftEnd': 'Konec',
      'totalHours': 'Celkem hodin',
      'shiftsCount': 'SmÄny',
      'workReport': 'ZprÃ¡va',
      'myTimesheets': 'Moje smÄny',
      'allTimesheets': 'VÅ¡echny smÄny',
      'gpsPermissionDenied': 'GPS nedostupnÃ© â smÄna zahÃ¡jena bez ovÄÅenÃ­ polohy',
      'gpsWarningTitle': 'Mimo zÃ³nu pracoviÅ¡tÄ',
      'gpsWarningText': 'VaÅ¡e poloha neodpovÃ­dÃ¡ adrese pracoviÅ¡tÄ.',
      'distance': 'VzdÃ¡lenost',
      'startAnyway': 'PÅesto zahÃ¡jit',
      'shiftTypeHourly': 'HodinovÃ¡',
      'shiftTypeAccord': 'PevnÃ¡ cena',
      'chooseShiftType': 'Typ smÄny',
      'shiftType': 'Typ prÃ¡ce',
      'reportRequired': 'VyplÅte zprÃ¡vu â co bylo udÄlÃ¡no',
      'viewSites': 'VÅ¡echna pracoviÅ¡tÄ',
      'navigateTo': 'Navigace',
      'linkUser': 'Propojit uÅ¾ivatele',
      'linkedUser': 'Propojeno s',
      'unlinkUser': 'Odpojit',
      'selectUserToLink': 'Vybrat uÅ¾ivatele',
      'notLinked': 'ÃÄet nenÃ­ propojen s profilem. Kontaktujte sprÃ¡vce.',
      'personTypePerson': 'Osoba',
      'personTypeObject': 'Objekt',
      'noObjects': 'ZatÃ­m Å¾Ã¡dnÃ© objekty. StisknÄte +',
      'objectCompleted': 'DokonÄeno',
      'markObjectCompleted': 'OznaÄit jako dokonÄenÃ©',
      'personTab': 'Osoby',
      'objectTab': 'Objekty',
      'cannotCompleteHasTools': 'Nelze dokonÄit: {n} nÃ¡strojÅ¯ na objektu',
      'cannotFireHasTools': 'Nelze propustit: zamÄstnanec mÃ¡ {n} nÃ¡strojÅ¯',
      'addObject': 'PÅidat objekt',
      'shiftReminder10hTitle': 'SmÄna trvÃ¡ 10 hodin',
      'shiftReminder10hBody': 'SmÄna je aktivnÃ­ dÃ©le neÅ¾ 10 hodin. NezapomeÅte ji uzavÅÃ­t.',
      'shiftReminder12hTitle': 'â ï¸ SmÄna 12 hodin!',
      'shiftReminder12hBody': 'VarovÃ¡nÃ­: smÄna probÃ­hÃ¡ dÃ©le neÅ¾ 12 hodin. UzavÅete smÄnu.',
      'offlineBanner': 'Bez pÅipojenÃ­ â¢ data z mezipamÄti',
      'alreadyHaveActiveShift': 'JiÅ¾ mÃ¡te aktivnÃ­ smÄnu. UzavÅete ji pÅed zahÃ¡jenÃ­m novÃ©.',
      'forceCloseShift': 'Vynutit uzavÅenÃ­',
      'forceCloseShiftHint': 'SmÄna bude nynÃ­ uzavÅena. MÅ¯Å¾ete pÅidat zprÃ¡vu.',
      'shiftClosed': 'SmÄna uzavÅena.',
      'archive': 'Archiv',
      'noArchive': 'Archiv je prÃ¡zdnÃ½',
      'notifications': 'OznÃ¡menÃ­',
      'noNotifications': 'Å½Ã¡dnÃ¡ novÃ¡ oznÃ¡menÃ­',
      'newMemberRequest': 'NovÃ¡ Å¾Ã¡dost o pÅijetÃ­',
      'markAllRead': 'OznaÄit vÅ¡e jako pÅeÄtenÃ©',
      'copyTool': 'KopÃ­rovat',
      'toolCopied': 'NÃ¡stroj zkopÃ­rovÃ¡n',
      'sortNameAZ': 'NÃ¡zev A-Z',
      'sortCountDesc': 'VelkÃ© skupiny napÅed',
      'sortDateDesc': 'NejnovÄjÅ¡Ã­ napÅed',
      'darkTheme': 'TmavÃ½ motiv',
      'lightTheme': 'SvÄtlÃ½ motiv',
      'systemTheme': 'SystÃ©movÃ½ motiv',
      'printQr': 'Tisknout QR',
      'saveAsPng': 'UloÅ¾it PNG',
      'thermalLabel': 'TepelnÃ½ Å¡tÃ­tek',
      'printAllQr': 'VÅ¡echny QR na list',
      'noResults': 'Nic nenalezeno',
    },

    AppLang.ro: {
      'appTitle': 'ToolKeeper', 'login': 'Autentificare', 'register': 'Ãnregistrare', 'enter': 'Conectare',
      'logout': 'Deconectare', 'people': 'Oameni', 'tools': 'Scule', 'tool': 'SculÄ',
      'inv': 'Nr. inv.', 'issue': 'Eliberare', 'profile': 'Profil', 'chooseLang': 'AlegeÈi limba',
      'companyNotFound': 'Companie negÄsitÄ', 'noAccessCompany': 'FÄrÄ acces la companie',
      'leaveCompany': 'IeÈi / alege altÄ companie', 'createCompany': 'Creare companie',
      'joinCompany': 'AlÄturare', 'or': 'SAU', 'companyName': 'Numele companiei',
      'role': 'Rol', 'role_owner': 'Proprietar', 'role_admin': 'Administrator',
      'role_foreman': 'Èef de echipÄ', 'role_employee': 'Angajat',
      'save': 'Salvare', 'cancel': 'Anulare', 'add': 'AdÄugare', 'delete': 'Ètergere',
      'noEmployees': 'Niciun angajat', 'noTools': 'Nicio sculÄ',
      'issued': 'Eliberat', 'returned': 'Returnat', 'history': 'Istoric',
      'total': 'Total', 'pcs': 'buc.', 'loading': 'Se Ã®ncarcÄ...', 'error': 'Eroare', 'ok': 'OK',
      'issueUpper': 'ELIBEREAZÄ', 'returnUpper': 'RETURNEAZÄ', 'noName': 'FÄrÄ nume',
      'confirmReturn': 'ReturneazÄ', 'confirmIssue': 'ElibereazÄ',
      'issueTab': 'Eliberare', 'returnTab': 'Returnare',
      'searchByNameOrPhone': 'CautÄ dupÄ nume sau telefon...',
      'birthDate': 'Data naÈterii', 'clothesSize': 'MÄrime Ã®mbrÄcÄminte', 'company': 'Companie',
      'continue': 'Continuare', 'done': 'Gata', 'firstName': 'Prenume', 'lastName': 'Nume',
      'password': 'ParolÄ', 'position': 'PoziÈie', 'reports': 'Rapoarte', 'welcome': 'Bun venit',
      'email': 'E-mail', 'employee': 'Angajat', 'employees': 'AngajaÈi',
      'owner': 'Proprietar', 'admin': 'Admin', 'worker': 'Angajat',
      'employeeStatus': 'Stare angajat', 'empStatusActive': 'Activ', 'empStatusFired': 'Concediat',
      'toolStatus': 'Stare sculÄ', 'toolStatusActive': 'ActivÄ', 'toolStatusRepair': 'Ãn reparaÈie',
      'toolStatusDisposed': 'CasatÄ', 'statusNote': 'NotÄ',
      'warehouse': 'Depozit', 'where': 'Unde', 'issuedAt': 'Eliberat', 'noData': 'FÄrÄ date',
      'subscriptionTitle': 'Abonament', 'subscriptionActive': 'Activ', 'subscriptionInactive': 'Inactiv',
      'buyRenew': 'CumpÄrare / Prelungire', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'AdÄugaÈi mai Ã®ntÃ¢i persoane', 'needToolsFirst': 'AdÄugaÈi mai Ã®ntÃ¢i scule',
      'noFreeTool': 'Nicio sculÄ liberÄ', 'person': 'PersoanÄ', 'returnTool': 'Returnare',
      'versionLabel': 'Versiune', 'lang': 'LimbÄ', 'selectPerson': 'SelectaÈi angajatul',
      'onHandsTotal': 'Ãn mÃ¢nÄ: {n} buc.', 'toolsCountLabel': 'Scule: {n}', 'whoLabel': 'La cine: {name}',
      'noReturnTool': 'Nicio sculÄ de returnat', 'noCompany': 'Nicio companie selectatÄ',
      'reportFilterHint': 'Filtre...', 'reportsPeople': 'Cine are ce (pe persoane)',
      'reportsTools': 'Unde e scula', 'searchByNameOrInv': 'CautÄ dupÄ nume sau nr...',
      'needAccount': 'Cont necesar', 'newPassword': 'ParolÄ nouÄ', 'noPeople': 'Nicio persoanÄ Ã®ncÄ',
      'onlyAdmin': 'Doar proprietar/admin', 'passwordsNotMatch': 'Parolele nu corespund',
      'changePlan': 'SchimbÄ planul', 'planLabel': 'Plan', 'planSaved': 'Plan salvat', 'gpsNotInPlan': 'UrmÄrire GPS disponibilÄ de la planul Pro', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'LimitÄ persoane', 'perMonth': 'lunÄ',
      'planChangeOnlyOwner': 'Doar proprietarul poate schimba planul.',
      'selectPlan': 'AlegeÈi planul', 'supportTitle': 'Suport',
      'supportDesc': 'Pentru Ã®ntrebÄri contactaÈi-ne:', 'tariffLimitsTitle': 'Tarif Èi limite',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Utilizat (activi)',
      'inactiveNotCountedNote': 'ConcediaÈii/inactivi nu sunt numÄraÈi Ã®n limitÄ.',
      'google': 'Google', 'enterEmailPass': 'IntroduceÈi e-mail Èi parolÄ',
      'addTool': 'AdÄugare sculÄ', 'addEmployee': 'AdÄugare angajat',
      'inviteCode': 'Cod de invitaÈie', 'requests': 'SolicitÄri', 'approve': 'AprobaÈi',
      'addPerson': 'AdÄugare persoanÄ', 'decline': 'RespingeÈi',
      'selectToolFirst': 'SelectaÈi mai Ã®ntÃ¢i scula', 'selectPersonFirst': 'SelectaÈi mai Ã®ntÃ¢i angajatul',
      'reportsByTool': 'Pe sculÄ', 'reportsByPerson': 'Pe angajat',
      'alreadyIn': 'Deja Ã®n companie', 'archivedCompany': 'Companie arhivatÄ',
      'subscriptionStatusLabel': 'Stare', 'subscriptionValidUntilLabel': 'Valabil pÃ¢nÄ la',
      'subscriptionTest': 'Mod test', 'subscriptionLive': 'Mod plÄtit',
      'buyRenewSoon': 'Plata Ã®n curÃ¢nd disponibilÄ. ContactaÈi suportul.',
      'billingModeLabel': 'Mod platÄ', 'emailLabel': 'E-mail',
      'returnTitle': 'ConfirmaÈi returnarea',
      'myShift': 'Tura mea', 'startShift': 'Ãncepe tura', 'endShift': 'TerminÄ tura',
      'currentShift': 'Tura curentÄ', 'shiftStarted': 'Tura a Ã®nceput!', 'shiftEnded': 'Tura s-a terminat!',
      'selectSite': 'SelectaÈi Èantierul', 'noSites': 'FÄrÄ Èantiere. ContactaÈi administratorul.',
      'writeReport': 'Raport turÄ', 'whatDone': 'Ce s-a fÄcut', 'timesheets': 'CondicÄ ture',
      'manageSites': 'Gestionare Èantiere', 'sites': 'Èantiere', 'addSite': 'AdÄugaÈi Èantier',
      'editSite': 'EditaÈi Èantierul', 'siteName': 'Nume Èantier', 'siteAddress': 'AdresÄ',
      'siteRadius': 'Raza check-in (m)', 'gpsInterval': 'Interval GPS (min)',
      'allTime': 'ToatÄ perioada',
      'allSites': 'Toate Èantierele',
      'allPeople': 'ToÈi angajaÈii',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Act PDF',
      'nakladnayaPdf': 'Aviz PDF',
      'gpsTrack': 'Traseu GPS',
      'noGpsData': 'FÄrÄ date GPS',
      'shiftActive': 'TurÄ activÄ',
      'shiftStart': 'Ãnceput',
      'shiftEnd': 'SfÃ¢rÈit',
      'totalHours': 'Total ore',
      'shiftsCount': 'Ture',
      'workReport': 'Raport',
      'myTimesheets': 'Turele mele',
      'allTimesheets': 'Toate turele',
      'gpsPermissionDenied': 'GPS indisponibil â turÄ pornitÄ fÄrÄ verificarea locaÈiei',
      'gpsWarningTitle': 'Ãn afara zonei Èantierului',
      'gpsWarningText': 'LocaÈia dvs. nu corespunde adresei Èantierului.',
      'distance': 'DistanÈÄ',
      'startAnyway': 'PorneÈte oricum',
      'shiftTypeHourly': 'Orar',
      'shiftTypeAccord': 'PreÈ fix',
      'chooseShiftType': 'Tip turÄ',
      'shiftType': 'Tip muncÄ',
      'reportRequired': 'CompletaÈi raportul â ce s-a fÄcut',
      'viewSites': 'Toate Èantierele',
      'navigateTo': 'Navigare',
      'linkUser': 'ConectaÈi utilizatorul',
      'linkedUser': 'Conectat la',
      'unlinkUser': 'DeconectaÈi',
      'selectUserToLink': 'SelectaÈi utilizatorul',
      'notLinked': 'Contul nu este conectat la un profil. ContactaÈi administratorul.',
      'personTypePerson': 'PersoanÄ',
      'personTypeObject': 'Obiect',
      'noObjects': 'Niciun obiect Ã®ncÄ. ApÄsaÈi +',
      'objectCompleted': 'Finalizat',
      'markObjectCompleted': 'MarcaÈi ca finalizat',
      'personTab': 'Persoane',
      'objectTab': 'Obiecte',
      'cannotCompleteHasTools': 'Nu se poate finaliza: {n} unelte pe obiect',
      'cannotFireHasTools': 'Nu se poate concedia: angajatul are {n} unelte',
      'addObject': 'AdÄugaÈi obiect',
      'shiftReminder10hTitle': 'Tura dureazÄ 10 ore',
      'shiftReminder10hBody': 'Tura este activÄ de peste 10 ore. Nu uitaÈi sÄ o Ã®nchideÈi.',
      'shiftReminder12hTitle': 'â ï¸ TurÄ 12 ore!',
      'shiftReminder12hBody': 'AtenÈie: tura este Ã®n desfÄÈurare de peste 12 ore. ÃnchideÈi tura.',
      'offlineBanner': 'FÄrÄ conexiune â¢ date din cache',
      'alreadyHaveActiveShift': 'AveÈi deja o turÄ activÄ. ÃnchideÈi-o Ã®nainte de a Ã®ncepe una nouÄ.',
      'forceCloseShift': 'ForÈaÈi Ã®nchiderea',
      'forceCloseShiftHint': 'Tura va fi Ã®nchisÄ acum. PuteÈi adÄuga un raport.',
      'shiftClosed': 'TurÄ Ã®nchisÄ.',
      'archive': 'ArhivÄ',
      'noArchive': 'Arhiva este goalÄ',
      'notifications': 'NotificÄri',
      'noNotifications': 'Nicio notificare nouÄ',
      'newMemberRequest': 'NouÄ cerere de aderare',
      'markAllRead': 'MarcaÈi toate ca citite',
      'copyTool': 'CopiaÈi',
      'toolCopied': 'UnealtÄ copiatÄ',
      'sortNameAZ': 'Nume A-Z',
      'sortCountDesc': 'Grupuri mari Ã®ntÃ¢i',
      'sortDateDesc': 'Cele mai noi Ã®ntÃ¢i',
      'darkTheme': 'TemÄ Ã®nchisÄ',
      'lightTheme': 'TemÄ deschisÄ',
      'systemTheme': 'TemÄ sistem',
      'printQr': 'PrintaÈi QR',
      'saveAsPng': 'SalvaÈi PNG',
      'thermalLabel': 'EtichetÄ termicÄ',
      'printAllQr': 'Toate QR pe foaie',
      'noResults': 'Nimic gÄsit',
    },

    AppLang.nl: {
      'appTitle': 'ToolKeeper', 'login': 'Inloggen', 'register': 'Registreren', 'enter': 'Inloggen',
      'logout': 'Uitloggen', 'people': 'Mensen', 'tools': 'Gereedschap', 'tool': 'Gereedschap',
      'inv': 'Inv. nr.', 'issue': 'Uitgifte', 'profile': 'Profiel', 'chooseLang': 'Taal kiezen',
      'companyNotFound': 'Bedrijf niet gevonden', 'noAccessCompany': 'Geen toegang tot bedrijf',
      'leaveCompany': 'Verlaten / ander bedrijf', 'createCompany': 'Bedrijf aanmaken',
      'joinCompany': 'Aansluiten', 'or': 'OF', 'companyName': 'Bedrijfsnaam',
      'role': 'Rol', 'role_owner': 'Eigenaar', 'role_admin': 'Beheerder',
      'role_foreman': 'Voorman', 'role_employee': 'Medewerker',
      'save': 'Opslaan', 'cancel': 'Annuleren', 'add': 'Toevoegen', 'delete': 'Verwijderen',
      'noEmployees': 'Geen medewerkers', 'noTools': 'Geen gereedschap',
      'issued': 'Uitgegeven', 'returned': 'Teruggegeven', 'history': 'Geschiedenis',
      'total': 'Totaal', 'pcs': 'st.', 'loading': 'Laden...', 'error': 'Fout', 'ok': 'OK',
      'issueUpper': 'UITGEVEN', 'returnUpper': 'TERUGGEVEN', 'noName': 'Geen naam',
      'confirmReturn': 'Teruggeven', 'confirmIssue': 'Uitgeven',
      'issueTab': 'Uitgifte', 'returnTab': 'Retour',
      'searchByNameOrPhone': 'Zoeken op naam of telefoon...',
      'birthDate': 'Geboortedatum', 'clothesSize': 'Kledingmaat', 'company': 'Bedrijf',
      'continue': 'Doorgaan', 'done': 'Klaar', 'firstName': 'Voornaam', 'lastName': 'Achternaam',
      'password': 'Wachtwoord', 'position': 'Positie', 'reports': 'Rapporten', 'welcome': 'Welkom',
      'email': 'E-mail', 'employee': 'Medewerker', 'employees': 'Medewerkers',
      'owner': 'Eigenaar', 'admin': 'Beheerder', 'worker': 'Medewerker',
      'employeeStatus': 'Medewerkerstatus', 'empStatusActive': 'Actief', 'empStatusFired': 'Ontslagen',
      'toolStatus': 'Gereedschapstatus', 'toolStatusActive': 'Actief', 'toolStatusRepair': 'In reparatie',
      'toolStatusDisposed': 'Afgevoerd', 'statusNote': 'Notitie',
      'warehouse': 'Magazijn', 'where': 'Waar', 'issuedAt': 'Uitgegeven', 'noData': 'Geen gegevens',
      'subscriptionTitle': 'Abonnement', 'subscriptionActive': 'Actief', 'subscriptionInactive': 'Inactief',
      'buyRenew': 'Kopen / Verlengen', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Voeg eerst mensen toe', 'needToolsFirst': 'Voeg eerst gereedschap toe',
      'noFreeTool': 'Geen vrij gereedschap', 'person': 'Persoon', 'returnTool': 'Teruggeven',
      'versionLabel': 'Versie', 'lang': 'Taal', 'selectPerson': 'Selecteer medewerker',
      'onHandsTotal': 'In handen: {n} st.', 'toolsCountLabel': 'Gereedschap: {n}', 'whoLabel': 'Wie: {name}',
      'noReturnTool': 'Geen gereedschap om terug te geven', 'noCompany': 'Geen bedrijf geselecteerd',
      'reportFilterHint': 'Filter...', 'reportsPeople': 'Wie heeft wat (per persoon)',
      'reportsTools': 'Waar is het gereedschap', 'searchByNameOrInv': 'Zoeken op naam of nr...',
      'needAccount': 'Account nodig', 'newPassword': 'Nieuw wachtwoord', 'noPeople': 'Nog geen mensen',
      'onlyAdmin': 'Alleen eigenaar/beheerder', 'passwordsNotMatch': 'Wachtwoorden komen niet overeen',
      'changePlan': 'Plan wijzigen', 'planLabel': 'Plan', 'planSaved': 'Plan opgeslagen', 'gpsNotInPlan': 'GPS-tracking beschikbaar vanaf Pro plan', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Personenlimiet', 'perMonth': 'maand',
      'planChangeOnlyOwner': 'Alleen de eigenaar kan het plan wijzigen.',
      'selectPlan': 'Plan kiezen', 'supportTitle': 'Support',
      'supportDesc': 'Voor vragen, neem contact op:', 'tariffLimitsTitle': 'Tarief en limieten',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Gebruikt (actief)',
      'inactiveNotCountedNote': 'Ontslagenen/inactieven tellen niet mee.',
      'google': 'Google', 'enterEmailPass': 'E-mail en wachtwoord invoeren',
      'addTool': 'Gereedschap toevoegen', 'addEmployee': 'Medewerker toevoegen',
      'inviteCode': 'Uitnodigingscode', 'requests': 'Verzoeken', 'approve': 'Goedkeuren',
      'addPerson': 'Persoon toevoegen', 'decline': 'Weigeren',
      'selectToolFirst': 'Selecteer eerst gereedschap', 'selectPersonFirst': 'Selecteer eerst medewerker',
      'reportsByTool': 'Per gereedschap', 'reportsByPerson': 'Per medewerker',
      'alreadyIn': 'Al in bedrijf', 'archivedCompany': 'Bedrijf gearchiveerd',
      'subscriptionStatusLabel': 'Status', 'subscriptionValidUntilLabel': 'Geldig tot',
      'subscriptionTest': 'Testmodus', 'subscriptionLive': 'Betaalmodus',
      'buyRenewSoon': 'Betaling binnenkort beschikbaar. Contact opnemen met support.',
      'billingModeLabel': 'Betalingsmodus', 'emailLabel': 'E-mail',
      'returnTitle': 'Retour bevestigen', 'switchAcc': 'Account wisselen',
      'myShift': 'Mijn dienst', 'startShift': 'Dienst starten', 'endShift': 'Dienst beÃ«indigen',
      'currentShift': 'Huidige dienst', 'shiftStarted': 'Dienst gestart!', 'shiftEnded': 'Dienst beÃ«indigd!',
      'selectSite': 'Selecteer locatie', 'noSites': 'Geen locaties. Neem contact op met de beheerder.',
      'writeReport': 'Dienstrapport', 'whatDone': 'Wat is er gedaan', 'timesheets': 'Urenregistratie',
      'manageSites': 'Locaties beheren', 'sites': 'Locaties', 'addSite': 'Locatie toevoegen',
      'editSite': 'Locatie bewerken', 'siteName': 'Locatienaam', 'siteAddress': 'Adres',
      'siteRadius': 'Check-in straal (m)', 'gpsInterval': 'GPS-interval (min)',
      'allTime': 'Hele periode',
      'allSites': 'Alle locaties',
      'allPeople': 'Alle medewerkers',
      'exportPdf': 'PDF exporteren',
      'exportXlsx': 'Excel exporteren',
      'actPdf': 'Akte PDF',
      'nakladnayaPdf': 'Leveringsbon PDF',
      'gpsTrack': 'GPS-track',
      'noGpsData': 'Geen GPS-data',
      'shiftActive': 'Dienst actief',
      'shiftStart': 'Begin',
      'shiftEnd': 'Einde',
      'totalHours': 'Totaal uren',
      'shiftsCount': 'Diensten',
      'workReport': 'Rapport',
      'myTimesheets': 'Mijn diensten',
      'allTimesheets': 'Alle diensten',
      'gpsPermissionDenied': 'GPS niet beschikbaar â dienst gestart zonder locatiecontrole',
      'gpsWarningTitle': 'Buiten de zone van de locatie',
      'gpsWarningText': 'Uw locatie komt niet overeen met het adres van de locatie.',
      'distance': 'Afstand',
      'startAnyway': 'Toch starten',
      'shiftTypeHourly': 'Per uur',
      'shiftTypeAccord': 'Vaste prijs',
      'chooseShiftType': 'Type dienst',
      'shiftType': 'Type werk',
      'reportRequired': 'Vul het rapport in â wat is er gedaan',
      'viewSites': 'Alle locaties',
      'navigateTo': 'Navigeer',
      'linkUser': 'Gebruiker koppelen',
      'linkedUser': 'Gekoppeld aan',
      'unlinkUser': 'Ontkoppelen',
      'selectUserToLink': 'Gebruiker selecteren',
      'notLinked': 'Account is niet gekoppeld aan een profiel. Neem contact op met de beheerder.',
      'personTypePerson': 'Persoon',
      'personTypeObject': 'Object',
      'noObjects': 'Nog geen objecten. Druk op +',
      'objectCompleted': 'Voltooid',
      'markObjectCompleted': 'Markeren als voltooid',
      'personTab': 'Personen',
      'objectTab': 'Objecten',
      'cannotCompleteHasTools': 'Kan niet voltooien: {n} gereedschappen op object',
      'cannotFireHasTools': 'Kan niet ontslaan: medewerker heeft {n} gereedschappen',
      'addObject': 'Object toevoegen',
      'shiftReminder10hTitle': 'Dienst duurt 10 uur',
      'shiftReminder10hBody': 'Dienst is al meer dan 10 uur actief. Vergeet niet te sluiten.',
      'shiftReminder12hTitle': 'â ï¸ Dienst 12 uur!',
      'shiftReminder12hBody': 'Waarschuwing: dienst loopt al meer dan 12 uur. Sluit de dienst.',
      'offlineBanner': 'Geen verbinding â¢ gegevens uit cache',
      'alreadyHaveActiveShift': 'U heeft al een actieve dienst. Sluit deze voor u een nieuwe start.',
      'forceCloseShift': 'Geforceerd sluiten',
      'forceCloseShiftHint': 'De dienst wordt nu gesloten. U kunt een rapport toevoegen.',
      'shiftClosed': 'Dienst gesloten.',
      'archive': 'Archief',
      'noArchive': 'Archief is leeg',
      'notifications': 'Meldingen',
      'noNotifications': 'Geen nieuwe meldingen',
      'newMemberRequest': 'Nieuw verzoek om lid te worden',
      'markAllRead': 'Alles als gelezen markeren',
      'copyTool': 'KopiÃ«ren',
      'toolCopied': 'Gereedschap gekopieerd',
      'sortNameAZ': 'Naam A-Z',
      'sortCountDesc': 'Grote groepen eerst',
      'sortDateDesc': 'Nieuwste eerst',
      'darkTheme': 'Donker thema',
      'lightTheme': 'Licht thema',
      'systemTheme': 'Systeemthema',
      'printQr': 'QR afdrukken',
      'saveAsPng': 'PNG opslaan',
      'thermalLabel': 'Thermisch etiket',
      'printAllQr': 'Alle QR op blad',
      'noResults': 'Niets gevonden',
    },

    AppLang.tr: {
      'appTitle': 'ToolKeeper', 'login': 'GiriÅ', 'register': 'KayÄ±t', 'enter': 'GiriÅ yap',
      'logout': 'ÃÄ±kÄ±Å yap', 'people': 'KiÅiler', 'tools': 'Aletler', 'tool': 'Alet',
      'inv': 'Env. no.', 'issue': 'DaÄÄ±tÄ±m', 'profile': 'Profil', 'chooseLang': 'Dil seÃ§in',
      'companyNotFound': 'Åirket bulunamadÄ±', 'noAccessCompany': 'Åirkete eriÅim yok',
      'leaveCompany': 'ÃÄ±k / baÅka Åirket seÃ§', 'createCompany': 'Åirket oluÅtur',
      'joinCompany': 'KatÄ±l', 'or': 'VEYA', 'companyName': 'Åirket adÄ±',
      'role': 'Rol', 'role_owner': 'Sahip', 'role_admin': 'YÃ¶netici',
      'role_foreman': 'UstabaÅÄ±', 'role_employee': 'ÃalÄ±Åan',
      'save': 'Kaydet', 'cancel': 'Ä°ptal', 'add': 'Ekle', 'delete': 'Sil',
      'noEmployees': 'ÃalÄ±Åan yok', 'noTools': 'Alet yok',
      'issued': 'Verildi', 'returned': 'Ä°ade edildi', 'history': 'GeÃ§miÅ',
      'total': 'Toplam', 'pcs': 'adet', 'loading': 'YÃ¼kleniyor...', 'error': 'Hata', 'ok': 'Tamam',
      'issueUpper': 'VER', 'returnUpper': 'Ä°ADE ET', 'noName': 'Ä°simsiz',
      'confirmReturn': 'Ä°ade et', 'confirmIssue': 'Ver',
      'issueTab': 'DaÄÄ±tÄ±m', 'returnTab': 'Ä°ade',
      'searchByNameOrPhone': 'Ad veya telefona gÃ¶re ara...',
      'birthDate': 'DoÄum tarihi', 'clothesSize': 'KÄ±yafet bedeni', 'company': 'Åirket',
      'continue': 'Devam et', 'done': 'Tamam', 'firstName': 'Ad', 'lastName': 'Soyad',
      'password': 'Åifre', 'position': 'Pozisyon', 'reports': 'Raporlar', 'welcome': 'HoÅ geldiniz',
      'email': 'E-posta', 'employee': 'ÃalÄ±Åan', 'employees': 'ÃalÄ±Åanlar',
      'owner': 'Sahip', 'admin': 'YÃ¶netici', 'worker': 'ÃalÄ±Åan',
      'employeeStatus': 'ÃalÄ±Åan durumu', 'empStatusActive': 'Aktif', 'empStatusFired': 'Ä°Åten Ã§Ä±karÄ±ldÄ±',
      'toolStatus': 'Alet durumu', 'toolStatusActive': 'Aktif', 'toolStatusRepair': 'Tamirde',
      'toolStatusDisposed': 'Hurdaya Ã§Ä±karÄ±ldÄ±', 'statusNote': 'Not',
      'warehouse': 'Depo', 'where': 'Nerede', 'issuedAt': 'Verildi', 'noData': 'Veri yok',
      'subscriptionTitle': 'Abonelik', 'subscriptionActive': 'Aktif', 'subscriptionInactive': 'Aktif deÄil',
      'buyRenew': 'SatÄ±n al / Uzat', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Ãnce kiÅi ekleyin', 'needToolsFirst': 'Ãnce alet ekleyin',
      'noFreeTool': 'Serbest alet yok', 'person': 'KiÅi', 'returnTool': 'Ä°ade et',
      'versionLabel': 'SÃ¼rÃ¼m', 'lang': 'Dil', 'selectPerson': 'ÃalÄ±Åan seÃ§in',
      'onHandsTotal': 'Elde: {n} adet', 'toolsCountLabel': 'Aletler: {n}', 'whoLabel': 'Kimde: {name}',
      'noReturnTool': 'Ä°ade edilecek alet yok', 'noCompany': 'Åirket seÃ§ilmedi',
      'reportFilterHint': 'Filtre...', 'reportsPeople': 'Kimde ne var (kiÅilere gÃ¶re)',
      'reportsTools': 'Alet nerede', 'searchByNameOrInv': 'Ada veya numaraya gÃ¶re ara...',
      'needAccount': 'Hesap gerekli', 'newPassword': 'Yeni Åifre', 'noPeople': 'HenÃ¼z kiÅi yok',
      'onlyAdmin': 'Sadece sahip/yÃ¶netici', 'passwordsNotMatch': 'Åifreler eÅleÅmiyor',
      'changePlan': 'PlanÄ± deÄiÅtir', 'planLabel': 'Plan', 'planSaved': 'Plan kaydedildi', 'gpsNotInPlan': 'GPS takibi Pro planÄ±ndan itibaren mevcut', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'KiÅi limiti', 'perMonth': 'ay',
      'planChangeOnlyOwner': 'YalnÄ±zca sahip planÄ± deÄiÅtirebilir.',
      'selectPlan': 'Plan seÃ§in', 'supportTitle': 'Destek',
      'supportDesc': 'SorularÄ±nÄ±z iÃ§in bize ulaÅÄ±n:', 'tariffLimitsTitle': 'Tarife ve limitler',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'KullanÄ±lan (aktif)',
      'inactiveNotCountedNote': 'Ä°Åten Ã§Ä±karÄ±lanlar/pasifler limite dahil deÄil.',
      'google': 'Google', 'enterEmailPass': 'E-posta ve Åifre girin',
      'addTool': 'Alet ekle', 'addEmployee': 'ÃalÄ±Åan ekle',
      'inviteCode': 'Davet kodu', 'requests': 'Ä°stekler', 'approve': 'Onayla',
      'addPerson': 'KiÅi ekle', 'decline': 'Reddet',
      'selectToolFirst': 'Ãnce alet seÃ§in', 'selectPersonFirst': 'Ãnce Ã§alÄ±Åan seÃ§in',
      'reportsByTool': 'Alete gÃ¶re', 'reportsByPerson': 'ÃalÄ±Åana gÃ¶re',
      'alreadyIn': 'Zaten Åirkette', 'archivedCompany': 'Åirket arÅivlendi',
      'subscriptionStatusLabel': 'Durum', 'subscriptionValidUntilLabel': 'Åu tarihe kadar geÃ§erli',
      'subscriptionTest': 'Test modu', 'subscriptionLive': 'Ãcretli mod',
      'buyRenewSoon': 'Ãdeme yakÄ±nda mevcut olacak. DesteÄe baÅvurun.',
      'billingModeLabel': 'Ãdeme modu', 'emailLabel': 'E-posta',
      'returnTitle': 'Ä°adeyi onayla', 'switchAcc': 'Hesap deÄiÅtir',
      'myShift': 'Vardiyam', 'startShift': 'Vardiya baÅlat', 'endShift': 'Vardiya bitir',
      'currentShift': 'Mevcut vardiya', 'shiftStarted': 'Vardiya baÅladÄ±!', 'shiftEnded': 'Vardiya bitti!',
      'selectSite': 'Åantiye seÃ§', 'noSites': 'Åantiye yok. YÃ¶neticiye baÅvurun.',
      'writeReport': 'Vardiya raporu', 'whatDone': 'Ne yapÄ±ldÄ±', 'timesheets': 'Vardiya kayÄ±tlarÄ±',
      'manageSites': 'Åantiyeleri yÃ¶net', 'sites': 'Åantiyeler', 'addSite': 'Åantiye ekle',
      'editSite': 'Åantiye dÃ¼zenle', 'siteName': 'Åantiye adÄ±', 'siteAddress': 'Adres',
      'siteRadius': 'Check-in yarÄ±Ã§apÄ± (m)', 'gpsInterval': 'GPS aralÄ±ÄÄ± (dak)',
      'allTime': 'TÃ¼m dÃ¶nem',
      'allSites': 'TÃ¼m Åantiyeler',
      'allPeople': 'TÃ¼m Ã§alÄ±Åanlar',
      'exportPdf': 'PDF dÄ±Åa aktar',
      'exportXlsx': 'Excel dÄ±Åa aktar',
      'actPdf': 'Belge PDF',
      'nakladnayaPdf': 'Ä°rsaliye PDF',
      'gpsTrack': 'GPS izi',
      'noGpsData': 'GPS verisi yok',
      'shiftActive': 'Vardiya aktif',
      'shiftStart': 'BaÅlangÄ±Ã§',
      'shiftEnd': 'BitiÅ',
      'totalHours': 'Toplam saat',
      'shiftsCount': 'Vardiyalar',
      'workReport': 'Rapor',
      'myTimesheets': 'VardiyalarÄ±m',
      'allTimesheets': 'TÃ¼m vardiyalar',
      'gpsPermissionDenied': 'GPS kullanÄ±lamÄ±yor â vardiya konum doÄrulamasÄ± olmadan baÅlatÄ±ldÄ±',
      'gpsWarningTitle': 'Saha bÃ¶lgesi dÄ±ÅÄ±nda',
      'gpsWarningText': 'Konumunuz saha adresiyle eÅleÅmiyor.',
      'distance': 'Mesafe',
      'startAnyway': 'Yine de baÅlat',
      'shiftTypeHourly': 'Saatlik',
      'shiftTypeAccord': 'Sabit fiyat',
      'chooseShiftType': 'Vardiya tÃ¼rÃ¼',
      'shiftType': 'Ä°Å tÃ¼rÃ¼',
      'reportRequired': 'Raporu doldurun â ne yapÄ±ldÄ±',
      'viewSites': 'TÃ¼m sahalar',
      'navigateTo': 'Rota',
      'linkUser': 'KullanÄ±cÄ± baÄla',
      'linkedUser': 'BaÄlÄ±',
      'unlinkUser': 'BaÄlantÄ±yÄ± kes',
      'selectUserToLink': 'KullanÄ±cÄ± seÃ§',
      'notLinked': 'Hesap bir profile baÄlÄ± deÄil. YÃ¶neticiyle iletiÅime geÃ§in.',
      'personTypePerson': 'KiÅi',
      'personTypeObject': 'Nesne',
      'noObjects': 'HenÃ¼z nesne yok. + tuÅuna basÄ±n',
      'objectCompleted': 'TamamlandÄ±',
      'markObjectCompleted': 'TamamlandÄ± olarak iÅaretle',
      'personTab': 'KiÅiler',
      'objectTab': 'Nesneler',
      'cannotCompleteHasTools': 'TamamlanamÄ±yor: nesnede {n} alet var',
      'cannotFireHasTools': 'Ä°Åten Ã§Ä±karÄ±lamÄ±yor: Ã§alÄ±ÅanÄ±n {n} aleti var',
      'addObject': 'Nesne ekle',
      'shiftReminder10hTitle': 'Vardiya 10 saattir sÃ¼rÃ¼yor',
      'shiftReminder10hBody': 'Vardiya 10 saatten fazla aktif. KapatmayÄ± unutmayÄ±n.',
      'shiftReminder12hTitle': 'â ï¸ Vardiya 12 saat!',
      'shiftReminder12hBody': 'UyarÄ±: vardiya 12 saatten fazla sÃ¼rÃ¼yor. VardiyayÄ± kapatÄ±n.',
      'offlineBanner': 'BaÄlantÄ± yok â¢ Ã¶nbellekten veri',
      'alreadyHaveActiveShift': 'Zaten aktif bir vardiyanz var. Yeni baÅlatmadan Ã¶nce kapatÄ±n.',
      'forceCloseShift': 'Zorla kapat',
      'forceCloseShiftHint': 'Vardiya Åimdi kapatÄ±lacak. Rapor ekleyebilirsiniz.',
      'shiftClosed': 'Vardiya kapatÄ±ldÄ±.',
      'archive': 'ArÅiv',
      'noArchive': 'ArÅiv boÅ',
      'notifications': 'Bildirimler',
      'noNotifications': 'Yeni bildirim yok',
      'newMemberRequest': 'Yeni katÄ±lÄ±m isteÄi',
      'markAllRead': 'TÃ¼mÃ¼nÃ¼ okundu iÅaretle',
      'copyTool': 'Kopyala',
      'toolCopied': 'Alet kopyalandÄ±',
      'sortNameAZ': 'Ad A-Z',
      'sortCountDesc': 'BÃ¼yÃ¼k gruplar Ã¶nce',
      'sortDateDesc': 'En yeniler Ã¶nce',
      'darkTheme': 'Koyu tema',
      'lightTheme': 'AÃ§Ä±k tema',
      'systemTheme': 'Sistem temasÄ±',
      'printQr': 'QR yazdÄ±r',
      'saveAsPng': 'PNG kaydet',
      'thermalLabel': 'Termal etiket',
      'printAllQr': 'TÃ¼m QR sayfaya',
      'noResults': 'SonuÃ§ yok',
    },

    AppLang.ar: {
      'appTitle': 'ToolKeeper', 'login': 'ØªØ³Ø¬ÙÙ Ø§ÙØ¯Ø®ÙÙ', 'register': 'Ø§ÙØªØ³Ø¬ÙÙ', 'enter': 'Ø¯Ø®ÙÙ',
      'logout': 'ØªØ³Ø¬ÙÙ Ø§ÙØ®Ø±ÙØ¬', 'people': 'Ø£Ø´Ø®Ø§Øµ', 'tools': 'Ø£Ø¯ÙØ§Øª', 'tool': 'Ø£Ø¯Ø§Ø©',
      'inv': 'Ø±ÙÙ Ø§ÙØ¬Ø±Ø¯', 'issue': 'Ø¥ØµØ¯Ø§Ø±', 'profile': 'Ø§ÙÙÙÙ Ø§ÙØ´Ø®ØµÙ', 'chooseLang': 'Ø§Ø®ØªØ± Ø§ÙÙØºØ©',
      'companyNotFound': 'Ø§ÙØ´Ø±ÙØ© ØºÙØ± ÙÙØ¬ÙØ¯Ø©', 'noAccessCompany': 'ÙØ§ ÙÙØ¬Ø¯ ÙØµÙÙ ÙÙØ´Ø±ÙØ©',
      'leaveCompany': 'Ø®Ø±ÙØ¬ / Ø§Ø®ØªÙØ§Ø± Ø´Ø±ÙØ© Ø£Ø®Ø±Ù', 'createCompany': 'Ø¥ÙØ´Ø§Ø¡ Ø´Ø±ÙØ©',
      'joinCompany': 'Ø§ÙØ¶ÙØ§Ù', 'or': 'Ø£Ù', 'companyName': 'Ø§Ø³Ù Ø§ÙØ´Ø±ÙØ©',
      'role': 'Ø§ÙØ¯ÙØ±', 'role_owner': 'Ø§ÙÙØ§ÙÙ', 'role_admin': 'Ø§ÙÙØ³Ø¤ÙÙ',
      'role_foreman': 'Ø§ÙÙØ´Ø±Ù', 'role_employee': 'Ø§ÙÙÙØ¸Ù',
      'save': 'Ø­ÙØ¸', 'cancel': 'Ø¥ÙØºØ§Ø¡', 'add': 'Ø¥Ø¶Ø§ÙØ©', 'delete': 'Ø­Ø°Ù',
      'noEmployees': 'ÙØ§ ÙÙØ¬Ø¯ ÙÙØ¸ÙÙÙ', 'noTools': 'ÙØ§ ØªÙØ¬Ø¯ Ø£Ø¯ÙØ§Øª',
      'issued': 'ØªÙ Ø§ÙØ¥ØµØ¯Ø§Ø±', 'returned': 'ØªÙ Ø§ÙØ¥Ø±Ø¬Ø§Ø¹', 'history': 'Ø§ÙØ³Ø¬Ù',
      'total': 'Ø§ÙÙØ¬ÙÙØ¹', 'pcs': 'ÙØ·Ø¹Ø©', 'loading': 'ØªØ­ÙÙÙ...', 'error': 'Ø®Ø·Ø£', 'ok': 'ÙÙØ§ÙÙ',
      'issueUpper': 'Ø¥ØµØ¯Ø§Ø±', 'returnUpper': 'Ø¥Ø±Ø¬Ø§Ø¹', 'noName': 'Ø¨Ø¯ÙÙ Ø§Ø³Ù',
      'confirmReturn': 'Ø¥Ø±Ø¬Ø§Ø¹', 'confirmIssue': 'Ø¥ØµØ¯Ø§Ø±',
      'issueTab': 'Ø¥ØµØ¯Ø§Ø±', 'returnTab': 'Ø¥Ø±Ø¬Ø§Ø¹',
      'searchByNameOrPhone': 'Ø¨Ø­Ø« Ø¨Ø§ÙØ§Ø³Ù Ø£Ù Ø§ÙÙØ§ØªÙ...',
      'birthDate': 'ØªØ§Ø±ÙØ® Ø§ÙÙÙÙØ§Ø¯', 'clothesSize': 'ÙÙØ§Ø³ Ø§ÙÙÙØ§Ø¨Ø³', 'company': 'Ø§ÙØ´Ø±ÙØ©',
      'continue': 'ÙØªØ§Ø¨Ø¹Ø©', 'done': 'ØªÙ', 'firstName': 'Ø§ÙØ§Ø³Ù Ø§ÙØ£ÙÙ', 'lastName': 'Ø§Ø³Ù Ø§ÙØ¹Ø§Ø¦ÙØ©',
      'password': 'ÙÙÙØ© Ø§ÙÙØ±ÙØ±', 'position': 'Ø§ÙÙÙØµØ¨', 'reports': 'Ø§ÙØªÙØ§Ø±ÙØ±', 'welcome': 'ÙØ±Ø­Ø¨Ø§Ù',
      'email': 'Ø§ÙØ¨Ø±ÙØ¯ Ø§ÙØ¥ÙÙØªØ±ÙÙÙ', 'employee': 'ÙÙØ¸Ù', 'employees': 'ÙÙØ¸ÙÙÙ',
      'owner': 'Ø§ÙÙØ§ÙÙ', 'admin': 'Ø§ÙÙØ³Ø¤ÙÙ', 'worker': 'Ø¹Ø§ÙÙ',
      'employeeStatus': 'Ø­Ø§ÙØ© Ø§ÙÙÙØ¸Ù', 'empStatusActive': 'ÙØ´Ø·', 'empStatusFired': 'ÙÙØµÙÙ',
      'toolStatus': 'Ø­Ø§ÙØ© Ø§ÙØ£Ø¯Ø§Ø©', 'toolStatusActive': 'ÙØ´Ø·Ø©', 'toolStatusRepair': 'ÙÙ Ø§ÙØ¥ØµÙØ§Ø­',
      'toolStatusDisposed': 'ÙÙØºØ§Ø©', 'statusNote': 'ÙÙØ§Ø­Ø¸Ø©',
      'warehouse': 'Ø§ÙÙØ³ØªÙØ¯Ø¹', 'where': 'Ø£ÙÙ', 'issuedAt': 'ØµØ¯Ø± ÙÙ', 'noData': 'ÙØ§ ØªÙØ¬Ø¯ Ø¨ÙØ§ÙØ§Øª',
      'subscriptionTitle': 'Ø§ÙØ§Ø´ØªØ±Ø§Ù', 'subscriptionActive': 'ÙØ´Ø·', 'subscriptionInactive': 'ØºÙØ± ÙØ´Ø·',
      'buyRenew': 'Ø´Ø±Ø§Ø¡ / ØªØ¬Ø¯ÙØ¯', 'billingLive': 'ÙØ¨Ø§Ø´Ø±', 'billingTest': 'Ø§Ø®ØªØ¨Ø§Ø±',
      'needPeopleFirst': 'Ø£Ø¶Ù Ø£Ø´Ø®Ø§ØµØ§Ù Ø£ÙÙØ§Ù', 'needToolsFirst': 'Ø£Ø¶Ù Ø£Ø¯ÙØ§Øª Ø£ÙÙØ§Ù',
      'noFreeTool': 'ÙØ§ ØªÙØ¬Ø¯ Ø£Ø¯Ø§Ø© Ø­Ø±Ø©', 'person': 'Ø´Ø®Øµ', 'returnTool': 'Ø¥Ø±Ø¬Ø§Ø¹',
      'versionLabel': 'Ø§ÙØ¥ØµØ¯Ø§Ø±', 'lang': 'Ø§ÙÙØºØ©', 'selectPerson': 'Ø§Ø®ØªØ± ÙÙØ¸ÙØ§Ù',
      'onHandsTotal': 'ÙÙ Ø§ÙÙØ¯: {n} ÙØ·Ø¹Ø©', 'toolsCountLabel': 'Ø§ÙØ£Ø¯ÙØ§Øª: {n}', 'whoLabel': 'Ø¹ÙØ¯ ÙÙ: {name}',
      'noReturnTool': 'ÙØ§ ØªÙØ¬Ø¯ Ø£Ø¯Ø§Ø© ÙÙØ¥Ø¹Ø§Ø¯Ø©', 'noCompany': 'ÙÙ ÙØªÙ Ø§Ø®ØªÙØ§Ø± Ø§ÙØ´Ø±ÙØ©',
      'reportFilterHint': 'ØªØµÙÙØ©...', 'reportsPeople': 'ÙÙ ÙØ¯ÙÙ ÙØ§Ø°Ø§ (Ø­Ø³Ø¨ Ø§ÙØ£Ø´Ø®Ø§Øµ)',
      'reportsTools': 'Ø£ÙÙ Ø§ÙØ£Ø¯Ø§Ø©', 'searchByNameOrInv': 'Ø¨Ø­Ø« Ø¨Ø§ÙØ§Ø³Ù Ø£Ù Ø§ÙØ±ÙÙ...',
      'needAccount': 'Ø­Ø³Ø§Ø¨ ÙØ·ÙÙØ¨', 'newPassword': 'ÙÙÙØ© ÙØ±ÙØ± Ø¬Ø¯ÙØ¯Ø©', 'noPeople': 'ÙØ§ ÙÙØ¬Ø¯ Ø£Ø´Ø®Ø§Øµ Ø¨Ø¹Ø¯',
      'onlyAdmin': 'ÙÙÙØ§ÙÙ/Ø§ÙÙØ³Ø¤ÙÙ ÙÙØ·', 'passwordsNotMatch': 'ÙÙÙØ§Øª Ø§ÙÙØ±ÙØ± ØºÙØ± ÙØªØ·Ø§Ø¨ÙØ©',
      'changePlan': 'ØªØºÙÙØ± Ø§ÙØ®Ø·Ø©', 'planLabel': 'Ø§ÙØ®Ø·Ø©', 'planSaved': 'ØªÙ Ø­ÙØ¸ Ø§ÙØ®Ø·Ø©', 'gpsNotInPlan': 'ØªØªØ¨Ø¹ GPS ÙØªØ§Ø­ ÙÙ Ø®Ø·Ø© Pro ÙÙØ§ ÙÙÙ', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Ø­Ø¯ Ø§ÙØ£Ø´Ø®Ø§Øµ', 'perMonth': 'Ø´ÙØ±',
      'planChangeOnlyOwner': 'Ø§ÙÙØ§ÙÙ ÙÙØ· ÙÙÙÙÙ ØªØºÙÙØ± Ø§ÙØ®Ø·Ø©.',
      'selectPlan': 'Ø§Ø®ØªØ± Ø§ÙØ®Ø·Ø©', 'supportTitle': 'Ø§ÙØ¯Ø¹Ù',
      'supportDesc': 'ÙÙØ£Ø³Ø¦ÙØ© ØªÙØ§ØµÙ ÙØ¹ÙØ§:', 'tariffLimitsTitle': 'Ø§ÙØªØ¹Ø±ÙØ© ÙØ§ÙØ­Ø¯ÙØ¯',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'ÙØ³ØªØ®Ø¯Ù (ÙØ´Ø·ÙÙ)',
      'inactiveNotCountedNote': 'Ø§ÙÙÙØµÙÙÙÙ/Ø§ÙØºÙØ± ÙØ´Ø·ÙÙ ÙØ§ ÙØ­Ø³Ø¨ÙÙ ÙÙ Ø§ÙØ­Ø¯.',
      'google': 'Google', 'enterEmailPass': 'Ø£Ø¯Ø®Ù Ø§ÙØ¨Ø±ÙØ¯ ÙÙÙÙØ© Ø§ÙÙØ±ÙØ±',
      'addTool': 'Ø¥Ø¶Ø§ÙØ© Ø£Ø¯Ø§Ø©', 'addEmployee': 'Ø¥Ø¶Ø§ÙØ© ÙÙØ¸Ù',
      'inviteCode': 'Ø±ÙØ² Ø§ÙØ¯Ø¹ÙØ©', 'requests': 'Ø§ÙØ·ÙØ¨Ø§Øª', 'approve': 'ÙÙØ§ÙÙØ©',
      'addPerson': 'Ø¥Ø¶Ø§ÙØ© Ø´Ø®Øµ', 'decline': 'Ø±ÙØ¶',
      'selectToolFirst': 'Ø§Ø®ØªØ± Ø£Ø¯Ø§Ø© Ø£ÙÙØ§Ù', 'selectPersonFirst': 'Ø§Ø®ØªØ± ÙÙØ¸ÙØ§Ù Ø£ÙÙØ§Ù',
      'reportsByTool': 'Ø­Ø³Ø¨ Ø§ÙØ£Ø¯Ø§Ø©', 'reportsByPerson': 'Ø­Ø³Ø¨ Ø§ÙÙÙØ¸Ù',
      'alreadyIn': 'ÙÙØ¬ÙØ¯ Ø¨Ø§ÙÙØ¹Ù ÙÙ Ø§ÙØ´Ø±ÙØ©', 'archivedCompany': 'Ø§ÙØ´Ø±ÙØ© ÙØ¤Ø±Ø´ÙØ©',
      'subscriptionStatusLabel': 'Ø§ÙØ­Ø§ÙØ©', 'subscriptionValidUntilLabel': 'ØµØ§ÙØ­ Ø­ØªÙ',
      'subscriptionTest': 'ÙØ¶Ø¹ ØªØ¬Ø±ÙØ¨Ù', 'subscriptionLive': 'ÙØ¶Ø¹ ÙØ¯ÙÙØ¹',
      'buyRenewSoon': 'Ø§ÙØ¯ÙØ¹ ÙØ±ÙØ¨Ø§Ù. ØªÙØ§ØµÙ ÙØ¹ Ø§ÙØ¯Ø¹Ù.',
      'billingModeLabel': 'ÙØ¶Ø¹ Ø§ÙØ¯ÙØ¹', 'emailLabel': 'Ø§ÙØ¨Ø±ÙØ¯ Ø§ÙØ¥ÙÙØªØ±ÙÙÙ',
      'returnTitle': 'ØªØ£ÙÙØ¯ Ø§ÙØ¥Ø±Ø¬Ø§Ø¹',
      'myShift': 'ÙØ±Ø¯ÛØªÙ', 'startShift': 'Ø¨Ø¯Ø¡ Ø§ÙÙØ±Ø¯ÙØ©', 'endShift': 'Ø¥ÙÙØ§Ø¡ Ø§ÙÙØ±Ø¯ÙØ©',
      'currentShift': 'Ø§ÙÙØ±Ø¯ÙØ© Ø§ÙØ­Ø§ÙÙØ©', 'shiftStarted': 'Ø¨Ø¯Ø£Øª Ø§ÙÙØ±Ø¯ÙØ©!', 'shiftEnded': 'Ø§ÙØªÙØª Ø§ÙÙØ±Ø¯ÙØ©!',
      'selectSite': 'Ø§Ø®ØªØ± Ø§ÙÙÙÙØ¹', 'noSites': 'ÙØ§ ØªÙØ¬Ø¯ ÙÙØ§ÙØ¹. Ø§ØªØµÙ Ø¨Ø§ÙÙØ³Ø¤ÙÙ.',
      'writeReport': 'ØªÙØ±ÙØ± Ø§ÙÙØ±Ø¯ÙØ©', 'whatDone': 'ÙØ§ ØªÙ Ø¥ÙØ¬Ø§Ø²Ù', 'timesheets': 'Ø³Ø¬Ù Ø§ÙÙØ±Ø¯ÙØ§Øª',
      'manageSites': 'Ø¥Ø¯Ø§Ø±Ø© Ø§ÙÙÙØ§ÙØ¹', 'sites': 'Ø§ÙÙÙØ§ÙØ¹', 'addSite': 'Ø¥Ø¶Ø§ÙØ© ÙÙÙØ¹',
      'editSite': 'ØªØ¹Ø¯ÙÙ Ø§ÙÙÙÙØ¹', 'siteName': 'Ø§Ø³Ù Ø§ÙÙÙÙØ¹', 'siteAddress': 'Ø§ÙØ¹ÙÙØ§Ù',
      'siteRadius': 'ÙØ·Ø§Ù ØªØ³Ø¬ÙÙ Ø§ÙØ­Ø¶ÙØ± (Ù)', 'gpsInterval': 'ÙØªØ±Ø© GPS (Ø¯ÙÙÙØ©)',
      'allTime': 'ÙÙ Ø§ÙÙÙØª',
      'allSites': 'Ø¬ÙÙØ¹ Ø§ÙÙÙØ§ÙØ¹',
      'allPeople': 'Ø¬ÙÙØ¹ Ø§ÙÙÙØ¸ÙÙÙ',
      'exportPdf': 'ØªØµØ¯ÙØ± PDF',
      'exportXlsx': 'ØªØµØ¯ÙØ± Excel',
      'actPdf': 'ÙØ«ÙÙØ© PDF',
      'nakladnayaPdf': 'Ø³ÙØ¯ ØªØ³ÙÙÙ PDF',
      'gpsTrack': 'ÙØ³Ø§Ø± GPS',
      'noGpsData': 'ÙØ§ ØªÙØ¬Ø¯ Ø¨ÙØ§ÙØ§Øª GPS',
      'shiftActive': 'Ø§ÙÙØ±Ø¯ÙØ© ÙØ´Ø·Ø©',
      'shiftStart': 'Ø§ÙØ¨Ø¯Ø§ÙØ©',
      'shiftEnd': 'Ø§ÙÙÙØ§ÙØ©',
      'totalHours': 'Ø¥Ø¬ÙØ§ÙÙ Ø§ÙØ³Ø§Ø¹Ø§Øª',
      'shiftsCount': 'Ø§ÙÙØ±Ø¯ÙØ§Øª',
      'workReport': 'ØªÙØ±ÙØ±',
      'myTimesheets': 'ÙØ±Ø¯ÙØªÙ',
      'allTimesheets': 'Ø¬ÙÙØ¹ Ø§ÙÙØ±Ø¯ÙØ§Øª',
      'gpsPermissionDenied': 'GPS ØºÙØ± ÙØªØ§Ø­ â Ø¨Ø¯Ø£Øª Ø§ÙÙØ±Ø¯ÙØ© Ø¨Ø¯ÙÙ Ø§ÙØªØ­ÙÙ ÙÙ Ø§ÙÙÙÙØ¹',
      'gpsWarningTitle': 'Ø®Ø§Ø±Ø¬ ÙÙØ·ÙØ© Ø§ÙÙÙÙØ¹',
      'gpsWarningText': 'ÙÙÙØ¹Ù ÙØ§ ÙØªØ·Ø§Ø¨Ù ÙØ¹ Ø¹ÙÙØ§Ù Ø§ÙÙÙÙØ¹.',
      'distance': 'Ø§ÙÙØ³Ø§ÙØ©',
      'startAnyway': 'Ø§Ø¨Ø¯Ø£ Ø¹ÙÙ Ø£Ù Ø­Ø§Ù',
      'shiftTypeHourly': 'Ø¨Ø§ÙØ³Ø§Ø¹Ø©',
      'shiftTypeAccord': 'Ø³Ø¹Ø± Ø«Ø§Ø¨Øª',
      'chooseShiftType': 'ÙÙØ¹ Ø§ÙÙØ±Ø¯ÙØ©',
      'shiftType': 'ÙÙØ¹ Ø§ÙØ¹ÙÙ',
      'reportRequired': 'Ø£ÙÙÙ Ø§ÙØªÙØ±ÙØ± â ÙØ§ Ø§ÙØ°Ù ØªÙ Ø¥ÙØ¬Ø§Ø²Ù',
      'viewSites': 'Ø¬ÙÙØ¹ Ø§ÙÙÙØ§ÙØ¹',
      'navigateTo': 'Ø§ÙØªÙÙÙ',
      'linkUser': 'Ø±Ø¨Ø· ÙØ³ØªØ®Ø¯Ù',
      'linkedUser': 'ÙØ±ØªØ¨Ø· Ø¨Ù',
      'unlinkUser': 'ÙØµÙ Ø§ÙØ§Ø±ØªØ¨Ø§Ø·',
      'selectUserToLink': 'Ø§Ø®ØªØ± ÙØ³ØªØ®Ø¯Ù',
      'notLinked': 'Ø§ÙØ­Ø³Ø§Ø¨ ØºÙØ± ÙØ±ØªØ¨Ø· Ø¨ÙÙÙ Ø´Ø®ØµÙ. ØªÙØ§ØµÙ ÙØ¹ Ø§ÙÙØ³Ø¤ÙÙ.',
      'personTypePerson': 'Ø´Ø®Øµ',
      'personTypeObject': 'ÙØ§Ø¦Ù',
      'noObjects': 'ÙØ§ ØªÙØ¬Ø¯ ÙØ§Ø¦ÙØ§Øª Ø­ØªÙ Ø§ÙØ¢Ù. Ø§Ø¶ØºØ· +',
      'objectCompleted': 'ÙÙØªÙÙ',
      'markObjectCompleted': 'ÙØ¶Ø¹ Ø¹ÙØ§ÙØ© ÙÙØªÙÙ',
      'personTab': 'Ø§ÙØ£Ø´Ø®Ø§Øµ',
      'objectTab': 'Ø§ÙÙØ§Ø¦ÙØ§Øª',
      'cannotCompleteHasTools': 'ÙØ§ ÙÙÙÙ Ø§ÙØ¥ÙÙØ§Ù: {n} Ø£Ø¯ÙØ§Øª Ø¹ÙÙ Ø§ÙÙØ§Ø¦Ù',
      'cannotFireHasTools': 'ÙØ§ ÙÙÙÙ Ø§ÙÙØµÙ: Ø§ÙÙÙØ¸Ù ÙØ¯ÙÙ {n} Ø£Ø¯ÙØ§Øª',
      'addObject': 'Ø¥Ø¶Ø§ÙØ© ÙØ§Ø¦Ù',
      'shiftReminder10hTitle': 'Ø§ÙÙØ±Ø¯ÙØ© ØªØ³ØªÙØ± 10 Ø³Ø§Ø¹Ø§Øª',
      'shiftReminder10hBody': 'Ø§ÙÙØ±Ø¯ÙØ© ÙØ´Ø·Ø© ÙØ£ÙØ«Ø± ÙÙ 10 Ø³Ø§Ø¹Ø§Øª. ÙØ§ ØªÙØ³Ù Ø¥ØºÙØ§ÙÙØ§.',
      'shiftReminder12hTitle': 'â ï¸ ÙØ±Ø¯ÙØ© 12 Ø³Ø§Ø¹Ø©!',
      'shiftReminder12hBody': 'ØªØ­Ø°ÙØ±: Ø§ÙÙØ±Ø¯ÙØ© Ø¬Ø§Ø±ÙØ© ÙÙØ° Ø£ÙØ«Ø± ÙÙ 12 Ø³Ø§Ø¹Ø©. Ø£ØºÙÙ Ø§ÙÙØ±Ø¯ÙØ©.',
      'offlineBanner': 'ÙØ§ ÙÙØ¬Ø¯ Ø§ØªØµØ§Ù â¢ Ø¨ÙØ§ÙØ§Øª ÙÙ Ø§ÙØ°Ø§ÙØ±Ø© Ø§ÙÙØ¤ÙØªØ©',
      'alreadyHaveActiveShift': 'ÙØ¯ÙÙ Ø¨Ø§ÙÙØ¹Ù ÙØ±Ø¯ÙØ© ÙØ´Ø·Ø©. Ø£ØºÙÙÙØ§ ÙØ¨Ù Ø¨Ø¯Ø¡ ÙØ±Ø¯ÙØ© Ø¬Ø¯ÙØ¯Ø©.',
      'forceCloseShift': 'Ø¥ØºÙØ§Ù ÙØ³Ø±Ù',
      'forceCloseShiftHint': 'Ø³ØªÙØºÙÙ Ø§ÙÙØ±Ø¯ÙØ© Ø§ÙØ¢Ù. ÙÙÙÙÙ Ø¥Ø¶Ø§ÙØ© ØªÙØ±ÙØ±.',
      'shiftClosed': 'ØªÙ Ø¥ØºÙØ§Ù Ø§ÙÙØ±Ø¯ÙØ©.',
      'archive': 'Ø£Ø±Ø´ÙÙ',
      'noArchive': 'Ø§ÙØ£Ø±Ø´ÙÙ ÙØ§Ø±Øº',
      'notifications': 'Ø§ÙØ¥Ø´Ø¹Ø§Ø±Ø§Øª',
      'noNotifications': 'ÙØ§ ØªÙØ¬Ø¯ Ø¥Ø´Ø¹Ø§Ø±Ø§Øª Ø¬Ø¯ÙØ¯Ø©',
      'newMemberRequest': 'Ø·ÙØ¨ Ø§ÙØ¶ÙØ§Ù Ø¬Ø¯ÙØ¯',
      'markAllRead': 'ØªØ­Ø¯ÙØ¯ Ø§ÙÙÙ ÙÙÙØ±ÙØ¡',
      'copyTool': 'ÙØ³Ø®',
      'toolCopied': 'ØªÙ ÙØ³Ø® Ø§ÙØ£Ø¯Ø§Ø©',
      'sortNameAZ': 'Ø§ÙØ§Ø³Ù Ø£-Ù',
      'sortCountDesc': 'Ø§ÙÙØ¬ÙÙØ¹Ø§Øª Ø§ÙÙØ¨ÙØ±Ø© Ø£ÙÙØ§Ù',
      'sortDateDesc': 'Ø§ÙØ£Ø­Ø¯Ø« Ø£ÙÙØ§Ù',
      'darkTheme': 'Ø§ÙÙØ¸ÙØ± Ø§ÙØ¯Ø§ÙÙ',
      'lightTheme': 'Ø§ÙÙØ¸ÙØ± Ø§ÙÙØ§ØªØ­',
      'systemTheme': 'ÙØ¸ÙØ± Ø§ÙÙØ¸Ø§Ù',
      'printQr': 'Ø·Ø¨Ø§Ø¹Ø© QR',
      'saveAsPng': 'Ø­ÙØ¸ PNG',
      'thermalLabel': 'ÙÙØµÙ Ø­Ø±Ø§Ø±Ù',
      'printAllQr': 'ÙÙ QR Ø¹ÙÙ ÙØ±ÙØ©',
      'noResults': 'ÙØ§ ÙØªØ§Ø¦Ø¬',
    },

    AppLang.hi: {
      'appTitle': 'ToolKeeper', 'login': 'à¤²à¥à¤à¤¿à¤¨', 'register': 'à¤°à¤à¤¿à¤¸à¥à¤à¤°', 'enter': 'à¤¸à¤¾à¤à¤¨ à¤à¤¨ à¤à¤°à¥à¤',
      'logout': 'à¤²à¥à¤à¤à¤à¤', 'people': 'à¤²à¥à¤', 'tools': 'à¤à¤à¤¼à¤¾à¤°', 'tool': 'à¤à¤à¤¼à¤¾à¤°',
      'inv': 'à¤à¤¨à¥à¤µ. à¤¨à¤.', 'issue': 'à¤à¤¾à¤°à¥ à¤à¤°à¤¨à¤¾', 'profile': 'à¤ªà¥à¤°à¥à¤«à¤¼à¤¾à¤à¤²', 'chooseLang': 'à¤­à¤¾à¤·à¤¾ à¤à¥à¤¨à¥à¤',
      'companyNotFound': 'à¤à¤à¤ªà¤¨à¥ à¤¨à¤¹à¥à¤ à¤®à¤¿à¤²à¥', 'noAccessCompany': 'à¤à¤à¤ªà¤¨à¥ à¤¤à¤ à¤ªà¤¹à¥à¤à¤ à¤¨à¤¹à¥à¤',
      'leaveCompany': 'à¤à¥à¤¡à¤¼à¥à¤ / à¤¦à¥à¤¸à¤°à¥ à¤à¤à¤ªà¤¨à¥', 'createCompany': 'à¤à¤à¤ªà¤¨à¥ à¤¬à¤¨à¤¾à¤à¤',
      'joinCompany': 'à¤à¥à¤¡à¤¼à¥à¤', 'or': 'à¤¯à¤¾', 'companyName': 'à¤à¤à¤ªà¤¨à¥ à¤à¤¾ à¤¨à¤¾à¤®',
      'role': 'à¤­à¥à¤®à¤¿à¤à¤¾', 'role_owner': 'à¤®à¤¾à¤²à¤¿à¤', 'role_admin': 'à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤',
      'role_foreman': 'à¤«à¥à¤°à¤®à¥à¤¨', 'role_employee': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥',
      'save': 'à¤¸à¤¹à¥à¤à¥à¤', 'cancel': 'à¤°à¤¦à¥à¤¦ à¤à¤°à¥à¤', 'add': 'à¤à¥à¤¡à¤¼à¥à¤', 'delete': 'à¤¹à¤à¤¾à¤à¤',
      'noEmployees': 'à¤à¥à¤ à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤¨à¤¹à¥à¤', 'noTools': 'à¤à¥à¤ à¤à¤à¤¼à¤¾à¤° à¤¨à¤¹à¥à¤',
      'issued': 'à¤à¤¾à¤°à¥ à¤à¤¿à¤¯à¤¾', 'returned': 'à¤µà¤¾à¤ªà¤¸ à¤à¤¿à¤¯à¤¾', 'history': 'à¤à¤¤à¤¿à¤¹à¤¾à¤¸',
      'total': 'à¤à¥à¤²', 'pcs': 'à¤ªà¥à¤¸', 'loading': 'à¤²à¥à¤¡ à¤¹à¥ à¤°à¤¹à¤¾ à¤¹à¥...', 'error': 'à¤¤à¥à¤°à¥à¤à¤¿', 'ok': 'à¤ à¥à¤ à¤¹à¥',
      'issueUpper': 'à¤à¤¾à¤°à¥ à¤à¤°à¥à¤', 'returnUpper': 'à¤µà¤¾à¤ªà¤¸ à¤à¤°à¥à¤', 'noName': 'à¤¨à¤¾à¤® à¤¨à¤¹à¥à¤',
      'confirmReturn': 'à¤µà¤¾à¤ªà¤¸ à¤à¤°à¥à¤', 'confirmIssue': 'à¤à¤¾à¤°à¥ à¤à¤°à¥à¤',
      'issueTab': 'à¤à¤¾à¤°à¥ à¤à¤°à¤¨à¤¾', 'returnTab': 'à¤µà¤¾à¤ªà¤¸à¥',
      'searchByNameOrPhone': 'à¤¨à¤¾à¤® à¤¯à¤¾ à¤«à¥à¤¨ à¤¸à¥ à¤à¥à¤à¥à¤...',
      'birthDate': 'à¤à¤¨à¥à¤® à¤¤à¤¿à¤¥à¤¿', 'clothesSize': 'à¤à¤ªà¤¡à¤¼à¥à¤ à¤à¤¾ à¤¸à¤¾à¤à¤à¤¼', 'company': 'à¤à¤à¤ªà¤¨à¥',
      'continue': 'à¤à¤¾à¤°à¥ à¤°à¤à¥à¤', 'done': 'à¤¹à¥ à¤à¤¯à¤¾', 'firstName': 'à¤¨à¤¾à¤®', 'lastName': 'à¤à¤ªà¤¨à¤¾à¤®',
      'password': 'à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡', 'position': 'à¤ªà¤¦', 'reports': 'à¤°à¤¿à¤ªà¥à¤°à¥à¤', 'welcome': 'à¤¸à¥à¤µà¤¾à¤à¤¤ à¤¹à¥',
      'email': 'à¤à¤®à¥à¤²', 'employee': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥', 'employees': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥',
      'owner': 'à¤®à¤¾à¤²à¤¿à¤', 'admin': 'à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤', 'worker': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥',
      'employeeStatus': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤¸à¥à¤¥à¤¿à¤¤à¤¿', 'empStatusActive': 'à¤¸à¤à¥à¤°à¤¿à¤¯', 'empStatusFired': 'à¤¬à¤°à¥à¤à¤¾à¤¸à¥à¤¤',
      'toolStatus': 'à¤à¤à¤¼à¤¾à¤° à¤¸à¥à¤¥à¤¿à¤¤à¤¿', 'toolStatusActive': 'à¤¸à¤à¥à¤°à¤¿à¤¯', 'toolStatusRepair': 'à¤®à¤°à¤®à¥à¤®à¤¤ à¤®à¥à¤',
      'toolStatusDisposed': 'à¤¬à¤à¤¦', 'statusNote': 'à¤¨à¥à¤',
      'warehouse': 'à¤à¥à¤¦à¤¾à¤®', 'where': 'à¤à¤¹à¤¾à¤', 'issuedAt': 'à¤à¤¾à¤°à¥ à¤à¤¿à¤¯à¤¾', 'noData': 'à¤à¥à¤ à¤¡à¥à¤à¤¾ à¤¨à¤¹à¥à¤',
      'subscriptionTitle': 'à¤¸à¤¬à¥à¤¸à¤à¥à¤°à¤¿à¤ªà¥à¤¶à¤¨', 'subscriptionActive': 'à¤¸à¤à¥à¤°à¤¿à¤¯', 'subscriptionInactive': 'à¤¨à¤¿à¤·à¥à¤à¥à¤°à¤¿à¤¯',
      'buyRenew': 'à¤à¤°à¥à¤¦à¥à¤ / à¤¨à¤µà¥à¤¨à¥à¤à¤°à¤£', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'à¤ªà¤¹à¤²à¥ à¤²à¥à¤à¥à¤ à¤à¥ à¤à¥à¤¡à¤¼à¥à¤', 'needToolsFirst': 'à¤ªà¤¹à¤²à¥ à¤à¤à¤¼à¤¾à¤° à¤à¥à¤¡à¤¼à¥à¤',
      'noFreeTool': 'à¤à¥à¤ à¤®à¥à¤«à¤¼à¥à¤¤ à¤à¤à¤¼à¤¾à¤° à¤¨à¤¹à¥à¤', 'person': 'à¤µà¥à¤¯à¤à¥à¤¤à¤¿', 'returnTool': 'à¤µà¤¾à¤ªà¤¸ à¤à¤°à¥à¤',
      'versionLabel': 'à¤¸à¤à¤¸à¥à¤à¤°à¤£', 'lang': 'à¤­à¤¾à¤·à¤¾', 'selectPerson': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤à¥à¤¨à¥à¤',
      'onHandsTotal': 'à¤¹à¤¾à¤¥ à¤®à¥à¤: {n} à¤ªà¥à¤¸', 'toolsCountLabel': 'à¤à¤à¤¼à¤¾à¤°: {n}', 'whoLabel': 'à¤à¤¿à¤¸à¤à¥ à¤ªà¤¾à¤¸: {name}',
      'noReturnTool': 'à¤µà¤¾à¤ªà¤¸ à¤à¤°à¤¨à¥ à¤à¥ à¤²à¤¿à¤ à¤à¥à¤ à¤à¤à¤¼à¤¾à¤° à¤¨à¤¹à¥à¤', 'noCompany': 'à¤à¥à¤ à¤à¤à¤ªà¤¨à¥ à¤¨à¤¹à¥à¤ à¤à¥à¤¨à¥',
      'reportFilterHint': 'à¤«à¤¼à¤¿à¤²à¥à¤à¤°...', 'reportsPeople': 'à¤à¤¿à¤¸à¤à¥ à¤ªà¤¾à¤¸ à¤à¥à¤¯à¤¾ (à¤²à¥à¤à¥à¤ à¤à¥ à¤à¤¨à¥à¤¸à¤¾à¤°)',
      'reportsTools': 'à¤à¤à¤¼à¤¾à¤° à¤à¤¹à¤¾à¤ à¤¹à¥', 'searchByNameOrInv': 'à¤¨à¤¾à¤® à¤¯à¤¾ à¤¨à¤. à¤¸à¥ à¤à¥à¤à¥à¤...',
      'needAccount': 'à¤à¤¾à¤¤à¤¾ à¤à¤µà¤¶à¥à¤¯à¤', 'newPassword': 'à¤¨à¤¯à¤¾ à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡', 'noPeople': 'à¤à¤­à¥ à¤à¥à¤ à¤²à¥à¤ à¤¨à¤¹à¥à¤',
      'onlyAdmin': 'à¤à¥à¤µà¤² à¤®à¤¾à¤²à¤¿à¤/à¤à¤¡à¤®à¤¿à¤¨', 'passwordsNotMatch': 'à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡ à¤®à¥à¤² à¤¨à¤¹à¥à¤ à¤à¤¾à¤¤à¥',
      'changePlan': 'à¤ªà¥à¤²à¤¾à¤¨ à¤¬à¤¦à¤²à¥à¤', 'planLabel': 'à¤ªà¥à¤²à¤¾à¤¨', 'planSaved': 'à¤ªà¥à¤²à¤¾à¤¨ à¤¸à¤¹à¥à¤à¤¾', 'gpsNotInPlan': 'GPS à¤à¥à¤°à¥à¤à¤¿à¤à¤ Pro à¤ªà¥à¤²à¤¾à¤¨ à¤¸à¥ à¤à¤ªà¤²à¤¬à¥à¤§', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'à¤²à¥à¤à¥à¤ à¤à¥ à¤¸à¥à¤®à¤¾', 'perMonth': 'à¤®à¤¹à¥à¤¨à¤¾',
      'planChangeOnlyOwner': 'à¤à¥à¤µà¤² à¤®à¤¾à¤²à¤¿à¤ à¤ªà¥à¤²à¤¾à¤¨ à¤¬à¤¦à¤² à¤¸à¤à¤¤à¥ à¤¹à¥à¤à¥¤',
      'selectPlan': 'à¤ªà¥à¤²à¤¾à¤¨ à¤à¥à¤¨à¥à¤', 'supportTitle': 'à¤¸à¤¹à¤¾à¤¯à¤¤à¤¾',
      'supportDesc': 'à¤ªà¥à¤°à¤¶à¥à¤¨à¥à¤ à¤à¥ à¤²à¤¿à¤ à¤¹à¤®à¤¸à¥ à¤¸à¤à¤ªà¤°à¥à¤ à¤à¤°à¥à¤:', 'tariffLimitsTitle': 'à¤à¥à¤°à¤¿à¤« à¤à¤° à¤¸à¥à¤®à¤¾à¤à¤',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'à¤à¤ªà¤¯à¥à¤ à¤à¤¿à¤¯à¤¾ (à¤¸à¤à¥à¤°à¤¿à¤¯)',
      'inactiveNotCountedNote': 'à¤¬à¤°à¥à¤à¤¾à¤¸à¥à¤¤/à¤¨à¤¿à¤·à¥à¤à¥à¤°à¤¿à¤¯ à¤¸à¥à¤®à¤¾ à¤®à¥à¤ à¤¨à¤¹à¥à¤ à¤à¤¿à¤¨à¥ à¤à¤¾à¤¤à¥à¥¤',
      'google': 'Google', 'enterEmailPass': 'à¤à¤®à¥à¤² à¤à¤° à¤ªà¤¾à¤¸à¤µà¤°à¥à¤¡ à¤¦à¤°à¥à¤ à¤à¤°à¥à¤',
      'addTool': 'à¤à¤à¤¼à¤¾à¤° à¤à¥à¤¡à¤¼à¥à¤', 'addEmployee': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤à¥à¤¡à¤¼à¥à¤',
      'inviteCode': 'à¤à¤®à¤à¤¤à¥à¤°à¤£ à¤à¥à¤¡', 'requests': 'à¤à¤¨à¥à¤°à¥à¤§', 'approve': 'à¤¸à¥à¤µà¥à¤à¥à¤¤ à¤à¤°à¥à¤',
      'addPerson': 'à¤µà¥à¤¯à¤à¥à¤¤à¤¿ à¤à¥à¤¡à¤¼à¥à¤', 'decline': 'à¤à¤¸à¥à¤µà¥à¤à¤¾à¤° à¤à¤°à¥à¤',
      'selectToolFirst': 'à¤ªà¤¹à¤²à¥ à¤à¤à¤¼à¤¾à¤° à¤à¥à¤¨à¥à¤', 'selectPersonFirst': 'à¤ªà¤¹à¤²à¥ à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤à¥à¤¨à¥à¤',
      'reportsByTool': 'à¤à¤à¤¼à¤¾à¤° à¤à¥ à¤à¤¨à¥à¤¸à¤¾à¤°', 'reportsByPerson': 'à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤à¥ à¤à¤¨à¥à¤¸à¤¾à¤°',
      'alreadyIn': 'à¤ªà¤¹à¤²à¥ à¤¸à¥ à¤à¤à¤ªà¤¨à¥ à¤®à¥à¤', 'archivedCompany': 'à¤à¤à¤ªà¤¨à¥ à¤¸à¤à¤à¥à¤°à¤¹à¥à¤¤',
      'subscriptionStatusLabel': 'à¤¸à¥à¤¥à¤¿à¤¤à¤¿', 'subscriptionValidUntilLabel': 'à¤¤à¤ à¤µà¥à¤§',
      'subscriptionTest': 'à¤ªà¤°à¥à¤à¥à¤·à¤£ à¤®à¥à¤¡', 'subscriptionLive': 'à¤­à¥à¤à¤¤à¤¾à¤¨ à¤®à¥à¤¡',
      'buyRenewSoon': 'à¤­à¥à¤à¤¤à¤¾à¤¨ à¤à¤²à¥à¤¦ à¤à¤ªà¤²à¤¬à¥à¤§à¥¤ à¤¸à¤¹à¤¾à¤¯à¤¤à¤¾ à¤¸à¥ à¤¸à¤à¤ªà¤°à¥à¤ à¤à¤°à¥à¤à¥¤',
      'billingModeLabel': 'à¤­à¥à¤à¤¤à¤¾à¤¨ à¤®à¥à¤¡', 'emailLabel': 'à¤à¤®à¥à¤²',
      'returnTitle': 'à¤µà¤¾à¤ªà¤¸à¥ à¤à¥ à¤ªà¥à¤·à¥à¤à¤¿ à¤à¤°à¥à¤',
      'myShift': 'à¤®à¥à¤°à¥ à¤ªà¤¾à¤²à¥', 'startShift': 'à¤ªà¤¾à¤²à¥ à¤¶à¥à¤°à¥ à¤à¤°à¥à¤', 'endShift': 'à¤ªà¤¾à¤²à¥ à¤¸à¤®à¤¾à¤ªà¥à¤¤ à¤à¤°à¥à¤',
      'currentShift': 'à¤µà¤°à¥à¤¤à¤®à¤¾à¤¨ à¤ªà¤¾à¤²à¥', 'shiftStarted': 'à¤ªà¤¾à¤²à¥ à¤¶à¥à¤°à¥ à¤¹à¥ à¤à¤!', 'shiftEnded': 'à¤ªà¤¾à¤²à¥ à¤¸à¤®à¤¾à¤ªà¥à¤¤ à¤¹à¥ à¤à¤!',
      'selectSite': 'à¤¸à¤¾à¤à¤ à¤à¥à¤¨à¥à¤', 'noSites': 'à¤à¥à¤ à¤¸à¤¾à¤à¤ à¤¨à¤¹à¥à¤à¥¤ à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤ à¤¸à¥ à¤¸à¤à¤ªà¤°à¥à¤ à¤à¤°à¥à¤à¥¤',
      'writeReport': 'à¤ªà¤¾à¤²à¥ à¤°à¤¿à¤ªà¥à¤°à¥à¤', 'whatDone': 'à¤à¥à¤¯à¤¾ à¤à¤¿à¤¯à¤¾ à¤à¤¯à¤¾', 'timesheets': 'à¤ªà¤¾à¤²à¥ à¤°à¤¿à¤à¥à¤°à¥à¤¡',
      'manageSites': 'à¤¸à¤¾à¤à¤ à¤ªà¥à¤°à¤¬à¤à¤§à¤¨', 'sites': 'à¤¸à¤¾à¤à¤à¥à¤', 'addSite': 'à¤¸à¤¾à¤à¤ à¤à¥à¤¡à¤¼à¥à¤',
      'editSite': 'à¤¸à¤¾à¤à¤ à¤¸à¤à¤ªà¤¾à¤¦à¤¿à¤¤ à¤à¤°à¥à¤', 'siteName': 'à¤¸à¤¾à¤à¤ à¤à¤¾ à¤¨à¤¾à¤®', 'siteAddress': 'à¤ªà¤¤à¤¾',
      'siteRadius': 'à¤à¥à¤-à¤à¤¨ à¤¤à¥à¤°à¤¿à¤à¥à¤¯à¤¾ (à¤®à¥)', 'gpsInterval': 'GPS à¤à¤à¤¤à¤°à¤¾à¤² (à¤®à¤¿à¤¨à¤)',
      'allTime': 'à¤ªà¥à¤°à¥ à¤à¤µà¤§à¤¿',
      'allSites': 'à¤¸à¤­à¥ à¤¸à¤¾à¤à¤à¥à¤',
      'allPeople': 'à¤¸à¤­à¥ à¤à¤°à¥à¤®à¤à¤¾à¤°à¥',
      'exportPdf': 'PDF à¤¨à¤¿à¤°à¥à¤¯à¤¾à¤¤',
      'exportXlsx': 'Excel à¤¨à¤¿à¤°à¥à¤¯à¤¾à¤¤',
      'actPdf': 'à¤à¤§à¤¿à¤¨à¤¿à¤¯à¤® PDF',
      'nakladnayaPdf': 'à¤¡à¤¿à¤²à¥à¤µà¤°à¥ à¤¨à¥à¤ PDF',
      'gpsTrack': 'GPS à¤à¥à¤°à¥à¤',
      'noGpsData': 'à¤à¥à¤ GPS à¤¡à¥à¤à¤¾ à¤¨à¤¹à¥à¤',
      'shiftActive': 'à¤¶à¤¿à¤«à¥à¤ à¤¸à¤à¥à¤°à¤¿à¤¯',
      'shiftStart': 'à¤¶à¥à¤°à¥à¤à¤¤',
      'shiftEnd': 'à¤¸à¤®à¤¾à¤ªà¥à¤¤à¤¿',
      'totalHours': 'à¤à¥à¤² à¤à¤à¤à¥',
      'shiftsCount': 'à¤¶à¤¿à¤«à¥à¤à¥à¤',
      'workReport': 'à¤°à¤¿à¤ªà¥à¤°à¥à¤',
      'myTimesheets': 'à¤®à¥à¤°à¥ à¤¶à¤¿à¤«à¥à¤à¥à¤',
      'allTimesheets': 'à¤¸à¤­à¥ à¤¶à¤¿à¤«à¥à¤à¥à¤',
      'gpsPermissionDenied': 'GPS à¤à¤ªà¤²à¤¬à¥à¤§ à¤¨à¤¹à¥à¤ â à¤¶à¤¿à¤«à¥à¤ à¤¸à¥à¤¥à¤¾à¤¨ à¤¸à¤¤à¥à¤¯à¤¾à¤ªà¤¨ à¤à¥ à¤¬à¤¿à¤¨à¤¾ à¤¶à¥à¤°à¥ à¤¹à¥à¤',
      'gpsWarningTitle': 'à¤¸à¤¾à¤à¤ à¤à¥à¤·à¥à¤¤à¥à¤° à¤¸à¥ à¤¬à¤¾à¤¹à¤°',
      'gpsWarningText': 'à¤à¤ªà¤à¤¾ à¤¸à¥à¤¥à¤¾à¤¨ à¤¸à¤¾à¤à¤ à¤à¥ à¤ªà¤¤à¥ à¤¸à¥ à¤®à¥à¤² à¤¨à¤¹à¥à¤ à¤à¤¾à¤¤à¤¾à¥¤',
      'distance': 'à¤¦à¥à¤°à¥',
      'startAnyway': 'à¤«à¤¿à¤° à¤­à¥ à¤¶à¥à¤°à¥ à¤à¤°à¥à¤',
      'shiftTypeHourly': 'à¤ªà¥à¤°à¤¤à¤¿ à¤à¤à¤à¤¾',
      'shiftTypeAccord': 'à¤¨à¤¿à¤¶à¥à¤à¤¿à¤¤ à¤®à¥à¤²à¥à¤¯',
      'chooseShiftType': 'à¤¶à¤¿à¤«à¥à¤ à¤ªà¥à¤°à¤à¤¾à¤°',
      'shiftType': 'à¤à¤¾à¤°à¥à¤¯ à¤ªà¥à¤°à¤à¤¾à¤°',
      'reportRequired': 'à¤°à¤¿à¤ªà¥à¤°à¥à¤ à¤­à¤°à¥à¤ â à¤à¥à¤¯à¤¾ à¤à¤¿à¤¯à¤¾ à¤à¤¯à¤¾',
      'viewSites': 'à¤¸à¤­à¥ à¤¸à¤¾à¤à¤à¥à¤',
      'navigateTo': 'à¤¨à¥à¤µà¤¿à¤à¥à¤ à¤à¤°à¥à¤',
      'linkUser': 'à¤à¤ªà¤¯à¥à¤à¤à¤°à¥à¤¤à¤¾ à¤²à¤¿à¤à¤ à¤à¤°à¥à¤',
      'linkedUser': 'à¤¸à¥ à¤²à¤¿à¤à¤',
      'unlinkUser': 'à¤à¤¨à¤²à¤¿à¤à¤ à¤à¤°à¥à¤',
      'selectUserToLink': 'à¤à¤ªà¤¯à¥à¤à¤à¤°à¥à¤¤à¤¾ à¤à¥à¤¨à¥à¤',
      'notLinked': 'à¤à¤¾à¤¤à¤¾ à¤ªà¥à¤°à¥à¤«à¤¼à¤¾à¤à¤² à¤¸à¥ à¤²à¤¿à¤à¤ à¤¨à¤¹à¥à¤ à¤¹à¥à¥¤ à¤µà¥à¤¯à¤µà¤¸à¥à¤¥à¤¾à¤ªà¤ à¤¸à¥ à¤¸à¤à¤ªà¤°à¥à¤ à¤à¤°à¥à¤à¥¤',
      'personTypePerson': 'à¤µà¥à¤¯à¤à¥à¤¤à¤¿',
      'personTypeObject': 'à¤µà¤¸à¥à¤¤à¥',
      'noObjects': 'à¤à¤­à¥ à¤à¥à¤ à¤µà¤¸à¥à¤¤à¥ à¤¨à¤¹à¥à¤à¥¤ + à¤¦à¤¬à¤¾à¤à¤',
      'objectCompleted': 'à¤ªà¥à¤°à¥à¤£',
      'markObjectCompleted': 'à¤ªà¥à¤°à¥à¤£ à¤à¥ à¤°à¥à¤ª à¤®à¥à¤ à¤à¤¿à¤¹à¥à¤¨à¤¿à¤¤ à¤à¤°à¥à¤',
      'personTab': 'à¤²à¥à¤',
      'objectTab': 'à¤µà¤¸à¥à¤¤à¥à¤à¤',
      'cannotCompleteHasTools': 'à¤ªà¥à¤°à¤¾ à¤¨à¤¹à¥à¤ à¤à¤° à¤¸à¤à¤¤à¥: à¤µà¤¸à¥à¤¤à¥ à¤ªà¤° {n} à¤à¤ªà¤à¤°à¤£ à¤¹à¥à¤',
      'cannotFireHasTools': 'à¤¬à¤°à¥à¤à¤¾à¤¸à¥à¤¤ à¤¨à¤¹à¥à¤ à¤à¤° à¤¸à¤à¤¤à¥: à¤à¤°à¥à¤®à¤à¤¾à¤°à¥ à¤à¥ à¤ªà¤¾à¤¸ {n} à¤à¤ªà¤à¤°à¤£ à¤¹à¥à¤',
      'addObject': 'à¤µà¤¸à¥à¤¤à¥ à¤à¥à¤¡à¤¼à¥à¤',
      'shiftReminder10hTitle': 'à¤¶à¤¿à¤«à¥à¤ 10 à¤à¤à¤à¥ à¤à¤² à¤°à¤¹à¥ à¤¹à¥',
      'shiftReminder10hBody': 'à¤¶à¤¿à¤«à¥à¤ 10 à¤à¤à¤à¥ à¤¸à¥ à¤à¤§à¤¿à¤ à¤¸à¤à¥à¤°à¤¿à¤¯ à¤¹à¥à¥¤ à¤¬à¤à¤¦ à¤à¤°à¤¨à¤¾ à¤¨ à¤­à¥à¤²à¥à¤à¥¤',
      'shiftReminder12hTitle': 'â ï¸ à¤¶à¤¿à¤«à¥à¤ 12 à¤à¤à¤à¥!',
      'shiftReminder12hBody': 'à¤à¥à¤¤à¤¾à¤µà¤¨à¥: à¤¶à¤¿à¤«à¥à¤ 12 à¤à¤à¤à¥ à¤¸à¥ à¤à¤§à¤¿à¤ à¤à¤² à¤°à¤¹à¥ à¤¹à¥à¥¤ à¤¶à¤¿à¤«à¥à¤ à¤¬à¤à¤¦ à¤à¤°à¥à¤à¥¤',
      'offlineBanner': 'à¤à¥à¤ à¤à¤¨à¥à¤à¥à¤¶à¤¨ à¤¨à¤¹à¥à¤ â¢ à¤à¥à¤¶ à¤¸à¥ à¤¡à¥à¤à¤¾',
      'alreadyHaveActiveShift': 'à¤à¤ªà¤à¥ à¤ªà¤¾à¤¸ à¤ªà¤¹à¤²à¥ à¤¸à¥ à¤à¤ à¤¸à¤à¥à¤°à¤¿à¤¯ à¤¶à¤¿à¤«à¥à¤ à¤¹à¥à¥¤ à¤¨à¤ à¤¶à¥à¤°à¥ à¤à¤°à¤¨à¥ à¤¸à¥ à¤ªà¤¹à¤²à¥ à¤¬à¤à¤¦ à¤à¤°à¥à¤à¥¤',
      'forceCloseShift': 'à¤à¤¬à¤°à¤¦à¤¸à¥à¤¤à¥ à¤¬à¤à¤¦ à¤à¤°à¥à¤',
      'forceCloseShiftHint': 'à¤¶à¤¿à¤«à¥à¤ à¤à¤­à¥ à¤¬à¤à¤¦ à¤¹à¥à¤à¥à¥¤ à¤à¤ª à¤°à¤¿à¤ªà¥à¤°à¥à¤ à¤à¥à¤¡à¤¼ à¤¸à¤à¤¤à¥ à¤¹à¥à¤à¥¤',
      'shiftClosed': 'à¤¶à¤¿à¤«à¥à¤ à¤¬à¤à¤¦ à¤¹à¥ à¤à¤à¥¤',
      'archive': 'à¤¸à¤à¤à¥à¤°à¤¹',
      'noArchive': 'à¤¸à¤à¤à¥à¤°à¤¹ à¤à¤¾à¤²à¥ à¤¹à¥',
      'notifications': 'à¤¸à¥à¤à¤¨à¤¾à¤à¤',
      'noNotifications': 'à¤à¥à¤ à¤¨à¤ à¤¸à¥à¤à¤¨à¤¾ à¤¨à¤¹à¥à¤',
      'newMemberRequest': 'à¤¨à¤¯à¤¾ à¤¶à¤¾à¤®à¤¿à¤² à¤¹à¥à¤¨à¥ à¤à¤¾ à¤à¤¨à¥à¤°à¥à¤§',
      'markAllRead': 'à¤¸à¤­à¥ à¤à¥ à¤ªà¤¢à¤¼à¤¾ à¤¹à¥à¤ à¤à¤¿à¤¹à¥à¤¨à¤¿à¤¤ à¤à¤°à¥à¤',
      'copyTool': 'à¤à¥à¤ªà¥ à¤à¤°à¥à¤',
      'toolCopied': 'à¤à¤ªà¤à¤°à¤£ à¤à¥à¤ªà¥ à¤à¤¿à¤¯à¤¾ à¤à¤¯à¤¾',
      'sortNameAZ': 'à¤¨à¤¾à¤® à¤-à¤à¤¼',
      'sortCountDesc': 'à¤¬à¤¡à¤¼à¥ à¤¸à¤®à¥à¤¹ à¤ªà¤¹à¤²à¥',
      'sortDateDesc': 'à¤¨à¤µà¥à¤¨à¤¤à¤® à¤ªà¤¹à¤²à¥',
      'darkTheme': 'à¤¡à¤¾à¤°à¥à¤ à¤¥à¥à¤®',
      'lightTheme': 'à¤²à¤¾à¤à¤ à¤¥à¥à¤®',
      'systemTheme': 'à¤¸à¤¿à¤¸à¥à¤à¤® à¤¥à¥à¤®',
      'printQr': 'QR à¤ªà¥à¤°à¤¿à¤à¤ à¤à¤°à¥à¤',
      'saveAsPng': 'PNG à¤¸à¤¹à¥à¤à¥à¤',
      'thermalLabel': 'à¤¥à¤°à¥à¤®à¤² à¤²à¥à¤¬à¤²',
      'printAllQr': 'à¤¸à¤­à¥ QR à¤¶à¥à¤ à¤ªà¤°',
      'noResults': 'à¤à¥à¤ à¤¨à¤¹à¥à¤ à¤®à¤¿à¤²à¤¾',
    },

    AppLang.ko: {
      'appTitle': 'ToolKeeper', 'login': 'ë¡ê·¸ì¸', 'register': 'íìê°ì', 'enter': 'ë¡ê·¸ì¸',
      'logout': 'ë¡ê·¸ìì', 'people': 'ì¬ëë¤', 'tools': 'ëêµ¬', 'tool': 'ëêµ¬',
      'inv': 'ì¬ê³  ë²í¸', 'issue': 'ëì¶', 'profile': 'íë¡í', 'chooseLang': 'ì¸ì´ ì í',
      'companyNotFound': 'íì¬ë¥¼ ì°¾ì ì ìì', 'noAccessCompany': 'íì¬ì ì ê·¼ ë¶ê°',
      'leaveCompany': 'ëê°ê¸° / ë¤ë¥¸ íì¬', 'createCompany': 'íì¬ ë§ë¤ê¸°',
      'joinCompany': 'ì°¸ê°', 'or': 'ëë', 'companyName': 'íì¬ ì´ë¦',
      'role': 'ì­í ', 'role_owner': 'ìì ì', 'role_admin': 'ê´ë¦¬ì',
      'role_foreman': 'íì¥ ê°ë', 'role_employee': 'ì§ì',
      'save': 'ì ì¥', 'cancel': 'ì·¨ì', 'add': 'ì¶ê°', 'delete': 'ì­ì ',
      'noEmployees': 'ì§ì ìì', 'noTools': 'ëêµ¬ ìì',
      'issued': 'ëì¶ë¨', 'returned': 'ë°ë©ë¨', 'history': 'ê¸°ë¡',
      'total': 'í©ê³', 'pcs': 'ê°', 'loading': 'ë¡ë© ì¤...', 'error': 'ì¤ë¥', 'ok': 'íì¸',
      'issueUpper': 'ëì¶', 'returnUpper': 'ë°ë©', 'noName': 'ì´ë¦ ìì',
      'confirmReturn': 'ë°ë©', 'confirmIssue': 'ëì¶',
      'issueTab': 'ëì¶', 'returnTab': 'ë°ë©',
      'searchByNameOrPhone': 'ì´ë¦ ëë ì íë²í¸ë¡ ê²ì...',
      'birthDate': 'ìëìì¼', 'clothesSize': 'ìë¥ ì¬ì´ì¦', 'company': 'íì¬',
      'continue': 'ê³ì', 'done': 'ìë£', 'firstName': 'ì´ë¦', 'lastName': 'ì±',
      'password': 'ë¹ë°ë²í¸', 'position': 'ì§ì', 'reports': 'ë³´ê³ ì', 'welcome': 'íìí©ëë¤',
      'email': 'ì´ë©ì¼', 'employee': 'ì§ì', 'employees': 'ì§ìë¤',
      'owner': 'ìì ì', 'admin': 'ê´ë¦¬ì', 'worker': 'ì§ì',
      'employeeStatus': 'ì§ì ìí', 'empStatusActive': 'íì±', 'empStatusFired': 'í´ê³ ë¨',
      'toolStatus': 'ëêµ¬ ìí', 'toolStatusActive': 'íì±', 'toolStatusRepair': 'ìë¦¬ ì¤',
      'toolStatusDisposed': 'íê¸°ë¨', 'statusNote': 'ë©ëª¨',
      'warehouse': 'ì°½ê³ ', 'where': 'ì´ë', 'issuedAt': 'ëì¶ì¼', 'noData': 'ë°ì´í° ìì',
      'subscriptionTitle': 'êµ¬ë', 'subscriptionActive': 'íì±', 'subscriptionInactive': 'ë¹íì±',
      'buyRenew': 'êµ¬ë§¤ / ê°±ì ', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'ë¨¼ì  ì¬ëì ì¶ê°íì¸ì', 'needToolsFirst': 'ë¨¼ì  ëêµ¬ë¥¼ ì¶ê°íì¸ì',
      'noFreeTool': 'ì¬ì© ê°ë¥í ëêµ¬ ìì', 'person': 'ì¬ë', 'returnTool': 'ë°ë©',
      'versionLabel': 'ë²ì ', 'lang': 'ì¸ì´', 'selectPerson': 'ì§ì ì í',
      'onHandsTotal': 'ë³´ì  ì¤: {n}ê°', 'toolsCountLabel': 'ëêµ¬: {n}ê°', 'whoLabel': 'ìì§ì: {name}',
      'noReturnTool': 'ë°ë©í  ëêµ¬ ìì', 'noCompany': 'ì íë íì¬ ìì',
      'reportFilterHint': 'íí°...', 'reportsPeople': 'ëê° ë¬´ìì (ì¬ëë³)',
      'reportsTools': 'ëêµ¬ ìì¹', 'searchByNameOrInv': 'ì´ë¦ ëë ë²í¸ë¡ ê²ì...',
      'needAccount': 'ê³ì  íì', 'newPassword': 'ì ë¹ë°ë²í¸', 'noPeople': 'ìì§ ì¬ë ìì',
      'onlyAdmin': 'ìì ì/ê´ë¦¬ìë§', 'passwordsNotMatch': 'ë¹ë°ë²í¸ê° ì¼ì¹íì§ ììµëë¤',
      'changePlan': 'íë ë³ê²½', 'planLabel': 'íë', 'planSaved': 'íë ì ì¥ë¨', 'gpsNotInPlan': 'GPS ì¶ì ì Pro íëë¶í° ì´ì© ê°ë¥', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'ì¸ì íë', 'perMonth': 'ì',
      'planChangeOnlyOwner': 'ìì ìë§ íëì ë³ê²½í  ì ììµëë¤.',
      'selectPlan': 'íë ì í', 'supportTitle': 'ì§ì',
      'supportDesc': 'ë¬¸ìì¬í­ì ì°ë½ì£¼ì¸ì:', 'tariffLimitsTitle': 'ìê¸ ë° íë',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'ì¬ì©ë¨ (íì±)',
      'inactiveNotCountedNote': 'í´ê³ /ë¹íì±ì íëì í¬í¨ëì§ ììµëë¤.',
      'google': 'Google', 'enterEmailPass': 'ì´ë©ì¼ê³¼ ë¹ë°ë²í¸ ìë ¥',
      'addTool': 'ëêµ¬ ì¶ê°', 'addEmployee': 'ì§ì ì¶ê°',
      'inviteCode': 'ì´ë ì½ë', 'requests': 'ìì²­', 'approve': 'ì¹ì¸',
      'addPerson': 'ì¬ë ì¶ê°', 'decline': 'ê±°ì ',
      'selectToolFirst': 'ë¨¼ì  ëêµ¬ë¥¼ ì ííì¸ì', 'selectPersonFirst': 'ë¨¼ì  ì§ìì ì ííì¸ì',
      'reportsByTool': 'ëêµ¬ë³', 'reportsByPerson': 'ì§ìë³',
      'alreadyIn': 'ì´ë¯¸ íì¬ì ìì', 'archivedCompany': 'íì¬ ë³´ê´ë¨',
      'subscriptionStatusLabel': 'ìí', 'subscriptionValidUntilLabel': 'ì í¨ê¸°ê°',
      'subscriptionTest': 'íì¤í¸ ëª¨ë', 'subscriptionLive': 'ì ë£ ëª¨ë',
      'buyRenewSoon': 'ê²°ì  ê³§ ê°ë¥. ì§ìíì ë¬¸ìíì¸ì.',
      'billingModeLabel': 'ê²°ì  ëª¨ë', 'emailLabel': 'ì´ë©ì¼',
      'returnTitle': 'ë°ë© íì¸',
      'myShift': 'ë´ ê·¼ë¬´', 'startShift': 'ê·¼ë¬´ ìì', 'endShift': 'ê·¼ë¬´ ì¢ë£',
      'currentShift': 'íì¬ ê·¼ë¬´', 'shiftStarted': 'ê·¼ë¬´ê° ììëììµëë¤!', 'shiftEnded': 'ê·¼ë¬´ê° ì¢ë£ëììµëë¤!',
      'selectSite': 'íì¥ ì í', 'noSites': 'íì¥ì´ ììµëë¤. ê´ë¦¬ììê² ë¬¸ìíì¸ì.',
      'writeReport': 'ê·¼ë¬´ ë³´ê³ ì', 'whatDone': 'ìíí ìì', 'timesheets': 'ê·¼ë¬´ ê¸°ë¡',
      'manageSites': 'íì¥ ê´ë¦¬', 'sites': 'íì¥', 'addSite': 'íì¥ ì¶ê°',
      'editSite': 'íì¥ í¸ì§', 'siteName': 'íì¥ ì´ë¦', 'siteAddress': 'ì£¼ì',
      'siteRadius': 'ì²´í¬ì¸ ë°ê²½ (m)', 'gpsInterval': 'GPS ê°ê²© (ë¶)',
      'allTime': 'ì ì²´ ê¸°ê°',
      'allSites': 'ëª¨ë  íì¥',
      'allPeople': 'ëª¨ë  ì§ì',
      'exportPdf': 'PDF ë´ë³´ë´ê¸°',
      'exportXlsx': 'Excel ë´ë³´ë´ê¸°',
      'actPdf': 'ì¦ì PDF',
      'nakladnayaPdf': 'ì¸ëì¥ PDF',
      'gpsTrack': 'GPS ì¶ì ',
      'noGpsData': 'GPS ë°ì´í° ìì',
      'shiftActive': 'êµë ì§í ì¤',
      'shiftStart': 'ìì',
      'shiftEnd': 'ì¢ë£',
      'totalHours': 'ì´ ìê°',
      'shiftsCount': 'êµë',
      'workReport': 'ë³´ê³ ì',
      'myTimesheets': 'ë´ êµë',
      'allTimesheets': 'ëª¨ë  êµë',
      'gpsPermissionDenied': 'GPS ì¬ì© ë¶ê° â ìì¹ íì¸ ìì´ êµë ììë¨',
      'gpsWarningTitle': 'íì¥ êµ¬ì­ ë°',
      'gpsWarningText': 'íì¬ ìì¹ê° íì¥ ì£¼ìì ì¼ì¹íì§ ììµëë¤.',
      'distance': 'ê±°ë¦¬',
      'startAnyway': 'ê·¸ëë ìì',
      'shiftTypeHourly': 'ìê°ì ',
      'shiftTypeAccord': 'ê³ ì  ê°ê²©',
      'chooseShiftType': 'êµë ì í',
      'shiftType': 'ìì ì í',
      'reportRequired': 'ë³´ê³ ìë¥¼ ìì±íì¸ì â ë¬´ìì íëì§',
      'viewSites': 'ëª¨ë  íì¥',
      'navigateTo': 'ê¸¸ ìë´',
      'linkUser': 'ì¬ì©ì ì°ê²°',
      'linkedUser': 'ì°ê²°ë',
      'unlinkUser': 'ì°ê²° í´ì ',
      'selectUserToLink': 'ì¬ì©ì ì í',
      'notLinked': 'ê³ì ì´ íë¡íì ì°ê²°ëì§ ìììµëë¤. ê´ë¦¬ììê² ë¬¸ìíì¸ì.',
      'personTypePerson': 'ì¬ë',
      'personTypeObject': 'ê°ì²´',
      'noObjects': 'ìì§ ê°ì²´ ìì. + ëë¥´ê¸°',
      'objectCompleted': 'ìë£',
      'markObjectCompleted': 'ìë£ë¡ íì',
      'personTab': 'ì¬ë',
      'objectTab': 'ê°ì²´',
      'cannotCompleteHasTools': 'ìë£í  ì ìì: ê°ì²´ì {n}ê° ëêµ¬ ìì',
      'cannotFireHasTools': 'í´ê³ í  ì ìì: ì§ììê² {n}ê° ëêµ¬ ìì',
      'addObject': 'ê°ì²´ ì¶ê°',
      'shiftReminder10hTitle': 'êµë 10ìê° ì§í ì¤',
      'shiftReminder10hBody': 'êµëê° 10ìê° ì´ì íì±íëììµëë¤. ë«ë ê²ì ìì§ ë§ì¸ì.',
      'shiftReminder12hTitle': 'â ï¸ êµë 12ìê°!',
      'shiftReminder12hBody': 'ê²½ê³ : êµëê° 12ìê° ì´ì ì§í ì¤ìëë¤. êµëë¥¼ ë«ì¼ì¸ì.',
      'offlineBanner': 'ì°ê²° ìì â¢ ìºì ë°ì´í°',
      'alreadyHaveActiveShift': 'ì´ë¯¸ íì± êµëê° ììµëë¤. ì êµëë¥¼ ììíê¸° ì ì ë«ì¼ì¸ì.',
      'forceCloseShift': 'ê°ì  ì¢ë£',
      'forceCloseShiftHint': 'êµëê° ì§ê¸ ì¢ë£ë©ëë¤. ë³´ê³ ìë¥¼ ì¶ê°í  ì ììµëë¤.',
      'shiftClosed': 'êµëê° ì¢ë£ëììµëë¤.',
      'archive': 'ë³´ê´í¨',
      'noArchive': 'ë³´ê´í¨ì´ ë¹ì´ ììµëë¤',
      'notifications': 'ìë¦¼',
      'noNotifications': 'ì ìë¦¼ ìì',
      'newMemberRequest': 'ì ê°ì ìì²­',
      'markAllRead': 'ëª¨ë ì½ìì¼ë¡ íì',
      'copyTool': 'ë³µì¬',
      'toolCopied': 'ëêµ¬ê° ë³µì¬ëììµëë¤',
      'sortNameAZ': 'ì´ë¦ ê°-í£',
      'sortCountDesc': 'í° ê·¸ë£¹ ë¨¼ì ',
      'sortDateDesc': 'ìµì  ì',
      'darkTheme': 'ì´ëì´ íë§',
      'lightTheme': 'ë°ì íë§',
      'systemTheme': 'ìì¤í íë§',
      'printQr': 'QR ì¸ì',
      'saveAsPng': 'PNG ì ì¥',
      'thermalLabel': 'ì´ ë¼ë²¨',
      'printAllQr': 'ëª¨ë  QR ìí¸ì',
      'noResults': 'ê²°ê³¼ ìì',
    },

    AppLang.ja: {
      'appTitle': 'ToolKeeper', 'login': 'ã­ã°ã¤ã³', 'register': 'ç»é²', 'enter': 'ã­ã°ã¤ã³',
      'logout': 'ã­ã°ã¢ã¦ã', 'people': 'äººå¡', 'tools': 'å·¥å·', 'tool': 'å·¥å·',
      'inv': 'å¨åº«çªå·', 'issue': 'è²¸åº', 'profile': 'ãã­ãã£ã¼ã«', 'chooseLang': 'è¨èªãé¸æ',
      'companyNotFound': 'ä¼ç¤¾ãè¦ã¤ããã¾ãã', 'noAccessCompany': 'ä¼ç¤¾ã¸ã®ã¢ã¯ã»ã¹ãªã',
      'leaveCompany': 'éåº / å¥ã®ä¼ç¤¾', 'createCompany': 'ä¼ç¤¾ãä½æ',
      'joinCompany': 'åå ', 'or': 'ã¾ãã¯', 'companyName': 'ä¼ç¤¾å',
      'role': 'å½¹å²', 'role_owner': 'ãªã¼ãã¼', 'role_admin': 'ç®¡çè',
      'role_foreman': 'ç¾å ´ç£ç£', 'role_employee': 'å¾æ¥­å¡',
      'save': 'ä¿å­', 'cancel': 'ã­ã£ã³ã»ã«', 'add': 'è¿½å ', 'delete': 'åé¤',
      'noEmployees': 'å¾æ¥­å¡ãªã', 'noTools': 'å·¥å·ãªã',
      'issued': 'è²¸åºæ¸', 'returned': 'è¿å´æ¸', 'history': 'å±¥æ­´',
      'total': 'åè¨', 'pcs': 'å', 'loading': 'èª­ã¿è¾¼ã¿ä¸­...', 'error': 'ã¨ã©ã¼', 'ok': 'OK',
      'issueUpper': 'è²¸åº', 'returnUpper': 'è¿å´', 'noName': 'ååãªã',
      'confirmReturn': 'è¿å´', 'confirmIssue': 'è²¸åº',
      'issueTab': 'è²¸åº', 'returnTab': 'è¿å´',
      'searchByNameOrPhone': 'ååã¾ãã¯é»è©±çªå·ã§æ¤ç´¢...',
      'birthDate': 'çå¹´ææ¥', 'clothesSize': 'æã®ãµã¤ãº', 'company': 'ä¼ç¤¾',
      'continue': 'ç¶ãã', 'done': 'å®äº', 'firstName': 'å', 'lastName': 'å§',
      'password': 'ãã¹ã¯ã¼ã', 'position': 'å½¹è·', 'reports': 'ã¬ãã¼ã', 'welcome': 'ãããã',
      'email': 'ã¡ã¼ã«', 'employee': 'å¾æ¥­å¡', 'employees': 'å¾æ¥­å¡',
      'owner': 'ãªã¼ãã¼', 'admin': 'ç®¡çè', 'worker': 'å¾æ¥­å¡',
      'employeeStatus': 'å¾æ¥­å¡ã¹ãã¼ã¿ã¹', 'empStatusActive': 'ã¢ã¯ãã£ã', 'empStatusFired': 'è§£éæ¸',
      'toolStatus': 'å·¥å·ã¹ãã¼ã¿ã¹', 'toolStatusActive': 'ã¢ã¯ãã£ã', 'toolStatusRepair': 'ä¿®çä¸­',
      'toolStatusDisposed': 'å»æ£æ¸', 'statusNote': 'ã¡ã¢',
      'warehouse': 'ååº«', 'where': 'ã©ã', 'issuedAt': 'è²¸åºæ¥', 'noData': 'ãã¼ã¿ãªã',
      'subscriptionTitle': 'ãµãã¹ã¯', 'subscriptionActive': 'ã¢ã¯ãã£ã', 'subscriptionInactive': 'éã¢ã¯ãã£ã',
      'buyRenew': 'è³¼å¥ / æ´æ°', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'ã¾ãäººå¡ãè¿½å ', 'needToolsFirst': 'ã¾ãå·¥å·ãè¿½å ',
      'noFreeTool': 'å©ç¨å¯è½ãªå·¥å·ãªã', 'person': 'äºº', 'returnTool': 'è¿å´',
      'versionLabel': 'ãã¼ã¸ã§ã³', 'lang': 'è¨èª', 'selectPerson': 'å¾æ¥­å¡ãé¸æ',
      'onHandsTotal': 'ä¿æä¸­: {n}å', 'toolsCountLabel': 'å·¥å·: {n}å', 'whoLabel': 'ä¿æè: {name}',
      'noReturnTool': 'è¿å´ããå·¥å·ãããã¾ãã', 'noCompany': 'ä¼ç¤¾ãé¸æããã¦ãã¾ãã',
      'reportFilterHint': 'ãã£ã«ã¿ã¼...', 'reportsPeople': 'èª°ãä½ãæã£ã¦ããã',
      'reportsTools': 'å·¥å·ã®å ´æ', 'searchByNameOrInv': 'ååã¾ãã¯çªå·ã§æ¤ç´¢...',
      'needAccount': 'ã¢ã«ã¦ã³ããå¿è¦', 'newPassword': 'æ°ãããã¹ã¯ã¼ã', 'noPeople': 'ã¾ã äººå¡ãªã',
      'onlyAdmin': 'ãªã¼ãã¼/ç®¡çèã®ã¿', 'passwordsNotMatch': 'ãã¹ã¯ã¼ããä¸è´ãã¾ãã',
      'changePlan': 'ãã©ã³ãå¤æ´', 'planLabel': 'ãã©ã³', 'planSaved': 'ãã©ã³ãä¿å­ãã¾ãã', 'gpsNotInPlan': 'GPSè¿½è·¡ã¯Proãã©ã³ä»¥ä¸ã§å©ç¨å¯è½', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'äººå¡ä¸é', 'perMonth': 'æ',
      'planChangeOnlyOwner': 'ãªã¼ãã¼ã®ã¿ãã©ã³ãå¤æ´ã§ãã¾ãã',
      'selectPlan': 'ãã©ã³ãé¸æ', 'supportTitle': 'ãµãã¼ã',
      'supportDesc': 'ãè³ªåã¯ãåãåãããã ãã:', 'tariffLimitsTitle': 'æéã¨ä¸é',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'ä½¿ç¨ä¸­ï¼ã¢ã¯ãã£ãï¼',
      'inactiveNotCountedNote': 'è§£é/éã¢ã¯ãã£ãã¯ä¸éã«å«ã¾ãã¾ããã',
      'google': 'Google', 'enterEmailPass': 'ã¡ã¼ã«ã¨ãã¹ã¯ã¼ããå¥å',
      'addTool': 'å·¥å·ãè¿½å ', 'addEmployee': 'å¾æ¥­å¡ãè¿½å ',
      'inviteCode': 'æå¾ã³ã¼ã', 'requests': 'ãªã¯ã¨ã¹ã', 'approve': 'æ¿èª',
      'addPerson': 'äººå¡ãè¿½å ', 'decline': 'æå¦',
      'selectToolFirst': 'ã¾ãå·¥å·ãé¸æ', 'selectPersonFirst': 'ã¾ãå¾æ¥­å¡ãé¸æ',
      'reportsByTool': 'å·¥å·å¥', 'reportsByPerson': 'å¾æ¥­å¡å¥',
      'alreadyIn': 'æ¢ã«ä¼ç¤¾ã«ãã¾ã', 'archivedCompany': 'ä¼ç¤¾ãã¢ã¼ã«ã¤ããã¾ãã',
      'subscriptionStatusLabel': 'ã¹ãã¼ã¿ã¹', 'subscriptionValidUntilLabel': 'æå¹æé',
      'subscriptionTest': 'ãã¹ãã¢ã¼ã', 'subscriptionLive': 'ææã¢ã¼ã',
      'buyRenewSoon': 'éããªãå©ç¨å¯è½ããµãã¼ãã¸ãåãåãããã ããã',
      'billingModeLabel': 'æ¯æãã¢ã¼ã', 'emailLabel': 'ã¡ã¼ã«',
      'returnTitle': 'è¿å´ãç¢ºèª',
      'myShift': 'ç§ã®ã·ãã', 'startShift': 'ã·ããéå§', 'endShift': 'ã·ããçµäº',
      'currentShift': 'ç¾å¨ã®ã·ãã', 'shiftStarted': 'ã·ãããå§ã¾ãã¾ãã!', 'shiftEnded': 'ã·ãããçµäºãã¾ãã!',
      'selectSite': 'ç¾å ´ãé¸æ', 'noSites': 'ç¾å ´ãããã¾ãããç®¡çèã«é£çµ¡ãã¦ãã ããã',
      'writeReport': 'ã·ããã¬ãã¼ã', 'whatDone': 'è¡ã£ããã¨', 'timesheets': 'ã·ããè¨é²',
      'manageSites': 'ç¾å ´ç®¡ç', 'sites': 'ç¾å ´', 'addSite': 'ç¾å ´ãè¿½å ',
      'editSite': 'ç¾å ´ãç·¨é', 'siteName': 'ç¾å ´å', 'siteAddress': 'ä½æ',
      'siteRadius': 'ãã§ãã¯ã¤ã³åå¾ (m)', 'gpsInterval': 'GPSééï¼åï¼',
      'allTime': 'å¨æé',
      'allSites': 'å¨ç¾å ´',
      'allPeople': 'å¨å¾æ¥­å¡',
      'exportPdf': 'PDFåºå',
      'exportXlsx': 'Excelåºå',
      'actPdf': 'è¨¼æ¸ PDF',
      'nakladnayaPdf': 'ç´åæ¸ PDF',
      'gpsTrack': 'GPSè¿½è·¡',
      'noGpsData': 'GPSãã¼ã¿ãªã',
      'shiftActive': 'ã·ããä¸­',
      'shiftStart': 'éå§',
      'shiftEnd': 'çµäº',
      'totalHours': 'åè¨æé',
      'shiftsCount': 'ã·ãã',
      'workReport': 'å ±åæ¸',
      'myTimesheets': 'èªåã®ã·ãã',
      'allTimesheets': 'å¨ã·ãã',
      'gpsPermissionDenied': 'GPSå©ç¨ä¸å¯ â ä½ç½®ç¢ºèªãªãã§ã·ããéå§',
      'gpsWarningTitle': 'ç¾å ´ã¾ã¼ã³å¤',
      'gpsWarningText': 'ç¾å¨å°ãç¾å ´ã®ä½æã¨ä¸è´ãã¾ããã',
      'distance': 'è·é¢',
      'startAnyway': 'ã¨ã«ããéå§',
      'shiftTypeHourly': 'æéå¶',
      'shiftTypeAccord': 'åºå®ä¾¡æ ¼',
      'chooseShiftType': 'ã·ããã¿ã¤ã',
      'shiftType': 'ä½æ¥­ã¿ã¤ã',
      'reportRequired': 'å ±åæ¸ãå¥åãã¦ãã ãã â ä½ãããã',
      'viewSites': 'å¨ç¾å ´',
      'navigateTo': 'ãã',
      'linkUser': 'ã¦ã¼ã¶ã¼ããªã³ã¯',
      'linkedUser': 'ãªã³ã¯å',
      'unlinkUser': 'ãªã³ã¯è§£é¤',
      'selectUserToLink': 'ã¦ã¼ã¶ã¼ãé¸æ',
      'notLinked': 'ã¢ã«ã¦ã³ãã¯ãã­ãã¡ã¤ã«ã«ãªã³ã¯ããã¦ãã¾ãããç®¡çèã«é£çµ¡ãã¦ãã ããã',
      'personTypePerson': 'äººç©',
      'personTypeObject': 'ãªãã¸ã§ã¯ã',
      'noObjects': 'ã¾ã ãªãã¸ã§ã¯ããªãã+ ãæ¼ãã¦ãã ãã',
      'objectCompleted': 'å®äº',
      'markObjectCompleted': 'å®äºã¨ãã¦ãã¼ã¯',
      'personTab': 'äººç©',
      'objectTab': 'ãªãã¸ã§ã¯ã',
      'cannotCompleteHasTools': 'å®äºã§ãã¾ããï¼ãªãã¸ã§ã¯ãã«{n}åã®å·¥å·ãããã¾ã',
      'cannotFireHasTools': 'è§£éã§ãã¾ããï¼å¾æ¥­å¡ã«{n}åã®å·¥å·ãããã¾ã',
      'addObject': 'ãªãã¸ã§ã¯ãè¿½å ',
      'shiftReminder10hTitle': 'ã·ããã10æéç¶ãã¦ãã¾ã',
      'shiftReminder10hBody': 'ã·ããã10æéä»¥ä¸ã¢ã¯ãã£ãã§ããéãããã¨ãå¿ããªãã§ãã ããã',
      'shiftReminder12hTitle': 'â ï¸ ã·ãã12æéï¼',
      'shiftReminder12hBody': 'è­¦åï¼ã·ããã12æéä»¥ä¸ç¶ãã¦ãã¾ããã·ãããéãã¦ãã ããã',
      'offlineBanner': 'æ¥ç¶ãªã â¢ ã­ã£ãã·ã¥ãã¼ã¿',
      'alreadyHaveActiveShift': 'ã¢ã¯ãã£ããªã·ããããã§ã«ããã¾ããæ°ããã·ãããéå§ããåã«éãã¦ãã ããã',
      'forceCloseShift': 'å¼·å¶çµäº',
      'forceCloseShiftHint': 'ã·ããã¯ä»ããçµäºãã¾ããå ±åæ¸ãè¿½å ã§ãã¾ãã',
      'shiftClosed': 'ã·ãããçµäºãã¾ããã',
      'archive': 'ã¢ã¼ã«ã¤ã',
      'noArchive': 'ã¢ã¼ã«ã¤ãã¯ç©ºã§ã',
      'notifications': 'éç¥',
      'noNotifications': 'æ°ããéç¥ãªã',
      'newMemberRequest': 'æ°ããåå ãªã¯ã¨ã¹ã',
      'markAllRead': 'ãã¹ã¦æ¢èª­ã«ãã',
      'copyTool': 'ã³ãã¼',
      'toolCopied': 'å·¥å·ãã³ãã¼ããã¾ãã',
      'sortNameAZ': 'åå ã¢-ã³',
      'sortCountDesc': 'å¤§ã°ã«ã¼ããåã«',
      'sortDateDesc': 'æ°ããé ',
      'darkTheme': 'ãã¼ã¯ãã¼ã',
      'lightTheme': 'ã©ã¤ããã¼ã',
      'systemTheme': 'ã·ã¹ãã ãã¼ã',
      'printQr': 'QRå°å·',
      'saveAsPng': 'PNGä¿å­',
      'thermalLabel': 'ç­ææ ç­¾',
      'printAllQr': 'å¨é¨QRæå°å°çº¸',
      'noResults': 'çµæãªã',
    },

    AppLang.zh: {
      'appTitle': 'ToolKeeper', 'login': 'ç»å½', 'register': 'æ³¨å', 'enter': 'ç»å½',
      'logout': 'éåº', 'people': 'äººå', 'tools': 'å·¥å·', 'tool': 'å·¥å·',
      'inv': 'åºå­ç¼å·', 'issue': 'åæ¾', 'profile': 'ä¸ªäººèµæ', 'chooseLang': 'éæ©è¯­è¨',
      'companyNotFound': 'æ¾ä¸å°å¬å¸', 'noAccessCompany': 'æ æ³è®¿é®å¬å¸',
      'leaveCompany': 'éåº / éæ©å¶ä»å¬å¸', 'createCompany': 'åå»ºå¬å¸',
      'joinCompany': 'å å¥', 'or': 'æ', 'companyName': 'å¬å¸åç§°',
      'role': 'è§è²', 'role_owner': 'ææè', 'role_admin': 'ç®¡çå',
      'role_foreman': 'å·¥å¤´', 'role_employee': 'åå·¥',
      'save': 'ä¿å­', 'cancel': 'åæ¶', 'add': 'æ·»å ', 'delete': 'å é¤',
      'noEmployees': 'æ²¡æåå·¥', 'noTools': 'æ²¡æå·¥å·',
      'issued': 'å·²åæ¾', 'returned': 'å·²å½è¿', 'history': 'åå²è®°å½',
      'total': 'æ»è®¡', 'pcs': 'ä»¶', 'loading': 'å è½½ä¸­...', 'error': 'éè¯¯', 'ok': 'ç¡®å®',
      'issueUpper': 'åæ¾', 'returnUpper': 'å½è¿', 'noName': 'æ åç§°',
      'confirmReturn': 'å½è¿', 'confirmIssue': 'åæ¾',
      'issueTab': 'åæ¾', 'returnTab': 'å½è¿',
      'searchByNameOrPhone': 'æå§åæçµè¯æç´¢...',
      'birthDate': 'åºçæ¥æ', 'clothesSize': 'æè£å°ºç ', 'company': 'å¬å¸',
      'continue': 'ç»§ç»­', 'done': 'å®æ', 'firstName': 'å', 'lastName': 'å§',
      'password': 'å¯ç ', 'position': 'èä½', 'reports': 'æ¥å', 'welcome': 'æ¬¢è¿',
      'email': 'çµå­é®ä»¶', 'employee': 'åå·¥', 'employees': 'åå·¥',
      'owner': 'ææè', 'admin': 'ç®¡çå', 'worker': 'åå·¥',
      'employeeStatus': 'åå·¥ç¶æ', 'empStatusActive': 'æ´»è·', 'empStatusFired': 'å·²è§£é',
      'toolStatus': 'å·¥å·ç¶æ', 'toolStatusActive': 'æ´»è·', 'toolStatusRepair': 'ç»´ä¿®ä¸­',
      'toolStatusDisposed': 'å·²æ¥åº', 'statusNote': 'å¤æ³¨',
      'warehouse': 'ä»åº', 'where': 'å¨åª', 'issuedAt': 'åæ¾æ¥æ', 'noData': 'æ æ°æ®',
      'subscriptionTitle': 'è®¢é', 'subscriptionActive': 'æ´»è·', 'subscriptionInactive': 'éæ´»è·',
      'buyRenew': 'è´­ä¹° / ç»­è´¹', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'è¯·åæ·»å äººå', 'needToolsFirst': 'è¯·åæ·»å å·¥å·',
      'noFreeTool': 'æ²¡æå¯ç¨å·¥å·', 'person': 'äººå', 'returnTool': 'å½è¿',
      'versionLabel': 'çæ¬', 'lang': 'è¯­è¨', 'selectPerson': 'éæ©åå·¥',
      'onHandsTotal': 'ææ: {n}ä»¶', 'toolsCountLabel': 'å·¥å·: {n}ä»¶', 'whoLabel': 'ææè: {name}',
      'noReturnTool': 'æ²¡æå¯å½è¿çå·¥å·', 'noCompany': 'æªéæ©å¬å¸',
      'reportFilterHint': 'ç­é...', 'reportsPeople': 'è°ææä»ä¹ï¼æäººåï¼',
      'reportsTools': 'å·¥å·å¨åªé', 'searchByNameOrInv': 'æåç§°æç¼å·æç´¢...',
      'needAccount': 'éè¦è´¦æ·', 'newPassword': 'æ°å¯ç ', 'noPeople': 'è¿æ²¡æäººå',
      'onlyAdmin': 'ä»ææè/ç®¡çå', 'passwordsNotMatch': 'å¯ç ä¸å¹é',
      'changePlan': 'æ´æ¹è®¡å', 'planLabel': 'è®¡å', 'planSaved': 'è®¡åå·²ä¿å­', 'gpsNotInPlan': 'GPSè¿½è¸ªéç¨äºProåä»¥ä¸å¥é¤', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'äººåéå¶', 'perMonth': 'æ',
      'planChangeOnlyOwner': 'åªæææèæè½æ´æ¹è®¡åã',
      'selectPlan': 'éæ©è®¡å', 'supportTitle': 'æ¯æ',
      'supportDesc': 'å¦æé®é¢è¯·èç³»æä»¬:', 'tariffLimitsTitle': 'èµè´¹åéå¶',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'å·²ä½¿ç¨ï¼æ´»è·ï¼',
      'inactiveNotCountedNote': 'ç¦»è/éæ´»è·ä¸è®¡å¥éå¶ã',
      'google': 'Google', 'enterEmailPass': 'è¾å¥é®ç®±åå¯ç ',
      'addTool': 'æ·»å å·¥å·', 'addEmployee': 'æ·»å åå·¥',
      'inviteCode': 'éè¯·ç ', 'requests': 'è¯·æ±', 'approve': 'æ¹å',
      'addPerson': 'æ·»å äººå', 'decline': 'æç»',
      'selectToolFirst': 'è¯·åéæ©å·¥å·', 'selectPersonFirst': 'è¯·åéæ©åå·¥',
      'reportsByTool': 'æå·¥å·', 'reportsByPerson': 'æåå·¥',
      'alreadyIn': 'å·²å¨å¬å¸ä¸­', 'archivedCompany': 'å¬å¸å·²å½æ¡£',
      'subscriptionStatusLabel': 'ç¶æ', 'subscriptionValidUntilLabel': 'æææè³',
      'subscriptionTest': 'æµè¯æ¨¡å¼', 'subscriptionLive': 'ä»è´¹æ¨¡å¼',
      'buyRenewSoon': 'ä»æ¬¾å³å°å¼æ¾ãè¯·èç³»æ¯æã',
      'billingModeLabel': 'ä»æ¬¾æ¨¡å¼', 'emailLabel': 'é®ç®±',
      'returnTitle': 'ç¡®è®¤å½è¿',
      'myShift': 'æçç­æ¬¡', 'startShift': 'å¼å§ç­æ¬¡', 'endShift': 'ç»æç­æ¬¡',
      'currentShift': 'å½åç­æ¬¡', 'shiftStarted': 'ç­æ¬¡å·²å¼å§ï¼', 'shiftEnded': 'ç­æ¬¡å·²ç»æï¼',
      'selectSite': 'éæ©å·¥å°', 'noSites': 'æ²¡æå·¥å°ãè¯·èç³»ç®¡çåã',
      'writeReport': 'ç­æ¬¡æ¥å', 'whatDone': 'å®æäºä»ä¹', 'timesheets': 'ç­æ¬¡è®°å½',
      'manageSites': 'ç®¡çå·¥å°', 'sites': 'å·¥å°', 'addSite': 'æ·»å å·¥å°',
      'editSite': 'ç¼è¾å·¥å°', 'siteName': 'å·¥å°åç§°', 'siteAddress': 'å°å',
      'siteRadius': 'æå¡åå¾ (m)', 'gpsInterval': 'GPSé´éï¼åéï¼',
      'allTime': 'å¨é¨æ¶é´',
      'allSites': 'ææå·¥å°',
      'allPeople': 'ææåå·¥',
      'exportPdf': 'å¯¼åºPDF',
      'exportXlsx': 'å¯¼åºExcel',
      'actPdf': 'å­è¯ PDF',
      'nakladnayaPdf': 'éè´§å PDF',
      'gpsTrack': 'GPSè½¨è¿¹',
      'noGpsData': 'æ GPSæ°æ®',
      'shiftActive': 'ç­æ¬¡è¿è¡ä¸­',
      'shiftStart': 'å¼å§',
      'shiftEnd': 'ç»æ',
      'totalHours': 'æ»å°æ¶æ°',
      'shiftsCount': 'ç­æ¬¡',
      'workReport': 'æ¥å',
      'myTimesheets': 'æçç­æ¬¡',
      'allTimesheets': 'ææç­æ¬¡',
      'gpsPermissionDenied': 'GPSä¸å¯ç¨ â ç­æ¬¡å¨æ²¡æä½ç½®éªè¯çæåµä¸å¼å§',
      'gpsWarningTitle': 'å¨å·¥å°åºåå¤',
      'gpsWarningText': 'æ¨çä½ç½®ä¸å·¥å°å°åä¸ç¬¦ã',
      'distance': 'è·ç¦»',
      'startAnyway': 'ä»ç¶å¼å§',
      'shiftTypeHourly': 'æå°æ¶',
      'shiftTypeAccord': 'åºå®ä»·æ ¼',
      'chooseShiftType': 'ç­æ¬¡ç±»å',
      'shiftType': 'å·¥ä½ç±»å',
      'reportRequired': 'å¡«åæ¥å â å®æäºä»ä¹',
      'viewSites': 'ææå·¥å°',
      'navigateTo': 'å¯¼èª',
      'linkUser': 'å³èç¨æ·',
      'linkedUser': 'å³èå°',
      'unlinkUser': 'åæ¶å³è',
      'selectUserToLink': 'éæ©ç¨æ·',
      'notLinked': 'è´¦æ·æªå³èå°ä¸ªäººèµæãè¯·èç³»ç®¡çåã',
      'personTypePerson': 'äººå',
      'personTypeObject': 'å¯¹è±¡',
      'noObjects': 'è¿æ²¡æå¯¹è±¡ãç¹å» +',
      'objectCompleted': 'å·²å®æ',
      'markObjectCompleted': 'æ è®°ä¸ºå®æ',
      'personTab': 'äººå',
      'objectTab': 'å¯¹è±¡',
      'cannotCompleteHasTools': 'æ æ³å®æï¼å¯¹è±¡ä¸æ {n} ä»¶å·¥å·',
      'cannotFireHasTools': 'æ æ³è§£éï¼åå·¥æ {n} ä»¶å·¥å·',
      'addObject': 'æ·»å å¯¹è±¡',
      'shiftReminder10hTitle': 'ç­æ¬¡å·²æç»­10å°æ¶',
      'shiftReminder10hBody': 'ç­æ¬¡å·²æ´»è·è¶è¿10å°æ¶ãå«å¿äºå³é­ã',
      'shiftReminder12hTitle': 'â ï¸ ç­æ¬¡12å°æ¶ï¼',
      'shiftReminder12hBody': 'è­¦åï¼ç­æ¬¡å·²æç»­è¶è¿12å°æ¶ãè¯·å³é­ç­æ¬¡ã',
      'offlineBanner': 'æ è¿æ¥ â¢ æ¥èªç¼å­çæ°æ®',
      'alreadyHaveActiveShift': 'æ¨å·²ç»æä¸ä¸ªæ´»è·ç­æ¬¡ãå¨å¼å§æ°ç­æ¬¡ä¹åè¯·åå³é­å®ã',
      'forceCloseShift': 'å¼ºå¶å³é­',
      'forceCloseShiftHint': 'ç­æ¬¡å°ç«å³å³é­ãæ¨å¯ä»¥æ·»å æ¥åã',
      'shiftClosed': 'ç­æ¬¡å·²å³é­ã',
      'archive': 'æ¡£æ¡',
      'noArchive': 'æ¡£æ¡ä¸ºç©º',
      'notifications': 'éç¥',
      'noNotifications': 'æ²¡ææ°éç¥',
      'newMemberRequest': 'æ°å å¥è¯·æ±',
      'markAllRead': 'å¨é¨æ è®°ä¸ºå·²è¯»',
      'copyTool': 'å¤å¶',
      'toolCopied': 'å·¥å·å·²å¤å¶',
      'sortNameAZ': 'åç§° A-Z',
      'sortCountDesc': 'å¤§ç»ä¼å',
      'sortDateDesc': 'ææ°ä¼å',
      'darkTheme': 'æ·±è²ä¸»é¢',
      'lightTheme': 'æµè²ä¸»é¢',
      'systemTheme': 'ç³»ç»ä¸»é¢',
      'printQr': 'æå°QR',
      'saveAsPng': 'ä¿å­PNG',
      'thermalLabel': 'ç­ææ ç­¾',
      'printAllQr': 'ææQRå°é¡µé¢',
      'noResults': 'æ ç»æ',
    },

    AppLang.id: {
      'appTitle': 'ToolKeeper', 'login': 'Masuk', 'register': 'Daftar', 'enter': 'Masuk',
      'logout': 'Keluar', 'people': 'Orang', 'tools': 'Alat', 'tool': 'Alat',
      'inv': 'No. inv.', 'issue': 'Pengeluaran', 'profile': 'Profil', 'chooseLang': 'Pilih bahasa',
      'companyNotFound': 'Perusahaan tidak ditemukan', 'noAccessCompany': 'Tidak ada akses ke perusahaan',
      'leaveCompany': 'Keluar / pilih lain', 'createCompany': 'Buat perusahaan',
      'joinCompany': 'Bergabung', 'or': 'ATAU', 'companyName': 'Nama perusahaan',
      'role': 'Peran', 'role_owner': 'Pemilik', 'role_admin': 'Administrator',
      'role_foreman': 'Mandor', 'role_employee': 'Karyawan',
      'save': 'Simpan', 'cancel': 'Batal', 'add': 'Tambah', 'delete': 'Hapus',
      'noEmployees': 'Tidak ada karyawan', 'noTools': 'Tidak ada alat',
      'issued': 'Dikeluarkan', 'returned': 'Dikembalikan', 'history': 'Riwayat',
      'total': 'Total', 'pcs': 'pcs', 'loading': 'Memuat...', 'error': 'Kesalahan', 'ok': 'OK',
      'issueUpper': 'KELUARKAN', 'returnUpper': 'KEMBALIKAN', 'noName': 'Tanpa nama',
      'confirmReturn': 'Kembalikan', 'confirmIssue': 'Keluarkan',
      'issueTab': 'Pengeluaran', 'returnTab': 'Pengembalian',
      'searchByNameOrPhone': 'Cari berdasarkan nama atau telepon...',
      'birthDate': 'Tanggal lahir', 'clothesSize': 'Ukuran pakaian', 'company': 'Perusahaan',
      'continue': 'Lanjutkan', 'done': 'Selesai', 'firstName': 'Nama', 'lastName': 'Nama belakang',
      'password': 'Kata sandi', 'position': 'Jabatan', 'reports': 'Laporan', 'welcome': 'Selamat datang',
      'email': 'Email', 'employee': 'Karyawan', 'employees': 'Karyawan',
      'owner': 'Pemilik', 'admin': 'Admin', 'worker': 'Karyawan',
      'employeeStatus': 'Status karyawan', 'empStatusActive': 'Aktif', 'empStatusFired': 'Dipecat',
      'toolStatus': 'Status alat', 'toolStatusActive': 'Aktif', 'toolStatusRepair': 'Dalam perbaikan',
      'toolStatusDisposed': 'Dibuang', 'statusNote': 'Catatan',
      'warehouse': 'Gudang', 'where': 'Di mana', 'issuedAt': 'Dikeluarkan', 'noData': 'Tidak ada data',
      'subscriptionTitle': 'Langganan', 'subscriptionActive': 'Aktif', 'subscriptionInactive': 'Tidak aktif',
      'buyRenew': 'Beli / Perpanjang', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Tambahkan orang terlebih dahulu', 'needToolsFirst': 'Tambahkan alat terlebih dahulu',
      'noFreeTool': 'Tidak ada alat bebas', 'person': 'Orang', 'returnTool': 'Kembalikan',
      'versionLabel': 'Versi', 'lang': 'Bahasa', 'selectPerson': 'Pilih karyawan',
      'onHandsTotal': 'Dipegang: {n} pcs', 'toolsCountLabel': 'Alat: {n}', 'whoLabel': 'Pemegang: {name}',
      'noReturnTool': 'Tidak ada alat untuk dikembalikan', 'noCompany': 'Tidak ada perusahaan dipilih',
      'reportFilterHint': 'Filter...', 'reportsPeople': 'Siapa yang memegang apa',
      'reportsTools': 'Di mana alat berada', 'searchByNameOrInv': 'Cari berdasarkan nama atau no...',
      'needAccount': 'Akun diperlukan', 'newPassword': 'Kata sandi baru', 'noPeople': 'Belum ada orang',
      'onlyAdmin': 'Hanya pemilik/admin', 'passwordsNotMatch': 'Kata sandi tidak cocok',
      'changePlan': 'Ubah paket', 'planLabel': 'Paket', 'planSaved': 'Paket disimpan', 'gpsNotInPlan': 'Pelacakan GPS tersedia dari paket Pro ke atas', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Batas orang', 'perMonth': 'bulan',
      'planChangeOnlyOwner': 'Hanya pemilik yang dapat mengubah paket.',
      'selectPlan': 'Pilih paket', 'supportTitle': 'Dukungan',
      'supportDesc': 'Untuk pertanyaan, hubungi kami:', 'tariffLimitsTitle': 'Tarif dan batas',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Digunakan (aktif)',
      'inactiveNotCountedNote': 'Yang dipecat/tidak aktif tidak dihitung.',
      'google': 'Google', 'enterEmailPass': 'Masukkan email dan kata sandi',
      'addTool': 'Tambah alat', 'addEmployee': 'Tambah karyawan',
      'inviteCode': 'Kode undangan', 'requests': 'Permintaan', 'approve': 'Setujui',
      'addPerson': 'Tambah orang', 'decline': 'Tolak',
      'selectToolFirst': 'Pilih alat terlebih dahulu', 'selectPersonFirst': 'Pilih karyawan terlebih dahulu',
      'reportsByTool': 'Per alat', 'reportsByPerson': 'Per karyawan',
      'alreadyIn': 'Sudah di perusahaan', 'archivedCompany': 'Perusahaan diarsipkan',
      'subscriptionStatusLabel': 'Status', 'subscriptionValidUntilLabel': 'Berlaku hingga',
      'subscriptionTest': 'Mode uji', 'subscriptionLive': 'Mode berbayar',
      'buyRenewSoon': 'Pembayaran segera tersedia. Hubungi dukungan.',
      'billingModeLabel': 'Mode pembayaran', 'emailLabel': 'Email',
      'returnTitle': 'Konfirmasi pengembalian',
      'myShift': 'Shift saya', 'startShift': 'Mulai shift', 'endShift': 'Akhiri shift',
      'currentShift': 'Shift saat ini', 'shiftStarted': 'Shift dimulai!', 'shiftEnded': 'Shift selesai!',
      'selectSite': 'Pilih lokasi', 'noSites': 'Tidak ada lokasi. Hubungi administrator.',
      'writeReport': 'Laporan shift', 'whatDone': 'Apa yang dikerjakan', 'timesheets': 'Absensi shift',
      'manageSites': 'Kelola lokasi', 'sites': 'Lokasi', 'addSite': 'Tambah lokasi',
      'editSite': 'Edit lokasi', 'siteName': 'Nama lokasi', 'siteAddress': 'Alamat',
      'siteRadius': 'Radius check-in (m)', 'gpsInterval': 'Interval GPS (mnt)',
      'allTime': 'Semua waktu',
      'allSites': 'Semua lokasi',
      'allPeople': 'Semua karyawan',
      'exportPdf': 'Ekspor PDF',
      'exportXlsx': 'Ekspor Excel',
      'actPdf': 'Akte PDF',
      'nakladnayaPdf': 'Surat Jalan PDF',
      'gpsTrack': 'Jejak GPS',
      'noGpsData': 'Tidak ada data GPS',
      'shiftActive': 'Shift aktif',
      'shiftStart': 'Mulai',
      'shiftEnd': 'Selesai',
      'totalHours': 'Total jam',
      'shiftsCount': 'Shift',
      'workReport': 'Laporan',
      'myTimesheets': 'Shift saya',
      'allTimesheets': 'Semua shift',
      'gpsPermissionDenied': 'GPS tidak tersedia â shift dimulai tanpa verifikasi lokasi',
      'gpsWarningTitle': 'Di luar zona lokasi',
      'gpsWarningText': 'Lokasi Anda tidak sesuai dengan alamat lokasi.',
      'distance': 'Jarak',
      'startAnyway': 'Mulai tetap saja',
      'shiftTypeHourly': 'Per jam',
      'shiftTypeAccord': 'Harga tetap',
      'chooseShiftType': 'Jenis shift',
      'shiftType': 'Jenis pekerjaan',
      'reportRequired': 'Isi laporan â apa yang telah dilakukan',
      'viewSites': 'Semua lokasi',
      'navigateTo': 'Navigasi',
      'linkUser': 'Hubungkan pengguna',
      'linkedUser': 'Terhubung ke',
      'unlinkUser': 'Putuskan hubungan',
      'selectUserToLink': 'Pilih pengguna',
      'notLinked': 'Akun tidak terhubung ke profil. Hubungi administrator.',
      'personTypePerson': 'Orang',
      'personTypeObject': 'Objek',
      'noObjects': 'Belum ada objek. Ketuk +',
      'objectCompleted': 'Selesai',
      'markObjectCompleted': 'Tandai sebagai selesai',
      'personTab': 'Orang',
      'objectTab': 'Objek',
      'cannotCompleteHasTools': 'Tidak dapat diselesaikan: {n} alat di objek',
      'cannotFireHasTools': 'Tidak dapat dipecat: karyawan memiliki {n} alat',
      'addObject': 'Tambah objek',
      'shiftReminder10hTitle': 'Shift berlangsung 10 jam',
      'shiftReminder10hBody': 'Shift aktif lebih dari 10 jam. Jangan lupa untuk menutupnya.',
      'shiftReminder12hTitle': 'â ï¸ Shift 12 jam!',
      'shiftReminder12hBody': 'Peringatan: shift berjalan lebih dari 12 jam. Tutup shift.',
      'offlineBanner': 'Tidak ada koneksi â¢ data dari cache',
      'alreadyHaveActiveShift': 'Anda sudah memiliki shift aktif. Tutup sebelum memulai yang baru.',
      'forceCloseShift': 'Paksa tutup',
      'forceCloseShiftHint': 'Shift akan ditutup sekarang. Anda dapat menambahkan laporan.',
      'shiftClosed': 'Shift ditutup.',
      'archive': 'Arsip',
      'noArchive': 'Arsip kosong',
      'notifications': 'Notifikasi',
      'noNotifications': 'Tidak ada notifikasi baru',
      'newMemberRequest': 'Permintaan bergabung baru',
      'markAllRead': 'Tandai semua sudah dibaca',
      'copyTool': 'Salin',
      'toolCopied': 'Alat disalin',
      'sortNameAZ': 'Nama A-Z',
      'sortCountDesc': 'Grup besar lebih dulu',
      'sortDateDesc': 'Terbaru lebih dulu',
      'darkTheme': 'Tema gelap',
      'lightTheme': 'Tema terang',
      'systemTheme': 'Tema sistem',
      'printQr': 'Cetak QR',
      'saveAsPng': 'Simpan PNG',
      'thermalLabel': 'Label termal',
      'printAllQr': 'Semua QR ke lembar',
      'noResults': 'Tidak ditemukan',
    },

    AppLang.vi: {
      'appTitle': 'ToolKeeper', 'login': 'ÄÄng nháº­p', 'register': 'ÄÄng kÃ½', 'enter': 'ÄÄng nháº­p',
      'logout': 'ÄÄng xuáº¥t', 'people': 'Má»i ngÆ°á»i', 'tools': 'Dá»¥ng cá»¥', 'tool': 'Dá»¥ng cá»¥',
      'inv': 'MÃ£ kiá»m kÃª', 'issue': 'Cáº¥p phÃ¡t', 'profile': 'Há» sÆ¡', 'chooseLang': 'Chá»n ngÃ´n ngá»¯',
      'companyNotFound': 'KhÃ´ng tÃ¬m tháº¥y cÃ´ng ty', 'noAccessCompany': 'KhÃ´ng cÃ³ quyá»n truy cáº­p',
      'leaveCompany': 'ThoÃ¡t / chá»n cÃ´ng ty khÃ¡c', 'createCompany': 'Táº¡o cÃ´ng ty',
      'joinCompany': 'Tham gia', 'or': 'HOáº¶C', 'companyName': 'TÃªn cÃ´ng ty',
      'role': 'Vai trÃ²', 'role_owner': 'Chá»§ sá» há»¯u', 'role_admin': 'Quáº£n trá» viÃªn',
      'role_foreman': 'Äá»c cÃ´ng', 'role_employee': 'NhÃ¢n viÃªn',
      'save': 'LÆ°u', 'cancel': 'Há»§y', 'add': 'ThÃªm', 'delete': 'XÃ³a',
      'noEmployees': 'KhÃ´ng cÃ³ nhÃ¢n viÃªn', 'noTools': 'KhÃ´ng cÃ³ dá»¥ng cá»¥',
      'issued': 'ÄÃ£ cáº¥p', 'returned': 'ÄÃ£ tráº£', 'history': 'Lá»ch sá»­',
      'total': 'Tá»ng cá»ng', 'pcs': 'cÃ¡i', 'loading': 'Äang táº£i...', 'error': 'Lá»i', 'ok': 'OK',
      'issueUpper': 'Cáº¤P PHÃT', 'returnUpper': 'TRáº¢ Láº I', 'noName': 'KhÃ´ng cÃ³ tÃªn',
      'confirmReturn': 'Tráº£ láº¡i', 'confirmIssue': 'Cáº¥p phÃ¡t',
      'issueTab': 'Cáº¥p phÃ¡t', 'returnTab': 'Tráº£ láº¡i',
      'searchByNameOrPhone': 'TÃ¬m theo tÃªn hoáº·c sá» Äiá»n thoáº¡i...',
      'birthDate': 'NgÃ y sinh', 'clothesSize': 'Cá»¡ quáº§n Ã¡o', 'company': 'CÃ´ng ty',
      'continue': 'Tiáº¿p tá»¥c', 'done': 'Xong', 'firstName': 'TÃªn', 'lastName': 'Há»',
      'password': 'Máº­t kháº©u', 'position': 'Chá»©c vá»¥', 'reports': 'BÃ¡o cÃ¡o', 'welcome': 'ChÃ o má»«ng',
      'email': 'Email', 'employee': 'NhÃ¢n viÃªn', 'employees': 'NhÃ¢n viÃªn',
      'owner': 'Chá»§ sá» há»¯u', 'admin': 'Quáº£n trá»', 'worker': 'CÃ´ng nhÃ¢n',
      'employeeStatus': 'Tráº¡ng thÃ¡i nhÃ¢n viÃªn', 'empStatusActive': 'Hoáº¡t Äá»ng', 'empStatusFired': 'ÄÃ£ sa tháº£i',
      'toolStatus': 'Tráº¡ng thÃ¡i dá»¥ng cá»¥', 'toolStatusActive': 'Hoáº¡t Äá»ng', 'toolStatusRepair': 'Äang sá»­a chá»¯a',
      'toolStatusDisposed': 'ÄÃ£ thanh lÃ½', 'statusNote': 'Ghi chÃº',
      'warehouse': 'Kho', 'where': 'á» ÄÃ¢u', 'issuedAt': 'ÄÃ£ cáº¥p', 'noData': 'KhÃ´ng cÃ³ dá»¯ liá»u',
      'subscriptionTitle': 'ÄÄng kÃ½', 'subscriptionActive': 'Hoáº¡t Äá»ng', 'subscriptionInactive': 'KhÃ´ng hoáº¡t Äá»ng',
      'buyRenew': 'Mua / Gia háº¡n', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'ThÃªm ngÆ°á»i trÆ°á»c', 'needToolsFirst': 'ThÃªm dá»¥ng cá»¥ trÆ°á»c',
      'noFreeTool': 'KhÃ´ng cÃ³ dá»¥ng cá»¥ trá»ng', 'person': 'NgÆ°á»i', 'returnTool': 'Tráº£ láº¡i',
      'versionLabel': 'PhiÃªn báº£n', 'lang': 'NgÃ´n ngá»¯', 'selectPerson': 'Chá»n nhÃ¢n viÃªn',
      'onHandsTotal': 'Äang giá»¯: {n} cÃ¡i', 'toolsCountLabel': 'Dá»¥ng cá»¥: {n}', 'whoLabel': 'NgÆ°á»i giá»¯: {name}',
      'noReturnTool': 'KhÃ´ng cÃ³ dá»¥ng cá»¥ Äá» tráº£', 'noCompany': 'ChÆ°a chá»n cÃ´ng ty',
      'reportFilterHint': 'Lá»c...', 'reportsPeople': 'Ai giá»¯ gÃ¬ (theo ngÆ°á»i)',
      'reportsTools': 'Dá»¥ng cá»¥ á» ÄÃ¢u', 'searchByNameOrInv': 'TÃ¬m theo tÃªn hoáº·c mÃ£...',
      'needAccount': 'Cáº§n tÃ i khoáº£n', 'newPassword': 'Máº­t kháº©u má»i', 'noPeople': 'ChÆ°a cÃ³ ngÆ°á»i',
      'onlyAdmin': 'Chá» chá»§ sá» há»¯u/admin', 'passwordsNotMatch': 'Máº­t kháº©u khÃ´ng khá»p',
      'changePlan': 'Äá»i gÃ³i', 'planLabel': 'GÃ³i', 'planSaved': 'ÄÃ£ lÆ°u gÃ³i', 'gpsNotInPlan': 'Theo dÃµi GPS kháº£ dá»¥ng tá»« gÃ³i Pro trá» lÃªn', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Giá»i háº¡n ngÆ°á»i', 'perMonth': 'thÃ¡ng',
      'planChangeOnlyOwner': 'Chá» chá»§ sá» há»¯u má»i cÃ³ thá» Äá»i gÃ³i.',
      'selectPlan': 'Chá»n gÃ³i', 'supportTitle': 'Há» trá»£',
      'supportDesc': 'Äá» ÄÆ°á»£c há» trá»£, liÃªn há» chÃºng tÃ´i:', 'tariffLimitsTitle': 'GiÃ¡ vÃ  giá»i háº¡n',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'ÄÃ£ dÃ¹ng (hoáº¡t Äá»ng)',
      'inactiveNotCountedNote': 'ÄÃ£ sa tháº£i/khÃ´ng hoáº¡t Äá»ng khÃ´ng tÃ­nh vÃ o giá»i háº¡n.',
      'google': 'Google', 'enterEmailPass': 'Nháº­p email vÃ  máº­t kháº©u',
      'addTool': 'ThÃªm dá»¥ng cá»¥', 'addEmployee': 'ThÃªm nhÃ¢n viÃªn',
      'inviteCode': 'MÃ£ má»i', 'requests': 'YÃªu cáº§u', 'approve': 'PhÃª duyá»t',
      'addPerson': 'ThÃªm ngÆ°á»i', 'decline': 'Tá»« chá»i',
      'selectToolFirst': 'Chá»n dá»¥ng cá»¥ trÆ°á»c', 'selectPersonFirst': 'Chá»n nhÃ¢n viÃªn trÆ°á»c',
      'reportsByTool': 'Theo dá»¥ng cá»¥', 'reportsByPerson': 'Theo nhÃ¢n viÃªn',
      'alreadyIn': 'ÄÃ£ trong cÃ´ng ty', 'archivedCompany': 'CÃ´ng ty ÄÃ£ lÆ°u trá»¯',
      'subscriptionStatusLabel': 'Tráº¡ng thÃ¡i', 'subscriptionValidUntilLabel': 'CÃ³ hiá»u lá»±c Äáº¿n',
      'subscriptionTest': 'Cháº¿ Äá» thá»­', 'subscriptionLive': 'Cháº¿ Äá» tráº£ phÃ­',
      'buyRenewSoon': 'Thanh toÃ¡n sáº¯p cÃ³. LiÃªn há» há» trá»£.',
      'billingModeLabel': 'Cháº¿ Äá» thanh toÃ¡n', 'emailLabel': 'Email',
      'returnTitle': 'XÃ¡c nháº­n tráº£ láº¡i',
      'myShift': 'Ca lÃ m cá»§a tÃ´i', 'startShift': 'Báº¯t Äáº§u ca', 'endShift': 'Káº¿t thÃºc ca',
      'currentShift': 'Ca hiá»n táº¡i', 'shiftStarted': 'Ca ÄÃ£ báº¯t Äáº§u!', 'shiftEnded': 'Ca ÄÃ£ káº¿t thÃºc!',
      'selectSite': 'Chá»n cÃ´ng trÃ¬nh', 'noSites': 'KhÃ´ng cÃ³ cÃ´ng trÃ¬nh. LiÃªn há» quáº£n trá» viÃªn.',
      'writeReport': 'BÃ¡o cÃ¡o ca lÃ m', 'whatDone': 'ÄÃ£ lÃ m gÃ¬', 'timesheets': 'Cháº¥m cÃ´ng',
      'manageSites': 'Quáº£n lÃ½ cÃ´ng trÃ¬nh', 'sites': 'CÃ´ng trÃ¬nh', 'addSite': 'ThÃªm cÃ´ng trÃ¬nh',
      'editSite': 'Sá»­a cÃ´ng trÃ¬nh', 'siteName': 'TÃªn cÃ´ng trÃ¬nh', 'siteAddress': 'Äá»a chá»',
      'siteRadius': 'BÃ¡n kÃ­nh check-in (m)', 'gpsInterval': 'Khoáº£ng GPS (phÃºt)',
      'allTime': 'ToÃ n bá» thá»i gian',
      'allSites': 'Táº¥t cáº£ cÃ´ng trÃ¬nh',
      'allPeople': 'Táº¥t cáº£ nhÃ¢n viÃªn',
      'exportPdf': 'Xuáº¥t PDF',
      'exportXlsx': 'Xuáº¥t Excel',
      'actPdf': 'BiÃªn báº£n PDF',
      'nakladnayaPdf': 'Phiáº¿u xuáº¥t kho PDF',
      'gpsTrack': 'Theo dÃµi GPS',
      'noGpsData': 'KhÃ´ng cÃ³ dá»¯ liá»u GPS',
      'shiftActive': 'Ca lÃ m viá»c Äang hoáº¡t Äá»ng',
      'shiftStart': 'Báº¯t Äáº§u',
      'shiftEnd': 'Káº¿t thÃºc',
      'totalHours': 'Tá»ng giá»',
      'shiftsCount': 'Ca',
      'workReport': 'BÃ¡o cÃ¡o',
      'myTimesheets': 'Ca cá»§a tÃ´i',
      'allTimesheets': 'Táº¥t cáº£ ca',
      'gpsPermissionDenied': 'GPS khÃ´ng kháº£ dá»¥ng â ca báº¯t Äáº§u mÃ  khÃ´ng xÃ¡c minh vá» trÃ­',
      'gpsWarningTitle': 'NgoÃ i vÃ¹ng cÃ´ng trÆ°á»ng',
      'gpsWarningText': 'Vá» trÃ­ cá»§a báº¡n khÃ´ng khá»p vá»i Äá»a chá» cÃ´ng trÆ°á»ng.',
      'distance': 'Khoáº£ng cÃ¡ch',
      'startAnyway': 'Váº«n báº¯t Äáº§u',
      'shiftTypeHourly': 'Theo giá»',
      'shiftTypeAccord': 'GiÃ¡ cá» Äá»nh',
      'chooseShiftType': 'Loáº¡i ca',
      'shiftType': 'Loáº¡i cÃ´ng viá»c',
      'reportRequired': 'Äiá»n bÃ¡o cÃ¡o â nhá»¯ng gÃ¬ ÄÃ£ lÃ m',
      'viewSites': 'Táº¥t cáº£ cÃ´ng trÆ°á»ng',
      'navigateTo': 'Dáº«n ÄÆ°á»ng',
      'linkUser': 'LiÃªn káº¿t ngÆ°á»i dÃ¹ng',
      'linkedUser': 'LiÃªn káº¿t Äáº¿n',
      'unlinkUser': 'Há»§y liÃªn káº¿t',
      'selectUserToLink': 'Chá»n ngÆ°á»i dÃ¹ng',
      'notLinked': 'TÃ i khoáº£n chÆ°a liÃªn káº¿t há» sÆ¡. LiÃªn há» quáº£n trá» viÃªn.',
      'personTypePerson': 'NgÆ°á»i',
      'personTypeObject': 'Äá»i tÆ°á»£ng',
      'noObjects': 'ChÆ°a cÃ³ Äá»i tÆ°á»£ng. Nháº¥n +',
      'objectCompleted': 'HoÃ n thÃ nh',
      'markObjectCompleted': 'ÄÃ¡nh dáº¥u hoÃ n thÃ nh',
      'personTab': 'NgÆ°á»i',
      'objectTab': 'Äá»i tÆ°á»£ng',
      'cannotCompleteHasTools': 'KhÃ´ng thá» hoÃ n thÃ nh: {n} cÃ´ng cá»¥ trÃªn Äá»i tÆ°á»£ng',
      'cannotFireHasTools': 'KhÃ´ng thá» sa tháº£i: nhÃ¢n viÃªn cÃ³ {n} cÃ´ng cá»¥',
      'addObject': 'ThÃªm Äá»i tÆ°á»£ng',
      'shiftReminder10hTitle': 'Ca lÃ m viá»c kÃ©o dÃ i 10 giá»',
      'shiftReminder10hBody': 'Ca ÄÃ£ hoáº¡t Äá»ng hÆ¡n 10 giá». Äá»«ng quÃªn ÄÃ³ng láº¡i.',
      'shiftReminder12hTitle': 'â ï¸ Ca 12 giá»!',
      'shiftReminder12hBody': 'Cáº£nh bÃ¡o: ca Äang kÃ©o dÃ i hÆ¡n 12 giá». ÄÃ³ng ca.',
      'offlineBanner': 'KhÃ´ng cÃ³ káº¿t ná»i â¢ dá»¯ liá»u tá»« bá» nhá» Äá»m',
      'alreadyHaveActiveShift': 'Báº¡n ÄÃ£ cÃ³ ca lÃ m viá»c Äang hoáº¡t Äá»ng. ÄÃ³ng nÃ³ trÆ°á»c khi báº¯t Äáº§u ca má»i.',
      'forceCloseShift': 'Buá»c ÄÃ³ng',
      'forceCloseShiftHint': 'Ca sáº½ ÄÃ³ng ngay bÃ¢y giá». Báº¡n cÃ³ thá» thÃªm bÃ¡o cÃ¡o.',
      'shiftClosed': 'Ca ÄÃ£ ÄÃ³ng.',
      'archive': 'LÆ°u trá»¯',
      'noArchive': 'LÆ°u trá»¯ trá»ng',
      'notifications': 'ThÃ´ng bÃ¡o',
      'noNotifications': 'KhÃ´ng cÃ³ thÃ´ng bÃ¡o má»i',
      'newMemberRequest': 'YÃªu cáº§u tham gia má»i',
      'markAllRead': 'ÄÃ¡nh dáº¥u táº¥t cáº£ ÄÃ£ Äá»c',
      'copyTool': 'Sao chÃ©p',
      'toolCopied': 'CÃ´ng cá»¥ ÄÃ£ sao chÃ©p',
      'sortNameAZ': 'TÃªn A-Z',
      'sortCountDesc': 'NhÃ³m lá»n trÆ°á»c',
      'sortDateDesc': 'Má»i nháº¥t trÆ°á»c',
      'darkTheme': 'Giao diá»n tá»i',
      'lightTheme': 'Giao diá»n sÃ¡ng',
      'systemTheme': 'Giao diá»n há» thá»ng',
      'printQr': 'In QR',
      'saveAsPng': 'LÆ°u PNG',
      'thermalLabel': 'NhÃ£n nhiá»t',
      'printAllQr': 'Táº¥t cáº£ QR ra trang',
      'noResults': 'KhÃ´ng tÃ¬m tháº¥y',
    },

    AppLang.tl: {
      'appTitle': 'ToolKeeper', 'login': 'Mag-login', 'register': 'Mag-register', 'enter': 'Pumasok',
      'logout': 'Mag-logout', 'people': 'Mga Tao', 'tools': 'Mga Kagamitan', 'tool': 'Kagamitan',
      'inv': 'Inv. no.', 'issue': 'Pag-isyu', 'profile': 'Profile', 'chooseLang': 'Pumili ng wika',
      'companyNotFound': 'Hindi nahanap ang kumpanya', 'noAccessCompany': 'Walang access sa kumpanya',
      'leaveCompany': 'Umalis / pumili ng iba', 'createCompany': 'Lumikha ng kumpanya',
      'joinCompany': 'Sumali', 'or': 'O', 'companyName': 'Pangalan ng kumpanya',
      'role': 'Papel', 'role_owner': 'May-ari', 'role_admin': 'Admin',
      'role_foreman': 'Capataz', 'role_employee': 'Empleyado',
      'save': 'I-save', 'cancel': 'Kanselahin', 'add': 'Idagdag', 'delete': 'Tanggalin',
      'noEmployees': 'Walang empleyado', 'noTools': 'Walang kagamitan',
      'issued': 'Naibigay', 'returned': 'Naibalik', 'history': 'Kasaysayan',
      'total': 'Kabuuan', 'pcs': 'piraso', 'loading': 'Naglo-load...', 'error': 'Error', 'ok': 'OK',
      'issueUpper': 'IBIGAY', 'returnUpper': 'IBALIK', 'noName': 'Walang pangalan',
      'confirmReturn': 'Ibalik', 'confirmIssue': 'Ibigay',
      'issueTab': 'Pag-isyu', 'returnTab': 'Pagbabalik',
      'searchByNameOrPhone': 'Maghanap sa pangalan o telepono...',
      'birthDate': 'Petsa ng kapanganakan', 'clothesSize': 'Sukat ng damit', 'company': 'Kumpanya',
      'continue': 'Magpatuloy', 'done': 'Tapos', 'firstName': 'Pangalan', 'lastName': 'Apelyido',
      'password': 'Password', 'position': 'Posisyon', 'reports': 'Mga Ulat', 'welcome': 'Maligayang pagdating',
      'email': 'Email', 'employee': 'Empleyado', 'employees': 'Mga Empleyado',
      'owner': 'May-ari', 'admin': 'Admin', 'worker': 'Manggagawa',
      'employeeStatus': 'Status ng empleyado', 'empStatusActive': 'Aktibo', 'empStatusFired': 'Tinanggal',
      'toolStatus': 'Status ng kagamitan', 'toolStatusActive': 'Aktibo', 'toolStatusRepair': 'Sa pagkukumpuni',
      'toolStatusDisposed': 'Itinatapon', 'statusNote': 'Tala',
      'warehouse': 'Bodega', 'where': 'Saan', 'issuedAt': 'Naibigay', 'noData': 'Walang data',
      'subscriptionTitle': 'Subscription', 'subscriptionActive': 'Aktibo', 'subscriptionInactive': 'Hindi aktibo',
      'buyRenew': 'Bumili / Mag-renew', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Magdagdag muna ng mga tao', 'needToolsFirst': 'Magdagdag muna ng mga kagamitan',
      'noFreeTool': 'Walang libreng kagamitan', 'person': 'Tao', 'returnTool': 'Ibalik',
      'versionLabel': 'Bersyon', 'lang': 'Wika', 'selectPerson': 'Pumili ng empleyado',
      'onHandsTotal': 'Hawak: {n} piraso', 'toolsCountLabel': 'Kagamitan: {n}', 'whoLabel': 'Sino: {name}',
      'noReturnTool': 'Walang kagamitang ibabalik', 'noCompany': 'Walang kumpanyang pinili',
      'reportFilterHint': 'Filter...', 'reportsPeople': 'Sino ang may hawak ng ano',
      'reportsTools': 'Nasaan ang kagamitan', 'searchByNameOrInv': 'Maghanap sa pangalan o bilang...',
      'needAccount': 'Kailangan ng account', 'newPassword': 'Bagong password', 'noPeople': 'Wala pang tao',
      'onlyAdmin': 'May-ari/admin lamang', 'passwordsNotMatch': 'Hindi magkatugma ang mga password',
      'changePlan': 'Baguhin ang plano', 'planLabel': 'Plano', 'planSaved': 'Nai-save ang plano', 'gpsNotInPlan': 'Available ang GPS tracking mula sa Pro plan pataas', 'gpsIncluded': 'GPS â', 'gpsNotIncluded': 'GPS â',
      'peopleLimitLabel': 'Limitasyon ng tao', 'perMonth': 'buwan',
      'planChangeOnlyOwner': 'Ang may-ari lamang ang maaaring magbago ng plano.',
      'selectPlan': 'Pumili ng plano', 'supportTitle': 'Suporta',
      'supportDesc': 'Para sa mga katanungan, makipag-ugnayan sa amin:', 'tariffLimitsTitle': 'Taripa at limitasyon',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Ginamit (aktibo)',
      'inactiveNotCountedNote': 'Ang tinanggal/hindi aktibo ay hindi binibilang sa limitasyon.',
      'google': 'Google', 'enterEmailPass': 'Ilagay ang email at password',
      'addTool': 'Magdagdag ng kagamitan', 'addEmployee': 'Magdagdag ng empleyado',
      'inviteCode': 'Invitation code', 'requests': 'Mga kahilingan', 'approve': 'Aprubahan',
      'addPerson': 'Magdagdag ng tao', 'decline': 'Tanggihan',
      'selectToolFirst': 'Pumili muna ng kagamitan', 'selectPersonFirst': 'Pumili muna ng empleyado',
      'reportsByTool': 'Ayon sa kagamitan', 'reportsByPerson': 'Ayon sa empleyado',
      'alreadyIn': 'Nasa kumpanya na', 'archivedCompany': 'Kumpanya ay naarchive',
      'subscriptionStatusLabel': 'Status', 'subscriptionValidUntilLabel': 'Hanggang',
      'subscriptionTest': 'Test mode', 'subscriptionLive': 'Bayad na mode',
      'buyRenewSoon': 'Ang bayad ay malapit na available. Makipag-ugnayan sa suporta.',
      'billingModeLabel': 'Mode ng bayad', 'emailLabel': 'Email',
      'returnTitle': 'Kumpirmahin ang pagbabalik',
      'myShift': 'Ang aking shift', 'startShift': 'Simulan ang shift', 'endShift': 'Tapusin ang shift',
      'currentShift': 'Kasalukuyang shift', 'shiftStarted': 'Nagsimula na ang shift!', 'shiftEnded': 'Tapos na ang shift!',
      'selectSite': 'Pumili ng lugar ng trabaho', 'noSites': 'Walang lugar ng trabaho. Makipag-ugnayan sa admin.',
      'writeReport': 'Ulat ng shift', 'whatDone': 'Ano ang nagawa', 'timesheets': 'Rekord ng shift',
      'manageSites': 'Pamahalaan ang mga lugar', 'sites': 'Mga lugar ng trabaho', 'addSite': 'Magdagdag ng lugar',
      'editSite': 'I-edit ang lugar', 'siteName': 'Pangalan ng lugar', 'siteAddress': 'Address',
      'siteRadius': 'Check-in radius (m)', 'gpsInterval': 'GPS agwat (min)',
      'allTime': 'Lahat ng oras',
      'allSites': 'Lahat ng lugar',
      'allPeople': 'Lahat ng empleyado',
      'exportPdf': 'I-export ang PDF',
      'exportXlsx': 'I-export ang Excel',
      'actPdf': 'Akte PDF',
      'nakladnayaPdf': 'Resibo PDF',
      'gpsTrack': 'GPS track',
      'noGpsData': 'Walang GPS data',
      'shiftActive': 'Aktibo ang shift',
      'shiftStart': 'Simula',
      'shiftEnd': 'Katapusan',
      'totalHours': 'Kabuuang oras',
      'shiftsCount': 'Mga shift',
      'workReport': 'Ulat',
      'myTimesheets': 'Aking mga shift',
      'allTimesheets': 'Lahat ng shift',
      'gpsPermissionDenied': 'Hindi available ang GPS â nagsimula ang shift nang walang location check',
      'gpsWarningTitle': 'Labas ng zone ng site',
      'gpsWarningText': 'Hindi tumutugma ang iyong lokasyon sa address ng site.',
      'distance': 'Distansya',
      'startAnyway': 'Magsimula pa rin',
      'shiftTypeHourly': 'Per oras',
      'shiftTypeAccord': 'Naayos na presyo',
      'chooseShiftType': 'Uri ng shift',
      'shiftType': 'Uri ng trabaho',
      'reportRequired': 'Punan ang ulat â ano ang nagawa',
      'viewSites': 'Lahat ng site',
      'navigateTo': 'Mag-navigate',
      'linkUser': 'I-link ang user',
      'linkedUser': 'Naka-link sa',
      'unlinkUser': 'I-unlink',
      'selectUserToLink': 'Pumili ng user',
      'notLinked': 'Ang account ay hindi naka-link sa profile. Makipag-ugnayan sa admin.',
      'personTypePerson': 'Tao',
      'personTypeObject': 'Bagay',
      'noObjects': 'Wala pang bagay. Pindutin ang +',
      'objectCompleted': 'Nakumpleto',
      'markObjectCompleted': 'Markahan bilang nakumpleto',
      'personTab': 'Mga tao',
      'objectTab': 'Mga bagay',
      'cannotCompleteHasTools': 'Hindi makumpleto: {n} kagamitan sa bagay',
      'cannotFireHasTools': 'Hindi matanggal: ang empleyado ay may {n} kagamitan',
      'addObject': 'Magdagdag ng bagay',
      'shiftReminder10hTitle': 'Ang shift ay 10 oras na',
      'shiftReminder10hBody': 'Aktibo ang shift nang mahigit 10 oras. Huwag kalimutang isara.',
      'shiftReminder12hTitle': 'â ï¸ Shift 12 oras!',
      'shiftReminder12hBody': 'Babala: tumatagal na ng mahigit 12 oras ang shift. Isara ang shift.',
      'offlineBanner': 'Walang koneksyon â¢ data mula sa cache',
      'alreadyHaveActiveShift': 'Mayroon ka nang aktibong shift. Isara ito bago magsimula ng bago.',
      'forceCloseShift': 'Puwersahang isara',
      'forceCloseShiftHint': 'Isasara ang shift ngayon. Maaari kang magdagdag ng ulat.',
      'shiftClosed': 'Sarado na ang shift.',
      'archive': 'Arkibo',
      'noArchive': 'Walang laman ang arkibo',
      'notifications': 'Mga abiso',
      'noNotifications': 'Walang bagong abiso',
      'newMemberRequest': 'Bagong kahilingang sumali',
      'markAllRead': 'Markahan lahat bilang nabasa',
      'copyTool': 'Kopyahin',
      'toolCopied': 'Nakopya ang kagamitan',
      'sortNameAZ': 'Pangalan A-Z',
      'sortCountDesc': 'Malalaking grupo muna',
      'sortDateDesc': 'Pinakabago muna',
      'darkTheme': 'Madilim na tema',
      'lightTheme': 'Maliwanag na tema',
      'systemTheme': 'Tema ng sistema',
      'printQr': 'I-print ang QR',
      'saveAsPng': 'I-save ang PNG',
      'thermalLabel': 'Thermal label',
      'printAllQr': 'Lahat ng QR sa pahina',
      'noResults': 'Walang nahanap',
    },

  };

  String t(String key) => _dict[lang]?[key] ?? _dict[AppLang.ru]?[key] ?? key;

  /// Translate with simple {placeholders} replacement.
  /// Example: tf('toolsCount', {'n': '3'}) where dict value is "Tools: {n}".
  String tf(String key, Map<String, String> params) {
    var s = t(key);
    params.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    return s;
  }
}

/// simple app state for language
class AppState extends InheritedNotifier<ValueNotifier<AppLang>> {
  final ValueNotifier<AppLang> lang;

  const AppState({
    super.key,
    required this.lang,
    required Widget child,
  }) : super(notifier: lang, child: child);

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppState>();
    if (s == null) throw Exception("No AppState");
    return s;
  }
}
/// ===================
/// FIRESTORE HELPERS
/// ===================
String uidOrThrow() {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) throw Exception('ÐÐµÑ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ');
  return u.uid;
}

DocumentReference<Map<String, dynamic>> userDoc([String? uid]) {
  final id = uid ?? uidOrThrow();
  return FirebaseFirestore.instance.collection('users').doc(id);
}

CollectionReference<Map<String, dynamic>> companiesRef() {
  return FirebaseFirestore.instance.collection('companies');
}

CollectionReference<Map<String, dynamic>> inviteCodesRef() {
  return FirebaseFirestore.instance.collection('inviteCodes');
}

DocumentReference<Map<String, dynamic>> companyDoc(String companyId) {
  return FirebaseFirestore.instance.collection('companies').doc(companyId);
}

CollectionReference<Map<String, dynamic>> companyPeopleRef(String companyId) {
  return companyDoc(companyId).collection('people');
}

CollectionReference<Map<String, dynamic>> companyToolsRef(String companyId) {
  return companyDoc(companyId).collection('tools');
}

CollectionReference<Map<String, dynamic>> companyMovesRef(String companyId) {
  return companyDoc(companyId).collection('moves');
}

/// True if the latest move for this tool is an "issue" (out == true).
Future<bool> toolIsOnHands(String companyId, String toolId) async {
  final q = await companyMovesRef(companyId).where('toolId', isEqualTo: toolId).get();
  if (q.docs.isEmpty) return false;

  int toMillis(dynamic v) {
    try {
      if (v != null && v.runtimeType.toString() == 'Timestamp') {
        // ignore: avoid_dynamic_calls
        return (v as dynamic).millisecondsSinceEpoch as int;
      }
    } catch (_) {}
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Map<String, dynamic>? latest;
  int latestTs = -1;

  for (final d in q.docs) {
    final m = d.data();
    final ts = toMillis(m['createdAt']);
    if (ts >= latestTs) {
      latestTs = ts;
      latest = m;
    }
  }

  final type = (latest?['type'] ?? '').toString();
  return type == 'out';
}

/// Count tools currently on hands for employee (latest move for that employee is out == true).
Future<int> employeeToolsOnHandsCount(String companyId, String personId) async {
  final q = await companyMovesRef(companyId).where('personId', isEqualTo: personId).get();

  int toMillis(dynamic v) {
    try {
      // Timestamp from cloud_firestore
      // ignore: avoid_dynamic_calls
      if (v != null && v.runtimeType.toString() == 'Timestamp') {
        // ignore: avoid_dynamic_calls
        return (v as dynamic).millisecondsSinceEpoch as int;
      }
    } catch (_) {}
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  // Track latest move per tool by createdAt
  final Map<String, Map<String, dynamic>> latest = {};
  for (final d in q.docs) {
    final m = d.data();
    final toolId = (m['toolId'] ?? '').toString();
    if (toolId.isEmpty) continue;

    final curTs = toMillis(m['createdAt']);
    final prev = latest[toolId];
    if (prev == null) {
      latest[toolId] = m;
      continue;
    }
    final prevTs = toMillis(prev['createdAt']);
    if (curTs >= prevTs) {
      latest[toolId] = m;
    }
  }

  int count = 0;
  for (final m in latest.values) {
    final type = (m['type'] ?? '').toString();
    if (type == 'out') count++;
  }
  return count;
}

DocumentReference<Map<String, dynamic>> companyMemberDoc(String companyId, String uid) {
  return companyDoc(companyId).collection('members').doc(uid);
}

CollectionReference<Map<String, dynamic>> companyMembersRef(String companyId) {
  return companyDoc(companyId).collection('members');
}

CollectionReference<Map<String, dynamic>> companyJoinRequestsRef(String companyId) {
  return companyDoc(companyId).collection('joinRequests');
}

CollectionReference<Map<String, dynamic>> companyNotificationsRef(String companyId) {
  return companyDoc(companyId).collection('notifications');
}

// ============== FIRESTORE REFS FOR TIME TRACKING ==============
CollectionReference<Map<String, dynamic>> companySitesRef(String companyId) {
  return FirebaseFirestore.instance.collection('companies').doc(companyId).collection('sites');
}

CollectionReference<Map<String, dynamic>> companyTimesheetsRef(String companyId) {
  return FirebaseFirestore.instance.collection('companies').doc(companyId).collection('timesheets');
}


/// ===================
/// ROLE / SORT HELPERS
/// ===================
String normText(String s) {
  final lower = s.toLowerCase().trim();
  // â Ð´Ð»Ñ Ð°Ð»ÑÐ°Ð²Ð¸ÑÐ°: "Ñ" ÑÑÐ¸ÑÐ°ÐµÐ¼ ÐºÐ°Ðº "Ðµ"
  return lower.replaceAll('Ñ', 'Ðµ');
}

String normalizeRole(String role) {
  final r = role.toLowerCase().trim();
  if (r == 'owner') return 'owner';
  if (r == 'admin') return 'admin';

  // ÐÑÐ¾ÑÐ°Ð± / Brygadzista (Ð¿Ð¾Ð´Ð´ÐµÑÐ¶ÐºÐ° ÑÑÐ°ÑÑÑ/Ð¾ÑÐ¸Ð±Ð¾ÑÐ½ÑÑ Ð·Ð½Ð°ÑÐµÐ½Ð¸Ð¹)
  if (r == 'foreman' || r == 'foramen' || r == '4man' || r == 'brygadzista' || r == 'Ð¿ÑÐ¾ÑÐ°Ð±') {
    return 'foreman';
  }

  // Ð¿Ð¾Ð´Ð´ÐµÑÐ¶ÐºÐ° ÑÑÐ°ÑÑÑ/Ð¾ÑÐ¸Ð±Ð¾ÑÐ½ÑÑ Ð·Ð½Ð°ÑÐµÐ½Ð¸Ð¹ Ð´Ð»Ñ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ°
  if (r == 'worker' || r == 'employee' || r == 'empire') return 'employee';
  return 'employee';
}


bool isAdminOrOwnerRole(String role) {
  final r = normalizeRole(role);
  return r == 'owner' || r == 'admin';
}

String roleLabel(I18n i18n, String role) {
  switch (normalizeRole(role)) {
    case 'owner':
      return i18n.t('role_owner');
    case 'admin':
      return i18n.t('role_admin');
    case 'foreman':
      return i18n.t('role_foreman');
    default:
      return i18n.t('role_employee');
  }
}



/// ===================
/// AUTH HELPERS
/// ===================
bool get isWindows => Platform.isWindows;

Future<void> signOutAll() async {
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}

/// ===================
/// APP
/// ===================
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ValueNotifier<AppLang> _lang = ValueNotifier<AppLang>(AppLang.ru);

  @override
  void initState() {
    super.initState();
    _loadLang();
  }

  AppLang _langFromLocale(String code) {
    const map = {
      'uk': AppLang.uk, 'pl': AppLang.pl, 'en': AppLang.en,
      'de': AppLang.de, 'fr': AppLang.fr, 'es': AppLang.es,
      'it': AppLang.it, 'pt': AppLang.pt, 'cs': AppLang.cs,
      'ro': AppLang.ro, 'nl': AppLang.nl, 'tr': AppLang.tr,
      'ar': AppLang.ar, 'hi': AppLang.hi, 'ko': AppLang.ko,
      'ja': AppLang.ja, 'zh': AppLang.zh, 'id': AppLang.id,
      'vi': AppLang.vi, 'tl': AppLang.tl,
    };
    return map[code] ?? AppLang.ru;
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_lang');
    if (saved != null) {
      final lang = AppLang.values.where((l) => l.name == saved).firstOrNull;
      if (lang != null) _lang.value = lang;
    } else {
      // First launch â detect from system locale
      final sysCode = ui.PlatformDispatcher.instance.locale.languageCode;
      _lang.value = _langFromLocale(sysCode);
    }
    // Save on every change
    _lang.addListener(() async {
      final p = await SharedPreferences.getInstance();
      p.setString('app_lang', _lang.value.name);
    });
  }

  @override
  void dispose() {
    _lang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppState(
      lang: _lang,
      child: ValueListenableBuilder<AppLang>(
        valueListenable: _lang,
        builder: (_, lang, __) {
          final i18n = I18n(lang);
          return MaterialApp(
            title: i18n.t('appTitle'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
            ),
            themeMode: ThemeMode.system,
            builder: (ctx, child) => _OfflineBanner(i18n: i18n, child: child!),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

// ÐÐ°Ð½Ð½ÐµÑ "Ð½ÐµÑ Ð¸Ð½ÑÐµÑÐ½ÐµÑÐ°" â Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÑÑÑ Ð¿Ð¾Ð²ÐµÑÑ Ð²ÑÐµÐ³Ð¾ Ð¿ÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ñ
class _OfflineBanner extends StatefulWidget {
  final I18n i18n;
  final Widget child;
  const _OfflineBanner({required this.i18n, required this.child});
  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  bool _isOffline = false;
  late final StreamSubscription<List<ConnectivityResult>> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.isNotEmpty &&
          results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) setState(() => _isOffline = offline);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isOffline)
          Material(
            color: Colors.orange.shade800,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(widget.i18n.t('offlineBanner'),
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// ===================
/// AUTH GATE
/// ===================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;

        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (user == null) {
          return const LoginPage();
        }

        return SessionChoicePage(user: user, title: i18n.t('sessionTitle'));
      },
    );
  }
}

/// Ð­ÐºÑÐ°Ð½ Ð²ÑÐ±Ð¾ÑÐ°: Ð¿ÑÐ¾Ð´Ð¾Ð»Ð¶Ð¸ÑÑ / ÑÐ¼ÐµÐ½Ð¸ÑÑ Ð°ÐºÐºÐ°ÑÐ½Ñ / Ð²ÑÐ¹ÑÐ¸
class SessionChoicePage extends StatelessWidget {
  final User user;
  final String title;
  const SessionChoicePage({super.key, required this.user, required this.title});

  Future<void> _switchAccount(BuildContext context) async {
    await signOutAll();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    final email = user.email ?? '(no email)';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text(
              '${i18n.t('alreadyIn')}\n$email',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AppRouter()),
                  );
                },
                child: Text(i18n.t('continue')),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _switchAccount(context),
                child: Text(i18n.t('switchAcc')),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await signOutAll();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthGate()),
                      (_) => false,
                    );
                  }
                },
                child: Text(i18n.t('logout')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// LOGIN / REGISTER
/// ===================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool loading = false;
  String? error;
  bool registerMode = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginOrRegister() async {
    final i18n = I18n(AppState.of(context).lang.value);

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final email = emailCtrl.text.trim();
      final pass = passCtrl.text;

      if (email.isEmpty || pass.isEmpty) {
        throw Exception(i18n.t('enterEmailPass'));
      }

      if (registerMode) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? e.code);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _google() async {
    final i18n = I18n(AppState.of(context).lang.value);

    if (isWindows) {
      setState(() {
        error =
            'Google Ð²ÑÐ¾Ð´ Ð½Ð° Windows Ð½Ðµ Ð¸ÑÐ¿Ð¾Ð»ÑÐ·ÑÐµÐ¼.\n'
            'ÐÑÐ»Ð¸ Ð°ÐºÐºÐ°ÑÐ½Ñ ÑÐ¾Ð·Ð´Ð°Ð²Ð°Ð»ÑÑ ÑÐµÑÐµÐ· Google Ð½Ð° ÑÐµÐ»ÐµÑÐ¾Ð½Ðµ â Ð¿ÑÐ¸Ð²ÑÐ¶Ð¸ Ð¿Ð°ÑÐ¾Ð»Ñ Ð² Ð¿ÑÐ¾ÑÐ¸Ð»Ðµ Ð½Ð° ÑÐµÐ»ÐµÑÐ¾Ð½Ðµ,\n'
            'Ð¸ Ð¿Ð¾ÑÐ¾Ð¼ Ð·Ð°ÑÐ¾Ð´Ð¸ Ð½Ð° ÐÐ Ð¿Ð¾ Email+ÐÐ°ÑÐ¾Ð»Ñ.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final GoogleSignIn googleSignIn = GoogleSignIn(scopes: const ['email']);

    try {
      try { await googleSignIn.disconnect(); } catch (_) {}
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) {
        setState(() => loading = false);
        return;
      }

      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${i18n.t('login')}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    final title = registerMode ? i18n.t('register') : i18n.t('login');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<AppLang>(
            tooltip: i18n.t('chooseLang'),
            icon: const Icon(Icons.language),
            onSelected: (v) => AppState.of(context).lang.value = v,
            itemBuilder: (_) => AppLang.values.map((lang) {
              return PopupMenuItem(value: lang, child: Text(kLangNames[lang] ?? lang.name));
            }).toList(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailCtrl,
              decoration: InputDecoration(labelText: i18n.t('email')),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: i18n.t('password')),
            ),
            const SizedBox(height: 12),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: loading ? null : _loginOrRegister,
                    child: Text(registerMode ? i18n.t('register') : i18n.t('enter')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: loading ? null : () => setState(() => registerMode = !registerMode),
                    child: Text(registerMode ? i18n.t('haveAccount') : i18n.t('needAccount')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(i18n.t('or')),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.login),
                onPressed: loading ? null : _google,
                label: Text(i18n.t('google')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// APP ROUTER
/// ===================
class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  Future<void> _logout(BuildContext context) async {
    await signOutAll();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc().snapshots(),
      builder: (c, s) {
        if (s.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(i18n.t('errUserRead'))),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('${i18n.t('errUserRead')}:\n${s.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => _logout(context), child: Text(i18n.t('logout'))),
                ],
              ),
            ),
          );
        }

        if (!s.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!s.data!.exists) {
          return const EnsureUserDocPage();
        }

        final data = s.data!.data() ?? {};

        final hasProfile = (data['firstName'] ?? '').toString().trim().isNotEmpty &&
            (data['lastName'] ?? '').toString().trim().isNotEmpty &&
            (data['phone'] ?? '').toString().trim().isNotEmpty;

        // ÐÐ½ÐºÐµÑÐ° Ð´Ð¾Ð»Ð¶Ð½Ð° Ð±ÑÑÑ Ð·Ð°Ð¿Ð¾Ð»Ð½ÐµÐ½Ð°, Ð½Ð¾ ÑÐµÐ¿ÐµÑÑ ÐµÑ Ð¼Ð¾Ð¶Ð½Ð¾ ÑÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°ÑÑ Ð² Ð»ÑÐ±Ð¾Ð¹ Ð¼Ð¾Ð¼ÐµÐ½Ñ (Ð² Ð¿ÑÐ¾ÑÐ¸Ð»Ðµ)
        if (!hasProfile) return const ProfileFormPage(isEdit: false);

        final activeCompanyId = (data['activeCompanyId'] ?? '').toString().trim();

if (activeCompanyId.isEmpty) {
  return const RestoreCompanyPage();
}

return CompanyGate(companyId: activeCompanyId);



      },
    );
  }
}

class EnsureUserDocPage extends StatefulWidget {
  const EnsureUserDocPage({super.key});

  @override
  State<EnsureUserDocPage> createState() => _EnsureUserDocPageState();
}

class _EnsureUserDocPageState extends State<EnsureUserDocPage> {
  String? error;

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  Future<void> _ensure() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;

      await userDoc(u.uid).set({
        'email': u.email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppRouter()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class RestoreCompanyPage extends StatefulWidget {
  const RestoreCompanyPage({super.key});

  @override
  State<RestoreCompanyPage> createState() => _RestoreCompanyPageState();
}

class _RestoreCompanyPageState extends State<RestoreCompanyPage> {
  String? error;
  bool done = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final uid = uidOrThrow();

      final Set<String> ids = {};

      // â 1) ÐÑÐ»Ð¸ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ Ð²Ð»Ð°Ð´ÐµÐ»ÐµÑ â Ð½Ð°ÑÐ¾Ð´Ð¸Ð¼ ÑÐ¸ÑÐ¼Ñ Ð¿Ð¾ ownerUid (ÑÑÐ¾ Ð±ÐµÐ·Ð¾Ð¿Ð°ÑÐ½ÑÐ¹ Ð·Ð°Ð¿ÑÐ¾Ñ)
      try {
        final ownerSnap = await companiesRef()
            .where('ownerUid', isEqualTo: uid)
            .where('deleted', isEqualTo: false)
            .get();
        for (final d in ownerSnap.docs) {
          ids.add(d.id);
        }
      } catch (_) {}

      // â 2) ÐÑÐ»Ð¸ Ð² members ÑÑÐ°Ð½Ð¸ÑÑÑ Ð¿Ð¾Ð»Ðµ uid â Ð¼Ð¾Ð¶Ð½Ð¾ Ð²Ð¾ÑÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÑ Ð¸ Ð´Ð»Ñ ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¾Ð²
      // (Ð¼Ñ Ð´Ð¾Ð±Ð°Ð²Ð¸Ð»Ð¸ 'uid' Ð² members Ð¿ÑÐ¸ ÑÐ¾Ð·Ð´Ð°Ð½Ð¸Ð¸/Ð²ÑÑÑÐ¿Ð»ÐµÐ½Ð¸Ð¸/Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ¶Ð´ÐµÐ½Ð¸Ð¸)
      try {
        final memberSnap = await FirebaseFirestore.instance
            .collectionGroup('members')
            .where('uid', isEqualTo: uid)
            .where('status', isEqualTo: 'active')
            .get();

        for (final m in memberSnap.docs) {
          final parentCompany = m.reference.parent.parent;
          if (parentCompany != null) ids.add(parentCompany.id);
        }
      } catch (_) {}

      final myCompanyIds = ids.toList();

      // 3) ÐÑÐ»Ð¸ Ð½Ð°ÑÐ»Ð¸ ÑÐ¾ÑÑ Ð±Ñ Ð¾Ð´Ð½Ñ ÑÐ¸ÑÐ¼Ñ â ÐÐ ÑÑÐ°Ð²Ð¸Ð¼ activeCompanyId Ð°Ð²ÑÐ¾Ð¼Ð°ÑÐ¸ÑÐµÑÐºÐ¸.
/// ÐÐ¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ ÑÐ¿Ð¸ÑÐ¾Ðº ÑÐ¸ÑÐ¼, ÑÑÐ¾Ð±Ñ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ ÑÐ°Ð¼ Ð²ÑÐ±ÑÐ°Ð» (Ð¸Ð»Ð¸ ÑÐ¾Ð·Ð´Ð°Ð» Ð½Ð¾Ð²ÑÑ).
if (myCompanyIds.isNotEmpty) {
  if (!mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => ChooseMyCompanyPage(companyIds: myCompanyIds)),
    (_) => false,
  );
  return;
}

// 4) ÐÑÐ»Ð¸ ÑÐ¸ÑÐ¼ Ð½ÐµÑ â ÑÐ¾Ð³Ð´Ð° ÑÐ¶Ðµ Ð´Ð°ÑÐ¼ Ð²ÑÐ±Ð¾Ñ ÑÐ¾Ð·Ð´Ð°ÑÑ/Ð²Ð¾Ð¹ÑÐ¸ Ð¿Ð¾ ÐºÐ¾Ð´Ñ
      if (myCompanyIds.isEmpty) {
        if (!mounted) return;
        setState(() => done = true);
        return;
      }

      // 5) ÐÑÐ»Ð¸ ÑÐ¸ÑÐ¼ Ð½ÐµÑÐºÐ¾Ð»ÑÐºÐ¾ â Ð¿Ð¾ÐºÐ°Ð¶ÐµÐ¼ ÑÐ¿Ð¸ÑÐ¾Ðº Ð²ÑÐ±Ð¾ÑÐ°
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ChooseMyCompanyPage(companyIds: myCompanyIds)),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'ÐÑÐ¸Ð±ÐºÐ° Ð²Ð¾ÑÑÑÐ°Ð½Ð¾Ð²Ð»ÐµÐ½Ð¸Ñ ÑÐ¸ÑÐ¼Ñ:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (done) {
      // ÑÐ¸ÑÐ¼ Ð½ÐµÑ â Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ Ð¾Ð±ÑÑÐ½ÑÐ¹ Ð²ÑÐ±Ð¾Ñ
      return const RoleChoicePage();
    }

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class ChooseMyCompanyPage extends StatelessWidget {
  final List<String> companyIds;
  const ChooseMyCompanyPage({super.key, required this.companyIds});

  Future<void> _select(BuildContext context, String companyId) async {
    await userDoc().set({
      'activeCompanyId': companyId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => CompanyGate(companyId: companyId)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ÐÑÐ±ÐµÑÐ¸ÑÐµ Ð²Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ')),
      body: ListView.builder(
        itemCount: companyIds.length,
        itemBuilder: (_, i) {
          final id = companyIds[i];
          return ListTile(
            title: Text('Ð¤Ð¸ÑÐ¼Ð°: $id'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _select(context, id),
          );
        },
      ),
    );
  }
}
/// ===================
/// AUTO RESTORE COMPANY (ÐµÑÐ»Ð¸ activeCompanyId Ð¿ÑÑÑÐ¾Ð¹)
/// ===================
class AutoRestoreCompanyPage extends StatefulWidget {
  const AutoRestoreCompanyPage({super.key});

  @override
  State<AutoRestoreCompanyPage> createState() => _AutoRestoreCompanyPageState();
}

class _AutoRestoreCompanyPageState extends State<AutoRestoreCompanyPage> {
  String? error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final uid = uidOrThrow();

      // ÐÑÐµÐ¼ ÑÐ¸ÑÐ¼Ñ, Ð³Ð´Ðµ ÑÑÐ¾Ñ uid ÑÐ¾ÑÑÐ¾Ð¸Ñ Ð² members Ð¸ status == active
      final companiesSnap = await companiesRef().get();

      String foundCompanyId = '';

      for (final c in companiesSnap.docs) {
        final companyId = c.id;

        final mSnap = await companyMemberDoc(companyId, uid).get();
        if (!mSnap.exists) continue;

        final m = mSnap.data() ?? {};
        final status = (m['status'] ?? '').toString();
        if (status != 'active') continue;

        final cData = c.data();
        final deleted = (cData['deleted'] ?? false) == true;
        if (deleted) continue;

        foundCompanyId = companyId;
        break;
      }

      if (!mounted) return;

      // ÐÑÐ»Ð¸ Ð½Ð°ÑÐ»Ð¸ â ÐÐ Ð·Ð°Ð¿Ð¸ÑÑÐ²Ð°ÐµÐ¼ activeCompanyId Ð°Ð²ÑÐ¾Ð¼Ð°ÑÐ¸ÑÐµÑÐºÐ¸.
/// ÐÐ¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ Ð²ÑÐ±Ð¾Ñ ÑÐ¸ÑÐ¼ (Ð´Ð°Ð¶Ðµ ÐµÑÐ»Ð¸ Ð¾Ð½Ð° Ð¾Ð´Ð½Ð°), ÑÑÐ¾Ð±Ñ Ð¸Ð·Ð±ÐµÐ¶Ð°ÑÑ ÑÐ¸ÐºÐ»Ð¾Ð².
if (foundCompanyId.isNotEmpty) {
  if (!mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => ChooseMyCompanyPage(companyIds: [foundCompanyId])),
    (_) => false,
  );
  return;
}

// ÐÐµ Ð½Ð°ÑÐ»Ð¸ â Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ Ð²ÑÐ±Ð¾Ñ (ÑÐ¾Ð·Ð´Ð°ÑÑ/Ð²Ð¾Ð¹ÑÐ¸ Ð¿Ð¾ ÐºÐ¾Ð´Ñ)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleChoicePage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('ÐÑÑ Ð²Ð°ÑÑ ÑÐ¸ÑÐ¼Ñ...'),
                  ],
                )
              : Text('ÐÑÐ¸Ð±ÐºÐ° Ð²Ð¾ÑÑÑÐ°Ð½Ð¾Ð²Ð»ÐµÐ½Ð¸Ñ ÑÐ¸ÑÐ¼Ñ:\n$error', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// ===================
/// PROFILE FORM (create/edit)
/// ===================
/// ===================
/// PROFILE FORM (create/edit)  â FIX PREFILL
/// ===================
class ProfileFormPage extends StatefulWidget {
  final bool isEdit;
  const ProfileFormPage({super.key, required this.isEdit});

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  final birthCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final shoeCtrl = TextEditingController();
  final clothesCtrl = TextEditingController();

  bool loading = false;
  String? error;

  bool _loadedOnce = false; // â Ð²Ð°Ð¶Ð½Ð¾

  @override
  void dispose() {
    firstCtrl.dispose();
    lastCtrl.dispose();
    birthCtrl.dispose();
    phoneCtrl.dispose();
    shoeCtrl.dispose();
    clothesCtrl.dispose();
    super.dispose();
  }

  void _prefillOnce(Map<String, dynamic> data) {
    if (_loadedOnce) return;
    _loadedOnce = true;

    firstCtrl.text = (data['firstName'] ?? '').toString();
    lastCtrl.text = (data['lastName'] ?? '').toString();
    birthCtrl.text = (data['birthDate'] ?? '').toString();
    phoneCtrl.text = (data['phone'] ?? '').toString();
    shoeCtrl.text = (data['shoeSize'] ?? '').toString();
    // legacy key: clothesSize, new key: clothingSize
    clothesCtrl.text = (data['clothingSize'] ?? data['clothesSize'] ?? '').toString();
  }

  Future<void> _save() async {
    final i18n = I18n(AppState.of(context).lang.value);

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final first = firstCtrl.text.trim();
      final last = lastCtrl.text.trim();
      final birth = birthCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      final shoe = shoeCtrl.text.trim();
      final clothes = clothesCtrl.text.trim();

      if (first.isEmpty || last.isEmpty || phone.isEmpty) {
        throw Exception(i18n.t('needProfile'));
      }

      final u = FirebaseAuth.instance.currentUser;

      await userDoc().set({
        'email': u?.email,
        'firstName': first,
        'lastName': last,
        'birthDate': birth,
        'phone': phone,
        'shoeSize': shoe,
        // write both keys for backward compatibility
        'clothingSize': clothes,
        'clothesSize': clothes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      if (widget.isEdit) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AppRouter()),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _logout() async {
    await signOutAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc().snapshots(),
      builder: (c, s) {
        if (s.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(i18n.t('profileForm'))),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${i18n.t('errUserRead')}: ${s.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }

        if (!s.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = s.data!.data() ?? {};
        _prefillOnce(data); // â Ð²Ð¾Ñ Ð¾Ð½Ð¾

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.isEdit ? i18n.t('editMyProfile') : i18n.t('profileForm')),
            actions: [
              IconButton(
                tooltip: i18n.t('logout'),
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              )
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: firstCtrl,
                decoration: InputDecoration(labelText: i18n.t('firstName')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lastCtrl,
                decoration: InputDecoration(labelText: i18n.t('lastName')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: birthCtrl,
                decoration: InputDecoration(labelText: i18n.t('birthDate')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(labelText: i18n.t('phone')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shoeCtrl,
                decoration: InputDecoration(labelText: i18n.t('shoeSize')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: clothesCtrl,
                decoration: InputDecoration(labelText: i18n.t('clothesSize')),
              ),
              const SizedBox(height: 16),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: loading ? null : _save,
                child: Text(i18n.t('saveProfile')),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ===================
/// LINK / CHANGE PASSWORD (for PC login)
/// ===================
class LinkPasswordPage extends StatefulWidget {
  const LinkPasswordPage({super.key});
  @override
  State<LinkPasswordPage> createState() => _LinkPasswordPageState();
}

class _LinkPasswordPageState extends State<LinkPasswordPage> {
  final pass1 = TextEditingController();
  final pass2 = TextEditingController();

  bool loading = false;
  String? error;

  @override
  void dispose() {
    pass1.dispose();
    pass2.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final i18n = I18n(AppState.of(context).lang.value);
    final u = FirebaseAuth.instance.currentUser;
    final email = u?.email;
    if (email == null || email.isEmpty) {
      setState(() => error = 'ÐÐµÑ email Ñ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ');
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${i18n.t('done')}')));
  }

  Future<void> _linkOrChange() async {
    final i18n = I18n(AppState.of(context).lang.value);
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final p1 = pass1.text.trim();
      final p2 = pass2.text.trim();

      if (p1.length < 6) throw Exception(i18n.t('newPassword'));
      if (p1 != p2) throw Exception(i18n.t('passwordsNotMatch'));

      final email = u.email;
      if (email == null || email.isEmpty) throw Exception('ÐÐµÑ email Ñ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ');

      final hasPasswordProvider = u.providerData.any((p) => p.providerId == 'password');

      if (hasPasswordProvider) {
        // ÑÐ¼ÐµÐ½Ð° Ð¿Ð°ÑÐ¾Ð»Ñ
        await u.updatePassword(p1);
      } else {
        // Ð¿ÑÐ¸Ð²ÑÐ·ÐºÐ° Ð¿Ð°ÑÐ¾Ð»Ñ Ðº Google-Ð°ÐºÐºÐ°ÑÐ½ÑÑ
        final cred = EmailAuthProvider.credential(email: email, password: p1);
        await u.linkWithCredential(cred);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('done'))));
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      // ÑÐ°ÑÑÐ¾ Ð½ÑÐ¶Ð½Ð¾ "recent login"
      setState(() {
        error = '${e.code}: ${e.message}\n${i18n.t('needReLogin')}';
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    final u = FirebaseAuth.instance.currentUser;
    final hasPasswordProvider = u?.providerData.any((p) => p.providerId == 'password') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('linkPassword'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              hasPasswordProvider ? i18n.t('changePassword') : i18n.t('setPassword'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pass1,
              obscureText: true,
              decoration: InputDecoration(labelText: i18n.t('newPassword')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pass2,
              obscureText: true,
              decoration: InputDecoration(labelText: i18n.t('repeatPassword')),
            ),
            const SizedBox(height: 12),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : _linkOrChange,
                child: Text(i18n.t('save')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: loading ? null : _sendReset,
                child: Text(i18n.t('sendReset')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// ROLE CHOICE
/// ===================
class RoleChoicePage extends StatelessWidget {
  const RoleChoicePage({super.key});

  Future<void> _logout(BuildContext context) async {
    await signOutAll();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('welcome')),
        actions: [
          PopupMenuButton<AppLang>(
            tooltip: i18n.t('chooseLang'),
            icon: const Icon(Icons.language),
            onSelected: (v) => AppState.of(context).lang.value = v,
            itemBuilder: (_) => AppLang.values.map((lang) {
              return PopupMenuItem(value: lang, child: Text(kLangNames[lang] ?? lang.name));
            }).toList(),
          ),
          IconButton(
            tooltip: i18n.t('logout'),
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(i18n.t('chooseRole'), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.business),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateCompanyPage()),
                ),
                label: Text(i18n.t('owner')),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.key),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const JoinCompanyPage()),
                ),
                label: Text(i18n.t('employee')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// CREATE COMPANY (OWNER)
/// ===================
class CreateCompanyPage extends StatefulWidget {
  const CreateCompanyPage({super.key});

  @override
  State<CreateCompanyPage> createState() => _CreateCompanyPageState();
}

class _CreateCompanyPageState extends State<CreateCompanyPage> {
  final nameCtrl = TextEditingController();

  bool loading = false;
  String? error;
  String? createdCode;

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _create() async {
    final i18n = I18n(AppState.of(context).lang.value);

    setState(() {
      loading = true;
      error = null;
      createdCode = null;
    });

    try {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) throw Exception(i18n.t('companyName'));

      final uid = uidOrThrow();

      // 1) Ð¡Ð¾Ð·Ð´Ð°ÑÐ¼ Ð·Ð°ÑÐ°Ð½ÐµÐµ companyId (Ð²Ð¼ÐµÑÑÐ¾ add)
      final companyDoc = companiesRef().doc();
      final companyId = companyDoc.id;

      // 2) ÐÐµÐ½ÐµÑÐ¸Ð¼ invite code (Ð¿Ð¾ÑÐ¾Ð¼ ÑÐ¾ÑÑÐ°Ð½Ð¸Ð¼ ÐºÐ°Ðº doc id)
      final code = _genCode();

      // 3) Batch: ÑÐ¸ÑÐ¼Ð° + inviteCode + member(owner) + activeCompanyId
      final batch = FirebaseFirestore.instance.batch();

      // COMPANY
      batch.set(companyDoc, {
        'name': name,
        'ownerUid': uid,
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,

        // â Ð¿Ð¾Ð»Ñ ÑÐ°ÑÐ¸ÑÐ° Ð´Ð»Ñ ÑÐ²Ð¾ÐµÐ¹ ÑÐ¸ÑÐ¼Ñ (Ð±ÐµÑÐ¿Ð»Ð°ÑÐ½Ð¾ Ð¸ Ð±ÐµÐ·Ð»Ð¸Ð¼Ð¸Ñ)
        'planId': 'unlimited',
        'billingMode': 'free_unlimited',
        'maxUsers': 999999,
        'subscriptionActive': true,
      });

      // INVITE CODE -> companyId
      batch.set(inviteCodesRef().doc(code), {
        'companyId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // MEMBER OWNER
      batch.set(companyMemberDoc(companyId, uid), {
        'uid': uid,
        'role': 'owner',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // USER -> activeCompanyId
      batch.set(
        userDoc(),
        {
          'activeCompanyId': companyId,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      setState(() => createdCode = code);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => CompanyGate(companyId: companyId)),
        (_) => false,
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('createCompany'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: i18n.t('companyName')),
            ),
            const SizedBox(height: 12),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            if (createdCode != null) ...[
              const SizedBox(height: 12),
              Text(
                '${i18n.t('yourInviteCode')}: $createdCode',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(i18n.t('copyCodeHint')),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : _create,
                child: Text(i18n.t('createCompany')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// JOIN COMPANY (EMPLOYEE)
/// ===================

class JoinByCodePage extends StatelessWidget {
  const JoinByCodePage({super.key});
  @override
  Widget build(BuildContext context) => const JoinCompanyPage();
}

class JoinCompanyPage extends StatefulWidget {
  const JoinCompanyPage({super.key});
  @override
  State<JoinCompanyPage> createState() => _JoinCompanyPageState();
}

class _JoinCompanyPageState extends State<JoinCompanyPage> {
  final codeCtrl = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final i18n = I18n(AppState.of(context).lang.value);

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final code = codeCtrl.text.trim().toUpperCase();
      if (code.isEmpty) throw Exception(i18n.t('inviteCode'));

      final uid = uidOrThrow();

      final uSnap = await userDoc().get();
      final u = uSnap.data() ?? {};
      final first = (u['firstName'] ?? '').toString();
      final last = (u['lastName'] ?? '').toString();
      final phone = (u['phone'] ?? '').toString();

      final codeSnap = await inviteCodesRef().doc(code).get();
      if (!codeSnap.exists) throw Exception(i18n.t('codeNotFound'));

      final companyId = (codeSnap.data()?['companyId'] ?? '').toString();
      if (companyId.isEmpty) throw Exception(i18n.t('codeNotFound'));

      // IMPORTANT:
      // Do NOT read /companies/{companyId} here.
      // A user who is not yet an active member can legitimately have no
      // permission to read the company document, which would cause
      // "permission-denied" during joining.
      // We rely on inviteCodes mapping + allowed writes to create a pending
      // membership + join request.

      await companyMemberDoc(companyId, uid).set({
        'uid': uid,
        'role': 'worker',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await companyJoinRequestsRef(companyId).doc(uid).set({
        'uid': uid,
        'firstName': first,
        'lastName': last,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // In-app notification for admin
      try {
        await companyNotificationsRef(companyId).doc(uid).set({
          'type': 'new_member',
          'uid': uid,
          'firstName': first,
          'lastName': last,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        }, SetOptions(merge: true));
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PendingPage(companyId: companyId)),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('joinCompany'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(labelText: i18n.t('inviteCode')),
            ),
            const SizedBox(height: 12),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : _join,
                child: Text(i18n.t('joinCompany')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================
/// PENDING PAGE (EMPLOYEE WAIT)
/// ===================
class PendingPage extends StatelessWidget {
  final String companyId;
  const PendingPage({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    final uid = uidOrThrow();

    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('pendingTitle'))),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: companyMemberDoc(companyId, uid).snapshots(),
        builder: (c, s) {
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${i18n.t('errMemberRead')}:\n${s.error}', style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = s.data!.data();
          final status = (data?['status'] ?? 'pending').toString();

          if (status == 'active') {
            Future.microtask(() async {
              try {
                await userDoc().set({'activeCompanyId': companyId}, SetOptions(merge: true));
              } catch (_) {}
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => CompanyGate(companyId: companyId)),
                  (_) => false,
                );
              }
            });

            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                i18n.t('pendingText'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ===================
/// COMPANY GATE  â FIX: ÐÐ Ð¡ÐÐ ÐÐ¡Ð«ÐÐÐÐ activeCompanyId Ð¡ÐÐÐ
/// ===================

/// ===================
/// AUTO KICK OUT (when membership is missing/removed/left)
/// ===================
class _KickOutToRoleChoicePage extends StatelessWidget {
  final String message;
  const _KickOutToRoleChoicePage({super.key, required this.message});

  Future<void> _leaveToRoleChoice(BuildContext context) async {
    try {
      await userDoc().set({'activeCompanyId': ''}, SetOptions(merge: true));
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRouter()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('leaveCompany'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _leaveToRoleChoice(context),
                  child: Text(i18n.t('leaveCompany')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class CompanyGate extends StatelessWidget {
  final String companyId;
  const CompanyGate({super.key, required this.companyId});

  Future<void> _leaveToRoleChoice(BuildContext context) async {
    // Ð¢ÐÐÐ¬ÐÐ Ð¿Ð¾ ÐºÐ½Ð¾Ð¿ÐºÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ, Ð° Ð½Ðµ Ð°Ð²ÑÐ¾Ð¼Ð°ÑÐ¸ÑÐµÑÐºÐ¸
    await userDoc().set({'activeCompanyId': ''}, SetOptions(merge: true));
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRouter()),
      (_) => false,
    );
  }

  @override
Widget build(BuildContext context) {
  if (companyId.trim().isEmpty) {
    return const RoleChoicePage();
  }

  final uid = uidOrThrow();
  final i18n = I18n(AppState.of(context).lang.value);

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: companyDoc(companyId).snapshots(),
      builder: (c, companySnap) {
        // 1) ÐÐ´ÑÐ¼
        if (companySnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2) ÐÑÐ¸Ð±ÐºÐ° ÑÑÐµÐ½Ð¸Ñ ÑÐ¸ÑÐ¼Ñ â ÐÐ Ð¡ÐÐ ÐÐ¡Ð«ÐÐÐÐ, Ð¿ÑÐ¾ÑÑÐ¾ Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼
        if (companySnap.hasError) {
  return Scaffold(
    appBar: AppBar(title: Text(i18n.t('errCompanyRead'))),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'ÐÑÐ¸Ð±ÐºÐ° Ð´Ð¾ÑÑÑÐ¿Ð° Ðº ÑÐ¸ÑÐ¼Ðµ:\n${companySnap.error}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    ),
  );
}

        // 3) Ð¤Ð¸ÑÐ¼Ñ Ð½ÐµÑ â ÐÐ Ð¡ÐÐ ÐÐ¡Ð«ÐÐÐÐ, Ð¿ÑÐ¾ÑÑÐ¾ Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼
        if (!companySnap.hasData || !companySnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ð¤Ð¸ÑÐ¼Ð° Ð½Ðµ Ð½Ð°Ð¹Ð´ÐµÐ½Ð°')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => _leaveToRoleChoice(context),
                  child: const Text('ÐÑÐ¹ÑÐ¸ / Ð²ÑÐ±ÑÐ°ÑÑ Ð´ÑÑÐ³ÑÑ ÑÐ¸ÑÐ¼Ñ'),
                ),
              ),
            ),
          );
        }

        final cData = companySnap.data!.data() ?? {};
        if ((cData['deleted'] ?? false) == true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ð¤Ð¸ÑÐ¼Ð° ÑÐ´Ð°Ð»ÐµÐ½Ð°')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => _leaveToRoleChoice(context),
                  child: const Text('ÐÑÐ¹ÑÐ¸ / Ð²ÑÐ±ÑÐ°ÑÑ Ð´ÑÑÐ³ÑÑ ÑÐ¸ÑÐ¼Ñ'),
                ),
              ),
            ),
          );
        }

        // 4) Ð¢ÐµÐ¿ÐµÑÑ Ð¿ÑÐ¾Ð²ÐµÑÑÐµÐ¼ ÑÑÐ°ÑÑÐ½Ð¸ÐºÐ°
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: companyMemberDoc(companyId, uid).snapshots(),
          builder: (c2, memberSnap) {
            if (memberSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // ÐÑÐ¸Ð±ÐºÐ° ÑÑÐµÐ½Ð¸Ñ ÑÑÐ°ÑÑÐ½Ð¸ÐºÐ° â ÐÐ Ð¡ÐÐ ÐÐ¡Ð«ÐÐÐÐ
            if (memberSnap.hasError) {
              return Scaffold(
                appBar: AppBar(title: Text(i18n.t('errMemberRead'))),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${i18n.t('errMemberRead')}:\n${memberSnap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _leaveToRoleChoice(context),
                        child: Text(i18n.t('leaveCompany')),
                      ),
                    ],
                  ),
                ),
              );
            }

            
// ÐÑÐ»Ð¸ Ð´Ð¾ÐºÑÐ¼ÐµÐ½ÑÐ° ÑÑÐ°ÑÑÐ½Ð¸ÐºÐ° Ð½ÐµÑ â Ð°Ð²ÑÐ¾Ð¼Ð°ÑÐ¸ÑÐµÑÐºÐ¸ Ð²ÑÑÐ¾Ð´Ð¸Ð¼ Ð½Ð° Ð²ÑÐ±Ð¾Ñ ÑÐ¸ÑÐ¼Ñ
if (!memberSnap.hasData || !memberSnap.data!.exists) {
  return _KickOutToRoleChoicePage(message: i18n.t('noAccessCompany'));
}

final m = memberSnap.data!.data() ?? {};
            final status = (m['status'] ?? '').toString();

            if (status == 'pending') {
  return PendingPage(companyId: companyId);
}
if (status != 'active') {
  // removed / left / any other -> kick out to choose company (can join again by code)
  return _KickOutToRoleChoicePage(message: i18n.t('removedFromCompany'));
}

      // Normalize role values (supports legacy values like "4man" / "foramen")
      final role = normalizeRole((m['role'] ?? 'worker').toString());
            return HomeCompanyPage(companyId: companyId, role: role);
          },
        );
      },
    );
  }
}

/// ===================
/// HOME (COMPANY)
/// ===================
class HomeCompanyPage extends StatefulWidget {
  final String companyId;
  final String role;
  const HomeCompanyPage({super.key, required this.companyId, required this.role});

  @override
  State<HomeCompanyPage> createState() => _HomeCompanyPageState();
}

class _HomeCompanyPageState extends State<HomeCompanyPage> {
  int index = 1;
  int _toolsOnHandsCount = 0;
  int _pendingCount = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _toolsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;

  @override
  void initState() {
    super.initState();
    _toolsSub = companyToolsRef(widget.companyId)
        .where('status', isEqualTo: 'issued')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _toolsOnHandsCount = snap.docs.length);
    });
    final isAdmin = widget.role == 'owner' || widget.role == 'admin';
    if (isAdmin) {
      _pendingSub = companyJoinRequestsRef(widget.companyId)
          .snapshots()
          .listen((snap) {
        if (mounted) setState(() => _pendingCount = snap.docs.length);
      });
    }
  }

  @override
  void dispose() {
    _toolsSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await signOutAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    final pages = [
      PeoplePage(companyId: widget.companyId, role: widget.role),
      ToolsPage(companyId: widget.companyId, role: widget.role),
      MovesPage(companyId: widget.companyId, role: widget.role),
      CompanyProfilePage(companyId: widget.companyId, role: widget.role, onLogout: _logout),
    ];


    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('appTitle')),
        actions: [
          IconButton(
            tooltip: i18n.t('logout'),
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.people), label: i18n.t('people')),
          NavigationDestination(icon: const Icon(Icons.build), label: i18n.t('tools')),
          NavigationDestination(
            icon: Badge(
              label: Text('$_toolsOnHandsCount'),
              isLabelVisible: _toolsOnHandsCount > 0,
              child: const Icon(Icons.swap_horiz),
            ),
            label: i18n.t('issue'),
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('$_pendingCount'),
              isLabelVisible: _pendingCount > 0,
              child: const Icon(Icons.person),
            ),
            label: i18n.t('profile'),
          ),
        ],
      ),
    );
  }
}

/// ===================
/// COMPANY PROFILE + MANAGEMENT + EMPLOYEES LIST + EDIT PROFILE
/// ===================
class CompanyProfilePage extends StatelessWidget {
  final String companyId;
  final String role;
  final Future<void> Function() onLogout;

  CompanyProfilePage({
    super.key,
    required this.companyId,
    required this.role,
    required this.onLogout,
  });

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isOwner => role == 'owner';


  Future<int> _activePeopleCount() async {
    final qs = await companyPeopleRef(companyId).get();
    int active = 0;
    for (final d in qs.docs) {
      final data = d.data();
      final status = (data['status'] as String?)?.toLowerCase();
      // â Ð Ð»Ð¸Ð¼Ð¸Ñ ÑÑÐ¸ÑÐ°ÐµÐ¼ Ð¢ÐÐÐ¬ÐÐ active (ÑÐ²Ð¾Ð»ÐµÐ½Ð½ÑÐµ/Ð½ÐµÐ°ÐºÑÐ¸Ð²Ð½ÑÐµ â Ð½Ðµ ÑÑÐ¸ÑÐ°ÐµÐ¼)
      if (status == 'inactive' || status == 'fired' || status == 'terminated') continue;
      active++;
    }
    return active;
  }

  Future<void> _changePlanDialog(BuildContext context, String currentPlan) async {
    final i18n = I18n(AppState.of(context).lang.value);
    String selected = currentPlan;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(i18n.t('selectPlan')),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: Plans.all.map((p) {
                final usd = Plans.priceUsd(p);
                final title = '${Plans.uiName(p)}${usd > 0 ? ' â \$$usd / ${i18n.t('perMonth')}' : ' â Free'}';
                final gps = Plans.gpsEnabled(p) ? i18n.t('gpsIncluded') : i18n.t('gpsNotIncluded');
                final subtitle = '${i18n.t('peopleLimitLabel')}: ${Plans.peopleLimit(p)}  Â·  $gps';
                return RadioListTile<String>(
                  value: p,
                  groupValue: selected,
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => selected = v);
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n.t('cancel'))),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n.t('ok'))),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await companyDoc(companyId).set({'plan': selected}, SetOptions(merge: true));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('planSaved'))));
  }


  String _fmtDate(dynamic ts) {
    try {
      if (ts is Timestamp) {
        final d = ts.toDate();
        String two(int n) => n < 10 ? '0$n' : '$n';
        return '${two(d.day)}.${two(d.month)}.${d.year}';
      }
    } catch (_) {}
    return 'â';
  }

  Future<void> _buyRenewDialog(BuildContext context) async {
    final i18n = I18n(AppState.of(context).lang.value);
    const email = 'merlinnikolapl@gmail.com';
    const tg = '@Mykola_Ivanov';
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(i18n.t('buyRenew')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n.t('buyRenewSoon')),
            const SizedBox(height: 12),
            Text('Email: $email'),
            Text('Telegram: $tg'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n.t('ok')),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: companyDoc(companyId).snapshots(),
      builder: (c, s) {
        final data = s.data?.data() ?? {};
        final billingMode = (data['billingMode'] as String?) ?? 'billing_test';

        final ent = data['entitlement'];
        final entMap = (ent is Map) ? ent : null;

        final String status = (entMap?['status'] as String?) ?? '';
        final bool isEntActive = status.toLowerCase() == 'active';
        final validUntil = entMap?['validUntil'];
        final String validUntilText = validUntil == null ? 'â' : _fmtDate(validUntil);

        final modeText = billingMode == 'billing_live' ? i18n.t('subscriptionLive') : i18n.t('subscriptionTest');
        final statusText = billingMode == 'billing_live'
            ? (isEntActive ? i18n.t('subscriptionActive') : i18n.t('subscriptionInactive'))
            : i18n.t('subscriptionTest');

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('subscriptionTitle'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${i18n.t('subscriptionModeLabel')}: $modeText'),
                const SizedBox(height: 4),
                Text('${i18n.t('subscriptionStatusLabel')}: $statusText'),
                if (billingMode == 'billing_live') ...[
                  const SizedBox(height: 4),
                  Text('${i18n.t('subscriptionValidUntilLabel')}: $validUntilText'),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isOwner ? () => _buyRenewDialog(context) : null,
                  child: Text(i18n.t('buyRenew')),
                ),
                if (!isOwner) ...[
                  const SizedBox(height: 6),
                  Text(i18n.t('planChangeOnlyOwner'), style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _planLimitsCard(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: companyDoc(companyId).snapshots(),
      builder: (c, s) {
        final data = s.data?.data() ?? {};
        final plan = (data['plan'] as String?) ?? Plans.free;
        final billingMode = (data['billingMode'] as String?) ?? 'billing_test';

        final limit = Plans.peopleLimit(plan);
        final priceUsd = Plans.priceUsd(plan);
        final planName = Plans.uiName(plan);
        final gpsOn = Plans.gpsEnabled(plan);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('tariffLimitsTitle'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${i18n.t('planLabel')}: $planName${priceUsd > 0 ? ' â \$$priceUsd / ${i18n.t('perMonth')}' : ' â Free'}'),
                const SizedBox(height: 4),
                Text('${i18n.t('peopleLimitLabel')}: $limit'),
                const SizedBox(height: 4),
                Text(gpsOn ? i18n.t('gpsIncluded') : i18n.t('gpsNotIncluded'),
                    style: TextStyle(color: gpsOn ? Colors.green : Colors.grey)),
                const SizedBox(height: 6),
                FutureBuilder<int>(
                  future: _activePeopleCount(),
                  builder: (_, cs) {
                    final used = cs.data;
                    final usedText = used == null ? 'â¦' : '$used / $limit';
                    return Text('${i18n.t('usedActiveLabel')}: $usedText');
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '${i18n.t('billingModeLabel')}: ${billingMode == 'billing_live' ? i18n.t('billingLive') : i18n.t('billingTest')}',
                  style: const TextStyle(color: Colors.green),
                ),
                const SizedBox(height: 6),
                Text(i18n.t('inactiveNotCountedNote')),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: isOwner ? () => _changePlanDialog(context, plan) : null,
                  child: Text(i18n.t('changePlan')),
                ),
                if (!isOwner) ...[
                  const SizedBox(height: 6),
                  Text(i18n.t('planChangeOnlyOwner'), style: const TextStyle(fontSize: 12)),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _supportCard(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    const email = 'merlinnikolapl@gmail.com';
    const tg = '@Mykola_Ivanov';
    const version = '1.0.0';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n.t('supportTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(i18n.t('supportDesc')),
            const SizedBox(height: 8),
            Text('${i18n.t('versionLabel')}: $version'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 18),
                const SizedBox(width: 8),
                Text('${i18n.t('emailLabel')}: $email'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 18),
                const SizedBox(width: 8),
                Text('${i18n.t('telegramLabel')}: $tg'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveCompany(BuildContext context) async {
    // Mark membership as "left" so the owner won't see the person in active list
    // and the same user can re-join later by code.
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      await companyMemberDoc(companyId, u.uid).set({
        'status': 'left',
        'leftAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await userDoc().set({'activeCompanyId': ''}, SetOptions(merge: true));
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRouter()),
      (_) => false,
    );
  }

  Future<void> _renameCompany(BuildContext context) async {
    final i18n = I18n(AppState.of(context).lang.value);
    String newName = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('renameCompany')),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: i18n.t('newCompanyName')),
          onChanged: (v) => newName = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(i18n.t('save'))),
        ],
      ),
    );

    final name = newName.trim();
    if (ok == true && name.isNotEmpty) {
      await companyDoc(companyId).set({'name': name}, SetOptions(merge: true));
    }
  }

  Future<void> _deleteCompany(BuildContext context) async {
    final i18n = I18n(AppState.of(context).lang.value);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('deleteCompanyTitle')),
        content: Text(i18n.t('deleteCompanyText')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.t('delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await companyDoc(companyId).set({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userDoc().set({'activeCompanyId': ''}, SetOptions(merge: true));

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRouter()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: companyDoc(companyId).snapshots(),
          builder: (c, s) {
            final data = s.data?.data();
            final name = (data?['name'] ?? '').toString();
            final invite = (data?['inviteCode'] ?? '').toString();
            final deleted = (data?['deleted'] ?? false) == true;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i18n.t('company')}: $name', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('${i18n.t('role')}: $role'),
                    const SizedBox(height: 10),
                    if (deleted) Text(i18n.t('archivedCompany'), style: const TextStyle(color: Colors.red)),
                    if (isAdmin && !deleted) ...[
                      Text('${i18n.t('yourInviteCode')}: $invite', style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(i18n.t('copyCodeHint')),
                    ],
                  ],
                ),
              ),
            );
          },
        ),

        _subscriptionCard(context),
        const SizedBox(height: 12),
        _planLimitsCard(context),
        const SizedBox(height: 12),
        _supportCard(context),
        const SizedBox(height: 12),

        const SizedBox(height: 12),

        // â Ð ÐÐÐÐÐ¢ÐÐ ÐÐÐÐ¢Ð¬ ÐÐÐ ÐÐ ÐÐ¤ÐÐÐ¬ (Ð² Ð»ÑÐ±Ð¾Ð¹ Ð¼Ð¾Ð¼ÐµÐ½Ñ)
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileFormPage(isEdit: true)),
          ),
          icon: const Icon(Icons.edit),
          label: Text(i18n.t('editMyProfile')),
        ),

        const SizedBox(height: 8),

        // â ÐÐ ÐÐÐ¯ÐÐÐ¢Ð¬ / Ð¡ÐÐÐÐÐ¢Ð¬ ÐÐÐ ÐÐÐ¬ ÐÐÐ¯ ÐÐ
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LinkPasswordPage()),
          ),
          icon: const Icon(Icons.lock),
          label: Text(i18n.t('linkPassword')),
        ),

        const SizedBox(height: 12),

        DropdownButton<AppLang>(
          value: AppState.of(context).lang.value,
          onChanged: (v) {
            if (v == null) return;
            AppState.of(context).lang.value = v;
          },
          items: AppLang.values.map((lang) {
            return DropdownMenuItem(value: lang, child: Text(kLangNames[lang] ?? lang.name));
          }).toList(),
        ),

        const SizedBox(height: 12),

        // â ÐÐÐ¯ÐÐÐ (OWNER/ADMIN)
        if (isAdmin) ...[
          Text(i18n.t('requests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          JoinRequestsCard(companyId: companyId),
          const SizedBox(height: 12),
        ],

        // â Ð¡ÐÐÐ¡ÐÐ Ð¡ÐÐ¢Ð Ð£ÐÐÐÐÐÐ (OWNER/ADMIN) â ÑÐ²Ð¾ÑÐ°ÑÐ¸Ð²Ð°ÐµÐ¼ÑÐ¹
        if (isAdmin) ...[
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.people),
              title: Text(i18n.t('employees'), style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: EmployeesListCard(companyId: companyId),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // --- ÐÐÐÐÐÐ ÐÐÐ§ÐÐÐ/ÐÐÐÐÐ Ð¨ÐÐÐÐ¯ Ð¡ÐÐÐÐ« (Ð²ÑÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ð¸) ---
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('myShift'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userDoc(FirebaseAuth.instance.currentUser?.uid ?? '').snapshots(),
                  builder: (c, s) {
                    final data = s.data?.data() ?? {};
                    final first = (data['firstName'] ?? '').toString();
                    final last = (data['lastName'] ?? '').toString();
                    final uName = ('$first $last').trim().isEmpty
                        ? (FirebaseAuth.instance.currentUser?.email ?? '')
                        : ('$first $last').trim();
                    return ShiftButton(
                      companyId: companyId,
                      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                      userName: uName,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // --- ÐÐÐ Ð¡ÐÐÐÐ« (Ð²ÑÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ð¸) ---
        OutlinedButton.icon(
          onPressed: () async {
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            String personIdToUse = uid;
            try {
              final snap = await companyPeopleRef(companyId)
                  .where('linkedUserId', isEqualTo: uid)
                  .limit(1)
                  .get();
              if (snap.docs.isNotEmpty) personIdToUse = snap.docs.first.id;
            } catch (_) {}
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TimesheetsPage(
                companyId: companyId,
                personId: personIdToUse,
              )),
            );
          },
          icon: const Icon(Icons.history),
          label: Text(i18n.t('myTimesheets')),
        ),
        const SizedBox(height: 8),

        // --- ÐÐ¡Ð ÐÐÐªÐÐÐ¢Ð« (Ð²ÑÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ð¸) â ÑÐ²Ð¾ÑÐ°ÑÐ¸Ð²Ð°ÐµÐ¼ÑÐ¹ Ð¸Ð½Ð»Ð°Ð¹Ð½ ---
        WorkSitesInlineCard(companyId: companyId),
        const SizedBox(height: 8),

        // --- ÐÐ¡Ð Ð¡ÐÐÐÐ« + Ð£ÐÐ ÐÐÐÐÐÐÐ ÐÐÐªÐÐÐ¢ÐÐÐ (ÑÐ¾Ð»ÑÐºÐ¾ admin/owner) ---
        if (isAdmin) ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TimesheetsPage(companyId: companyId, isAdmin: true)),
            ),
            icon: const Icon(Icons.bar_chart),
            label: Text(i18n.t('allTimesheets')),
          ),
          const SizedBox(height: 8),
          // Ð£Ð¿ÑÐ°Ð²Ð»ÐµÐ½Ð¸Ðµ Ð¾Ð±ÑÐµÐºÑÐ°Ð¼Ð¸ â ÑÐ²Ð¾ÑÐ°ÑÐ¸Ð²Ð°ÐµÐ¼ÑÐ¹ Ð¸Ð½Ð»Ð°Ð¹Ð½
          SitesManageInlineCard(companyId: companyId),
          const SizedBox(height: 8),
        ],

        OutlinedButton.icon(
          onPressed: () => _leaveCompany(context),
          icon: const Icon(Icons.swap_horiz),
          label: Text(i18n.t('leaveCompany')),
        ),
        const SizedBox(height: 8),
        if (isAdmin)
          OutlinedButton.icon(
            onPressed: () => _renameCompany(context),
            icon: const Icon(Icons.edit),
            label: Text(i18n.t('editCompany')),
          ),
        const SizedBox(height: 8),
        if (isOwner)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _deleteCompany(context),
            icon: const Icon(Icons.delete_forever),
            label: Text(i18n.t('deleteCompany')),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async => onLogout(),
          child: Text(i18n.t('logout')),
        ),
      ],
    );
  }
}

/// â Ð¡Ð¿Ð¸ÑÐ¾Ðº ÑÐ¾ÑÑÑÐ´Ð½Ð¸ÐºÐ¾Ð² (Ð´Ð»Ñ Ð²Ð»Ð°Ð´ÐµÐ»ÑÑÐ°/Ð°Ð´Ð¼Ð¸Ð½Ð°) Ñ Ð¿Ð¾Ð¸ÑÐºÐ¾Ð¼ Ð¸ ÑÐ¾ÑÑÐ¸ÑÐ¾Ð²ÐºÐ¾Ð¹
class EmployeesListCard extends StatefulWidget {
  final String companyId;
  const EmployeesListCard({super.key, required this.companyId});

  @override
  State<EmployeesListCard> createState() => _EmployeesListCardState();
}

class _EmployeesListCardState extends State<EmployeesListCard> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    final myUid = uidOrThrow();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: companyMemberDoc(widget.companyId, myUid).snapshots(),
      builder: (context, mySnap) {
        final myRoleRaw = (mySnap.data?.data() ?? {})['role']?.toString() ?? 'employee';
        final myRole = normalizeRole(myRoleRaw);
        final isOwner = myRole == 'owner';
        final isAdmin = myRole == 'admin';
        final canEditProfiles = isOwner || isAdmin; // â Ð°Ð½ÐºÐµÑÑ ÑÐµÐ´Ð°ÐºÑÐ¸ÑÑÐµÑ Ð²Ð»Ð°Ð´ÐµÐ»ÐµÑ Ð¸ Ð°Ð´Ð¼Ð¸Ð½

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: companyMembersRef(widget.companyId).where('status', isEqualTo: 'active').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final memberDocs = snapshot.data!.docs;

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: () async {
                // ÐÐ°Ð³ÑÑÐ¶Ð°ÐµÐ¼ Ð°Ð½ÐºÐµÑÑ, ÑÑÐ¾Ð±Ñ Ð·Ð½Ð°ÑÑ ÐºÐ°ÐºÐ¸Ðµ UIDs ÑÐ¶Ðµ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½Ñ
                final peopleSnap = await companyPeopleRef(widget.companyId).get();
                final linkedUids = <String>{};
                for (final p in peopleSnap.docs) {
                  final uid = (p.data()['linkedUserId'] ?? '').toString();
                  if (uid.isNotEmpty) linkedUids.add(uid);
                }

                final out = <Map<String, dynamic>>[];
                for (final m in memberDocs) {
                  final uid = m.id;
                  final roleRaw = (m.data()['role'] ?? 'employee').toString();
                  final role = normalizeRole(roleRaw);

                  final u = await userDoc(uid).get();
                  final ud = u.data() ?? {};

                  final first = (ud['firstName'] ?? '').toString();
                  final last = (ud['lastName'] ?? '').toString();
                  final phone = (ud['phone'] ?? '').toString();
                  final position = (ud['position'] ?? '').toString();

                  final name = ('$first $last').trim().isEmpty ? uid : ('$first $last').trim();

                  out.add({
                    'uid': uid,
                    'roleRaw': roleRaw,
                    'role': role,
                    'name': name,
                    'phone': phone,
                    'position': position,
                    'isLinked': linkedUids.contains(uid),
                  });
                }

                // â Ð°Ð»ÑÐ°Ð²Ð¸Ñ (Ñ ÑÑÐµÑÐ¾Ð¼ Ñ -> Ðµ)
                out.sort((a, b) => normText(a['name']).compareTo(normText(b['name'])));
                return out;
              }(),
              builder: (context, listSnap) {
                if (!listSnap.hasData) return const Center(child: CircularProgressIndicator());

                var list = listSnap.data!;

                if (_searchQuery.isNotEmpty) {
                  final q = normText(_searchQuery);
                  list = list.where((e) {
                    final name = normText((e['name'] ?? '').toString());
                    final phone = normText((e['phone'] ?? '').toString());
                    return name.contains(q) || phone.contains(q);
                  }).toList();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: i18n.t('searchByNameOrPhone'),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final uid = list[i]['uid'] as String;
                        final name = list[i]['name'] as String;
                        final phone = (list[i]['phone'] ?? '').toString();
                        final position = (list[i]['position'] ?? '').toString();
                        final roleRaw = (list[i]['roleRaw'] ?? 'employee').toString();
                        final roleNorm = normalizeRole(roleRaw);
                        final isLinked = (list[i]['isLinked'] as bool?) ?? false;
                        final canDeleteMember =
                            (isOwner && uid != myUid && roleNorm != 'owner') ||
                            (isAdmin && uid != myUid && (roleNorm == 'foreman' || roleNorm == 'employee'));

                        final roleText = roleLabel(i18n, roleRaw);
                        final nameColor = isLinked ? null : Colors.red.shade700;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isLinked ? null : Colors.red.shade100,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(color: isLinked ? null : Colors.red.shade700),
                            ),
                          ),
                          title: Row(children: [
                            Expanded(
                              child: Text(
                                position.isNotEmpty ? '$name ($position)' : name,
                                style: TextStyle(color: nameColor),
                              ),
                            ),
                            if (!isLinked)
                              Tooltip(
                                message: i18n.t('notLinked'),
                                child: Icon(Icons.link_off, size: 16, color: Colors.red.shade400),
                              ),
                          ]),
                          subtitle: Text('${roleText}${phone.isNotEmpty ? '\n$phone' : ''}'),
                          isThreeLine: phone.isNotEmpty,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // â Ð²Ð»Ð°Ð´ÐµÐ»ÐµÑ Ð½Ð°Ð·Ð½Ð°ÑÐ°ÐµÑ ÑÐ¾Ð»Ñ
                              if ((isOwner || isAdmin) && uid != myUid && roleNorm != 'owner')
                                PopupMenuButton<String>(
                                  tooltip: i18n.t('setRole'),
                                  onSelected: (v) async {
                                    await companyMemberDoc(widget.companyId, uid).set(
                                      {'role': v},
                                      SetOptions(merge: true),
                                    );
                                  },
                                  itemBuilder: (_) {
                                    final items = <PopupMenuEntry<String>>[];
                                    if (isOwner) {
                                      items.add(PopupMenuItem(value: 'admin', child: Text(i18n.t('role_admin'))));
                                    }
                                    items.add(PopupMenuItem(value: 'foreman', child: Text(i18n.t('role_foreman'))));
                                    items.add(PopupMenuItem(value: 'employee', child: Text(i18n.t('role_employee'))));
                                    return items;
                                  },

                                  icon: const Icon(Icons.manage_accounts),
                                ),
                              if (canEditProfiles)
                                IconButton(
                                  tooltip: i18n.t('editProfile'),
                                  icon: const Icon(Icons.edit),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => EmployeeProfileEditPage(employeeUid: uid)),
                                    );
                                  },
                                ),
                              if (canDeleteMember)
                                IconButton(
                                  tooltip: i18n.t('delete'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(i18n.t('delete')),
                                        content: Text('${i18n.t('delete')} "$name"?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('no'))),
                                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(i18n.t('yes'))),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await companyMemberDoc(widget.companyId, uid).delete();
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

}

/// ===================
/// JOIN REQUESTS (OWNER/ADMIN)
/// ===================
class JoinRequestsCard extends StatelessWidget {
  final String companyId;
  const JoinRequestsCard({super.key, required this.companyId});

  void _toast(BuildContext context, String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _approve(BuildContext context, String uid) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        companyMemberDoc(companyId, uid),
        {
          'uid': uid,
          'status': 'active',
          'approvedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.delete(companyJoinRequestsRef(companyId).doc(uid));

      await batch.commit();
      _toast(context, 'Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ¶Ð´ÑÐ½');
    } catch (e) {
      _toast(context, 'ÐÑÐ¸Ð±ÐºÐ° Ð¿Ð¾Ð´ÑÐ²ÐµÑÐ¶Ð´ÐµÐ½Ð¸Ñ: $e');
    }
  }

  Future<void> _decline(BuildContext context, String uid) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.delete(companyJoinRequestsRef(companyId).doc(uid));
      batch.delete(companyMemberDoc(companyId, uid));

      await batch.commit();
      _toast(context, 'ÐÐ°ÑÐ²ÐºÐ° Ð¾ÑÐºÐ»Ð¾Ð½ÐµÐ½Ð°');
    } catch (e) {
      _toast(context, 'ÐÑÐ¸Ð±ÐºÐ° Ð¾ÑÐºÐ»Ð¾Ð½ÐµÐ½Ð¸Ñ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyJoinRequestsRef(companyId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;

        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(i18n.t('noRequests')),
            ),
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final uid = d.id;

            final fn = (data['firstName'] ?? '').toString().trim();
            final ln = (data['lastName'] ?? '').toString().trim();
            final phone = (data['phone'] ?? '').toString().trim();
            final fullName = ('$fn $ln').trim();

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName.isEmpty ? 'ÐÐµÐ· Ð¸Ð¼ÐµÐ½Ð¸' : fullName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            phone.isEmpty ? 'Ð¢ÐµÐ»ÐµÑÐ¾Ð½ Ð½Ðµ ÑÐºÐ°Ð·Ð°Ð½' : phone,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      children: [
                        SizedBox(
                          width: 140,
                          child: OutlinedButton(
                            onPressed: () => _decline(context, uid),
                            child: Text(i18n.t('decline')),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 140,
                          child: FilledButton(
                            onPressed: () => _approve(context, uid),
                            child: Text(i18n.t('approve')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// ===================
/// PEOPLE (company scoped)
/// ===================
class PeoplePage extends StatefulWidget {
  final String companyId;
  final String role;
  const PeoplePage({super.key, required this.companyId, required this.role});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  String get _role => normalizeRole(widget.role.trim());
  bool get isOwner => _role == 'owner';
  bool get isAdmin => _role == 'admin';
  bool get canManage => isOwner || isAdmin;

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _addPersonDialog() async {
    final i18n = I18n(AppState.of(context).lang.value);
    if (!canManage) { _toast(i18n.t('onlyAdmin')); return; }

    String first = '', last = '', pos = '', type = 'person';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(i18n.t('addPerson')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: ChoiceChip(
                  label: Center(child: Text(i18n.t('personTypePerson'))),
                  selected: type == 'person',
                  onSelected: (_) => setDlg(() => type = 'person'),
                )),
                const SizedBox(width: 8),
                Expanded(child: ChoiceChip(
                  label: Center(child: Text(i18n.t('personTypeObject'))),
                  selected: type == 'object',
                  onSelected: (_) => setDlg(() => type = 'object'),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(decoration: InputDecoration(labelText: i18n.t('firstName')), onChanged: (v) => first = v),
              const SizedBox(height: 8),
              TextField(decoration: InputDecoration(labelText: i18n.t('lastName')), onChanged: (v) => last = v),
              const SizedBox(height: 8),
              TextField(decoration: InputDecoration(labelText: i18n.t('position')), onChanged: (v) => pos = v),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(i18n.t('add'))),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (first.trim().isEmpty || last.trim().isEmpty || pos.trim().isEmpty) return;

    // Plan limit check (people + objects count together)
    final compSnap = await companyDoc(widget.companyId).get();
    final plan = (compSnap.data()?['plan'] as String?) ?? Plans.free;
    final limit = Plans.peopleLimit(plan);
    final cntSnap = await companyPeopleRef(widget.companyId).count().get();
    if ((cntSnap.count ?? 0) >= limit) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('ÐÐ¸Ð¼Ð¸Ñ'),
          content: Text('Ð Ð²Ð°ÑÐµÐ¼ ÑÐ°ÑÐ¸ÑÐµ Ð¼Ð°ÐºÑÐ¸Ð¼ÑÐ¼ $limit Ð·Ð°Ð¿Ð¸ÑÐµÐ¹. ÐÐµÑÐµÐ¹Ð´Ð¸ÑÐµ Ð½Ð° ÑÐ°ÑÐ¸Ñ Ð²ÑÑÐµ.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    await companyPeopleRef(widget.companyId).add({
      'firstName': first.trim(),
      'lastName': last.trim(),
      'position': pos.trim(),
      'type': type,
      'status': 'active',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deletePerson(String id) async {
    if (!canManage) return;
    await companyPeopleRef(widget.companyId).doc(id).delete();
  }

  // Link an app user (Firebase Auth member) to a people/object record
  Future<void> _linkPersonDialog(String personId, Map<String, dynamic> personData) async {
    final i18n = I18n(AppState.of(context).lang.value);

    final membersSnap = await companyMembersRef(widget.companyId)
        .where('status', isEqualTo: 'active')
        .get();
    if (!mounted) return;
    if (membersSnap.docs.isEmpty) { _toast(i18n.t('noEmployees')); return; }

    final members = <Map<String, dynamic>>[];
    for (final m in membersSnap.docs) {
      try {
        final ud = (await userDoc(m.id).get()).data() ?? {};
        final name = '${ud['firstName'] ?? ''} ${ud['lastName'] ?? ''}'.trim();
        members.add({'uid': m.id, 'name': name.isEmpty ? m.id : name});
      } catch (_) {
        members.add({'uid': m.id, 'name': m.id});
      }
    }
    if (!mounted) return;

    final currentUid = (personData['linkedUserId'] ?? '').toString();
    final personName = '${personData['firstName'] ?? ''} ${personData['lastName'] ?? ''}'.trim();

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${i18n.t('selectUserToLink')}: $personName'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              title: Text(i18n.t('unlinkUser')),
              leading: Icon(Icons.link_off, color: currentUid.isEmpty ? Colors.green : Colors.grey),
              selected: currentUid.isEmpty,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const Divider(),
            ...members.map((m) => ListTile(
              title: Text(m['name']),
              leading: Icon(Icons.person, color: m['uid'] == currentUid ? Colors.green : Colors.grey),
              selected: m['uid'] == currentUid,
              onTap: () => Navigator.pop(ctx, m['uid']),
            )),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(i18n.t('cancel')))],
      ),
    );

    if (selected == null) return;
    await companyPeopleRef(widget.companyId).doc(personId).set(
      {'linkedUserId': selected.isEmpty ? FieldValue.delete() : selected},
      SetOptions(merge: true),
    );
  }

  // type=null shows archive (all fired/completed); activeOnly filters by status
  Widget _buildList(I18n i18n, {String? type, bool activeOnly = true}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyPeopleRef(widget.companyId).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());

        final docs = s.data!.docs.where((d) {
          final data = d.data();
          final docType = (data['type'] ?? 'person').toString();
          final status = (data['status'] ?? 'active').toString();

          if (type != null && docType != type) return false;
          if (activeOnly && status != 'active') return false;
          if (!activeOnly && status == 'active') return false;

          if (_searchQuery.isEmpty) return true;
          final full = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}';
          return full.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (docs.isEmpty) {
          if (type == null) return Center(child: Text(i18n.t('noArchive')));
          return Center(child: Text(i18n.t(type == 'person' ? 'noPeople' : 'noObjects')));
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final docType = (data['type'] ?? 'person').toString();
            final status = (data['status'] ?? 'active').toString();
            final pos = (data['position'] ?? '').toString();
            final isLinked = (data['linkedUserId'] ?? '').toString().isNotEmpty;

            // In archive tab show type label; in person/object tabs show status
            final statusLabel = type == null
                ? '${docType == 'object' ? i18n.t('personTypeObject') : i18n.t('personTypePerson')} â¢ ${status == 'fired' ? i18n.t('empStatusFired') : i18n.t('objectCompleted')}'
                : (type == 'object'
                    ? (status == 'completed' ? i18n.t('objectCompleted') : i18n.t('empStatusActive'))
                    : (status == 'fired' ? i18n.t('empStatusFired') : i18n.t('empStatusActive')));

            return ListTile(
              title: Text('${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim()),
              subtitle: Text(pos.isEmpty ? statusLabel : '$pos â¢ $statusLabel'),
              onTap: isOwner ? () => _editPersonDialog(docs[i].id, data) : null,
              trailing: canManage
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      // Link icon only for persons, not objects
                      if (docType != 'object')
                        IconButton(
                          icon: Icon(isLinked ? Icons.link : Icons.link_off,
                              color: isLinked ? Colors.green : Colors.grey, size: 20),
                          tooltip: i18n.t('linkUser'),
                          onPressed: () => _linkPersonDialog(docs[i].id, data),
                        ),
                      PopupMenuButton<String>(
                        tooltip: i18n.t('employeeStatus'),
                        onSelected: (v) async {
                          if (v == 'fired' || v == 'completed') {
                            final cnt = await employeeToolsOnHandsCount(widget.companyId, docs[i].id);
                            if (cnt > 0) {
                              _toast((v == 'fired'
                                  ? i18n.t('cannotFireHasTools')
                                  : i18n.t('cannotCompleteHasTools'))
                                  .replaceAll('{n}', '$cnt'));
                              return;
                            }
                          }
                          await companyPeopleRef(widget.companyId).doc(docs[i].id).set(
                            {'status': v, 'statusUpdatedAt': FieldValue.serverTimestamp()},
                            SetOptions(merge: true),
                          );
                        },
                        itemBuilder: (_) => (type ?? docType) == 'object'
                            ? [
                                PopupMenuItem(value: 'active', child: Text(i18n.t('empStatusActive'))),
                                PopupMenuItem(value: 'completed', child: Text(i18n.t('objectCompleted'))),
                              ]
                            : [
                                PopupMenuItem(value: 'active', child: Text(i18n.t('empStatusActive'))),
                                PopupMenuItem(value: 'fired', child: Text(i18n.t('empStatusFired'))),
                              ],
                      ),
                      if (isOwner) ...[
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _editPersonDialog(docs[i].id, data)),
                        IconButton(icon: const Icon(Icons.delete), onPressed: () => _deletePerson(docs[i].id)),
                      ],
                    ])
                  : null,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: canManage
            ? FloatingActionButton(onPressed: _addPersonDialog, child: const Icon(Icons.add))
            : null,
        body: Column(
          children: [
            TabBar(tabs: [
              Tab(text: i18n.t('personTab')),
              Tab(text: i18n.t('objectTab')),
              Tab(icon: const Icon(Icons.archive_outlined, size: 18), text: i18n.t('archive')),
            ]),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: i18n.t('searchByNameOrPhone'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() { _searchQuery = ""; _searchController.clear(); }))
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _buildList(i18n, type: 'person'),
                _buildList(i18n, type: 'object'),
                _buildList(i18n, activeOnly: false),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPersonDialog(String personId, Map<String, dynamic> data) async {
    final i18n = I18n(AppState.of(context).lang.value);
    final firstCtrl = TextEditingController(text: (data['firstName'] ?? '').toString());
    final lastCtrl = TextEditingController(text: (data['lastName'] ?? '').toString());
    final posCtrl = TextEditingController(text: (data['position'] ?? '').toString());
    String type = (data['type'] ?? 'person').toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(i18n.t('editEmployee')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ð¢Ð¸Ð¿ â Ð¼Ð¾Ð¶Ð½Ð¾ Ð¿ÐµÑÐµÐºÐ»ÑÑÐ¸ÑÑ Ð¼ÐµÐ¶Ð´Ñ ÑÐµÐ»Ð¾Ð²ÐµÐºÐ¾Ð¼ Ð¸ Ð¾Ð±ÑÐµÐºÑÐ¾Ð¼
              Row(children: [
                Expanded(child: ChoiceChip(
                  label: Center(child: Text(i18n.t('personTypePerson'))),
                  selected: type == 'person',
                  onSelected: (_) => setDlg(() => type = 'person'),
                )),
                const SizedBox(width: 8),
                Expanded(child: ChoiceChip(
                  label: Center(child: Text(i18n.t('personTypeObject'))),
                  selected: type == 'object',
                  onSelected: (_) => setDlg(() => type = 'object'),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(controller: firstCtrl, decoration: InputDecoration(labelText: i18n.t('firstName'))),
              TextField(controller: lastCtrl, decoration: InputDecoration(labelText: i18n.t('lastName'))),
              TextField(controller: posCtrl, decoration: InputDecoration(labelText: i18n.t('position'))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(i18n.t('save'))),
          ],
        ),
      ),
    );

    if (saved != true) return;

    await companyPeopleRef(widget.companyId).doc(personId).set({
      'firstName': firstCtrl.text.trim(),
      'lastName': lastCtrl.text.trim(),
      'position': posCtrl.text.trim(),
      'type': type,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// ===================
/// TOOLS (company scoped)
/// ===================
class ToolsPage extends StatefulWidget {
  final String companyId;
  final String role;
  const ToolsPage({super.key, required this.companyId, required this.role});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  String _sortMode = 'name'; // 'name' | 'count' | 'date'
  String get _role => normalizeRole(widget.role.trim());
  bool get isOwner => _role == 'owner';
  bool get isAdmin => _role == 'admin';
  bool get canManage => isOwner || isAdmin;

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _nextInv(List<String> existing) {
    int maxNum = 0;
    String prefix = '';
    int padLen = 3;
    for (final inv in existing) {
      final m = RegExp(r'^(.*?)(\d+)$').firstMatch(inv);
      if (m != null) {
        final n = int.parse(m.group(2)!);
        if (n >= maxNum) {
          maxNum = n;
          prefix = m.group(1)!;
          padLen = m.group(2)!.length;
        }
      }
    }
    if (maxNum == 0 && existing.isNotEmpty) return '${existing.last}-copy';
    return '$prefix${(maxNum + 1).toString().padLeft(padLen, '0')}';
  }

  Future<void> _printQrCode(String toolId, String toolName, String inv) async {
    final painter = QrPainter(
      data: 'toolkeeper:$toolId',
      version: QrVersions.auto,
      gapless: true,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );
    final image = await painter.toImage(400);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;

    final doc = pw.Document();
    final qrImage = pw.MemoryImage(bytes.buffer.asUint8List());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context ctx) => pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(toolName,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            if (inv.isNotEmpty)
              pw.Text(inv, style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 16),
            pw.Image(qrImage, width: 220, height: 220),
          ],
        ),
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // PNG â share QR as image file
  Future<void> _exportQrPng(String toolId, String toolName, String inv) async {
    final painter = QrPainter(
      data: 'toolkeeper:$toolId',
      version: QrVersions.auto,
      gapless: true,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );
    final image = await painter.toImage(600);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final safeName = toolName.replaceAll(RegExp(r'[^\w]'), '_');
    final file = File('${dir.path}/qr_$safeName.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
            await Share.shareXFiles(
                        [XFile(file.path)],
                        subject: inv.isNotEmpty ? '$toolName â $inv' : toolName,
                      );
  }

  // Thermal label PDF â 57Ã32mm (Brother QL / Zebra format)
  Future<void> _printQrThermal(String toolId, String toolName, String inv) async {
    final painter = QrPainter(
      data: 'toolkeeper:$toolId',
      version: QrVersions.auto,
      gapless: true,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );
    final image = await painter.toImage(300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final qrImage = pw.MemoryImage(bytes.buffer.asUint8List());

    const labelW = 57.0 * PdfPageFormat.mm;
    const labelH = 32.0 * PdfPageFormat.mm;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(labelW, labelH, marginAll: 2 * PdfPageFormat.mm),
      build: (ctx) => pw.Row(
        children: [
          pw.Image(qrImage, width: 28 * PdfPageFormat.mm, height: 28 * PdfPageFormat.mm),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(toolName,
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    maxLines: 2),
                if (inv.isNotEmpty)
                  pw.Text(inv, style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // A4 grid â all tools, 3 per row
  Future<void> _printAllQrA4(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final doc = pw.Document();
    const cols = 3;
    const cellW = (210 - 20) / cols * PdfPageFormat.mm;
    const cellH = 80.0 * PdfPageFormat.mm;

    // Build QR images for all docs
    final List<Map<String, dynamic>> items = [];
    for (final d in docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString();
      final inv = (data['inv'] ?? '').toString();
      final painter = QrPainter(
        data: 'toolkeeper:${d.id}',
        version: QrVersions.auto,
        gapless: true,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
      );
      final img = await painter.toImage(300);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        items.add({'name': name, 'inv': inv, 'img': pw.MemoryImage(bytes.buffer.asUint8List())});
      }
    }

    // Split into rows of 3
    final rows = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < items.length; i += cols) {
      rows.add(items.sublist(i, i + cols > items.length ? items.length : i + cols));
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginTop: 10 * PdfPageFormat.mm,
        marginBottom: 10 * PdfPageFormat.mm,
        marginLeft: 10 * PdfPageFormat.mm,
        marginRight: 10 * PdfPageFormat.mm,
      ),
      build: (ctx) => rows.map((row) => pw.Row(
        children: [
          ...row.map((item) => pw.Container(
            width: cellW,
            height: cellH,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Image(item['img'] as pw.MemoryImage, width: 55 * PdfPageFormat.mm, height: 55 * PdfPageFormat.mm),
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
                pw.Text(item['name'] as String,
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center, maxLines: 2),
                if ((item['inv'] as String).isNotEmpty)
                  pw.Text(item['inv'] as String,
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center),
              ],
            ),
          )),
          // fill empty cells in last row
          ...List.generate(cols - row.length, (_) => pw.Container(width: cellW, height: cellH)),
        ],
      )).toList(),
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Widget _qrActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: Colors.black87),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      ),
    );
  }

  void _showQrDialog(String toolId, String toolName, String inv, String? customQr) {
    if (!mounted) return;
    final i18n = I18n(AppState.of(context).lang.value);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$toolName${inv.isNotEmpty ? ' â $inv' : ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: 'toolkeeper:$toolId',
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 8),
              if (inv.isNotEmpty)
                Text(inv, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text(toolName, style: const TextStyle(color: Colors.black54)),
            if (customQr != null && customQr.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.black12),
              Row(children: [
                const Icon(Icons.qr_code_2, size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(child: Text('ÐÐ½ÐµÑÐ½Ð¸Ð¹ QR: $customQr',
                    style: const TextStyle(fontSize: 12, color: Colors.green))),
                IconButton(
                  icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
                  tooltip: 'ÐÑÐ²ÑÐ·Ð°ÑÑ QR',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await companyToolsRef(widget.companyId).doc(toolId).update(
                        {'customQr': FieldValue.delete()});
                    _toast('ÐÐ½ÐµÑÐ½Ð¸Ð¹ QR Ð¾ÑÐ²ÑÐ·Ð°Ð½');
                  },
                ),
              ]),
            ],
              const SizedBox(height: 12),
              const Divider(color: Colors.black12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _qrActionBtn(Icons.print, 'A4', () { Navigator.pop(ctx); _printQrCode(toolId, toolName, inv); }),
                  _qrActionBtn(Icons.image_outlined, 'PNG', () { Navigator.pop(ctx); _exportQrPng(toolId, toolName, inv); }),
                  _qrActionBtn(Icons.label_outline, i18n.t('thermalLabel'), () { Navigator.pop(ctx); _printQrThermal(toolId, toolName, inv); }),
                  if (canManage)
                    _qrActionBtn(Icons.qr_code_scanner, customQr != null && customQr.isNotEmpty ? 'âº QR' : '+ QR', () { Navigator.pop(ctx); _linkCustomQr(toolId, toolName, inv); }),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÐÐ°ÐºÑÑÑÑ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _linkCustomQr(String toolId, String toolName, String inv) async {
    final rawValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage(
        hint: 'ÐÐ°Ð²ÐµÐ´Ð¸ÑÐµ Ð½Ð° ÑÑÑÐµÑÑÐ²ÑÑÑÑÑ Ð½Ð°ÐºÐ»ÐµÐ¹ÐºÑ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ°',
      )),
    );
    if (rawValue == null || !mounted) return;

    if (rawValue.startsWith('toolkeeper:')) {
      _toast('Ð­ÑÐ¾ ÑÐ¶Ðµ QR-ÐºÐ¾Ð´ ToolKeeper â Ð²Ð½ÐµÑÐ½ÑÑ Ð½Ð°ÐºÐ»ÐµÐ¹ÐºÐ° Ð½Ðµ Ð½ÑÐ¶Ð½Ð°');
      return;
    }

    // ÐÑÐ¾Ð²ÐµÑÑÐµÐ¼ Ð½Ðµ Ð·Ð°Ð½ÑÑ Ð»Ð¸ ÐºÐ¾Ð´ Ð´ÑÑÐ³Ð¸Ð¼ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÐ¾Ð¼
    final existing = await companyToolsRef(widget.companyId)
        .where('customQr', isEqualTo: rawValue)
        .limit(1)
        .get();
    if (!mounted) return;
    if (existing.docs.isNotEmpty && existing.docs.first.id != toolId) {
      _toast('Ð­ÑÐ¾Ñ QR ÑÐ¶Ðµ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½ Ðº Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ "${existing.docs.first.data()['name'] ?? ''}"');
      return;
    }

    await companyToolsRef(widget.companyId).doc(toolId).set(
      {'customQr': rawValue},
      SetOptions(merge: true),
    );
    _toast('QR-Ð½Ð°ÐºÐ»ÐµÐ¹ÐºÐ° Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½Ð° Ðº $toolName â $inv');
  }

  Future<void> _copyTool(
    Map<String, dynamic> data,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groupItems,
  ) async {
    final i18n = I18n(AppState.of(context).lang.value);
    final invs = groupItems.map((d) => (d.data()['inv'] ?? '').toString()).toList();
    final newInv = _nextInv(invs);
    await companyToolsRef(widget.companyId).add({
      'name': data['name'],
      'inv': newInv,
      'status': 'active',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _toast(i18n.t('toolCopied'));
  }

  Future<void> _addToolDialog() async {
    final i18n = I18n(AppState.of(context).lang.value);
    if (!canManage) {
      _toast(i18n.t('onlyAdmin'));
      return;
    }
    String name = '';
    String inv = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('addTool')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(decoration: InputDecoration(labelText: i18n.t('toolNameHint')), onChanged: (v) => name = v),
            const SizedBox(height: 8),
            TextField(decoration: InputDecoration(labelText: i18n.t('invHint')), onChanged: (v) => inv = v),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(i18n.t('add'))),
        ],
      ),
    );
    if (ok == true && name.trim().isNotEmpty && inv.trim().isNotEmpty) {
      await companyToolsRef(widget.companyId).add({
        'name': name.trim(),
        'inv': inv.trim(),
        'status': 'active',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _deleteTool(String id) async {
    if (!canManage) return;
    await companyToolsRef(widget.companyId).doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton(onPressed: _addToolDialog, child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          // ð ÐÐÐÐ ÐÐÐÐ¡ÐÐ (ÐÐÐ¡Ð¢Ð Ð£ÐÐÐÐ¢Ð«)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: i18n.t('searchByNameOrInv'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      setState(() { _searchQuery = ""; _searchController.clear(); });
                    }) 
                  : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          // Ð¡ÑÑÐ¾ÐºÐ° ÑÐ¾ÑÑÐ¸ÑÐ¾Ð²ÐºÐ¸ + Ð¿ÐµÑÐ°ÑÑ Ð²ÑÐµÑ QR
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              const Icon(Icons.sort, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: _sortMode,
                isDense: true,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'name', child: Text(i18n.t('sortNameAZ'))),
                  DropdownMenuItem(value: 'count', child: Text(i18n.t('sortCountDesc'))),
                  DropdownMenuItem(value: 'date', child: Text(i18n.t('sortDateDesc'))),
                ],
                onChanged: (v) => setState(() => _sortMode = v!),
              ),
              const Spacer(),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: companyToolsRef(widget.companyId).snapshots(),
                builder: (_, snap) {
                  final docs = snap.data?.docs ?? [];
                  return IconButton(
                    icon: const Icon(Icons.print_outlined),
                    tooltip: i18n.t('printAllQr'),
                    onPressed: docs.isEmpty ? null : () => _printAllQrA4(docs),
                  );
                },
              ),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: companyToolsRef(widget.companyId).orderBy('createdAt', descending: true).snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final docs = s.data!.docs;
                if (docs.isEmpty) return Center(child: Text(i18n.t('noTools')));

                // ÐÑÑÐ¿Ð¿Ð¸ÑÐ¾Ð²ÐºÐ° Ñ ÑÐ¸Ð»ÑÑÑÐ°ÑÐ¸ÐµÐ¹
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groups = {};
                for (final d in docs) {
                  final name = (d.data()['name'] ?? 'ÐÐµÐ· Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ').toString();
                  final inv = (d.data()['inv'] ?? '').toString();
                  final q = _normTools(_searchQuery);
                  if (q.isEmpty || _normTools(name).contains(q) || _normTools(inv).contains(q)) {
                    groups.putIfAbsent(name, () => []).add(d);
                  }
                }

                final names = groups.keys.toList();
                if (_sortMode == 'name') {
                  names.sort((a, b) => _normTools(a).compareTo(_normTools(b)));
                } else if (_sortMode == 'count') {
                  names.sort((a, b) => (groups[b]!.length).compareTo(groups[a]!.length));
                }
                // 'date' â ÑÐ¶Ðµ Ð¾ÑÑÐ¾ÑÑÐ¸ÑÐ¾Ð²Ð°Ð½Ð¾ Ð¿Ð¾ÑÐ¾ÐºÐ¾Ð¼ (createdAt desc), Ð¿Ð¾ÑÑÐ´Ð¾Ðº Ð³ÑÑÐ¿Ð¿ ÑÐ¾ÑÑÐ°Ð½ÑÐµÑÑÑ
                if (names.isEmpty) return Center(child: Text(i18n.t('noTools')));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: names.length,
                  itemBuilder: (context, i) {
                    final toolName = names[i];
                    final items = groups[toolName]!;
                    items.sort((a, b) {
                      final ia = (a.data()['inv'] ?? '').toString();
                      final ib = (b.data()['inv'] ?? '').toString();
                      return ia.compareTo(ib);
                    });
                    return Card(
                      child: ExpansionTile(
                        initiallyExpanded: _searchQuery.isNotEmpty, // Ð Ð°ÑÐºÑÑÐ²Ð°ÐµÐ¼ Ð¿ÑÐ¸ Ð¿Ð¾Ð¸ÑÐºÐµ
                        title: Text('$toolName (${items.length})'),
                        children: items.map((d) {
                          final inv = (d.data()['inv'] ?? '').toString();
                          final status = (d.data()['status'] ?? 'active').toString();
                          final note = (d.data()['statusNote'] ?? '').toString().trim();
                          final customQr = (d.data()['customQr'] ?? '').toString().trim();
                          final hasCustomQr = customQr.isNotEmpty;
                          final statusLabel = status == 'disposed'
                              ? i18n.t('toolStatusDisposed')
                              : (status == 'repair' ? i18n.t('toolStatusRepair') : i18n.t('toolStatusActive'));
                          final subtitleText = note.isEmpty ? statusLabel : '$statusLabel â¢ $note';

                          return ListTile(
                            title: Row(children: [
                              Text(inv),
                              if (hasCustomQr) ...[
                                const SizedBox(width: 6),
                                const Tooltip(
                                  message: 'ÐÐ½ÐµÑÐ½Ð¸Ð¹ QR Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½',
                                  child: Icon(Icons.qr_code_2, size: 14, color: Colors.green),
                                ),
                              ],
                            ]),
                            subtitle: Text(subtitleText),
                            onTap: canManage ? () => _editToolDialog(d.id, d.data()) : null,
                            trailing: canManage
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    PopupMenuButton<String>(
                                      tooltip: i18n.t('toolStatus'),
                                      onSelected: (v) async {
                                        if (v != 'active') {
                                          final onHands = await toolIsOnHands(widget.companyId, d.id);
                                          if (onHands) {
                                            _toast(i18n.t('cannotSetToolStatusOnHands'));
                                            return;
                                          }
                                        }
                                        await companyToolsRef(widget.companyId).doc(d.id).set(
                                          {'status': v, 'statusUpdatedAt': FieldValue.serverTimestamp()},
                                          SetOptions(merge: true),
                                        );
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(value: 'active', child: Text(i18n.t('markToolActive'))),
                                        PopupMenuItem(value: 'repair', child: Text(i18n.t('markToolRepair'))),
                                        PopupMenuItem(value: 'disposed', child: Text(i18n.t('markToolDisposed'))),
                                      ],
                                    ),
                                    IconButton(icon: const Icon(Icons.qr_code, size: 20), tooltip: 'QR-ÐºÐ¾Ð´', onPressed: () => _showQrDialog(d.id, (d.data()['name'] ?? '').toString(), inv, hasCustomQr ? customQr : null)),
                                    IconButton(icon: const Icon(Icons.copy, size: 20), tooltip: i18n.t('copyTool'), onPressed: () => _copyTool(d.data(), items)),
                                    IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editToolDialog(d.id, d.data())),
                                    IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _deleteTool(d.id)),
                                  ])
                                : null,
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  String _normTools(String s) => s.toLowerCase().replaceAll('Ñ', 'Ðµ').trim();

  Future<void> _editToolDialog(String toolId, Map<String, dynamic> data) async {
    final i18n = I18n(AppState.of(context).lang.value);
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final invCtrl = TextEditingController(text: (data['inv'] ?? '').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.t('editTool')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: i18n.t('toolName'))),
            TextField(controller: invCtrl, decoration: InputDecoration(labelText: i18n.t('invNumber'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(i18n.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(i18n.t('save'))),
        ],
      ),
    );

    if (saved != true) return;

    await FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('tools')
        .doc(toolId)
        .set({
      'name': nameCtrl.text.trim(),
      'inv': invCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

}

/// ===================
/// MOVES (company scoped)
/// ===================
class MovesPage extends StatefulWidget {
  final String companyId;
  final String role;

  const MovesPage({
    super.key,
    required this.companyId,
    required this.role,
  });

  @override
  State<MovesPage> createState() => _MovesPageState();
}

class _MovesPageState extends State<MovesPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    return Column(
      children: [
        TabBar(
          controller: _tab,
          tabs: [
            Tab(text: i18n.t('issue')),
            Tab(text: i18n.t('history')),
            Tab(text: i18n.t('reports')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              IssueTab(companyId: widget.companyId, role: widget.role, t: (k) => i18n.t(k)),
              HistoryTab(companyId: widget.companyId),
              ReportsTab(companyId: widget.companyId),
            ],
          ),
        ),
      ],
    );
  }
}

class HistoryTab extends StatefulWidget {
  final String companyId;
  const HistoryTab({super.key, required this.companyId});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  String _searchQuery = "";

  Future<void> _openOnWindows(String path) async {
    try {
      await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
    } catch (_) {}
  }

  Future<File> _saveBytes(String filename, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openOrShare(File file, {String? mimeType}) async {
    try {
      if (Platform.isWindows) {
        await _openOnWindows(file.path);
      } else {
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ð¤Ð°Ð¹Ð» ÑÐ¾ÑÑÐ°Ð½ÑÐ½: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° ÑÐºÑÐ¿Ð¾ÑÑÐ°: $e')));
      }
    }
  }

  pw.Widget _actRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 160,
          child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        ),
        pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 11))),
      ],
    ),
  );

  Future<void> _exportActPdf({
    required String moveId,
    required String type,
    required String toolName,
    required String inv,
    required String personName,
    required String personPos,
    required dynamic createdAt,
  }) async {
    String companyName = 'ToolKeeper';
    try {
      final snap = await companyDoc(widget.companyId).get();
      if (snap.exists) companyName = (snap.data()?['name'] ?? 'ToolKeeper').toString();
    } catch (_) {}

    final theme = await _pdfTheme();
    final doc = pw.Document(theme: theme);

    DateTime? dt;
    if (createdAt is Timestamp) dt = createdAt.toDate();

    final dd = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'
        : '___';
    final shortId = moveId.length > 8 ? moveId.substring(0, 8).toUpperCase() : moveId.toUpperCase();
    final isIssue = type == 'out';
    final transferrer = isIssue
        ? companyName
        : '$personName${personPos.isNotEmpty ? " ($personPos)" : ""}';
    final receiver = isIssue
        ? '$personName${personPos.isNotEmpty ? " ($personPos)" : ""}'
        : companyName;
    final actTitle = isIssue ? 'ÐÐÐ¢ ÐÐ«ÐÐÐ§Ð ÐÐÐ¡Ð¢Ð Ð£ÐÐÐÐ¢Ð' : 'ÐÐÐ¢ ÐÐÐÐÐ ÐÐ¢Ð ÐÐÐ¡Ð¢Ð Ð£ÐÐÐÐ¢Ð';

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(companyName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(actTitle, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('â $shortId  Ð¾Ñ  $dd', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 32),
          _actRow('ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ:', toolName),
          _actRow('ÐÐ½Ð²ÐµÐ½ÑÐ°ÑÐ½ÑÐ¹ â:', inv.isNotEmpty ? inv : 'â'),
          pw.SizedBox(height: 16),
          _actRow(isIssue ? 'ÐÐµÑÐµÐ´Ð°ÑÑ:' : 'Ð¡Ð´Ð°ÑÑ:', transferrer),
          _actRow(isIssue ? 'ÐÐ¾Ð»ÑÑÐ°ÐµÑ:' : 'ÐÑÐ¸Ð½Ð¸Ð¼Ð°ÐµÑ:', receiver),
          pw.SizedBox(height: 16),
          _actRow('Ð¡Ð¾ÑÑÐ¾ÑÐ½Ð¸Ðµ Ð¿ÑÐ¸ Ð¿ÐµÑÐµÐ´Ð°ÑÐµ:', '______________________________'),
          pw.SizedBox(height: 40),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(isIssue ? 'ÐÐµÑÐµÐ´Ð°Ð»:' : 'ÐÑÐ¸Ð½ÑÐ»:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(isIssue ? 'ÐÐ¾Ð»ÑÑÐ¸Ð»:' : 'Ð¡Ð´Ð°Ð»:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ));

    final bytes = await doc.save();
    final file = await _saveBytes('act_${moveId}_${DateTime.now().millisecondsSinceEpoch}.pdf', bytes);
    await _openOrShare(file, mimeType: 'application/pdf');
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: i18n.t('searchByToolOrLastName'),
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: companyMovesRef(widget.companyId).orderBy('createdAt', descending: true).snapshots(),
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());

              final docs = s.data!.docs.where((d) {
                final data = d.data();
                final tool = (data['toolName'] ?? '').toString().toLowerCase();
                final inv = (data['inv'] ?? '').toString().toLowerCase();
                final person = (data['personName'] ?? '').toString().toLowerCase();
                return tool.contains(_searchQuery) || inv.contains(_searchQuery) || person.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) return Center(child: Text(i18n.t('historyEmpty')));

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final data = docs[i].data();
                  final type = (data['type'] ?? '').toString();
                  final person = (data['personName'] ?? '').toString();
                  final pos = (data['personPos'] ?? '').toString();
                  final tool = (data['toolName'] ?? '').toString();
                  final inv = (data['inv'] ?? '').toString();

                  final title = type == 'out' ? i18n.t('issued') : i18n.t('returned');
                  final ts = data['createdAt'];
                  String dateStr = '';
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    dateStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
                  }
                  final moveId = docs[i].id;
                  return ListTile(
                    leading: Icon(
                      type == 'out' ? Icons.arrow_upward : Icons.arrow_downward,
                      color: type == 'out' ? Colors.orange : Colors.green,
                    ),
                    title: Text('$title: $tool â $inv'),
                    subtitle: Text('$person${pos.isNotEmpty ? " ($pos)" : ""}${dateStr.isNotEmpty ? " Â· $dateStr" : ""}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      tooltip: i18n.t('actPdf'),
                      onPressed: () => _exportActPdf(
                        moveId: moveId,
                        type: type,
                        toolName: tool,
                        inv: inv,
                        personName: person,
                        personPos: pos,
                        createdAt: ts,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ---------- TAB: Reports (ÐÐ¢Ð§ÐÐ¢Ð«)
class ReportsTab extends StatefulWidget {
  final String companyId;
  const ReportsTab({super.key, required this.companyId});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> with SingleTickerProviderStateMixin {
  Future<void> _openOnWindows(String path) async {
    try {
      // Opens file with the default associated app on Windows.
      await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
    } catch (_) {}
  }

  late final TabController _tab;
  String? _selectedToolName;
  String? _selectedPersonId;
  String? _selectedPersonName;

  // -------- Sorting helpers (same logic everywhere) --------
  String _norm(String s) {
    var x = s.trim().toLowerCase();
    // RU
    x = x.replaceAll('Ñ', 'Ðµ');
    // UA
    x = x.replaceAll('Ñ', 'Ðµ');
    x = x.replaceAll('Ñ', 'Ð¸');
    x = x.replaceAll('Ñ', 'Ð¸');
    // PL diacritics (basic)
    x = x.replaceAll('Ä', 'a').replaceAll('Ä', 'c').replaceAll('Ä', 'e')
         .replaceAll('Å', 'l').replaceAll('Å', 'n').replaceAll('Ã³', 'o')
         .replaceAll('Å', 's').replaceAll('Å¼', 'z').replaceAll('Åº', 'z');
    return x;
  }

  int _invSort(String a, String b) {
    // Sort like LDL-004, LDL-017, etc.
    final ra = RegExp(r'^([A-Za-z]+)[\-_ ]*0*([0-9]+)$');
    final ma = ra.firstMatch(a.trim());
    final mb = ra.firstMatch(b.trim());
    if (ma != null && mb != null) {
      final pa = ma.group(1)!.toUpperCase();
      final pb = mb.group(1)!.toUpperCase();
      final c1 = pa.compareTo(pb);
      if (c1 != 0) return c1;
      final na = int.tryParse(ma.group(2)!) ?? 0;
      final nb = int.tryParse(mb.group(2)!) ?? 0;
      return na.compareTo(nb);
    }
    return a.compareTo(b);
  }


  String _personLabel(Map<String, dynamic> p) {
    final n = (p['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final fn = (p['firstName'] ?? '').toString().trim();
    final ln = (p['lastName'] ?? '').toString().trim();
    final full = ('$fn $ln').trim();
    if (full.isNotEmpty) return full;
    final phone = (p['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return p['id']?.toString() ?? '';
  }


  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<Map<String, Map<String, dynamic>>> _lastByInv() async {
    // Read ALL moves once and compute last move per inv (or toolId fallback).
    final snap = await companyMovesRef(widget.companyId).get();
    final Map<String, Map<String, dynamic>> best = {};
    int tsOf(Map<String, dynamic> m) {
      final t = m['createdAt'];
      // Firestore Timestamp or int millis
      if (t is Timestamp) return t.millisecondsSinceEpoch;
      final ms = m['createdAtMs'];
      if (ms is int) return ms;
      if (ms is String) return int.tryParse(ms) ?? 0;
      return 0;
    }

    for (final d in snap.docs) {
      final m = d.data();
      final inv = (m['inv'] ?? '').toString().trim();
      final toolId = (m['toolId'] ?? '').toString().trim();
      final key = inv.isNotEmpty ? inv : toolId;
      if (key.isEmpty) continue;

      final cur = best[key];
      if (cur == null || tsOf(m) > tsOf(cur)) {
        best[key] = m;
      }
    }
    return best;
  }

  Future<File> _saveBytes(String filename, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openOrShare(File file, {String? mimeType}) async {
    try {
      if (Platform.isWindows) {
        await _openOnWindows(file.path);
      } else {
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ð¤Ð°Ð¹Ð» ÑÐ¾ÑÑÐ°Ð½ÑÐ½: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° ÑÐºÑÐ¿Ð¾ÑÑÐ°: $e')),
        );
      }
    }
  }

  // Save exported bytes to a writable location and then open (Windows) or share (mobile).
  Future<void> _saveAndOpenExport({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
  }) async {
    final file = await _saveBytes(fileName, bytes);
    await _openOrShare(file, mimeType: mimeType);
  }



  Future<void> _exportToolPdf(I18n i18n, String toolName, List<Map<String, dynamic>> rows) async {
    // ÐÐ¾Ð»ÑÑÐ°ÐµÐ¼ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ðµ ÐºÐ¾Ð¼Ð¿Ð°Ð½Ð¸Ð¸
    String companyName = 'ToolKeeper';
    try {
      final companySnap = await companyDoc(widget.companyId).get();
      if (companySnap.exists) {
        companyName = (companySnap.data()?['name'] ?? 'ToolKeeper').toString();
      }
    } catch (_) {}

    final doc = pw.Document(theme: await _pdfTheme());

    final headers = <String>[
      i18n.t('tool'),
      i18n.t('inv'),
      i18n.t('where'),
      i18n.t('issuedAt'),
    ];

    final data = rows.map((r) {
      return <String>[
        (r['toolName'] ?? '').toString(),
        (r['inv'] ?? '').toString(),
        (r['where'] ?? '').toString(),
        (r['issuedAt'] ?? '').toString(),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(
            companyName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            toolName,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(2.0),
            },
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('_______________________', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('${i18n.t('name')}: ', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await _saveAndOpenExport(
      bytes: bytes,
      fileName: 'report_tool_${DateTime.now().millisecondsSinceEpoch}.pdf',
      mimeType: 'application/pdf',
    );
  }

  Future<void> _exportToolXlsx(I18n i18n, String toolName, List<Map<String, dynamic>> rows) async {
    // ÐÐ¾Ð»ÑÑÐ°ÐµÐ¼ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ðµ ÐºÐ¾Ð¼Ð¿Ð°Ð½Ð¸Ð¸
    String companyName = 'ToolKeeper';
    try {
      final companySnap = await companyDoc(widget.companyId).get();
      if (companySnap.exists) {
        companyName = (companySnap.data()?['name'] ?? 'ToolKeeper').toString();
      }
    } catch (_) {}

    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    // ÐÐ¾Ð±Ð°Ð²Ð»ÑÐµÐ¼ Ð·Ð°Ð³Ð¾Ð»Ð¾Ð²Ð¾Ðº Ñ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸ÐµÐ¼ ÐºÐ¾Ð¼Ð¿Ð°Ð½Ð¸Ð¸
    sheet.appendRow([TextCellValue('$companyName â $toolName')]);
    sheet.appendRow([TextCellValue('')]);

    final h1 = i18n.t('tool');
    final h2 = i18n.t('inv');
    final h3 = i18n.t('where');
    final h4 = i18n.t('issuedAt');

    final maxLens = <int>[h1.length, h2.length, h3.length, h4.length];

    void upd(int idx, String v) {
      if (v.length > maxLens[idx]) maxLens[idx] = v.length;
    }

    sheet.appendRow([
      TextCellValue(h1),
      TextCellValue(h2),
      TextCellValue(h3),
      TextCellValue(h4),
    ]);

    for (final r in rows) {
      final v1 = (r['toolName'] ?? '').toString();
      final v2 = (r['inv'] ?? '').toString();
      final v3 = (r['where'] ?? '').toString();
      final v4 = (r['issuedAt'] ?? '').toString();

      upd(0, v1);
      upd(1, v2);
      upd(2, v3);
      upd(3, v4);

      sheet.appendRow([
        TextCellValue(v1),
        TextCellValue(v2),
        TextCellValue(v3),
        TextCellValue(v4),
      ]);
    }

    // Simple auto-width (in "character" units). Keeps it readable without manual resizing.
    for (var c = 0; c < maxLens.length; c++) {
      final w = (maxLens[c] + 2).clamp(10, 60).toDouble();
      sheet.setColumnWidth(c, w);
    }

    final bytes = excel.encode()!;
    await _saveAndOpenExport(
      bytes: bytes,
      fileName: 'report_tool_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _exportNakladnayaPdf(
    String personName,
    String personPos,
    List<Map<String, dynamic>> rows,
  ) async {
    String companyName = 'ToolKeeper';
    try {
      final snap = await companyDoc(widget.companyId).get();
      if (snap.exists) companyName = (snap.data()?['name'] ?? 'ToolKeeper').toString();
    } catch (_) {}

    final theme = await _pdfTheme();
    final doc = pw.Document(theme: theme);
    final now = DateTime.now();
    final dd = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    final tableData = rows.asMap().entries.map((e) {
      final idx = e.key;
      final m = e.value;
      return [
        '${idx + 1}',
        (m['toolName'] ?? '').toString(),
        (m['inv'] ?? '').toString(),
        _formatTs(m['createdAt']),
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => [
        pw.Text(companyName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Text(
            'ÐÐÐÐÐÐÐÐÐ¯ ÐÐ ÐÐ«ÐÐÐ§Ð£ ÐÐÐ¡Ð¢Ð Ð£ÐÐÐÐ¢Ð',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('Ð¾Ñ $dd', style: const pw.TextStyle(fontSize: 11))),
        pw.SizedBox(height: 16),
        pw.Text(
          'ÐÐ¾Ð»ÑÑÐ°ÑÐµÐ»Ñ: $personName${personPos.isNotEmpty ? " ($personPos)" : ""}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 16),
        pw.Table.fromTextArray(
          headers: ['â', 'ÐÐ½ÑÑÑÑÐ¼ÐµÐ½Ñ', 'ÐÐ½Ð². â', 'ÐÐ°ÑÐ° Ð²ÑÐ´Ð°ÑÐ¸'],
          data: tableData,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          columnWidths: const {
            0: pw.FixedColumnWidth(24),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(2),
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'ÐÑÐ¾Ð³Ð¾ ÐµÐ´Ð¸Ð½Ð¸Ñ: ${rows.length}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
        ),
        pw.SizedBox(height: 40),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ÐÑÐ´Ð°Ð»:', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 24),
                  pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ÐÐ¾Ð»ÑÑÐ¸Ð»:', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 24),
                  pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
          ],
        ),
      ],
    ));

    final bytes = await doc.save();
    await _saveAndOpenExport(
      bytes: bytes,
      fileName: 'nakladnaya_${DateTime.now().millisecondsSinceEpoch}.pdf',
      mimeType: 'application/pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Column(
      children: [
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [
            Tab(text: i18n.t('reportsByTool')),
            Tab(text: i18n.t('reportsByPerson')),
            Tab(text: i18n.t('warehouse')),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
              tooltip: 'Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: () async {
                try {
                  final last = await _lastByInv();
                  if (_tab.index == 0) {
                    final tname = _selectedToolName;
                    if (tname == null || tname.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('selectToolFirst'))));
                      return;
                    }
                    final toolsSnap = await companyToolsRef(widget.companyId).where('name', isEqualTo: tname).get();
                    final rows = <Map<String, dynamic>>[];
                    for (final d in toolsSnap.docs) {
                      final t = d.data();
                      final inv = (t['inv'] ?? '').toString().trim();
                      final m = last[inv];
                      final isOut = m != null && (m['type'] ?? '') == 'out';
                      final where = isOut ? (m['personName'] ?? '') : i18n.t('warehouse');
                      final issuedAt = isOut ? _formatTs(m['createdAt']) : '';
                      rows.add({'toolName': tname, 'inv': inv, 'where': where, 'issuedAt': issuedAt});
                    }
                    rows.sort((a,b)=>_invSort((a['inv']??'').toString(), (b['inv']??'').toString()));
                    await _exportToolXlsx(i18n, tname, rows);
                  } else if (_tab.index == 1) {
                    final pid = _selectedPersonId;
                    if (pid == null || pid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('selectPersonFirst'))));
                      return;
                    }
                    final rows = <Map<String, dynamic>>[];
                    for (final e in last.entries) {
                      final m = e.value;
                      if ((m['type'] ?? '') != 'out') continue;
                      if ((m['personId'] ?? '').toString() != pid) continue;
                      rows.add({
                        'toolName': m['toolName'] ?? '',
                        'inv': m['inv'] ?? '',
                        'where': m['personName'] ?? '',
                        'issuedAt': _formatTs(m['createdAt']),
                      });
                    }
                    rows.sort((a,b){
                      final na=_norm((a['toolName']??'').toString());
                      final nb=_norm((b['toolName']??'').toString());
                      final c=na.compareTo(nb);
                      if (c!=0) return c;
                      return _invSort((a['inv']??'').toString(), (b['inv']??'').toString());
                    });
                    final personTitle = (_selectedPersonName != null && _selectedPersonName!.trim().isNotEmpty)
                        ? _selectedPersonName!.trim()
                        : pid;
                    await _exportToolXlsx(i18n, personTitle, rows);
                  } else if (_tab.index == 2) {
                    // Ð­ÐºÑÐ¿Ð¾ÑÑ ÑÐºÐ»Ð°Ð´Ð°
                    final rows = <Map<String, dynamic>>[];
                    for (final e in last.entries) {
                      final m = e.value;
                      if ((m['type'] ?? '') == 'out') continue; // ÐÑÐ¾Ð¿ÑÑÐºÐ°ÐµÐ¼ Ð²ÑÐ´Ð°Ð½Ð½ÑÐµ
                      rows.add({
                        'toolName': m['toolName'] ?? '',
                        'inv': m['inv'] ?? '',
                        'where': i18n.t('warehouse'),
                        'issuedAt': '',
                      });
                    }
                    // ÐÐ¾Ð±Ð°Ð²Ð»ÑÐµÐ¼ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ Ð±ÐµÐ· Ð´Ð²Ð¸Ð¶ÐµÐ½Ð¸Ð¹
                    final toolsSnap = await companyToolsRef(widget.companyId).get();
                    for (final d in toolsSnap.docs) {
                      final t = d.data();
                      final inv = (t['inv'] ?? '').toString().trim();
                      final status = (t['status'] ?? 'active').toString();
                      if (status != 'active') continue;
                      if (!last.containsKey(inv)) {
                        rows.add({
                          'toolName': t['name'] ?? '',
                          'inv': inv,
                          'where': i18n.t('warehouse'),
                          'issuedAt': '',
                        });
                      }
                    }
                    rows.sort((a,b){
                      final na=_norm((a['toolName']??'').toString());
                      final nb=_norm((b['toolName']??'').toString());
                      final c=na.compareTo(nb);
                      if (c!=0) return c;
                      return _invSort((a['inv']??'').toString(), (b['inv']??'').toString());
                    });
                    await _exportToolXlsx(i18n, i18n.t('warehouse'), rows);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° ÑÐºÑÐ¿Ð¾ÑÑÐ°: $e')));
                }
              },
            ),
              IconButton(
              tooltip: 'PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                try {
                  final last = await _lastByInv();
                  if (_tab.index == 0) {
                    final tname = _selectedToolName;
                    if (tname == null || tname.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('selectToolFirst'))));
                      return;
                    }
                    final toolsSnap = await companyToolsRef(widget.companyId).where('name', isEqualTo: tname).get();
                    final rows = <Map<String, dynamic>>[];
                    for (final d in toolsSnap.docs) {
                      final t = d.data();
                      final inv = (t['inv'] ?? '').toString().trim();
                      final m = last[inv];
                      final isOut = m != null && (m['type'] ?? '') == 'out';
                      final where = isOut ? (m['personName'] ?? '') : i18n.t('warehouse');
                      final issuedAt = isOut ? _formatTs(m['createdAt']) : '';
                      rows.add({'toolName': tname, 'inv': inv, 'where': where, 'issuedAt': issuedAt});
                    }
                    rows.sort((a,b)=>_invSort((a['inv']??'').toString(), (b['inv']??'').toString()));
                    await _exportToolPdf(i18n, tname, rows);
                  } else if (_tab.index == 1) {
                    final pid = _selectedPersonId;
                    if (pid == null || pid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('selectPersonFirst'))));
                      return;
                    }
                    final rows = <Map<String, dynamic>>[];
                    for (final e in last.entries) {
                      final m = e.value;
                      if ((m['type'] ?? '') != 'out') continue;
                      if ((m['personId'] ?? '').toString() != pid) continue;
                      rows.add({
                        'toolName': m['toolName'] ?? '',
                        'inv': m['inv'] ?? '',
                        'where': m['personName'] ?? '',
                        'issuedAt': _formatTs(m['createdAt']),
                      });
                    }
                    rows.sort((a,b){
                      final na=_norm((a['toolName']??'').toString());
                      final nb=_norm((b['toolName']??'').toString());
                      final c=na.compareTo(nb);
                      if (c!=0) return c;
                      return _invSort((a['inv']??'').toString(), (b['inv']??'').toString());
                    });
                    final personTitle = (_selectedPersonName != null && _selectedPersonName!.trim().isNotEmpty)
                        ? _selectedPersonName!.trim()
                        : pid;
                    await _exportToolPdf(i18n, personTitle, rows);
                  } else if (_tab.index == 2) {
                    // Ð­ÐºÑÐ¿Ð¾ÑÑ ÑÐºÐ»Ð°Ð´Ð° PDF
                    final rows = <Map<String, dynamic>>[];
                    for (final e in last.entries) {
                      final m = e.value;
                      if ((m['type'] ?? '') == 'out') continue;
                      rows.add({
                        'toolName': m['toolName'] ?? '',
                        'inv': m['inv'] ?? '',
                        'where': i18n.t('warehouse'),
                        'issuedAt': '',
                      });
                    }
                    final toolsSnap = await companyToolsRef(widget.companyId).get();
                    for (final d in toolsSnap.docs) {
                      final t = d.data();
                      final inv = (t['inv'] ?? '').toString().trim();
                      final status = (t['status'] ?? 'active').toString();
                      if (status != 'active') continue;
                      if (!last.containsKey(inv)) {
                        rows.add({
                          'toolName': t['name'] ?? '',
                          'inv': inv,
                          'where': i18n.t('warehouse'),
                          'issuedAt': '',
                        });
                      }
                    }
                    rows.sort((a,b){
                      final na=_norm((a['toolName']??'').toString());
                      final nb=_norm((b['toolName']??'').toString());
                      final c=na.compareTo(nb);
                      if (c!=0) return c;
                      return _invSort((a['inv']??'').toString(), (b['inv']??'').toString());
                    });
                    await _exportToolPdf(i18n, i18n.t('warehouse'), rows);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° ÑÐºÑÐ¿Ð¾ÑÑÐ°: $e')));
                }
              },
            ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildByTool(context, i18n),
              _buildByPerson(context, i18n),
              _buildWarehouse(context, i18n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildByTool(BuildContext context, I18n i18n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyToolsRef(widget.companyId).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs.map((d) => d.data()).toList();
        // group by name
        final Map<String, int> counts = {};
        for (final t in docs) {
          final name = (t['name'] ?? '').toString();
          if (name.isEmpty) continue;
          counts[name] = (counts[name] ?? 0) + 1;
        }
        final names = counts.keys.toList()
          ..sort((a,b)=>_norm(a).compareTo(_norm(b)));

        _selectedToolName ??= names.isNotEmpty ? names.first : null;

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _lastByInv(),
          builder: (c2, s2) {
            if (!s2.hasData) return const Center(child: CircularProgressIndicator());
            final last = s2.data!;

            final selected = _selectedToolName;
            final toolItems = docs.where((t)=> (t['name'] ?? '').toString() == selected).toList()
              ..sort((a,b)=>_invSort((a['inv']??'').toString(), (b['inv']??'').toString()));

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: InputDecoration(
                    labelText: i18n.t('selectTool'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: names.map((n)=>DropdownMenuItem(value: n, child: Text('$n (${counts[n]})'))).toList(),
                  onChanged: (v)=>setState(()=>_selectedToolName=v),
                ),
                const SizedBox(height: 12),
                if (selected == null || toolItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(i18n.t('noData'))),
                  )
                else
                  ...toolItems.map((t) {
                    final inv = (t['inv'] ?? '').toString().trim();
                    final m = last[inv];
                    final isOut = m != null && (m['type'] ?? '') == 'out';
                    final where = isOut ? (m['personName'] ?? '') : i18n.t('warehouse');
                    final issuedAt = isOut ? _formatTs(m['createdAt']) : '';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.build),
                        title: Text('${i18n.t('inv')}: $inv'),
                        subtitle: Text('${i18n.t('where')}: $where\n${i18n.t('issuedAt')}: $issuedAt'),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildByPerson(BuildContext context, I18n i18n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyPeopleRef(widget.companyId).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final people = s.data!.docs.map((d)=>{'id': d.id, ...(d.data())}).toList();
        people.sort((a,b)=>_norm(_personLabel(a)).compareTo(_norm(_personLabel(b))));

        _selectedPersonId ??= people.isNotEmpty ? people.first['id'].toString() : null;

        // Keep a cached human-readable name for exports (PDF/Excel) so we don't show person_xxx ids.
        if (_selectedPersonId != null && (_selectedPersonName == null || _selectedPersonName!.trim().isEmpty)) {
          final p = people.firstWhere(
            (e) => (e['id']?.toString() ?? '') == _selectedPersonId,
            orElse: () => const <String, dynamic>{},
          );
          if (p.isNotEmpty) {
            _selectedPersonName = _personLabel(p);
          }
        }

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _lastByInv(),
          builder: (c2, s2) {
            if (!s2.hasData) return const Center(child: CircularProgressIndicator());
            final last = s2.data!;
            final pid = _selectedPersonId;

            final rows = <Map<String, dynamic>>[];
            if (pid != null) {
              for (final e in last.entries) {
                final m = e.value;
                if ((m['type'] ?? '') != 'out') continue; // returned tools are NOT on hands
                if ((m['personId'] ?? '').toString() != pid) continue;
                rows.add(m);
              }
              rows.sort((a,b){
                final na=_norm((a['toolName']??'').toString());
                final nb=_norm((b['toolName']??'').toString());
                final c=na.compareTo(nb);
                if (c!=0) return c;
                return _invSort((a['inv']??'').toString(), (b['inv']??'').toString());
              });
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                DropdownButtonFormField<String>(
                  value: pid,
                  decoration: InputDecoration(
                    labelText: i18n.t('selectPerson'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: people.map((p)=>DropdownMenuItem(value: p['id'].toString(), child: Text(_personLabel(p)))).toList(),
                  onChanged: (v){
                    final p = people.firstWhere((x)=>x['id'].toString()==v, orElse: ()=>{});
                    setState((){ _selectedPersonId=v; _selectedPersonName = (p.isEmpty ? null : _personLabel(p)); });
                  },
                ),
                const SizedBox(height: 12),
                if (pid == null)
                  Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(i18n.t('noData'))))
                else if (rows.isEmpty)
                  Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(i18n.t('noIssued'))))
                else ...[
                  ...rows.map((m){
                    final inv = (m['inv'] ?? '').toString();
                    final toolName = (m['toolName'] ?? '').toString();
                    final issuedAt = _formatTs(m['createdAt']);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.build),
                        title: Text('$toolName â¢ ${i18n.t('inv')}: $inv'),
                        subtitle: Text('${i18n.t('issuedAt')}: $issuedAt'),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(i18n.t('nakladnayaPdf')),
                      onPressed: () {
                        final personPos = rows.isNotEmpty ? (rows.first['personPos'] ?? '').toString() : '';
                        _exportNakladnayaPdf(_selectedPersonName ?? pid ?? '', personPos, rows);
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWarehouse(BuildContext context, I18n i18n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyToolsRef(widget.companyId).snapshots(),
      builder: (c, toolsSnap) {
        if (!toolsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: companyMovesRef(widget.companyId).snapshots(),
          builder: (c, movesSnap) {
            if (!movesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // ÐÑÑÐ¸ÑÐ»ÑÐµÐ¼ Ð¿Ð¾ÑÐ»ÐµÐ´Ð½ÐµÐµ Ð´Ð²Ð¸Ð¶ÐµÐ½Ð¸Ðµ Ð¿Ð¾ ÐºÐ°Ð¶Ð´Ð¾Ð¼Ñ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ
            final Map<String, Map<String, dynamic>> lastByToolId = {};
            for (final d in movesSnap.data!.docs) {
              final m = d.data();
              final toolId = (m['toolId'] ?? '').toString();
              if (toolId.isEmpty) continue;

              final cur = lastByToolId[toolId];
              if (cur == null || _tsOf(m) > _tsOf(cur)) {
                lastByToolId[toolId] = m;
              }
            }

            // Ð¤Ð¸Ð»ÑÑÑÑÐµÐ¼ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½ÑÐµ Ð¸Ð½ÑÑÑÑÐ¼ÐµÐ½ÑÑ
            final freeTools = <Map<String, dynamic>>[];
            for (final d in toolsSnap.data!.docs) {
              final toolData = d.data();
              final toolId = d.id;
              final toolName = (toolData['name'] ?? '').toString();
              final inv = (toolData['inv'] ?? '').toString();
              final status = (toolData['status'] ?? 'active').toString();

              if (status != 'active') continue;

              final lastMove = lastByToolId[toolId];
              if (lastMove == null) {
                // ÐÐµÑ Ð´Ð²Ð¸Ð¶ÐµÐ½Ð¸Ð¹ â ÑÐ²Ð¾Ð±Ð¾Ð´ÐµÐ½
                freeTools.add({
                  'toolId': toolId,
                  'toolName': toolName,
                  'inv': inv,
                });
              } else {
                final lastType = (lastMove['type'] ?? '').toString();
                if (lastType != 'out') {
                  // ÐÐ¾ÑÐ»ÐµÐ´Ð½ÐµÐµ Ð´Ð²Ð¸Ð¶ÐµÐ½Ð¸Ðµ â Ð²Ð¾Ð·Ð²ÑÐ°Ñ, Ð·Ð½Ð°ÑÐ¸Ñ ÑÐ²Ð¾Ð±Ð¾Ð´ÐµÐ½
                  freeTools.add({
                    'toolId': toolId,
                    'toolName': toolName,
                    'inv': inv,
                  });
                }
              }
            }

            // ÐÑÑÐ¿Ð¿Ð¸ÑÑÐµÐ¼ Ð¿Ð¾ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ
            final Map<String, List<Map<String, dynamic>>> grouped = {};
            for (final t in freeTools) {
              final name = t['toolName'] as String;
              grouped.putIfAbsent(name, () => []).add(t);
            }

            // Ð¡Ð¾ÑÑÐ¸ÑÑÐµÐ¼ Ð½Ð°Ð·Ð²Ð°Ð½Ð¸Ñ
            final sortedNames = grouped.keys.toList()..sort((a, b) => _norm(a).compareTo(_norm(b)));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (freeTools.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(i18n.t('noFreeTool')),
                    ),
                  )
                else
                  ...sortedNames.map((name) {
                    final items = grouped[name]!;
                    // Ð¡Ð¾ÑÑÐ¸ÑÑÐµÐ¼ Ð¸Ð½Ð²ÐµÐ½ÑÐ°ÑÐ½ÑÐµ Ð½Ð¾Ð¼ÐµÑÐ° Ð²Ð½ÑÑÑÐ¸ Ð³ÑÑÐ¿Ð¿Ñ
                    items.sort((a, b) => _invSort(a['inv'] as String, b['inv'] as String));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                          '$name  Ã${items.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        children: items.map((t) {
                          final inv = t['inv'] as String;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined, size: 20),
                            title: Text(inv.isNotEmpty ? inv : 'â'),
                          );
                        }).toList(),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  int _tsOf(Map<String, dynamic> m) {
    final t = m['createdAt'];
    if (t is Timestamp) return t.millisecondsSinceEpoch;
    final ms = m['createdAtMs'];
    if (ms is int) return ms;
    if (ms is String) return int.tryParse(ms) ?? 0;
    return 0;
  }

  String _formatTs(dynamic ts) {
    try {
      DateTime dt;
      if (ts is Timestamp) dt = ts.toDate();
      else if (ts is int) dt = DateTime.fromMillisecondsSinceEpoch(ts);
      else return '';
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = dt.year.toString();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$dd.$mm.$yy $hh:$mi';
    } catch (_) {
      return '';
    }
  }
}


  String _personDisplay(Map<String, dynamic> p) {
    final name = (p['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final fn = (p['firstName'] ?? '').toString().trim();
    final ln = (p['lastName'] ?? '').toString().trim();
    final full = ('$fn $ln').trim();
    return full.isNotEmpty ? full : (p['phone'] ?? '').toString().trim();
  }



/// ===================
/// EMPLOYEE PROFILE EDIT
/// ===================
class EmployeeProfileEditPage extends StatefulWidget {
  final String employeeUid;
  const EmployeeProfileEditPage({super.key, required this.employeeUid});

  @override
  State<EmployeeProfileEditPage> createState() => _EmployeeProfileEditPageState();
}


  Future<pw.ThemeData> _pdfTheme() async {
    // Use bundled assets font for cross-platform Cyrillic support (iOS fix)
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final font = pw.Font.ttf(fontData);
      return pw.ThemeData.withFont(base: font, bold: font);
    } catch (e) {
      return pw.ThemeData();
    }
  }

class _EmployeeProfileEditPageState extends State<EmployeeProfileEditPage> {
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  final birthCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final shoeCtrl = TextEditingController();
  final clothesCtrl = TextEditingController();

  bool loading = false;
  String? error;
  bool _prefilled = false;

  @override
  void dispose() {
    for (var c in [firstCtrl, lastCtrl, birthCtrl, phoneCtrl, shoeCtrl, clothesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefillOnce(Map<String, dynamic> data) {
    if (_prefilled) return;
    _prefilled = true;
    firstCtrl.text = (data['firstName'] ?? '').toString();
    lastCtrl.text = (data['lastName'] ?? '').toString();
    birthCtrl.text = (data['birthDate'] ?? '').toString();
    phoneCtrl.text = (data['phone'] ?? '').toString();
    shoeCtrl.text = (data['shoeSize'] ?? '').toString();
    // legacy key: clothesSize, new key: clothingSize
    clothesCtrl.text = (data['clothingSize'] ?? data['clothesSize'] ?? '').toString();
  }

  Future<void> _save() async {
    final i18n = I18n(AppState.of(context).lang.value);
    setState(() { loading = true; error = null; });

    try {
      if (firstCtrl.text.isEmpty || lastCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
        throw Exception(i18n.t('needProfile'));
      }

      await userDoc(widget.employeeUid).set({
        'firstName': firstCtrl.text.trim(),
        'lastName': lastCtrl.text.trim(),
        'birthDate': birthCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'shoeSize': shoeCtrl.text.trim(),
        // write both keys for backward compatibility
        'clothingSize': clothesCtrl.text.trim(),
        'clothesSize': clothesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uidOrThrow(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('done'))));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc(widget.employeeUid).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = s.data!.data() ?? {};
        _prefillOnce(data);

        return Scaffold(
          appBar: AppBar(title: Text(i18n.t('editProfile'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: firstCtrl, decoration: InputDecoration(labelText: i18n.t('firstName'))),
              const SizedBox(height: 10),
              TextField(controller: lastCtrl, decoration: InputDecoration(labelText: i18n.t('lastName'))),
              const SizedBox(height: 10),
              TextField(controller: birthCtrl, decoration: InputDecoration(labelText: i18n.t('birthDate'))),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: i18n.t('phone'), hintText: '+7...')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: shoeCtrl, decoration: InputDecoration(labelText: i18n.t('shoeSize')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: clothesCtrl, decoration: InputDecoration(labelText: i18n.t('clothesSize')))),
                ],
              ),
              const SizedBox(height: 20),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : _save,
                  child: loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(i18n.t('save')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============== TIME TRACKING CLASSES ==============

// Ð¡ÑÑÐ°Ð½Ð¸ÑÐ° ÑÐ¿ÑÐ°Ð²Ð»ÐµÐ½Ð¸Ñ Ð¾Ð±ÑÐµÐºÑÐ°Ð¼Ð¸ (Ð´Ð»Ñ Ð°Ð´Ð¼Ð¸Ð½Ð°)
class SitesPage extends StatefulWidget {
  final String companyId;
  
  const SitesPage({super.key, required this.companyId});
  
  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  @override
  Widget build(BuildContext context) {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('sites'), style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: companySitesRef(widget.companyId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final sites = snapshot.data!.docs;
          
          if (sites.isEmpty) {
            return Center(child: Text(i18n.t('noSites')));
          }
          
          return ListView.builder(
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final doc = sites[index];
              final data = doc.data();
              final name = data['name'] ?? '';
              final address = data['address'] ?? '';
              
              final interval = (data['gpsIntervalMinutes'] as int?) ?? 15;
              return ListTile(
                title: Text(name),
                subtitle: Text('$address\nGPS: $interval Ð¼Ð¸Ð½'),
                isThreeLine: address.isNotEmpty,
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _addOrEditSite(existing: data, siteId: doc.id),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditSite(),
        child: const Icon(Icons.add),
      ),
    );
  }
  
  Future<void> _addOrEditSite({Map<String, dynamic>? existing, String? siteId}) async {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);
    
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final addressController = TextEditingController(text: existing?['address'] ?? '');
    final latController = TextEditingController(text: (existing?['latitude'] ?? 0.0).toString());
    final lngController = TextEditingController(text: (existing?['longitude'] ?? 0.0).toString());
    final radiusController = TextEditingController(text: (existing?['radius'] ?? 100).toString());
    int selectedInterval = (existing?['gpsIntervalMinutes'] as int?) ?? 15;
    bool saving = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
        title: Text(existing == null ? i18n.t('addSite') : i18n.t('editSite')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: InputDecoration(labelText: i18n.t('siteName')), controller: nameController),
              TextField(decoration: InputDecoration(labelText: i18n.t('siteAddress')), controller: addressController),
              TextField(decoration: InputDecoration(labelText: 'Latitude'), controller: latController, keyboardType: TextInputType.number),
              TextField(decoration: InputDecoration(labelText: 'Longitude'), controller: lngController, keyboardType: TextInputType.number),
              TextField(decoration: InputDecoration(labelText: i18n.t('siteRadius')), controller: radiusController, keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: selectedInterval,
                decoration: InputDecoration(labelText: i18n.t('gpsInterval')),
                items: [5, 15, 30, 60].map((v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v Ð¼Ð¸Ð½'),
                )).toList(),
                onChanged: (v) { if (v != null) setDlg(() => selectedInterval = v); },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('cancel'))),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              TextButton(
                onPressed: saving ? null : () async {
                  if (nameController.text.trim().isEmpty) {
                    setDlg(() => err = '${i18n.t('siteName')} â Ð¾Ð±ÑÐ·Ð°ÑÐµÐ»ÑÐ½Ð¾Ðµ Ð¿Ð¾Ð»Ðµ');
                    return;
                  }
                  setDlg(() { saving = true; err = null; });
                  try {
                    final ref = siteId == null
                        ? companySitesRef(widget.companyId).doc()
                        : companySitesRef(widget.companyId).doc(siteId);
                    await ref.set({
                      'name': nameController.text.trim(),
                      'address': addressController.text.trim(),
                      'latitude': double.tryParse(latController.text) ?? 0.0,
                      'longitude': double.tryParse(lngController.text) ?? 0.0,
                      'radius': int.tryParse(radiusController.text) ?? 100,
                      'gpsIntervalMinutes': selectedInterval,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    setDlg(() { saving = false; err = e.toString(); });
                  }
                },
                child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(i18n.t('save')),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ÐÐ¸Ð´Ð¶ÐµÑ ÐºÐ½Ð¾Ð¿ÐºÐ¸ Ð½Ð°ÑÐ°Ð»Ð°/ÐºÐ¾Ð½ÑÐ° ÑÐ¼ÐµÐ½Ñ
class ShiftButton extends StatefulWidget {
  final String companyId;
  final String userId;
  final String userName;
  
  const ShiftButton({super.key, required this.companyId, required this.userId, required this.userName});
  
  @override
  State<ShiftButton> createState() => _ShiftButtonState();
}

class _ShiftButtonState extends State<ShiftButton> {
  // ID Ð°Ð½ÐºÐµÑÑ, Ðº ÐºÐ¾ÑÐ¾ÑÐ¾Ð¹ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ñ (null = Ð½Ðµ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½)
  String? _linkedPersonId;
  bool _linkedPersonLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedPerson();
  }

  Future<void> _loadLinkedPerson() async {
    try {
      final snap = await companyPeopleRef(widget.companyId)
          .where('linkedUserId', isEqualTo: widget.userId)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        _linkedPersonId = snap.docs.isNotEmpty ? snap.docs.first.id : null;
        _linkedPersonLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _linkedPersonLoaded = true);
    }
  }

  // Ð ÐµÐ°Ð»ÑÐ½ÑÐ¹ ID Ð´Ð»Ñ Ð¿Ð¾Ð¸ÑÐºÐ° ÑÐ¼ÐµÐ½: Ð°Ð½ÐºÐµÑÐ° (ÐµÑÐ»Ð¸ Ð¿ÑÐ¸Ð²ÑÐ·Ð°Ð½) Ð¸Ð»Ð¸ uid
  String get _queryPersonId => _linkedPersonId ?? widget.userId;

  @override
  Widget build(BuildContext context) {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);

    if (!_linkedPersonLoaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyTimesheetsRef(widget.companyId)
          .where('personId', isEqualTo: _queryPersonId)
          .where('endTime', isNull: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final activeShifts = snapshot.data!.docs;

        if (activeShifts.isEmpty) {
          return ElevatedButton(
            onPressed: _startShift,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(i18n.t('startShift')),
          );
        }

        // ÐÐ´Ð½Ð° Ð¸Ð»Ð¸ Ð½ÐµÑÐºÐ¾Ð»ÑÐºÐ¾ Ð°ÐºÑÐ¸Ð²Ð½ÑÑ ÑÐ¼ÐµÐ½ â Ð¿Ð¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ Ð²ÑÐµ Ñ ÐºÐ½Ð¾Ð¿ÐºÐ°Ð¼Ð¸ Ð·Ð°Ð²ÐµÑÑÐµÐ½Ð¸Ñ
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeShifts.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'ÐÐºÑÐ¸Ð²Ð½ÑÑ ÑÐ¼ÐµÐ½: ${activeShifts.length}',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ...activeShifts.map((shiftDoc) {
              final shift = shiftDoc.data();
              final siteName = (shift['siteName'] ?? '').toString();
              final startTime = (shift['startTime'] as Timestamp?)?.toDate();
              final startStr = startTime != null
                  ? '${startTime.day.toString().padLeft(2,'0')}.${startTime.month.toString().padLeft(2,'0')} ${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}'
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${i18n.t('currentShift')}: $siteName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (startStr.isNotEmpty)
                      Text(startStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () => _endShift(shiftDoc.id),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: Text(i18n.t('endShift')),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
  
  Future<void> _startShift() async {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);

    // ÐÐ´Ð½Ð¾ÑÐ°Ð·Ð¾Ð²Ð¾Ðµ Ð¿ÑÐµÐ´ÑÐ¿ÑÐµÐ¶Ð´ÐµÐ½Ð¸Ðµ Ð¾Ð± Ð¾Ð¿ÑÐ¸Ð¼Ð¸Ð·Ð°ÑÐ¸Ð¸ Ð±Ð°ÑÐ°ÑÐµÐ¸ (Samsung/Xiaomi)
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('battery_tip_shown') ?? false;
      if (!shown && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('GPS-ÑÑÐµÐºÐ¸Ð½Ð³'),
            content: const Text(
              'ÐÐ»Ñ ÑÑÐ°Ð±Ð¸Ð»ÑÐ½Ð¾Ð¹ ÑÐ°Ð±Ð¾ÑÑ GPS Ð¾ÑÐºÐ»ÑÑÐ¸ÑÐµ Ð¾Ð¿ÑÐ¸Ð¼Ð¸Ð·Ð°ÑÐ¸Ñ Ð±Ð°ÑÐ°ÑÐµÐ¸:\n\n'
              'ÐÐ°ÑÑÑÐ¾Ð¹ÐºÐ¸ â ÐÑÐ¸Ð»Ð¾Ð¶ÐµÐ½Ð¸Ñ â ToolKeeper â ÐÐ°ÑÐ°ÑÐµÑ â ÐÐµÐ· Ð¾Ð³ÑÐ°Ð½Ð¸ÑÐµÐ½Ð¸Ð¹\n\n'
              'ÐÐµÐ· ÑÑÐ¾Ð³Ð¾ Samsung/Xiaomi Ð¼Ð¾Ð¶ÐµÑ Ð¾ÑÐºÐ»ÑÑÐ¸ÑÑ GPS ÑÐµÑÐµÐ· Ð½ÐµÑÐºÐ¾Ð»ÑÐºÐ¾ Ð¼Ð¸Ð½ÑÑ.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ÐÐ¾Ð½ÑÑÐ½Ð¾'),
              ),
            ],
          ),
        );
        await prefs.setBool('battery_tip_shown', true);
      }
    }
    if (!mounted) return;

    final sitesSnap = await companySitesRef(widget.companyId).get();
    if (!mounted) return;
    if (sitesSnap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('noSites'))));
      return;
    }

    // 1. ÐÐ¾ÑÐ»ÐµÐ´Ð½ÑÑ Ð¸Ð·Ð²ÐµÑÑÐ½Ð°Ñ Ð¿Ð¾Ð·Ð¸ÑÐ¸Ñ (Ð±ÐµÐ· Ð·Ð°Ð´ÐµÑÐ¶ÐºÐ¸) Ð´Ð»Ñ ÑÐ¸Ð»ÑÑÑÐ°ÑÐ¸Ð¸ Ð¾Ð±ÑÐµÐºÑÐ¾Ð²
    Position? lastPos;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        lastPos = await Geolocator.getLastKnownPosition();
      }
    } catch (_) {}
    if (!mounted) return;

    // 2. ÐÐ¾ÐºÐ°Ð·ÑÐ²Ð°ÐµÐ¼ ÑÐ¾Ð»ÑÐºÐ¾ Ð¾Ð±ÑÐµÐºÑÑ Ð² ÑÐ°Ð´Ð¸ÑÑÐµ 5000 Ð¼ (Ð¸Ð»Ð¸ Ð²ÑÐµ, ÐµÑÐ»Ð¸ GPS Ð½ÐµÐ´Ð¾ÑÑÑÐ¿ÐµÐ½)
    final allDocs = sitesSnap.docs;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> showDocs;
    if (lastPos != null) {
      final nearby = allDocs.where((d) {
        final lat = (d.data()['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (d.data()['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat == 0.0 && lng == 0.0) return true;
        return Geolocator.distanceBetween(lastPos!.latitude, lastPos!.longitude, lat, lng) <= 5000;
      }).toList();
      showDocs = nearby.isNotEmpty ? nearby : allDocs.toList();
    } else {
      showDocs = allDocs.toList();
    }

    // 3. ÐÑÐ±ÑÐ°ÑÑ Ð¾Ð±ÑÐµÐºÑ
    String? selectedSiteId;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('selectSite')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: showDocs.map((doc) {
              final data = doc.data();
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text(data['address'] ?? ''),
                onTap: () { selectedSiteId = doc.id; Navigator.pop(ctx); },
              );
            }).toList(),
          ),
        ),
      ),
    );
    if (selectedSiteId == null || !mounted) return;

    // Lookup linked person record â required to start a shift
    String personIdForShift = widget.userId;
    String personNameForShift = widget.userName;
    try {
      final linkedSnap = await companyPeopleRef(widget.companyId)
          .where('linkedUserId', isEqualTo: widget.userId)
          .limit(1)
          .get();
      if (!mounted) return;
      if (linkedSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('notLinked'))),
        );
        return;
      }
      final lp = linkedSnap.docs.first;
      final lpData = lp.data();
      personIdForShift = lp.id;
      final n = '${lpData['firstName'] ?? ''} ${lpData['lastName'] ?? ''}'.trim();
      if (n.isNotEmpty) personNameForShift = n;
    } catch (_) {}
    if (!mounted) return;

    // Block starting a new shift if one is already active for this person
    try {
      final activeSnap = await companyTimesheetsRef(widget.companyId)
          .where('personId', isEqualTo: personIdForShift)
          .where('endTime', isNull: true)
          .limit(1)
          .get();
      if (!mounted) return;
      if (activeSnap.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('alreadyHaveActiveShift'))),
        );
        return;
      }
    } catch (_) {}
    if (!mounted) return;

    // Shift type selection
    final shiftTypeResult = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = 'hourly';
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(i18n.t('chooseShiftType')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text(i18n.t('shiftTypeHourly')),
                  value: 'hourly',
                  groupValue: selected,
                  onChanged: (v) => setSt(() => selected = v!),
                ),
                RadioListTile<String>(
                  title: Text(i18n.t('shiftTypeAccord')),
                  value: 'accord',
                  groupValue: selected,
                  onChanged: (v) => setSt(() => selected = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: Text(i18n.t('ok'))),
            ],
          ),
        );
      },
    );
    if (shiftTypeResult == null || !mounted) return;

    final siteData = sitesSnap.docs.firstWhere((d) => d.id == selectedSiteId).data();
    final siteLat = (siteData['latitude'] as num?)?.toDouble() ?? 0.0;
    final siteLng = (siteData['longitude'] as num?)?.toDouble() ?? 0.0;
    final siteRadius = (siteData['radius'] as num?)?.toDouble() ?? 100.0;
    final siteGpsInterval = (siteData['gpsIntervalMinutes'] as int?) ?? 15;

    // 4. GPS â Ð·Ð°Ð¿ÑÐ°ÑÐ¸Ð²Ð°ÐµÐ¼ ÑÐ°Ð·ÑÐµÑÐµÐ½Ð¸Ðµ ÐÐÐÐ£Ð¡ÐÐÐÐÐ (Android 14+: Ð±ÐµÐ· ÑÐ°Ð·ÑÐµÑÐµÐ½Ð¸Ñ foreground service Ñ ÑÐ¸Ð¿Ð¾Ð¼ location ÐºÑÐ°ÑÐ¸Ñ Ð½Ð°ÑÐ¸Ð²Ð½Ð¾)
    double userLat = 0.0, userLng = 0.0;
    LocationPermission gpsPermission = LocationPermission.denied;
    try {
      gpsPermission = await Geolocator.checkPermission();
      if (gpsPermission == LocationPermission.denied) {
        gpsPermission = await Geolocator.requestPermission();
      }
    } catch (_) {}
    if (!mounted) return;

    if (siteLat != 0.0 || siteLng != 0.0) {
      try {
        if (gpsPermission == LocationPermission.denied || gpsPermission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('gpsPermissionDenied'))));
        } else {
          final pos = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10),
          );
          if (!mounted) return;
          userLat = pos.latitude;
          userLng = pos.longitude;

          final distance = Geolocator.distanceBetween(userLat, userLng, siteLat, siteLng);
          if (distance > siteRadius) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(i18n.t('gpsWarningTitle')),
                content: Text(
                  '${i18n.t('gpsWarningText')}\n\n'
                  '${i18n.t('distance')}: ${distance.toStringAsFixed(0)} Ð¼\n'
                  '${i18n.t('siteRadius')}: ${siteRadius.toStringAsFixed(0)} Ð¼',
                ),
                actions: [
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('ok'))),
                ],
              ),
            );
            return; // Ð¶ÑÑÑÐºÐ¸Ð¹ Ð±Ð»Ð¾Ðº
          }
        }
      } catch (_) {}
    }

    // 5. ÐÐ°Ð¿Ð¸ÑÐ°ÑÑ ÑÐ¼ÐµÐ½Ñ
    final shiftRef = await companyTimesheetsRef(widget.companyId).add({
      'personId': personIdForShift,
      'personName': personNameForShift,
      'authorUid': widget.userId,
      'siteId': selectedSiteId,
      'siteName': siteData['name'] ?? '',
      'startTime': Timestamp.now(),
      'startLocation': {'lat': userLat, 'lng': userLng},
      'endTime': null,
      'endLocation': null,
      'totalHours': 0.0,
      'workReport': '',
      'shiftType': shiftTypeResult,
    });

    // ÐÐ°Ð¿Ð»Ð°Ð½Ð¸ÑÐ¾Ð²Ð°ÑÑ ÑÐ²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ñ â ÑÐµÑÐµÐ· 10Ñ Ð¸ 12Ñ ÐµÑÐ»Ð¸ ÑÐ¼ÐµÐ½Ð° Ð½Ðµ Ð·Ð°ÐºÑÑÑÐ°
    await _scheduleShiftNotif(
      101, const Duration(hours: 10),
      i18n.t('shiftReminder10hTitle'),
      i18n.t('shiftReminder10hBody'),
    );
    await _scheduleShiftNotif(
      102, const Duration(hours: 12),
      i18n.t('shiftReminder12hTitle'),
      i18n.t('shiftReminder12hBody'),
    );

    // ÐÐ°Ð¿ÑÑÑÐ¸ÑÑ foreground service GPS-ÑÑÐµÐºÐ¸Ð½Ð³Ð° (ÑÐ¾Ð»ÑÐºÐ¾ ÐµÑÐ»Ð¸ ÑÐ°Ð·ÑÐµÑÐµÐ½Ð¸Ðµ Ð²ÑÐ´Ð°Ð½Ð¾)
    if (Platform.isAndroid &&
        gpsPermission != LocationPermission.denied &&
        gpsPermission != LocationPermission.deniedForever) {

      // ÐÑÐ¾Ð²ÐµÑÑÐµÐ¼ ÑÐ°ÑÐ¸Ñ â GPS ÑÐ¾Ð»ÑÐºÐ¾ Ñ ÐÑÐ¾ Ð¸ Ð²ÑÑÐµ
      String companyPlan = Plans.free;
      try {
        final compSnap = await companyDoc(widget.companyId).get();
        companyPlan = (compSnap.data()?['plan'] as String?) ?? Plans.free;
      } catch (_) {}
      if (!Plans.gpsEnabled(companyPlan)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(i18n.t('gpsNotInPlan')),
            duration: const Duration(seconds: 4),
          ));
        }
        // GPS Ð½Ðµ Ð·Ð°Ð¿ÑÑÐºÐ°ÐµÐ¼, ÑÐ¼ÐµÐ½Ð° ÑÐ¶Ðµ ÑÐ¾Ð·Ð´Ð°Ð½Ð°
      } else {

      // ÐÑÐ¾Ð²ÐµÑÑÐµÐ¼ ÑÐ²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ñ â Ð±ÐµÐ· Ð½Ð¸Ñ startForeground() ÐºÑÐ°ÑÐ¸Ñ Ð²ÐµÑÑ Ð¿ÑÐ¾ÑÐµÑÑ (Android 14+)
      final androidNotifImpl = _localNotifs.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final notifEnabled = await androidNotifImpl?.areNotificationsEnabled() ?? true;

      if (!notifEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('GPS-ÑÑÐµÐºÐ¸Ð½Ð³ Ð½ÐµÐ´Ð¾ÑÑÑÐ¿ÐµÐ½: Ð²ÐºÐ»ÑÑÐ¸ ÑÐ²ÐµÐ´Ð¾Ð¼Ð»ÐµÐ½Ð¸Ñ Ð´Ð»Ñ ToolKeeper Ð² Ð½Ð°ÑÑÑÐ¾Ð¹ÐºÐ°Ñ'),
          duration: Duration(seconds: 5),
        ));
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('shift_companyId', widget.companyId);
        await prefs.setString('shift_shiftId', shiftRef.id);

        // ÐÐ°Ð¿ÑÑÐº ÑÐµÑÐ²Ð¸ÑÐ° â fire-and-forget, Ð½Ðµ Ð±Ð»Ð¾ÐºÐ¸ÑÑÐµÑ UI
        final capturedCompany = widget.companyId;
        final capturedShift = shiftRef.id;
        final capturedInterval = siteGpsInterval;
        await prefs.setInt('shift_gpsInterval', capturedInterval);
        Future(() async {
          try {
            await _initBackgroundService();
            final bgService = FlutterBackgroundService();
            await bgService.startService();
            await Future.delayed(const Duration(milliseconds: 2000));
            bgService.invoke('startTracking', {
              'companyId': capturedCompany,
              'shiftId': capturedShift,
              'interval': capturedInterval,
            });
          } catch (e) {
            print('[GPS] Launch error: $e');
          }
        });
      }
      } // end else gpsEnabled
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('shiftStarted'))));
    }
  }
  
  Future<void> _endShift(String shiftId) async {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);

    // ÐÐ°Ð³ÑÑÐ¶Ð°ÐµÐ¼ Ð´Ð°Ð½Ð½ÑÐµ ÑÐ¼ÐµÐ½Ñ Ð¸ Ð¾Ð±ÑÐµÐºÑÐ° Ð·Ð°ÑÐ°Ð½ÐµÐµ
    final shiftDoc = await companyTimesheetsRef(widget.companyId).doc(shiftId).get();
    if (!mounted || !shiftDoc.exists) return;
    final shiftData = shiftDoc.data()!;
    final siteId = (shiftData['siteId'] ?? '').toString();

    double siteLat = 0.0, siteLng = 0.0, siteRadius = 0.0;
    if (siteId.isNotEmpty) {
      try {
        final siteDoc = await companySitesRef(widget.companyId).doc(siteId).get();
        if (siteDoc.exists) {
          final sd = siteDoc.data()!;
          siteLat = (sd['latitude'] as num?)?.toDouble() ?? 0.0;
          siteLng = (sd['longitude'] as num?)?.toDouble() ?? 0.0;
          siteRadius = (sd['radius'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (_) {}
    }
    if (!mounted) return;

    final reportController = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: Text(i18n.t('writeReport')),
          content: TextField(
            controller: reportController,
            decoration: InputDecoration(labelText: i18n.t('whatDone')),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(i18n.t('cancel')),
            ),
            TextButton(
              onPressed: saving ? null : () async {
                setDlg(() => saving = true);
                try {
                  final startTime = (shiftData['startTime'] as Timestamp).toDate();
                  final endNow = DateTime.now();
                  final hours = endNow.difference(startTime).inSeconds / 3600.0;

                  double endLat = 0.0, endLng = 0.0;
                  double? distFromSite;
                  try {
                    final pos = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high,
              
                          timeLimit: Duration(seconds: 10),
                    );
                    endLat = pos.latitude;
                    endLng = pos.longitude;
                    if ((siteLat != 0.0 || siteLng != 0.0) && siteRadius > 0) {
                      distFromSite = Geolocator.distanceBetween(
                          endLat, endLng, siteLat, siteLng);
                    }
                  } catch (_) {}

                  String report = reportController.text.trim();

                  // ÐÑÑÑÑ Ð¾Ð±ÑÐ·Ð°ÑÐµÐ»ÐµÐ½
                  if (report.isEmpty) {
                    setDlg(() => saving = false);
                    if (ctx2.mounted) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(i18n.t('reportRequired'))),
                      );
                    }
                    return;
                  }

                  // ÐÑÐµÐ´ÑÐ¿ÑÐµÐ¶Ð´ÐµÐ½Ð¸Ðµ ÐµÑÐ»Ð¸ Ð·Ð° Ð¿ÑÐµÐ´ÐµÐ»Ð°Ð¼Ð¸ Ð·Ð¾Ð½Ñ (Ð½Ðµ Ð±Ð»Ð¾ÐºÐ¸ÑÑÐµÐ¼)
                  if (distFromSite != null && distFromSite > siteRadius) {
                    final dist = distFromSite.toStringAsFixed(0);
                    final rad = siteRadius.toStringAsFixed(0);
                    if (ctx2.mounted) {
                      await showDialog<void>(
                        context: ctx2,
                        builder: (c) => AlertDialog(
                          title: Text(i18n.t('gpsWarningTitle')),
                          content: Text(
                            '${i18n.t('gpsWarningText')}\n\n'
                            '${i18n.t('distance')}: $dist Ð¼\n'
                            '${i18n.t('siteRadius')}: $rad Ð¼',
                          ),
                          actions: [
                            FilledButton(
                                onPressed: () => Navigator.pop(c),
                                child: Text(i18n.t('ok'))),
                          ],
                        ),
                      );
                    }
                    // ÐÐ²ÑÐ¾Ð¼Ð°ÑÐ¸ÑÐµÑÐºÐ¸ Ð´Ð¾Ð±Ð°Ð²Ð»ÑÐµÐ¼ Ð¼ÐµÑÐºÑ Ð² Ð¾ÑÑÑÑ
                    final note =
                        'â ï¸ ${i18n.t('distance')}: $dist Ð¼ (${endLat.toStringAsFixed(5)}, ${endLng.toStringAsFixed(5)})';
                    report = report.isEmpty ? note : '$report\n$note';
                  }

                  await companyTimesheetsRef(widget.companyId).doc(shiftId).update({
                    'endTime': Timestamp.now(),
                    'endLocation': {'lat': endLat, 'lng': endLng},
                    'totalHours': hours,
                    'workReport': report,
                  });

                  // ÐÑÐ¼ÐµÐ½Ð¸ÑÑ Ð·Ð°Ð¿Ð»Ð°Ð½Ð¸ÑÐ¾Ð²Ð°Ð½Ð½ÑÐµ Ð½Ð°Ð¿Ð¾Ð¼Ð¸Ð½Ð°Ð½Ð¸Ñ
                  await _localNotifs.cancel(101);
                  await _localNotifs.cancel(102);

                  // ÐÑÑÐ°Ð½Ð¾Ð²Ð¸ÑÑ foreground service GPS-ÑÑÐµÐºÐ¸Ð½Ð³Ð°
                  if (Platform.isAndroid) {
                    try {
                      FlutterBackgroundService().invoke('stopService');
                      await Future.delayed(const Duration(milliseconds: 500));
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('shift_companyId');
                      await prefs.remove('shift_shiftId');
                    } catch (_) {}
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(i18n.t('shiftEnded'))));
                  }
                } catch (e) {
                  setDlg(() => saving = false);
                  if (ctx2.mounted) {
                    ScaffoldMessenger.of(ctx2)
                        .showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ°: $e')));
                  }
                }
              },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(i18n.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}

// Ð¡ÑÑÐ°Ð½Ð¸ÑÐ° Ð¸ÑÑÐ¾ÑÐ¸Ð¸ ÑÐ¼ÐµÐ½
class TimesheetsPage extends StatefulWidget {
  final String companyId;
  final String? personId;
  final bool isAdmin;

  const TimesheetsPage({super.key, required this.companyId, this.personId, this.isAdmin = false});

  @override
  State<TimesheetsPage> createState() => _TimesheetsPageState();
}

class _TimesheetsPageState extends State<TimesheetsPage> {
  String? _monthFilter;
  String? _siteFilter;
  String? _personFilter;
  List<Map<String, dynamic>> _sites = [];
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    try {
      final snap = await companySitesRef(widget.companyId).get();
      if (!mounted) return;
      setState(() {
        _sites = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {
    // For personId queries avoid orderBy â it requires a composite Firestore index.
    // Sort client-side instead.
    if (widget.personId != null) {
      return companyTimesheetsRef(widget.companyId)
          .where('personId', isEqualTo: widget.personId)
          .snapshots();
    }
    return companyTimesheetsRef(widget.companyId)
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var result = docs.toList();
    if (widget.personId != null) {
      result.sort((a, b) {
        final ta = (a.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);
        final tb = (b.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);
        return tb.compareTo(ta);
      });
    }
    if (_monthFilter != null) {
      final p = _monthFilter!.split('-');
      final y = int.parse(p[0]), m = int.parse(p[1]);
      result = result.where((d) {
        final dt = (d.data()['startTime'] as Timestamp?)?.toDate();
        return dt != null && dt.year == y && dt.month == m;
      }).toList();
    }
    if (_siteFilter != null) {
      result = result.where((d) => d.data()['siteId'] == _siteFilter).toList();
    }
    if (_personFilter != null) {
      result = result.where((d) => d.data()['personId'] == _personFilter).toList();
    }
    return result;
  }

  String _fmtMonth(String ym) {
    final p = ym.split('-');
    return '${p[1]}.${p[0]}';
  }

  String _fmt(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}.${p(dt.month)}.${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
  }

  String _fmtDuration(double hours) {
    final totalMin = (hours * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h == 0) return '${m}Ð¼Ð¸Ð½';
    if (m == 0) return '${h}Ñ';
    return '${h}Ñ ${m}Ð¼Ð¸Ð½';
  }

  Future<File> _saveBytes(String filename, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _shareFile(File file, {String? mimeType}) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
      } else {
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ð¤Ð°Ð¹Ð» ÑÐ¾ÑÑÐ°Ð½ÑÐ½: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° ÑÐºÑÐ¿Ð¾ÑÑÐ°: $e')),
        );
      }
    }
  }

  Future<void> _showGpsTrack(I18n i18n, String shiftId) async {
    try {
    // Load shift + site data
    final shiftDoc = await companyTimesheetsRef(widget.companyId).doc(shiftId).get();
    if (!mounted || !shiftDoc.exists) return;
    final shiftData = shiftDoc.data()!;
    final siteId = (shiftData['siteId'] ?? '').toString();
    final personName = (shiftData['personName'] ?? '').toString();
    final siteName = (shiftData['siteName'] ?? '').toString();
    final startTime = (shiftData['startTime'] as Timestamp?)?.toDate();

    double siteLat = 0.0, siteLng = 0.0, siteRadius = 0.0;
    bool hasSite = false;
    if (siteId.isNotEmpty) {
      try {
        final siteDoc = await companySitesRef(widget.companyId).doc(siteId).get();
        if (siteDoc.exists) {
          final sd = siteDoc.data()!;
          siteLat = (sd['latitude'] as num?)?.toDouble() ?? 0.0;
          siteLng = (sd['longitude'] as num?)?.toDouble() ?? 0.0;
          siteRadius = (sd['radius'] as num?)?.toDouble() ?? 100.0;
          hasSite = siteLat != 0.0 || siteLng != 0.0;
        }
      } catch (_) {}
    }

    final snap = await FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('timesheets')
        .doc(shiftId)
        .collection('locations')
        .orderBy('createdAt')
        .get();
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(i18n.t('noGpsData'))),
      );
      return;
    }

    // Build enriched ping list
    final pings = snap.docs.map((doc) {
      final d = doc.data();
      final lat = (d['lat'] as num?)?.toDouble() ?? 0.0;
      final lng = (d['lng'] as num?)?.toDouble() ?? 0.0;
      final acc = (d['accuracy'] as num?)?.toDouble() ?? 0.0;
      final ts = d['createdAt'];
      String timeStr = '';
      if (ts is Timestamp) {
        final dt = ts.toDate();
        timeStr =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      double? dist;
      bool outside = false;
      if (hasSite) {
        dist = Geolocator.distanceBetween(lat, lng, siteLat, siteLng);
        outside = dist > siteRadius;
      }
      return <String, dynamic>{
        'lat': lat, 'lng': lng, 'acc': acc,
        'timeStr': timeStr, 'dist': dist, 'outside': outside,
      };
    }).toList();

    final violations = pings.where((p) => p['outside'] == true).length;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(i18n.t('gpsTrack')),
            if (personName.isNotEmpty)
              Text(personName, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            if (hasSite && violations > 0)
              Text('â  ÐÑÑÐ¾Ð´Ð¾Ð² Ð¸Ð· Ð·Ð¾Ð½Ñ: $violations',
                  style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
            if (hasSite && violations == 0 && pings.isNotEmpty)
              const Text('â ÐÑÑ Ð²ÑÐµÐ¼Ñ Ð² Ð·Ð¾Ð½Ðµ',
                  style: TextStyle(fontSize: 13, color: Colors.green)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView.builder(
            itemCount: pings.length,
            itemBuilder: (_, i) {
              final p = pings[i];
              final lat = p['lat'] as double;
              final lng = p['lng'] as double;
              final acc = p['acc'] as double;
              final timeStr = p['timeStr'] as String;
              final dist = p['dist'] as double?;
              final outside = p['outside'] as bool;
              final distStr = dist != null ? '  â¢  ${dist.toStringAsFixed(0)} Ð¼' : '';
              return ListTile(
                dense: true,
                leading: Icon(
                  outside ? Icons.warning_amber_rounded : Icons.check_circle,
                  size: 20,
                  color: outside ? Colors.red : Colors.green,
                ),
                title: Text(
                  '$timeStr  Â±${acc.toStringAsFixed(0)} Ð¼',
                  style: TextStyle(color: outside ? Colors.red : null),
                ),
                subtitle: Text(
                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}$distStr',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng')),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(i18n.t('ok')),
          ),
          TextButton.icon(
            icon: const Icon(Icons.table_chart, color: Colors.green, size: 18),
            label: const Text('Excel'),
            onPressed: () {
              Navigator.pop(ctx);
              _exportGpsTrackXlsx(personName, siteName, siteRadius, pings);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
            label: const Text('PDF'),
            onPressed: () {
              Navigator.pop(ctx);
              _exportGpsTrackPdf(personName, siteName, startTime, siteRadius, pings);
            },
          ),
        ],
      ),
    );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° GPS: $e')));
      }
    }
  }

  Future<void> _exportGpsTrackPdf(
    String personName,
    String siteName,
    DateTime? shiftDate,
    double siteRadius,
    List<Map<String, dynamic>> pings,
  ) async {
    try {
      String companyName = 'ToolKeeper';
      try {
        final snap = await companyDoc(widget.companyId).get();
        if (snap.exists) companyName = (snap.data()?['name'] ?? 'ToolKeeper').toString();
      } catch (_) {}

      final theme = await _pdfTheme();
      final doc = pw.Document(theme: theme);
      final dateStr = shiftDate != null
          ? '${shiftDate.day.toString().padLeft(2, '0')}.${shiftDate.month.toString().padLeft(2, '0')}.${shiftDate.year}'
          : '';
      final violations = pings.where((p) => p['outside'] == true).length;

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(companyName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 8),
          pw.Text('ÐÐ¢Ð§ÐÐ¢ GPS-Ð¢Ð ÐÐÐÐÐÐ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.SizedBox(height: 12),
          pw.Text('Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº: $personName', style: const pw.TextStyle(fontSize: 11)),
          pw.Text('ÐÐ±ÑÐµÐºÑ: $siteName', style: const pw.TextStyle(fontSize: 11)),
          if (dateStr.isNotEmpty)
            pw.Text('ÐÐ°ÑÐ°: $dateStr', style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Ð Ð°Ð´Ð¸ÑÑ Ð·Ð¾Ð½Ñ: ${siteRadius.toStringAsFixed(0)} Ð¼',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 6),
          pw.Text(
            'Ð¢Ð¾ÑÐµÐº: ${pings.length}   â¢   ÐÑÑÐ¾Ð´Ð¾Ð² Ð¸Ð· Ð·Ð¾Ð½Ñ: $violations',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: violations > 0 ? PdfColors.red700 : PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['â', 'ÐÑÐµÐ¼Ñ', 'Ð¨Ð¸ÑÐ¾ÑÐ°', 'ÐÐ¾Ð»Ð³Ð¾ÑÐ°', 'ÐÐ¾ Ð¾Ð±ÑÐµÐºÑÐ° (Ð¼)', 'Ð¡ÑÐ°ÑÑÑ'],
            data: pings.asMap().entries.map((e) {
              final p = e.value;
              final dist = p['dist'] as double?;
              final outside = p['outside'] as bool;
              return [
                '${e.key + 1}',
                p['timeStr'] as String,
                (p['lat'] as double).toStringAsFixed(5),
                (p['lng'] as double).toStringAsFixed(5),
                dist != null ? dist.toStringAsFixed(0) : 'â',
                outside ? 'â  ÐÐ½Ðµ Ð·Ð¾Ð½Ñ' : 'â Ð Ð·Ð¾Ð½Ðµ',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            cellAlignments: {
              0: pw.Alignment.center,
              4: pw.Alignment.centerRight,
            },
          ),
        ],
      ));

      final bytes = await doc.save();
      final file = await _saveBytes('gps_track_${DateTime.now().millisecondsSinceEpoch}.pdf', bytes);
      await _shareFile(file, mimeType: 'application/pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° PDF: $e')));
      }
    }
  }

  Future<void> _exportGpsTrackXlsx(
    String personName,
    String siteName,
    double siteRadius,
    List<Map<String, dynamic>> pings,
  ) async {
    try {
      final xl = Excel.createExcel();
      final sheet = xl['GPS Track'];
      // Header info rows
      sheet.appendRow([TextCellValue('Ð¡Ð¾ÑÑÑÐ´Ð½Ð¸Ðº'), TextCellValue(personName)]);
      sheet.appendRow([TextCellValue('ÐÐ±ÑÐµÐºÑ'), TextCellValue(siteName)]);
      sheet.appendRow([TextCellValue('Ð Ð°Ð´Ð¸ÑÑ Ð·Ð¾Ð½Ñ (Ð¼)'), TextCellValue(siteRadius.toStringAsFixed(0))]);
      final violations = pings.where((p) => p['outside'] == true).length;
      sheet.appendRow([
        TextCellValue('Ð¢Ð¾ÑÐµÐº: ${pings.length}'),
        TextCellValue('ÐÑÑÐ¾Ð´Ð¾Ð² Ð¸Ð· Ð·Ð¾Ð½Ñ: $violations'),
      ]);
      sheet.appendRow([TextCellValue('')]);
      // Table header
      sheet.appendRow([
        TextCellValue('â'),
        TextCellValue('ÐÑÐµÐ¼Ñ'),
        TextCellValue('Ð¨Ð¸ÑÐ¾ÑÐ°'),
        TextCellValue('ÐÐ¾Ð»Ð³Ð¾ÑÐ°'),
        TextCellValue('ÐÐ¾ Ð¾Ð±ÑÐµÐºÑÐ° (Ð¼)'),
        TextCellValue('Ð¡ÑÐ°ÑÑÑ'),
      ]);
      // Data rows
      for (var i = 0; i < pings.length; i++) {
        final p = pings[i];
        final dist = p['dist'] as double?;
        final outside = p['outside'] as bool;
        sheet.appendRow([
          TextCellValue('${i + 1}'),
          TextCellValue(p['timeStr'] as String),
          TextCellValue((p['lat'] as double).toStringAsFixed(5)),
          TextCellValue((p['lng'] as double).toStringAsFixed(5)),
          TextCellValue(dist != null ? dist.toStringAsFixed(0) : 'â'),
          TextCellValue(outside ? 'ÐÐ½Ðµ Ð·Ð¾Ð½Ñ' : 'Ð Ð·Ð¾Ð½Ðµ'),
        ]);
      }
      final bytes = xl.encode()!;
      final file = await _saveBytes(
          'gps_track_${DateTime.now().millisecondsSinceEpoch}.xlsx', bytes);
      await _shareFile(file,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° Excel: $e')));
      }
    }
  }

  Future<void> _forceCloseShift(
    I18n i18n,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final reportController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('forceCloseShift')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(i18n.t('forceCloseShiftHint')),
            const SizedBox(height: 12),
            TextField(
              controller: reportController,
              decoration: InputDecoration(
                labelText: i18n.t('workReport'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.t('forceCloseShift')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final now = DateTime.now();
      final startTime = (doc.data()['startTime'] as Timestamp?)?.toDate();
      final totalHours = startTime != null
          ? now.difference(startTime).inMinutes / 60.0
          : 0.0;
      await companyTimesheetsRef(widget.companyId).doc(doc.id).update({
        'endTime': Timestamp.fromDate(now),
        'totalHours': double.parse(totalHours.toStringAsFixed(2)),
        if (reportController.text.trim().isNotEmpty)
          'workReport': reportController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('shiftClosed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ°: $e')),
        );
      }
    }
  }

  Future<void> _exportPdf(
    I18n i18n,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rows,
  ) async {
    if (!mounted) return;
    setState(() => _exporting = true);
    try {
      String companyName = 'ToolKeeper';
      try {
        final snap = await companyDoc(widget.companyId).get();
        if (snap.exists) companyName = (snap.data()?['name'] ?? 'ToolKeeper').toString();
      } catch (_) {}

      final totalHours = rows.fold<double>(
          0.0, (s, d) => s + ((d.data()['totalHours'] as num?) ?? 0.0));

      // Determine date range from rows
      DateTime? minDate, maxDate;
      for (final d in rows) {
        final st = (d.data()['startTime'] as Timestamp?)?.toDate();
        if (st == null) continue;
        if (minDate == null || st.isBefore(minDate)) minDate = st;
        if (maxDate == null || st.isAfter(maxDate)) maxDate = st;
      }
      final fmtDate = (DateTime dt) =>
          '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      final periodStr = minDate != null && maxDate != null
          ? (minDate.day == maxDate.day && minDate.month == maxDate.month && minDate.year == maxDate.year
              ? fmtDate(minDate)
              : '${fmtDate(minDate)} â ${fmtDate(maxDate)}')
          : '';

      final doc = pw.Document(theme: await _pdfTheme());
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text(companyName,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(i18n.t('timesheets'),
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (periodStr.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('ÐÐµÑÐ¸Ð¾Ð´: $periodStr', style: const pw.TextStyle(fontSize: 11)),
          ],
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: [
              i18n.t('people'), i18n.t('sites'),
              i18n.t('shiftStart'), i18n.t('shiftEnd'), i18n.t('totalHours'),
            ],
            data: rows.map((d) {
              final m = d.data();
              final st = (m['startTime'] as Timestamp?)?.toDate();
              final et = (m['endTime'] as Timestamp?)?.toDate();
              return [
                (m['personName'] ?? '').toString(),
                (m['siteName'] ?? '').toString(),
                st != null ? _fmt(st) : '',
                et != null ? _fmt(et) : i18n.t('shiftActive'),
                et != null ? ((m['totalHours'] as num?) ?? 0.0).toStringAsFixed(2) : '',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'ÐÑÐ¾Ð³Ð¾ ÑÐ°ÑÐ¾Ð²: ${totalHours.toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Ð¡Ð¾ÑÑÐ°Ð²Ð¸Ð»:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Ð£ÑÐ²ÐµÑÐ´Ð¸Ð»:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(Ð¿Ð¾Ð´Ð¿Ð¸ÑÑ / Ð¤.Ð.Ð.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ));
      final bytes = await doc.save();
      final file = await _saveBytes(
          'timesheets_${DateTime.now().millisecondsSinceEpoch}.pdf', bytes);
      await _shareFile(file, mimeType: 'application/pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportXlsx(
    I18n i18n,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rows,
  ) async {
    if (!mounted) return;
    setState(() => _exporting = true);
    try {
      final xl = Excel.createExcel();
      final sheet = xl['Timesheets'];
      sheet.appendRow([
        TextCellValue(i18n.t('people')),
        TextCellValue(i18n.t('sites')),
        TextCellValue(i18n.t('shiftStart')),
        TextCellValue(i18n.t('shiftEnd')),
        TextCellValue(i18n.t('totalHours')),
        TextCellValue(i18n.t('workReport')),
      ]);
      for (final d in rows) {
        final m = d.data();
        final st = (m['startTime'] as Timestamp?)?.toDate();
        final et = (m['endTime'] as Timestamp?)?.toDate();
        sheet.appendRow([
          TextCellValue((m['personName'] ?? '').toString()),
          TextCellValue((m['siteName'] ?? '').toString()),
          TextCellValue(st != null ? _fmt(st) : ''),
          TextCellValue(et != null ? _fmt(et) : i18n.t('shiftActive')),
          TextCellValue(et != null
              ? ((m['totalHours'] as num?) ?? 0.0).toStringAsFixed(2)
              : ''),
          TextCellValue((m['workReport'] ?? '').toString()),
        ]);
      }
      final bytes = xl.encode()!;
      final file = await _saveBytes(
          'timesheets_${DateTime.now().millisecondsSinceEpoch}.xlsx', bytes);
      await _shareFile(file,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ÐÑÐ¸Ð±ÐºÐ° Excel: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);
    final now = DateTime.now();
    final monthOptions = List.generate(13, (i) {
      final dt = DateTime(now.year, now.month - i, 1);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('timesheets'),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (ctx, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('ÐÑÐ¸Ð±ÐºÐ°: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;
          final filtered = _applyFilters(allDocs);
          final totalHours = filtered.fold<double>(
              0.0, (s, d) => s + ((d.data()['totalHours'] as num?) ?? 0.0));

          // Collect unique persons from ALL docs for the person filter dropdown
          final persons = <String, String>{};
          if (widget.personId == null) {
            for (final d in allDocs) {
              final pid = (d.data()['personId'] ?? '').toString();
              final pname = (d.data()['personName'] ?? '').toString();
              if (pid.isNotEmpty) persons[pid] = pname;
            }
          }

          return Column(
            children: [
              // Filter bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  DropdownButton<String?>(
                    value: _monthFilter,
                    isDense: true,
                    hint: Text(i18n.t('allTime')),
                    items: [
                      DropdownMenuItem(
                          value: null, child: Text(i18n.t('allTime'))),
                      ...monthOptions.map((m) => DropdownMenuItem(
                          value: m, child: Text(_fmtMonth(m)))),
                    ],
                    onChanged: (v) => setState(() => _monthFilter = v),
                  ),
                  if (_sites.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: _siteFilter,
                      isDense: true,
                      hint: Text(i18n.t('allSites')),
                      items: [
                        DropdownMenuItem(
                            value: null, child: Text(i18n.t('allSites'))),
                        ..._sites.map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text((s['name'] ?? '').toString()),
                            )),
                      ],
                      onChanged: (v) => setState(() => _siteFilter = v),
                    ),
                  ],
                  if (widget.personId == null && persons.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: persons.containsKey(_personFilter)
                          ? _personFilter
                          : null,
                      isDense: true,
                      hint: Text(i18n.t('allPeople')),
                      items: [
                        DropdownMenuItem(
                            value: null, child: Text(i18n.t('allPeople'))),
                        ...persons.entries.map((e) =>
                            DropdownMenuItem(value: e.key, child: Text(e.value))),
                      ],
                      onChanged: (v) => setState(() => _personFilter = v),
                    ),
                  ],
                ]),
              ),
              // Summary bar with export buttons
              Container(
                color: Colors.blue.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.access_time, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${i18n.t('totalHours')}: ${totalHours.toStringAsFixed(1)} Ñ (${_fmtDuration(totalHours)})  â¢  ${i18n.t('shiftsCount')}: ${filtered.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_exporting)
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else ...[
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      tooltip: i18n.t('exportPdf'),
                      onPressed: filtered.isEmpty
                          ? null
                          : () => _exportPdf(i18n, filtered),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.table_chart, color: Colors.green),
                      tooltip: i18n.t('exportXlsx'),
                      onPressed: filtered.isEmpty
                          ? null
                          : () => _exportXlsx(i18n, filtered),
                    ),
                  ],
                ]),
              ),
              // Shift list
              if (filtered.isEmpty)
                Expanded(child: Center(child: Text(i18n.t('noData'))))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final data = filtered[index].data();
                      final personName = (data['personName'] ?? '').toString();
                      final siteName = (data['siteName'] ?? '').toString();
                      final startTime =
                          (data['startTime'] as Timestamp?)?.toDate();
                      final endTime =
                          (data['endTime'] as Timestamp?)?.toDate();
                      final hours = (data['totalHours'] as num?) ?? 0.0;
                      final report =
                          (data['workReport'] ?? '').toString().trim();
                      final isActive = endTime == null;
                      final shiftTypeRaw = (data['shiftType'] ?? '').toString();
                      final shiftTypeLabel = shiftTypeRaw == 'accord'
                          ? i18n.t('shiftTypeAccord')
                          : shiftTypeRaw == 'hourly'
                              ? i18n.t('shiftTypeHourly')
                              : '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ExpansionTile(
                          leading: Icon(
                            isActive ? Icons.play_circle : Icons.check_circle,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                          title: Text(personName.isNotEmpty
                              ? '$personName â $siteName'
                              : siteName),
                          subtitle: Text(isActive
                              ? i18n.t('shiftActive')
                              : '${hours.toStringAsFixed(1)} Ñ Â· ${_fmtDuration(hours.toDouble())}  â¢  ${startTime != null ? _fmt(startTime).substring(0, 10) : ''}'),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (startTime != null)
                                    Row(children: [
                                      const Icon(Icons.login,
                                          size: 16, color: Colors.green),
                                      const SizedBox(width: 6),
                                      Text(
                                          '${i18n.t('shiftStart')}: ${_fmt(startTime)}'),
                                    ]),
                                  if (endTime != null) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      const Icon(Icons.logout,
                                          size: 16, color: Colors.red),
                                      const SizedBox(width: 6),
                                      Text(
                                          '${i18n.t('shiftEnd')}: ${_fmt(endTime)}'),
                                    ]),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      const Icon(Icons.timer,
                                          size: 16, color: Colors.blue),
                                      const SizedBox(width: 6),
                                      Text(
                                          '${i18n.t('totalHours')}: ${hours.toStringAsFixed(2)} Ñ (${_fmtDuration(hours.toDouble())})'),
                                    ]),
                                  ],
                                  if (shiftTypeLabel.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      const Icon(Icons.work_outline,
                                          size: 16, color: Colors.orange),
                                      const SizedBox(width: 6),
                                      Text('${i18n.t('shiftType')}: $shiftTypeLabel'),
                                    ]),
                                  ],
                                  if (report.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(i18n.t('workReport'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(report),
                                  ],
                                  if (widget.isAdmin) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.location_history, size: 18),
                                        label: Text(i18n.t('gpsTrack')),
                                        onPressed: () => _showGpsTrack(i18n, filtered[index].id),
                                      ),
                                    ),
                                  ],
                                  if (isActive && widget.isAdmin) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                                        label: Text(i18n.t('forceCloseShift')),
                                        onPressed: () => _forceCloseShift(i18n, filtered[index]),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ÐÐ¸Ð°Ð»Ð¾Ð³ Ð´Ð¾Ð±Ð°Ð²Ð»ÐµÐ½Ð¸Ñ / ÑÐµÐ´Ð°ÐºÑÐ¸ÑÐ¾Ð²Ð°Ð½Ð¸Ñ Ð¾Ð±ÑÐµÐºÑÐ° (shared)
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
Future<void> _showSiteDialog(
  BuildContext context,
  String companyId, {
  Map<String, dynamic>? existing,
  String? siteId,
}) async {
  final i18n = I18n(AppState.of(context).lang.value);
  final nameCtrl    = TextEditingController(text: existing?['name'] ?? '');
  final addressCtrl = TextEditingController(text: existing?['address'] ?? '');
  final latCtrl     = TextEditingController(text: (existing?['latitude']  ?? 0.0).toString());
  final lngCtrl     = TextEditingController(text: (existing?['longitude'] ?? 0.0).toString());
  final radiusCtrl  = TextEditingController(text: (existing?['radius']    ?? 100).toString());
  int interval = (existing?['gpsIntervalMinutes'] as int?) ?? 15;
  bool saving = false;
  String? err;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text(existing == null ? i18n.t('addSite') : i18n.t('editSite')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: InputDecoration(labelText: i18n.t('siteName')),    controller: nameCtrl),
              TextField(decoration: InputDecoration(labelText: i18n.t('siteAddress')), controller: addressCtrl),
              TextField(decoration: InputDecoration(labelText: 'Latitude'),  controller: latCtrl,    keyboardType: TextInputType.number),
              TextField(decoration: InputDecoration(labelText: 'Longitude'), controller: lngCtrl,    keyboardType: TextInputType.number),
              TextField(decoration: InputDecoration(labelText: i18n.t('siteRadius')),  controller: radiusCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: interval,
                decoration: InputDecoration(labelText: i18n.t('gpsInterval')),
                items: [5, 15, 30, 60].map((v) => DropdownMenuItem(value: v, child: Text('$v Ð¼Ð¸Ð½'))).toList(),
                onChanged: (v) { if (v != null) setDlg(() => interval = v); },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('cancel'))),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              TextButton(
                onPressed: saving ? null : () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    setDlg(() => err = '${i18n.t('siteName')} â Ð¾Ð±ÑÐ·Ð°ÑÐµÐ»ÑÐ½Ð¾Ðµ Ð¿Ð¾Ð»Ðµ');
                    return;
                  }
                  setDlg(() { saving = true; err = null; });
                  try {
                    final ref = siteId == null
                        ? companySitesRef(companyId).doc()
                        : companySitesRef(companyId).doc(siteId);
                    await ref.set({
                      'name':               nameCtrl.text.trim(),
                      'address':            addressCtrl.text.trim(),
                      'latitude':           double.tryParse(latCtrl.text)    ?? 0.0,
                      'longitude':          double.tryParse(lngCtrl.text)    ?? 0.0,
                      'radius':             int.tryParse(radiusCtrl.text)    ?? 100,
                      'gpsIntervalMinutes': interval,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    setDlg(() { saving = false; err = e.toString(); });
                  }
                },
                child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(i18n.t('save')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ÐÑÐµ Ð¾Ð±ÑÐµÐºÑÑ â Ð¸Ð½Ð»Ð°Ð¹Ð½ ÐºÐ°ÑÑÐ¾ÑÐºÐ° Ñ Ð¿Ð¾Ð¸ÑÐºÐ¾Ð¼ (Ð²ÑÐµ Ð¿Ð¾Ð»ÑÐ·Ð¾Ð²Ð°ÑÐµÐ»Ð¸)
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
class WorkSitesInlineCard extends StatefulWidget {
  final String companyId;
  const WorkSitesInlineCard({super.key, required this.companyId});
  @override
  State<WorkSitesInlineCard> createState() => _WorkSitesInlineCardState();
}

class _WorkSitesInlineCardState extends State<WorkSitesInlineCard> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.map),
        title: Text(i18n.t('viewSites'), style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: i18n.t('searchSite'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: companySitesRef(widget.companyId).snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    var docs = snap.data!.docs;
                    if (_search.isNotEmpty) {
                      final q = normText(_search);
                      docs = docs.where((d) {
                        final name = normText((d.data()['name'] ?? '').toString());
                        final addr = normText((d.data()['address'] ?? '').toString());
                        return name.contains(q) || addr.contains(q);
                      }).toList();
                    }
                    if (docs.isEmpty) return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(i18n.t('noSites')),
                    );
                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data();
                        final name    = (data['name']    ?? '').toString();
                        final address = (data['address'] ?? '').toString();
                        final lat     = (data['latitude']  as num?)?.toDouble() ?? 0.0;
                        final lng     = (data['longitude'] as num?)?.toDouble() ?? 0.0;
                        final radius  = (data['radius']    as num?)?.toDouble() ?? 0.0;
                        final hasGps  = lat != 0.0 || lng != 0.0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on, color: Colors.orange),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (address.isNotEmpty) Text(address),
                                if (hasGps) Text(
                                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                                  '${radius > 0 ? '  â¢  R: ${radius.toStringAsFixed(0)} Ð¼' : ''}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                            trailing: hasGps
                                ? IconButton(
                                    icon: const Icon(Icons.map, color: Colors.blue),
                                    tooltip: i18n.t('navigateTo'),
                                    onPressed: () async {
                                      final url = Uri.parse(
                                        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                                      );
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// Ð£Ð¿ÑÐ°Ð²Ð»ÐµÐ½Ð¸Ðµ Ð¾Ð±ÑÐµÐºÑÐ°Ð¼Ð¸ â Ð¸Ð½Ð»Ð°Ð¹Ð½ ÐºÐ°ÑÑÐ¾ÑÐºÐ° Ñ Ð¿Ð¾Ð¸ÑÐºÐ¾Ð¼ (admin)
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
class SitesManageInlineCard extends StatefulWidget {
  final String companyId;
  const SitesManageInlineCard({super.key, required this.companyId});
  @override
  State<SitesManageInlineCard> createState() => _SitesManageInlineCardState();
}

class _SitesManageInlineCardState extends State<SitesManageInlineCard> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.location_on),
        title: Text(i18n.t('manageSites'), style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: i18n.t('searchSite'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: companySitesRef(widget.companyId).snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    var docs = snap.data!.docs;
                    if (_search.isNotEmpty) {
                      final q = normText(_search);
                      docs = docs.where((d) {
                        final name = normText((d.data()['name'] ?? '').toString());
                        final addr = normText((d.data()['address'] ?? '').toString());
                        return name.contains(q) || addr.contains(q);
                      }).toList();
                    }
                    return Column(
                      children: [
                        if (docs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(i18n.t('noSites')),
                          )
                        else
                          ...docs.map((doc) {
                            final data     = doc.data();
                            final name     = (data['name']    ?? '').toString();
                            final address  = (data['address'] ?? '').toString();
                            final interval = (data['gpsIntervalMinutes'] as int?) ?? 15;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_city, color: Colors.blue),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  '${address.isNotEmpty ? '$address  â¢  ' : ''}GPS: $interval Ð¼Ð¸Ð½',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showSiteDialog(
                                    context, widget.companyId,
                                    existing: data, siteId: doc.id,
                                  ),
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _showSiteDialog(context, widget.companyId),
                          icon: const Icon(Icons.add),
                          label: Text(i18n.t('addSite')),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Read-only sites page â visible to ALL users with Google Maps navigation
class WorkSitesReadOnlyPage extends StatelessWidget {
  final String companyId;
  const WorkSitesReadOnlyPage({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('sites'))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: companySitesRef(companyId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return Center(child: Text(i18n.t('noSites')));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data();
              final name = (data['name'] ?? '').toString();
              final address = (data['address'] ?? '').toString();
              final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
              final lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
              final radius = (data['radius'] as num?)?.toDouble() ?? 0.0;
              final hasGps = lat != 0.0 || lng != 0.0;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.orange),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (address.isNotEmpty) Text(address),
                      if (hasGps)
                        Text(
                          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                          '${radius > 0 ? '  â¢  ${i18n.t('siteRadius')}: ${radius.toStringAsFixed(0)} Ð¼' : ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                  isThreeLine: address.isNotEmpty && hasGps,
                  trailing: hasGps
                      ? IconButton(
                          icon: const Icon(Icons.map, color: Colors.blue),
                          tooltip: i18n.t('navigateTo'),
                          onPressed: () async {
                            final url = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
