import 'admin_employee_pages.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart'; import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'billing/plans.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import 'package:home_widget/home_widget.dart';

/// Глобальный экземпляр локальных уведомлений
final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

/// Действие, запрошенное через виджет рабочего стола ('start'/'end')
final ValueNotifier<String?> pendingWidgetAction = ValueNotifier<String?>(null);

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
Future<bool> iosBackgroundHandler(ServiceInstance service) async {
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
            iosConfiguration: IosConfiguration(autoStart: false, onForeground: gpsServiceMain, onBackground: iosBackgroundHandler),
  );
}

/// ✅ ОДИН main()
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  // Офлайн-кэш Firestore (размер не ограничен)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await _initLocalNotifications();
  try {
    await HomeWidget.setAppGroupId('group.com.toolkeeper.app.widget');
  } catch (_) {}
  runApp(const MyApp());
}

/// ===================
/// SIMPLE LANG
/// ===================
enum AppLang { ru, uk, pl, en, de, fr, es, it, pt, cs, ro, nl, tr, ar, hi, ko, ja, zh, id, vi, tl } Locale localeForAppLang(AppLang l) { if (l == AppLang.tl) return const Locale('fil'); return Locale(l.name); }

/// Human-readable names for all supported languages
const Map<AppLang, String> kLangNames = {
  AppLang.ru: 'Русский',
  AppLang.uk: 'Українська',
  AppLang.pl: 'Polski',
  AppLang.en: 'English',
  AppLang.de: 'Deutsch',
  AppLang.fr: 'Français',
  AppLang.es: 'Español',
  AppLang.it: 'Italiano',
  AppLang.pt: 'Português',
  AppLang.cs: 'Čeština',
  AppLang.ro: 'Română',
  AppLang.nl: 'Nederlands',
  AppLang.tr: 'Türkçe',
  AppLang.ar: 'العربية',
  AppLang.hi: 'हिन्दी',
  AppLang.ko: '한국어',
  AppLang.ja: '日本語',
  AppLang.zh: '中文',
  AppLang.id: 'Indonesia',
  AppLang.vi: 'Tiếng Việt',
  AppLang.tl: 'Filipino',
};

class I18n {
  final AppLang lang;
  const I18n(this.lang);

  static const _dict = <AppLang, Map<String, String>>{
    AppLang.ru: {
      'appTitle': 'ToolKeeper',
      'login': 'Вход',
      'register': 'Регистрация',
      'email': 'Email',
      'password': 'Пароль',
      'enter': 'Войти',
      'haveAccount': 'Уже есть аккаунт',
      'needAccount': 'Регистрация',
      'or': 'ИЛИ',
      'google': 'Войти через Google',
      'continue': 'Продолжить',
      'switchAcc': 'Сменить аккаунт',
      'logout': 'Выйти',
      'deleteAccount': 'Удалить аккаунт',
      'deleteAccountTitle': 'Удалить аккаунт?',
      'deleteAccountText': 'Все ваши данные будут удалены. Это действие нельзя отменить.',
      'people': 'Люди',
      'tools': 'Инструменты',
      'tool': 'Инструмент',
      'inv': 'Инв. №',
      'issue': 'Выдача',
      'profile': 'Профиль',
      'add': 'Добавить',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'delete': 'Удалить',
      'noPeople': 'Людей пока нет. Нажми +',
      'noTools': 'Инструментов пока нет. Нажми +',
      'history': 'История',
      'reports': 'Отчёты',
      'issueTool': 'Выдать',
      'returnTool': 'Вернуть',
      'issueTitle': 'Выдать инструмент',
      'returnTitle': 'Принять возврат',
      'person': 'Человек',
      'toolInv': 'Инструмент (инв. №)',
      'historyEmpty': 'История пустая',
      'reportsPeople': 'У кого что на руках (по людям)',
      'reportsTools': 'Где инструмент (по инструментам)',
      'reportFilterHint': 'Фильтр отчета...',
      'onHandsTotal': 'Сейчас на руках всего: {n} ед.',
      'toolsCountLabel': 'Инструментов: {n}',
      'whoLabel': 'У кого: {name}',
      'noneIssued': 'Сейчас ни у кого ничего не выдано.',
      'noneIssued2': 'Сейчас нет выданного инструмента.',
      'issued': 'ВЫДАНО',
      'returned': 'ВОЗВРАТ',
      'addPerson': 'Добавить человека',
      'firstName': 'Имя',
      'lastName': 'Фамилия',
      'position': 'Должность',
      'addTool': 'Добавить инструмент',
      'toolNameHint': 'Название (например: Перфоратор)',
      'invHint': 'Инвентарный номер (например: SIM-001)',
      'needPeopleFirst': 'Сначала добавь людей',
      'needToolsFirst': 'Сначала добавь инструменты',
      'noFreeTool': 'Нет свободного инструмента',
      'noReturnTool': 'Нет инструмента для возврата',
      'lang': 'Язык',
      'chooseLang': 'Выбери язык',
      'sessionTitle': 'Вход',
      'alreadyIn': 'Вы уже вошли как:',
      'enterEmailPass': 'Введите email и пароль',

      // Firms
      'welcome': 'Добро пожаловать',
      'chooseRole': 'Кто вы?',
      'owner': 'Создать команду',
      'employee': 'Вступить в команду',
      'createCompany': 'Создать команду',
      'joinCompany': 'Войти в фирму по коду',
      'companyName': 'Название фирмы (например: SIMKA)',
      'inviteCode': 'Код приглашения',
      'yourInviteCode': 'Ваш код приглашения',
      'copyCodeHint': 'Скопируйте и отправьте сотруднику',
      'pendingTitle': 'Ожидание подтверждения',
      'pendingText': 'Вы отправили заявку. Владелец фирмы должен подтвердить доступ.',
      'requests': 'Заявки сотрудников',
      'approve': 'Подтвердить',
      'decline': 'Отклонить',
      'noRequests': 'Пока нет заявок.',
      'profileForm': 'Анкета сотрудника',
      'birthDate': 'Дата рождения (YYYY-MM-DD)',
      'phone': 'Телефон (международный формат, например +48...)',
      'shoeSize': 'Размер обуви',
      'clothesSize': 'Размер одежды',
      'saveProfile': 'Сохранить анкету',
      'needProfile': 'Сначала заполните анкету',
      'company': 'Фирма',
      'role': 'Роль',
      'admin': 'Админ',
      'worker': 'Сотрудник',
      'onlyAdmin': 'Доступно только владельцу/админу',
      'codeNotFound': 'Код не найден',

      // Company management
      'leaveCompany': 'Сменить фирму / выйти из фирмы',
      'leaveCompanyConfirm': 'Вы уверены, что хотите выйти из этой команды?',
      'editCompany': 'Редактировать фирму',
      'renameCompany': 'Переименовать фирму',
      'newCompanyName': 'Новое название',
      'deleteCompany': 'Удалить фирму полностью',
      'deleteCompanyTitle': 'Удалить фирму?',
      'deleteCompanyText':
          'Фирма будет удалена полностью: люди, инструменты, выдачи, участники и код.\n\nДействие необратимо.',
      'archivedCompany': 'Фирма удалена (архив).',

      // Employees list
      'employees': 'Сотрудники',
      'noEmployees': 'Пока нет сотрудников.',
      'editMyProfile': 'Редактировать мой профиль',
      'linkPassword': 'Вход на ПК: привязать/сменить пароль',
      'setPassword': 'Установить пароль',
      'changePassword': 'Сменить пароль',
      'newPassword': 'Новый пароль (минимум 6 символов)',
      'repeatPassword': 'Повторите пароль',
      'passwordsNotMatch': 'Пароли не совпадают',
      'needReLogin': 'Нужно перелогиниться (Google) и повторить',
      'sendReset': 'Отправить сброс пароля на email',
      'done': 'Готово',

      // Errors / Fix
      'fixAccess':
          'Похоже, у аккаунта нет доступа к фирме (PERMISSION_DENIED) или activeCompanyId указывает не туда.\n'
              'Я сбросил activeCompanyId, чтобы ты мог выбрать/создать фирму заново.',
      'errUserRead': 'Ошибка чтения профиля пользователя',
      'errCompanyRead': 'Ошибка чтения фирмы',
      'errMemberRead': 'Ошибка чтения участника фирмы',
      'noAccessCompany': 'Нет доступа к фирме',
      'removedFromCompany': 'Вас удалили из фирмы. Введите код заново и дождитесь подтверждения.',
      'selectModeFirst': 'Сначала выберите: ВЫДАТЬ или ВЕРНУТЬ',
      'selectPersonForReturnFirst': 'Сначала выберите сотрудника для ВОЗВРАТА',
      'noRightsIssueReturn': 'Нет прав на выдачу/возврат',
      'selectPersonAndTool': 'Выберите сотрудника и инструмент',
      'searchEmployee': 'Поиск сотрудника...',
      'searchTool': 'Поиск инструмента...',
      'issueUpper': 'ВЫДАТЬ',
      'returnUpper': 'ВЕРНУТЬ',
      'invShort': 'Инв',
      'invNumber': 'Инв. номер',
      'noName': 'Без имени',
      'noTitle': 'Без названия',
      'noFreeTools': 'Нет свободных инструментов',
      'noToolsOnHands': 'Нет инструмента на руках',
      'whoSelectEmployee': 'Кому выдаем?',
      'whoField': 'КТО (Выбор сотрудника)',
      'whatSelectEmployeeTool': 'Выберите сотрудника и инструмент',
      'whatSelectFreeTool': 'Выберите свободный инструмент',
      'whatFieldOnHands': 'ЧТО (Инструмент этого сотрудника)',
      'whatFieldFree': 'ЧТО (Свободный инструмент)',
      'confirmIssue': 'Подтвердить выдачу',
      'confirmReturn': 'Подтвердить возврат',
    'issueTab': 'Выдача',
    'returnTab': 'Возврат',
    'role_owner': 'Владелец',
    'role_admin': 'Админ',
      'role_foreman': 'Прораб',
    'role_employee': 'Сотрудник',
    'searchByNameOrPhone': 'Поиск по имени или телефону...',
    'searchSite': 'Поиск по названию или адресу...',
    'editProfile': 'Редактировать профиль',
    'setRole': 'Назначить роль',
      'langRu': 'Русский',
      'langUk': 'Українська',
      'langPl': 'Polski',
      'langEn': 'English',
      'searchByNameOrInv': 'Поиск по названию или №...',
      'searchByToolOrLastName': 'Поиск по инструменту или фамилии...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Статус сотрудника',
      'empStatusActive': 'Активен',
      'empStatusFired': 'Уволен',
      'toolStatus': 'Статус инструмента',
      'toolStatusActive': 'Рабочий',
      'toolStatusRepair': 'В ремонте',
      'toolStatusDisposed': 'Списан',
      'markToolActive': 'Сделать рабочим',
      'markToolRepair': 'Отправить в ремонт',
      'markToolDisposed': 'Списать (утилизация)',
      'statusNote': 'Комментарий',
      'reportsByTool': 'По инструменту',
      'reportsByPerson': 'По сотруднику',
      'selectTool': 'Выбери инструмент',
      'selectPerson': 'Выбери сотрудника',
      'selectToolFirst': 'Сначала выбери инструмент',
      'selectPersonFirst': 'Сначала выбери сотрудника',
      'warehouse': 'Склад',
      'where': 'Где',
      'issuedAt': 'Выдано',
      'noData': 'Нет данных',
      'noIssued': 'Ничего не выдано',

      'tariffLimitsTitle': 'Тариф и лимиты',
      'subscriptionTitle': 'Подписка',
      'subscriptionStatusLabel': 'Статус',
      'subscriptionModeLabel': 'Режим',
      'subscriptionValidUntilLabel': 'Действует до',
      'subscriptionTest': 'Тестовый режим',
      'subscriptionLive': 'Платный режим',
      'subscriptionActive': 'Активна',
      'subscriptionInactive': 'Не активна',
      'buyRenew': 'Купить / Продлить',
      'buyRenewSoon': 'Оплата скоро будет доступна. Пока для покупки/продления свяжитесь с поддержкой.',
      'planLabel': 'Тариф',
      'perMonth': 'месяц',
      'peopleLimitLabel': 'Лимит людей',
      'usedActiveLabel': 'Использовано (активные)',
      'inactiveNotCountedNote': 'Уволенные/неактивные не считаются в лимит.',
      'billingModeLabel': 'Режим оплаты',
      'billingTest': 'ТЕСТ',
      'billingLive': 'БОЕВОЙ',
      'changePlan': 'Изменить тариф',
      'planChangeOnlyOwner': 'Только владелец (owner) может менять тариф.',
      'selectPlan': 'Выберите тариф',
      'ok': 'OK',
      'planSaved': 'Тариф сохранён',
      'gpsNotInPlan': 'GPS-трекинг доступен с тарифа Про и выше',
      'gpsIncluded': 'GPS ✓',
      'gpsNotIncluded': 'GPS —',
      'supportTitle': 'Поддержка',
      'supportDesc': 'По вопросам работы приложения вы можете связаться с нами:',
      'versionLabel': 'Версия',
      'emailLabel': 'Email',
      'telegramLabel': 'Telegram',
      'myShift': 'Моя смена',
      'startShift': 'Начать смену',
      'endShift': 'Завершить смену',
      'currentShift': 'Текущая смена',
      'shiftStarted': 'Смена началась!',
      'shiftEnded': 'Смена завершена!',
      'shiftActive': 'Смена активна',
      'shiftStart': 'Начало',
      'shiftEnd': 'Конец',
      'selectSite': 'Выберите объект',
      'noSites': 'Объекты не добавлены. Попросите администратора.',
      'writeReport': 'Отчёт за смену',
      'whatDone': 'Что было сделано',
      'workReport': 'Отчёт',
      'timesheets': 'Табель смен',
      'myTimesheets': 'Мои смены',
      'allTimesheets': 'Все смены',
      'totalHours': 'Итого часов',
      'shiftsCount': 'Смен',
      'manageSites': 'Управление объектами',
      'sites': 'Объекты',
      'addSite': 'Добавить объект',
      'editSite': 'Редактировать объект',
      'siteName': 'Название объекта',
      'siteAddress': 'Адрес',
      'siteRadius': 'Радиус чек-ина (м)',
      'gpsInterval': 'Интервал GPS (мин)',
      'gpsPermissionDenied': 'GPS недоступен — смена начата без проверки координат',
      'gpsWarningTitle': 'Вы вне зоны объекта',
      'gpsWarningText': 'Ваше местоположение не совпадает с адресом объекта.',
      'distance': 'Расстояние',
      'startAnyway': 'Начать всё равно',
      'allTime': 'Всё время', 'allDays': 'Все дни', 'today': 'Сегодня', 'allStatuses': 'Все статусы', 'filterActive': 'Активна', 'shiftCompleted': 'Завершена',
      'allSites': 'Все объекты',
      'allPeople': 'Все сотрудники',
      'exportPdf': 'Экспорт PDF',
      'exportXlsx': 'Экспорт Excel',
      'shiftTypeHourly': 'По часам',
      'shiftTypeAccord': 'Аккорд',
      'chooseShiftType': 'Тип смены',
      'shiftType': 'Тип работы',
      'reportRequired': 'Заполните отчёт — что было сделано',
      'viewSites': 'Все объекты',
      'navigateTo': 'Маршрут',
      'linkUser': 'Привязать пользователя',
      'linkedUser': 'Привязан к',
      'unlinkUser': 'Отвязать',
      'selectUserToLink': 'Выберите пользователя',
      'notLinked': 'Аккаунт не привязан к анкете. Обратитесь к администратору.',
      'personTypePerson': 'Человек',
      'personTypeObject': 'Объект',
      'noObjects': 'Объектов пока нет. Нажми +',
      'objectCompleted': 'Завершён',
      'markObjectCompleted': 'Завершить объект',
      'personTab': 'Люди',
      'objectTab': 'Объекты',
      'cannotCompleteHasTools': 'Нельзя завершить: на объекте {n} инструментов',
      'cannotFireHasTools': 'Нельзя уволить: у сотрудника {n} инструментов',
      'addObject': 'Добавить объект',
      'shiftReminder10hTitle': 'Смена идёт 10 часов',
      'shiftReminder10hBody': 'Смена активна больше 10 часов. Не забудьте закрыть.',
      'shiftReminder12hTitle': '⚠️ Смена 12 часов!',
      'shiftReminder12hBody': 'Внимание: смена идёт больше 12 часов. Закройте смену.',
      'offlineBanner': 'Нет подключения • данные из кэша',
      'alreadyHaveActiveShift': 'У вас уже есть активная смена. Закройте её перед началом новой.',
      'forceCloseShift': 'Принудительно закрыть',
      'forceCloseShiftHint': 'Смена будет закрыта прямо сейчас. Вы можете добавить отчёт.',
      'shiftClosed': 'Смена закрыта.',
      'archive': 'Архив',
      'noArchive': 'Архив пуст',
      'notifications': 'Уведомления',
      'noNotifications': 'Нет новых уведомлений',
      'newMemberRequest': 'Новая заявка на вступление',
      'markAllRead': 'Отметить все прочитанными',
      'pendingRequests': 'Заявки',
      'copyTool': 'Копировать',
      'toolCopied': 'Инструмент скопирован',
      'sortNameAZ': 'Название А-Я',
      'sortCountDesc': 'Сначала большие группы',
      'sortDateDesc': 'Сначала новые',
      'darkTheme': 'Тёмная тема',
      'lightTheme': 'Светлая тема',
      'systemTheme': 'Системная тема',
      'printQr': 'Распечатать QR',
      'saveAsPng': 'Сохранить PNG',
      'thermalLabel': 'Термо-этикетка',
      'printAllQr': 'Все QR на лист',
      'noResults': 'Ничего не найдено',
      'actPdf': 'Акт PDF',
      'nakladnayaPdf': 'Накладная PDF',
      'yes': 'Да',
      'no': 'Нет',
      'name': 'Имя',
      'toolName': 'Название инструмента',
      'editTool': 'Редактировать инструмент',
      'editEmployee': 'Редактировать сотрудника',
      'cannotSetToolStatusOnHands': 'Нельзя изменить статус: инструмент на руках',
      'gpsTrack': 'GPS-трек',
      'noGpsData': 'Нет GPS-данных',
},
    AppLang.uk: {
      'appTitle': 'ToolKeeper',
      'login': 'Вхід',
      'register': 'Реєстрація',
      'enter': 'Увійти',
      'logout': 'Вийти',
      'deleteAccount': 'Видалити акаунт',
      'deleteAccountTitle': 'Видалити акаунт?',
      'deleteAccountText': 'Усі ваші дані будуть видалені. Цю дію неможливо скасувати.',
      'people': 'Люди',
      'tools': 'Інструменти',
      'tool': 'Інструмент',
      'inv': 'Інв. №',
      'issue': 'Видача',
      'profile': 'Профіль',
      'chooseLang': 'Обери мову',
      'chooseCompany': 'Оберіть вашу фірму',
      'searchingCompany': 'Шукаю вашу фірму...',
      'companyNotFound': 'Фірму не знайдено',
      'companyDeleted': 'Фірму видалено',
      'noAccessCompany': 'Немає доступу до фірми',
      'removedFromCompany': 'Вас видалили з фірми. Введіть код ще раз і дочекайтесь підтвердження.',
      'leaveCompany': 'Вийти / обрати іншу фірму',
      'leaveCompanyConfirm': 'Ви впевнені, що хочете вийти з цієї команди?',
      'createCompany': 'Створити команду',
      'enterInviteCode': 'Введіть код запрошення',
      'joinCompany': 'Приєднатися',
      'or': 'АБО',
      'companyName': 'Назва фірми',
      'create': 'Створити',
      'myCompany': 'Моя фірма',
      'myProfile': 'Мій профіль',
      'role': 'Роль',
      'role_owner': 'Власник',
      'role_admin': 'Адміністратор',
      'role_foreman': 'Прораб',
      'role_employee': 'Працівник',
      'editRoles': 'Редагувати ролі',
      'save': 'Зберегти',
      'cancel': 'Скасувати',
      'inviteCode': 'Код запрошення',
      'copy': 'Копіювати',
      'copied': 'Скопійовано',
      'share': 'Поділитися',
      'pendingRequests': 'Заявки на вступ',
      'accept': 'Прийняти',
      'deny': 'Відхилити',
      'noRequests': 'Немає заявок',
      'members': 'Учасники',
      'noMembers': 'Немає учасників',
      'addEmployee': 'Додати працівника',
      'employeeFirstName': "Ім'я",
      'employeeLastName': 'Прізвище',
      'employeePosition': 'Посада',
      'phone': 'Телефон',
      'add': 'Додати',
      'editEmployee': 'Редагувати працівника',
      'deleteEmployee': 'Видалити працівника',
      'delete': 'Видалити',
      'deleteConfirm': 'Точно видалити?',
      'searchEmployee': 'Пошук працівника...',
      'noEmployees': 'Немає працівників',
      'addTool': 'Додати інструмент',
      'toolName': 'Назва інструменту',
      'toolInv': 'Інв. номер',
      'addToolBtn': 'Додати',
      'editTool': 'Редагувати інструмент',
      'deleteTool': 'Видалити інструмент',
      'searchTool': 'Пошук інструменту...',
      'noTools': 'Немає інструментів',
      'issueTitle': 'Видача / Повернення',
      'issueTo': 'Видати',
      'returnFrom': 'Повернути',
      'selectEmployee': 'Оберіть працівника',
      'selectTool': 'Оберіть інструмент',
      'issued': 'Видано',
      'returned': 'Повернено',
      'history': 'Історія',
      'searchHistory': 'Пошук по історії...',
      'noMoves': 'Немає записів',
      'moveIssue': 'Видача',
      'moveReturn': 'Повернення',
      'onHands': 'На руках',
      'freeTools': 'Вільні',
      'total': 'Всього',
      'toolsCount': 'Інструментів',
      'pcs': 'шт.',
      'report': 'Звіт',
      'filter': 'Фільтр',
      'reset': 'Скинути',
      'export': 'Експорт',
      'exportCsv': 'Експорт CSV',
      'exportPdf': 'Експорт PDF',
      'exportDone': 'Експорт готовий',
      'loading': 'Завантаження...',
      'error': 'Помилка',
      'ok': 'ОК',
      'yes': 'Так',
      'no': 'Ні',
      'langRu': 'Русский',
      'langUk': 'Українська',
      'langPl': 'Polski',
      'langEn': 'English',
      'selectModeFirst': 'Спочатку виберіть: ВИДАТИ або ПОВЕРНУТИ',
      'selectPersonForReturnFirst': 'Спочатку виберіть працівника для ПОВЕРНЕННЯ',
      'noRightsIssueReturn': 'Немає прав на видачу/повернення',
      'selectPersonAndTool': 'Оберіть працівника та інструмент',
      'issueUpper': 'ВИДАТИ',
      'returnUpper': 'ПОВЕРНУТИ',
      'invShort': 'Інв',
      'invNumber': 'Інв. номер',
      'noName': 'Без імені',
      'noTitle': 'Без назви',
      'noFreeTools': 'Немає вільних інструментів',
      'noToolsOnHands': 'Немає інструментів на руках',
      'whoSelectEmployee': 'Кому видати',
      'whoField': 'КТО (Вибір співробітника)',
      'whatSelectEmployeeTool': 'Що видати',
      'whatSelectFreeTool': 'Що повернути',
      'whatFieldOnHands': 'ЧТО (Інструмент цього співробітника)',
      'whatFieldFree': 'ЧТО (Вільний інструмент)',
      'confirmReturn': 'Повернути',
      'confirmIssue': 'Видати',
      'restoreCompanyError': 'Не вдалося відновити вибір фірми',
      'restoredCompanyId': 'Я відновив activeCompanyId з вашого профілю',
      'resetActiveCompanyId': 'Я скинув activeCompanyId, щоб ви могли вибрати/створити фірму заново.',
      'errUserRead': 'Помилка читання профілю користувача',
      'errCompanyRead': 'Помилка читання фірми',
      'errMemberRead': 'Помилка читання учасника фірми',
    'addPerson': 'Додати людину',
    'alreadyIn': 'Вже у компанії',
    'approve': 'Підтвердити',
    'archivedCompany': 'Компанію архівовано',
    'askAdminIssueReturn': 'Попросіть адміна видати/прийняти',
    'deleteCompanyConfirm': 'Видалити компанію повністю?',
    'deleteCompanyWarn': 'Буде видалено всі дані. Дію не можна скасувати.',
    'issueTab': 'Видача',
    'returnTab': 'Повернення',
    'searchByNameOrPhone': 'Пошук за ім’ям або телефоном...',
    'selectToolFirst': 'Спочатку виберіть інструмент',
    'birthDate': 'Дата народження',
    'changePassword': 'Змінити / встановити пароль',
    'chooseRole': 'Виберіть роль',
    'clothesSize': 'Розмір одягу',
    'codeNotFound': 'Код не знайдено',
    'company': 'Компанія',
    'continue': 'Продовжити',
    'copyCodeHint': 'Скопіюйте та надішліть співробітнику',
    'decline': 'Відхилити',
    'deleteCompany': 'Видалити компанію',
    'deleteCompanyText': 'Видалити компанію повністю',
    'deleteCompanyTitle': 'Видалення компанії',
    'done': 'Готово',
    'editCompany': 'Редагувати компанію',
    'editMyProfile': 'Редагувати мій профіль',
    'editProfile': 'Редагувати профіль',
    'employeeRequests': 'Заявки співробітників',
    'enterPassword': 'Введіть пароль',
    'enterPhone': 'Введіть телефон',
    'firstName': 'Ім’я',
    'invHint': 'Інвентарний номер (напр. SKDW-001)',
    'join': 'Приєднатися',
    'lastName': 'Прізвище',
    'loginPc': 'Вхід на ПК: прив’язати/змінити пароль',
    'name': 'Назва',
    'noCompany': 'Компанію не вибрано',
    'noRights': 'Немає прав',
    'password': 'Пароль',
    'position': 'Посада',
    'reports': 'Звіти',
    'reportsPeople': 'У кого що (по людях)',
    'reportsTools': 'Де інструмент (по інструментах)',
    'reportFilterHint': 'Фільтр звіту...',
    'onHandsTotal': 'Зараз на руках всього: {n} од.',
    'toolsCountLabel': 'Інструментів: {n}',
    'whoLabel': 'У кого: {name}',
    'requests': 'Заявки',
    'saveProfile': 'Зберегти профіль',
    'sendReset': 'Надіслати посилання для скидання',
    'sessionTitle': 'Сесія',
    'setPassword': 'Встановити пароль',
    'setRole': 'Призначити роль',
    'shoeSize': 'Розмір взуття',
    'switchAcc': 'Змінити акаунт',
    'toolNameHint': 'Назва (напр. Болгарка)',
    'welcome': 'Ласкаво просимо',
    'yourInviteCode': 'Ваш код запрошення',
    'repeatPassword': 'Повторіть пароль',
    'email': 'Ел. пошта',
    'employee': 'Вступити в команду',
    'employees': 'Співробітники',
    'enterEmailPass': 'Введіть email і пароль',
    'google': 'Google',
    'haveAccount': 'Вже є акаунт?',
    'historyEmpty': 'Історії ще немає',
    'linkPassword': 'Прив’язати/встановити пароль',
    'needAccount': 'Потрібен акаунт',
    'needProfile': 'Заповніть профіль',
    'needReLogin': 'Увійдіть знову',
    'newCompanyName': 'Нова назва компанії',
    'newPassword': 'Новий пароль',
    'noPeople': 'Поки що немає людей',
    'noneIssued': 'Нічого не видано',
    'noneIssued2': 'Немає інструментів на руках',
    'onlyAdmin': 'Лише власник/адмін',
    'owner': 'Створити команду',
    'passwordsNotMatch': 'Паролі не співпадають',
    'pendingText': 'Ваша заявка очікує підтвердження',
    'pendingTitle': 'Очікує',
    'profileForm': 'Форма профілю',
    'renameCompany': 'Перейменувати компанію',
      'searchByNameOrInv': 'Пошук за назвою або №...',
      'searchByToolOrLastName': 'Пошук за інструментом або прізвищем...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Статус працівника',
      'empStatusActive': 'Активний',
      'empStatusFired': 'Звільнений',
      'toolStatus': 'Статус інструменту',
      'toolStatusActive': 'Робочий',
      'toolStatusRepair': 'В ремонті',
      'toolStatusDisposed': 'Списано',
      'markToolActive': 'Зробити робочим',
      'markToolRepair': 'Відправити в ремонт',
      'markToolDisposed': 'Списати (утилізація)',
      'statusNote': 'Коментар',
      'reportsByTool': 'За інструментом',
      'reportsByPerson': 'За працівником',
      'selectPerson': 'Обери працівника',
      'selectPersonFirst': 'Спочатку обери працівника',
      'warehouse': 'Склад',
      'where': 'Де',
      'issuedAt': 'Видано',
      'noData': 'Немає даних',
      'noIssued': 'Нічого не видано',
      'subscriptionTitle': 'Підписка',
      'subscriptionStatusLabel': 'Статус',
      'subscriptionModeLabel': 'Режим',
      'subscriptionValidUntilLabel': 'Діє до',
      'subscriptionTest': 'Тестовий режим',
      'subscriptionLive': 'Платний режим',
      'subscriptionActive': 'Активна',
      'subscriptionInactive': 'Не активна',
      'buyRenew': 'Купити / Подовжити',
      'buyRenewSoon': 'Оплата скоро буде доступна. Поки що для купівлі/продовження зверніться в підтримку.',
      'admin': 'Адмін',
      'billingLive': 'LIVE',
      'billingTest': 'ТЕСТ',
      'billingModeLabel': 'Режим оплати',
      'changePlan': 'Змінити тариф',
      'emailLabel': 'Email',
      'needPeopleFirst': 'Спочатку додайте людей',
      'needToolsFirst': 'Спочатку додайте інструменти',
      'noFreeTool': 'Немає вільного інструмента',
      'noReturnTool': 'Немає інструмента для повернення',
      'peopleLimitLabel': 'Ліміт людей',
      'perMonth': 'міс.',
      'person': 'Особа',
      'planChangeOnlyOwner': 'Лише власник може змінити тариф.',
      'planLabel': 'Тариф',
      'planSaved': 'Тариф збережено',
      'gpsNotInPlan': 'GPS-трекінг доступний з тарифу Про і вище',
      'gpsIncluded': 'GPS ✓',
      'gpsNotIncluded': 'GPS —',
      'returnTitle': 'Підтвердити повернення',
      'returnTool': 'Повернення',
      'selectPlan': 'Виберіть тариф',
      'supportDesc': 'З питань роботи застосунку ви можете зв’язатися з нами:',
      'supportTitle': 'Підтримка',
      'tariffLimitsTitle': 'Тариф і ліміти',
      'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Використано (активні)',
      'inactiveNotCountedNote': 'Звільнені/неактивні не рахуються в ліміт.',
      'versionLabel': 'Версія',
      'worker': 'Працівник',
      'myShift': 'Моя зміна',
      'startShift': 'Почати зміну',
      'endShift': 'Завершити зміну',
      'currentShift': 'Поточна зміна',
      'shiftStarted': 'Зміну розпочато!',
      'shiftEnded': 'Зміну завершено!',
      'shiftActive': 'Зміна активна',
      'shiftStart': 'Початок',
      'shiftEnd': 'Кінець',
      'selectSite': 'Оберіть об\'єкт',
      'noSites': 'Об\'єкти не додані. Зверніться до адміністратора.',
      'writeReport': 'Звіт за зміну',
      'whatDone': 'Що зроблено',
      'workReport': 'Звіт',
      'timesheets': 'Табель змін',
      'myTimesheets': 'Мої зміни',
      'allTimesheets': 'Всі зміни',
      'totalHours': 'Всього годин',
      'shiftsCount': 'Змін',
      'manageSites': 'Управління об\'єктами',
      'sites': 'Об\'єкти',
      'addSite': 'Додати об\'єкт',
      'editSite': 'Редагувати об\'єкт',
      'siteName': 'Назва об\'єкту',
      'siteAddress': 'Адреса',
      'siteRadius': 'Радіус чек-іну (м)',
      'gpsInterval': 'Інтервал GPS (хв)',
      'gpsPermissionDenied': 'GPS недоступний — зміну розпочато без перевірки координат',
      'gpsWarningTitle': 'Ви поза зоною об\'єкту',
      'gpsWarningText': 'Ваше місцезнаходження не збігається з адресою об\'єкту.',
      'distance': 'Відстань',
      'startAnyway': 'Почати все одно',
      'allTime': 'Весь час',
      'allSites': 'Всі об\'єкти',
      'allPeople': 'Всі співробітники',
      'exportXlsx': 'Експорт Excel',
      'actPdf': 'Акт PDF',
      'nakladnayaPdf': 'Накладна PDF',
      'gpsTrack': 'GPS-трек',
      'noGpsData': 'Немає GPS-даних',
      'shiftTypeHourly': 'Погодинно',
      'shiftTypeAccord': 'Акорд',
      'chooseShiftType': 'Тип зміни',
      'shiftType': 'Тип роботи',
      'reportRequired': 'Заповніть звіт — що було зроблено',
      'viewSites': 'Всі об\'єкти',
      'navigateTo': 'Маршрут',
      'linkUser': 'Прив\'язати користувача',
      'linkedUser': 'Прив\'язаний до',
      'unlinkUser': 'Відв\'язати',
      'selectUserToLink': 'Оберіть користувача',
      'notLinked': 'Акаунт не прив\'язаний до анкети. Зверніться до адміністратора.',
      'personTypePerson': 'Людина',
      'personTypeObject': 'Об\'єкт',
      'noObjects': 'Об\'єктів поки немає. Натисніть +',
      'objectCompleted': 'Завершений',
      'markObjectCompleted': 'Завершити об\'єкт',
      'personTab': 'Люди',
      'objectTab': 'Об\'єкти',
      'cannotCompleteHasTools': 'Не можна завершити: на об\'єкті {n} інструментів',
      'cannotFireHasTools': 'Не можна звільнити: у співробітника {n} інструментів',
      'addObject': 'Додати об\'єкт',
      'shiftReminder10hTitle': 'Зміна триває 10 годин',
      'shiftReminder10hBody': 'Зміна активна більше 10 годин. Не забудьте закрити.',
      'shiftReminder12hTitle': '⚠️ Зміна 12 годин!',
      'shiftReminder12hBody': 'Увага: зміна триває більше 12 годин. Закрийте зміну.',
      'offlineBanner': 'Немає підключення • дані з кешу',
      'alreadyHaveActiveShift': 'У вас вже є активна зміна. Закрийте її перед початком нової.',
      'forceCloseShift': 'Примусово закрити',
      'forceCloseShiftHint': 'Зміну буде закрито зараз. Ви можете додати звіт.',
      'shiftClosed': 'Зміну закрито.',
      'archive': 'Архів',
      'noArchive': 'Архів порожній',
      'notifications': 'Сповіщення',
      'noNotifications': 'Немає нових сповіщень',
      'newMemberRequest': 'Нова заявка на вступ',
      'markAllRead': 'Позначити всі як прочитані',
      'copyTool': 'Копіювати',
      'toolCopied': 'Інструмент скопійовано',
      'sortNameAZ': 'Назва А-Я',
      'sortCountDesc': 'Спочатку великі групи',
      'sortDateDesc': 'Спочатку нові',
      'darkTheme': 'Темна тема',
      'lightTheme': 'Світла тема',
      'systemTheme': 'Системна тема',
      'printQr': 'Надрукувати QR',
      'saveAsPng': 'Зберегти PNG',
      'thermalLabel': 'Термо-етикетка',
      'printAllQr': 'Усі QR на аркуш',
      'noResults': 'Нічого не знайдено',
    },
    AppLang.pl: {
      'appTitle': 'ToolKeeper',
      'login': 'Logowanie',
      'register': 'Rejestracja',
      'enter': 'Zaloguj',
      'logout': 'Wyloguj',
      'deleteAccount': 'Usuń konto',
      'deleteAccountTitle': 'Usuń konto?',
      'deleteAccountText': 'Wszystkie Twoje dane zostaną usunięte. Tej operacji nie można cofnąć.',
      'people': 'Ludzie',
      'tools': 'Narzędzia',
      'tool': 'Narzędzie',
      'inv': 'Nr inw.',
      'issue': 'Wydanie',
      'profile': 'Profil',
      'chooseLang': 'Wybierz język',
      'chooseCompany': 'Wybierz firmę',
      'searchingCompany': 'Szukam Twojej firmy...',
      'companyNotFound': 'Nie znaleziono firmy',
      'companyDeleted': 'Firma została usunięta',
      'noAccessCompany': 'Brak dostępu do firmy',
      'removedFromCompany': 'Zostałeś usunięty z firmy. Wpisz kod ponownie i poczekaj na akceptację.',
      'leaveCompany': 'Wyjdź / wybierz inną firmę',
      'leaveCompanyConfirm': 'Czy na pewno chcesz opuścić ten zespół?',
      'createCompany': 'Utwórz zespół',
      'enterInviteCode': 'Wpisz kod zaproszenia',
      'joinCompany': 'Dołącz',
      'or': 'LUB',
      'companyName': 'Nazwa firmy',
      'create': 'Utwórz',
      'myCompany': 'Moja firma',
      'myProfile': 'Mój profil',
      'role': 'Rola',
      'role_owner': 'Właściciel',
      'role_admin': 'Administrator',
      'role_foreman': 'Brygadzista',
      'role_employee': 'Pracownik',
      'editRoles': 'Edytuj role',
      'save': 'Zapisz',
      'cancel': 'Anuluj',
      'inviteCode': 'Kod zaproszenia',
      'copy': 'Kopiuj',
      'copied': 'Skopiowano',
      'share': 'Udostępnij',
      'pendingRequests': 'Prośby o dołączenie',
      'accept': 'Akceptuj',
      'deny': 'Odrzuć',
      'noRequests': 'Brak próśb',
      'members': 'Członkowie',
      'noMembers': 'Brak członków',
      'addEmployee': 'Dodaj pracownika',
      'employeeFirstName': 'Imię',
      'employeeLastName': 'Nazwisko',
      'employeePosition': 'Stanowisko',
      'phone': 'Telefon',
      'add': 'Dodaj',
      'editEmployee': 'Edytuj pracownika',
      'deleteEmployee': 'Usuń pracownika',
      'delete': 'Usuń',
      'deleteConfirm': 'Na pewno usunąć?',
      'searchEmployee': 'Szukaj pracownika...',
      'noEmployees': 'Brak pracowników',
      'addTool': 'Dodaj narzędzie',
      'toolName': 'Nazwa narzędzia',
      'toolInv': 'Nr inw.',
      'addToolBtn': 'Dodaj',
      'editTool': 'Edytuj narzędzie',
      'deleteTool': 'Usuń narzędzie',
      'searchTool': 'Szukaj narzędzia...',
      'noTools': 'Brak narzędzi',
      'issueTitle': 'Wydanie / Zwrot',
      'issueTo': 'Wydać',
      'returnFrom': 'Zwrócić',
      'selectEmployee': 'Wybierz pracownika',
      'selectTool': 'Wybierz narzędzie',
      'issued': 'Wydano',
      'returned': 'Zwrócono',
      'history': 'Historia',
      'searchHistory': 'Szukaj w historii...',
      'noMoves': 'Brak wpisów',
      'moveIssue': 'Wydanie',
      'moveReturn': 'Zwrot',
      'onHands': 'Na rękach',
      'freeTools': 'Wolne',
      'total': 'Razem',
      'toolsCount': 'Narzędzi',
      'pcs': 'szt.',
      'report': 'Raport',
      'filter': 'Filtr',
      'reset': 'Reset',
      'export': 'Eksport',
      'exportCsv': 'Eksport CSV',
      'exportPdf': 'Eksport PDF',
      'exportDone': 'Eksport gotowy',
      'loading': 'Ładowanie...',
      'error': 'Błąd',
      'ok': 'OK',
      'yes': 'Tak',
      'no': 'Nie',
      'langRu': 'Русский',
      'langUk': 'Українська',
      'langPl': 'Polski',
      'langEn': 'English',
      'selectModeFirst': 'Najpierw wybierz: WYDANIE albo ZWROT',
      'selectPersonForReturnFirst': 'Najpierw wybierz pracownika do ZWROTU',
      'noRightsIssueReturn': 'Brak uprawnień do wydania/zwrotu',
      'selectPersonAndTool': 'Wybierz pracownika i narzędzie',
      'issueUpper': 'WYDAĆ',
      'returnUpper': 'ZWRÓCIĆ',
      'invShort': 'Inw',
      'invNumber': 'Nr inw.',
      'noName': 'Bez imienia',
      'noTitle': 'Bez nazwy',
      'noFreeTools': 'Brak wolnych narzędzi',
      'noToolsOnHands': 'Brak narzędzi na rękach',
      'whoSelectEmployee': 'Komu wydać',
      'whoField': 'KTO (Wybór pracownika)',
      'whatSelectEmployeeTool': 'Co wydać',
      'whatSelectFreeTool': 'Co zwrócić',
      'whatFieldOnHands': 'CO (Narzędzie tego pracownika)',
      'whatFieldFree': 'CO (Wolne narzędzie)',
      'confirmReturn': 'Zwróć',
      'confirmIssue': 'Wydaj',
      'restoreCompanyError': 'Nie udało się przywrócić wyboru firmy',
      'restoredCompanyId': 'Przywróciłam activeCompanyId z Twojego profilu',
      'resetActiveCompanyId': 'Zresetowałam activeCompanyId, abyś mógł wybrać/utworzyć firmę ponownie.',
      'errUserRead': 'Błąd odczytu profilu użytkownika',
      'errCompanyRead': 'Błąd odczytu firmy',
      'errMemberRead': 'Błąd odczytu członka firmy',
    'addPerson': 'Dodaj osobę',
    'alreadyIn': 'Już w firmie',
    'approve': 'Zatwierdź',
    'archivedCompany': 'Firma zarchiwizowana',
    'askAdminIssueReturn': 'Poproś admina o wydanie/zwrot',
    'deleteCompanyConfirm': 'Usunąć firmę całkowicie?',
    'deleteCompanyWarn': 'To usunie wszystkie dane. Tego nie da się cofnąć.',
    'issueTab': 'Wydanie',
    'returnTab': 'Zwrot',
    'searchByNameOrPhone': 'Szukaj po imieniu lub telefonie...',
    'selectToolFirst': 'Najpierw wybierz narzędzie',
    'birthDate': 'Data urodzenia',
    'changePassword': 'Zmień / ustaw hasło',
    'chooseRole': 'Wybierz rolę',
    'clothesSize': 'Rozmiar odzieży',
    'codeNotFound': 'Nie znaleziono kodu',
    'company': 'Firma',
    'continue': 'Kontynuuj',
    'copyCodeHint': 'Skopiuj i wyślij pracownikowi',
    'decline': 'Odrzuć',
    'deleteCompany': 'Usuń firmę',
    'deleteCompanyText': 'Usuń firmę całkowicie',
    'deleteCompanyTitle': 'Usuwanie firmy',
    'done': 'Gotowe',
    'editCompany': 'Edytuj firmę',
    'editMyProfile': 'Edytuj mój profil',
    'editProfile': 'Edytuj profil',
    'employeeRequests': 'Wnioski pracowników',
    'enterPassword': 'Wpisz hasło',
    'enterPhone': 'Wpisz telefon',
    'firstName': 'Imię',
    'invHint': 'Numer inwentarzowy (np. SKDW-001)',
    'join': 'Dołącz',
    'lastName': 'Nazwisko',
    'loginPc': 'Logowanie PC: powiąż/zmień hasło',
    'name': 'Nazwa',
    'noCompany': 'Nie wybrano firmy',
    'noRights': 'Brak uprawnień',
    'password': 'Hasło',
    'position': 'Stanowisko',
    'reports': 'Raporty',
    'reportsPeople': 'Kto ma co (wg osób)',
    'reportsTools': 'Gdzie jest narzędzie (wg narzędzi)',
    'reportFilterHint': 'Filtr raportu...',
    'onHandsTotal': 'Na rękach łącznie: {n} szt.',
    'toolsCountLabel': 'Narzędzia: {n}',
    'whoLabel': 'U kogo: {name}',
    'requests': 'Wnioski',
    'saveProfile': 'Zapisz profil',
    'sendReset': 'Wyślij link resetu',
    'sessionTitle': 'Sesja',
    'setPassword': 'Ustaw hasło',
    'setRole': 'Ustaw rolę',
    'shoeSize': 'Rozmiar buta',
    'switchAcc': 'Zmień konto',
    'toolNameHint': 'Nazwa (np. Szlifierka)',
    'welcome': 'Witamy',
    'yourInviteCode': 'Twój kod zaproszenia',
    'repeatPassword': 'Powtórz hasło',
    'email': 'Email',
    'employee': 'Dołącz do zespołu',
    'employees': 'Pracownicy',
    'enterEmailPass': 'Wpisz email i hasło',
    'google': 'Google',
    'haveAccount': 'Masz już konto?',
    'historyEmpty': 'Brak historii',
    'linkPassword': 'Powiąż/ustaw hasło',
    'needAccount': 'Potrzebne konto',
    'needProfile': 'Uzupełnij profil',
    'needReLogin': 'Zaloguj się ponownie',
    'newCompanyName': 'Nowa nazwa firmy',
    'newPassword': 'Nowe hasło',
    'noPeople': 'Brak osób',
    'noneIssued': 'Nic nie wydano',
    'noneIssued2': 'Brak narzędzi na rękach',
    'onlyAdmin': 'Tylko właściciel/admin',
    'owner': 'Utwórz zespół',
    'passwordsNotMatch': 'Hasła nie pasują',
    'pendingText': 'Twoja prośba czeka na akceptację',
    'pendingTitle': 'Oczekuje',
    'profileForm': 'Formularz profilu',
    'renameCompany': 'Zmień nazwę firmy',
      'searchByNameOrInv': 'Szukaj po nazwie lub nr...',
      'searchByToolOrLastName': 'Szukaj po narzędziu lub nazwisku...',

      // --- Employee/Tool status ---
      'employeeStatus': 'Status pracownika',
      'empStatusActive': 'Aktywny',
      'empStatusFired': 'Zwolniony',
      'toolStatus': 'Status narzędzia',
      'toolStatusActive': 'Sprawne',
      'toolStatusRepair': 'W naprawie',
      'toolStatusDisposed': 'Zlikwidowane',
      'markToolActive': 'Oznacz jako sprawne',
      'markToolRepair': 'Wyślij do naprawy',
      'markToolDisposed': 'Spisz (utylizacja)',
      'statusNote': 'Komentarz',
      'reportsByTool': 'Po narzędziu',
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
      'subscriptionValidUntilLabel': 'Ważna do',
      'subscriptionTest': 'Tryb testowy',
      'subscriptionLive': 'Tryb płatny',
      'subscriptionActive': 'Aktywna',
      'subscriptionInactive': 'Nieaktywna',
      'buyRenew': 'Kup / Przedłuż',
      'buyRenewSoon': 'Płatności będą dostępne wkrótce. Na razie, aby kupić/przedłużyć, skontaktuj się z pomocą.',
      'admin': 'Admin',
      'billingLive': 'LIVE',
      'billingTest': 'TEST',
      'billingModeLabel': 'Tryb płatności',
      'changePlan': 'Zmień plan',
      'emailLabel': 'Email',
      'lang': 'Język',
      'needToolsFirst': 'Najpierw dodaj narzędzia',
      'noFreeTool': 'Brak wolnego narzędzia',
      'noReturnTool': 'Brak narzędzia do zwrotu',
      'peopleLimitLabel': 'Limit osób',
      'perMonth': 'mies.',
      'person': 'Osoba',
      'planChangeOnlyOwner': 'Tylko właściciel może zmienić plan.',
      'planLabel': 'Plan',
      'planSaved': 'Plan zapisany',
      'gpsNotInPlan': 'Śledzenie GPS dostępne od planu Pro i wyżej',
      'gpsIncluded': 'GPS ✓',
      'gpsNotIncluded': 'GPS —',
      'returnTitle': 'Potwierdź zwrot',
      'returnTool': 'Zwrot',
      'selectPlan': 'Wybierz plan',
      'supportDesc': 'W sprawie działania aplikacji możesz się z nami skontaktować:',
      'supportTitle': 'Wsparcie',
      'tariffLimitsTitle': 'Taryf i limity',
      'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Użyto (aktywni)',
      'inactiveNotCountedNote': 'Zwolnieni/nieaktywni nie są wliczani do limitu.',
      'versionLabel': 'Wersja',
      'worker': 'Pracownik',
      'myShift': 'Moja zmiana',
      'startShift': 'Rozpocznij zmianę',
      'endShift': 'Zakończ zmianę',
      'currentShift': 'Aktualna zmiana',
      'shiftStarted': 'Zmiana rozpoczęta!',
      'shiftEnded': 'Zmiana zakończona!',
      'shiftActive': 'Zmiana aktywna',
      'shiftStart': 'Początek',
      'shiftEnd': 'Koniec',
      'selectSite': 'Wybierz obiekt',
      'noSites': 'Brak obiektów. Skontaktuj się z administratorem.',
      'writeReport': 'Raport ze zmiany',
      'whatDone': 'Co zostało zrobione',
      'workReport': 'Raport',
      'timesheets': 'Grafik zmian',
      'myTimesheets': 'Moje zmiany',
      'allTimesheets': 'Wszystkie zmiany',
      'totalHours': 'Łącznie godzin',
      'shiftsCount': 'Zmian',
      'manageSites': 'Zarządzanie obiektami',
      'sites': 'Obiekty',
      'addSite': 'Dodaj obiekt',
      'editSite': 'Edytuj obiekt',
      'siteName': 'Nazwa obiektu',
      'siteAddress': 'Adres',
      'siteRadius': 'Promień meldowania (m)',
      'gpsInterval': 'Interwał GPS (min)',
      'gpsPermissionDenied': 'GPS niedostępny — zmiana rozpoczęta bez weryfikacji lokalizacji',
      'gpsWarningTitle': 'Jesteś poza strefą obiektu',
      'gpsWarningText': 'Twoja lokalizacja nie zgadza się z adresem obiektu.',
      'distance': 'Odległość',
      'startAnyway': 'Rozpocznij mimo to',
      'allTime': 'Cały czas',
      'allSites': 'Wszystkie obiekty',
      'allPeople': 'Wszyscy pracownicy',
      'exportXlsx': 'Eksport Excel',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'WZ PDF',
      'cannotSetToolStatusOnHands': 'Nie można zmienić statusu: narzędzie jest wydane',
      'gpsTrack': 'Ślad GPS',
      'noGpsData': 'Brak danych GPS',
      'shiftTypeHourly': 'Godzinowy',
      'shiftTypeAccord': 'Akordowy',
      'chooseShiftType': 'Typ zmiany',
      'shiftType': 'Typ pracy',
      'reportRequired': 'Uzupełnij raport — co zostało zrobione',
      'viewSites': 'Wszystkie obiekty',
      'navigateTo': 'Trasa',
      'linkUser': 'Połącz użytkownika',
      'linkedUser': 'Połączony z',
      'unlinkUser': 'Rozłącz',
      'selectUserToLink': 'Wybierz użytkownika',
      'notLinked': 'Konto nie jest połączone z profilem. Skontaktuj się z administratorem.',
      'personTypePerson': 'Osoba',
      'personTypeObject': 'Obiekt',
      'noObjects': 'Brak obiektów. Naciśnij +',
      'objectCompleted': 'Zakończony',
      'markObjectCompleted': 'Zakończ obiekt',
      'personTab': 'Osoby',
      'objectTab': 'Obiekty',
      'cannotCompleteHasTools': 'Nie można zakończyć: {n} narzędzi na obiekcie',
      'cannotFireHasTools': 'Nie można zwolnić: pracownik ma {n} narzędzi',
      'addObject': 'Dodaj obiekt',
      'shiftReminder10hTitle': 'Zmiana trwa 10 godzin',
      'shiftReminder10hBody': 'Zmiana aktywna ponad 10 godzin. Pamiętaj o zamknięciu.',
      'shiftReminder12hTitle': '⚠️ Zmiana 12 godzin!',
      'shiftReminder12hBody': 'Uwaga: zmiana trwa ponad 12 godzin. Zamknij zmianę.',
      'offlineBanner': 'Brak połączenia • dane z cache',
      'alreadyHaveActiveShift': 'Masz już aktywną zmianę. Zamknij ją przed rozpoczęciem nowej.',
      'forceCloseShift': 'Wymuś zamknięcie',
      'forceCloseShiftHint': 'Zmiana zostanie zamknięta teraz. Możesz dodać raport.',
      'shiftClosed': 'Zmiana zamknięta.',
      'archive': 'Archiwum',
      'noArchive': 'Archiwum puste',
      'notifications': 'Powiadomienia',
      'noNotifications': 'Brak nowych powiadomień',
      'newMemberRequest': 'Nowe zgłoszenie dołączenia',
      'markAllRead': 'Oznacz wszystkie jako przeczytane',
      'copyTool': 'Kopiuj',
      'toolCopied': 'Narzędzie skopiowane',
      'sortNameAZ': 'Nazwa A-Z',
      'sortCountDesc': 'Duże grupy najpierw',
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
      'deleteAccount': 'Delete account',
      'deleteAccountTitle': 'Delete account?',
      'deleteAccountText': 'All your data will be deleted. This action cannot be undone.',
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
      'leaveCompanyConfirm': 'Are you sure you want to leave this team?',
      'createCompany': 'Create team',
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
      'langRu': 'Русский',
      'langUk': 'Українська',
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
    'employee': 'Join a team',
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
    'owner': 'Create a team',
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
      'fixAccess': "It looks like this account has no access to the company (PERMISSION_DENIED) or activeCompanyId points to the wrong company.\n" + 'Go to Profile → select a company / enter invite code, or ask the owner for access.',
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
      'gpsIncluded': 'GPS ✓',
      'gpsNotIncluded': 'GPS —',
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
      'gpsPermissionDenied': 'GPS unavailable — shift started without location check',
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
      'reportRequired': 'Fill in the report — what was done',
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
      'shiftReminder12hTitle': '⚠️ Shift 12 hours!',
      'shiftReminder12hBody': 'Warning: shift has been running for over 12 hours. Close the shift.',
      'offlineBanner': 'No connection • data from cache',
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
      'deleteAccount': 'Konto löschen',
      'deleteAccountTitle': 'Konto löschen?',
      'deleteAccountText': 'Alle Ihre Daten werden gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
      'inv': 'Inv.-Nr.', 'issue': 'Ausgabe', 'profile': 'Profil', 'chooseLang': 'Sprache wählen',
      'companyNotFound': 'Firma nicht gefunden', 'noAccessCompany': 'Kein Zugang zur Firma',
      'leaveCompany': 'Verlassen / andere Firma wählen', 'createCompany': 'Team erstellen',
      'leaveCompanyConfirm': 'Möchten Sie dieses Team wirklich verlassen?',
      'joinCompany': 'Beitreten', 'or': 'ODER', 'companyName': 'Firmenname',
      'create': 'Erstellen', 'myCompany': 'Meine Firma', 'myProfile': 'Mein Profil',
      'role': 'Rolle', 'role_owner': 'Eigentümer', 'role_admin': 'Administrator',
      'role_foreman': 'Vorarbeiter', 'role_employee': 'Mitarbeiter',
      'save': 'Speichern', 'cancel': 'Abbrechen', 'copy': 'Kopieren', 'copied': 'Kopiert',
      'accept': 'Annehmen', 'deny': 'Ablehnen', 'noRequests': 'Keine Anfragen',
      'members': 'Mitglieder', 'phone': 'Telefon', 'add': 'Hinzufügen', 'delete': 'Löschen',
      'deleteConfirm': 'Wirklich löschen?', 'searchEmployee': 'Mitarbeiter suchen...',
      'noEmployees': 'Keine Mitarbeiter', 'toolName': 'Werkzeugname', 'toolInv': 'Inv.-Nr.',
      'searchTool': 'Werkzeug suchen...', 'noTools': 'Keine Werkzeuge',
      'selectEmployee': 'Mitarbeiter auswählen', 'selectTool': 'Werkzeug auswählen',
      'issued': 'Ausgegeben', 'returned': 'Zurückgegeben', 'history': 'Verlauf',
      'noMoves': 'Keine Einträge', 'moveIssue': 'Ausgabe', 'moveReturn': 'Rückgabe',
      'onHands': 'In Händen', 'freeTools': 'Frei', 'total': 'Gesamt', 'toolsCount': 'Werkzeuge',
      'pcs': 'Stk.', 'report': 'Bericht', 'filter': 'Filter', 'reset': 'Zurücksetzen',
      'export': 'Export', 'exportCsv': 'CSV exportieren', 'exportPdf': 'PDF exportieren',
      'exportDone': 'Export fertig', 'loading': 'Laden...', 'error': 'Fehler',
      'ok': 'OK', 'yes': 'Ja', 'no': 'Nein',
      'issueUpper': 'AUSGEBEN', 'returnUpper': 'ZURÜCKGEBEN', 'invShort': 'Inv',
      'invNumber': 'Inv.-Nr.', 'noName': 'Kein Name', 'noTitle': 'Kein Titel',
      'noFreeTools': 'Keine freien Werkzeuge', 'noToolsOnHands': 'Keine Werkzeuge in Händen',
      'whoSelectEmployee': 'Ausgabe an', 'whoField': 'WER', 'whatSelectEmployeeTool': 'Was ausgeben',
      'whatSelectFreeTool': 'Was zurückgeben', 'whatFieldOnHands': 'WAS (In Händen)',
      'whatFieldFree': 'WAS (Freies Werkzeug)', 'confirmReturn': 'Zurückgeben', 'confirmIssue': 'Ausgeben',
      'errUserRead': 'Fehler Benutzerprofil', 'errCompanyRead': 'Fehler Firma',
      'addPerson': 'Person hinzufügen', 'approve': 'Genehmigen',
      'issueTab': 'Ausgabe', 'returnTab': 'Rückgabe',
      'searchByNameOrPhone': 'Suche nach Name oder Telefon...',
      'birthDate': 'Geburtsdatum', 'clothesSize': 'Kleidergröße', 'company': 'Firma',
      'continue': 'Weiter', 'decline': 'Ablehnen', 'done': 'Fertig',
      'firstName': 'Vorname', 'invHint': 'Inventarnummer (z.B. SKDW-001)', 'lastName': 'Nachname',
      'password': 'Passwort', 'position': 'Position', 'reports': 'Berichte', 'welcome': 'Willkommen',
      'email': 'E-Mail', 'employee': 'Team beitreten', 'employees': 'Mitarbeiter',
      'owner': 'Erstelle ein Team', 'admin': 'Admin', 'worker': 'Mitarbeiter',
      'employeeStatus': 'Mitarbeiterstatus', 'empStatusActive': 'Aktiv', 'empStatusFired': 'Entlassen',
      'toolStatus': 'Werkzeugstatus', 'toolStatusActive': 'Aktiv', 'toolStatusRepair': 'In Reparatur',
      'toolStatusDisposed': 'Ausgesondert', 'markToolActive': 'Als aktiv markieren',
      'markToolRepair': 'Zur Reparatur senden', 'markToolDisposed': 'Aussondern',
      'statusNote': 'Notiz', 'reportsByTool': 'Nach Werkzeug', 'reportsByPerson': 'Nach Mitarbeiter',
      'selectPerson': 'Mitarbeiter auswählen', 'selectPersonFirst': 'Zuerst Mitarbeiter auswählen',
      'selectToolFirst': 'Zuerst Werkzeug auswählen',
      'warehouse': 'Lager', 'where': 'Wo', 'issuedAt': 'Ausgegeben am',
      'noData': 'Keine Daten', 'noIssued': 'Nichts ausgegeben',
      'subscriptionTitle': 'Abonnement', 'subscriptionStatusLabel': 'Status',
      'subscriptionModeLabel': 'Modus', 'subscriptionValidUntilLabel': 'Gültig bis',
      'subscriptionTest': 'Testmodus', 'subscriptionLive': 'Bezahlmodus',
      'subscriptionActive': 'Aktiv', 'subscriptionInactive': 'Inaktiv',
      'buyRenew': 'Kaufen / Verlängern',
      'buyRenewSoon': 'Zahlung bald verfügbar. Bitte Support kontaktieren.',
      'admin2': 'Admin', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'billingModeLabel': 'Zahlungsmodus', 'emailLabel': 'E-Mail',
      'needPeopleFirst': 'Zuerst Personen hinzufügen', 'needToolsFirst': 'Zuerst Werkzeuge hinzufügen',
      'noFreeTool': 'Kein freies Werkzeug', 'noReturnTool': 'Kein Werkzeug zur Rückgabe',
      'peopleLimitLabel': 'Personenlimit', 'perMonth': 'Monat', 'person': 'Person',
      'planChangeOnlyOwner': 'Nur der Eigentümer kann den Plan ändern.',
      'planLabel': 'Plan', 'planSaved': 'Plan gespeichert', 'gpsNotInPlan': 'GPS-Tracking ab Plan Pro verfügbar', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'returnTitle': 'Rückgabe bestätigen', 'returnTool': 'Zurückgeben',
      'selectPlan': 'Plan auswählen', 'supportTitle': 'Support',
      'supportDesc': 'Bei Fragen zur App kontaktieren Sie uns:',
      'tariffLimitsTitle': 'Tarif und Limits', 'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Verwendet (aktiv)',
      'inactiveNotCountedNote': 'Entlassene/Inaktive zählen nicht zum Limit.',
      'versionLabel': 'Version', 'lang': 'Sprache', 'noCompany': 'Keine Firma ausgewählt',
      'noRights': 'Keine Rechte', 'join': 'Beitreten', 'name': 'Name',
      'onHandsTotal': 'Aktuell in Händen: {n} Stk.', 'toolsCountLabel': 'Werkzeuge: {n}',
      'whoLabel': 'Wer: {name}', 'reportFilterHint': 'Berichtsfilter...',
      'reportsPeople': 'Wer hat was (nach Personen)',
      'reportsTools': 'Wo ist das Werkzeug (nach Werkzeug)',
      'searchByNameOrInv': 'Suche nach Name oder Nr...',
      'searchByToolOrLastName': 'Suche nach Werkzeug oder Nachname...',
      'saveProfile': 'Profil speichern', 'setRole': 'Rolle festlegen', 'shoeSize': 'Schuhgröße',
      'switchAcc': 'Konto wechseln', 'yourInviteCode': 'Ihr Einladungscode',
      'repeatPassword': 'Passwort wiederholen', 'haveAccount': 'Bereits ein Konto?',
      'historyEmpty': 'Noch kein Verlauf', 'needAccount': 'Konto benötigt',
      'newCompanyName': 'Neuer Firmenname', 'newPassword': 'Neues Passwort',
      'noPeople': 'Noch keine Personen', 'noneIssued': 'Nichts ausgegeben',
      'noneIssued2': 'Keine Werkzeuge in Händen',
      'onlyAdmin': 'Nur Eigentümer/Admin', 'passwordsNotMatch': 'Passwörter stimmen nicht überein',
      'profileForm': 'Profilformular', 'renameCompany': 'Firma umbenennen',
      'changePlan': 'Plan ändern', 'enterEmailPass': 'E-Mail und Passwort eingeben',
      'google': 'Google', 'linkPassword': 'Passwort verknüpfen',
      'needProfile': 'Bitte Profil ausfüllen', 'needReLogin': 'Bitte erneut anmelden',
      'pendingText': 'Ihre Anfrage wartet auf Genehmigung', 'pendingTitle': 'Ausstehend',
      'sendReset': 'Reset-Link senden', 'sessionTitle': 'Sitzung', 'setPassword': 'Passwort festlegen',
      'toolNameHint': 'Name (z.B. Schleifer)', 'editProfile': 'Profil bearbeiten',
      'editMyProfile': 'Mein Profil bearbeiten', 'editCompany': 'Firma bearbeiten',
      'chooseRole': 'Rolle wählen', 'codeNotFound': 'Code nicht gefunden',
      'copyCodeHint': 'Kopieren und an Mitarbeiter senden',
      'deleteCompany': 'Firma löschen', 'deleteCompanyTitle': 'Firma löschen',
      'deleteCompanyText': 'Firma vollständig löschen',
      'inviteCode': 'Einladungscode', 'requests': 'Anfragen',
      'alreadyIn': 'Bereits in Firma', 'archivedCompany': 'Firma archiviert',
      'issueTo': 'Ausgeben', 'returnFrom': 'Zurückgeben',
      'selectModeFirst': 'Zuerst wählen: AUSGABE oder RÜCKGABE',
      'selectPersonForReturnFirst': 'Zuerst Mitarbeiter für Rückgabe auswählen',
      'noRightsIssueReturn': 'Keine Rechte zur Ausgabe/Rückgabe',
      'selectPersonAndTool': 'Mitarbeiter und Werkzeug auswählen',
      'addTool': 'Werkzeug hinzufügen', 'addEmployee': 'Mitarbeiter hinzufügen',
      'editTool': 'Werkzeug bearbeiten', 'editEmployee': 'Mitarbeiter bearbeiten',
      'deleteTool': 'Werkzeug löschen', 'deleteEmployee': 'Mitarbeiter löschen',
      'issueTitle': 'Ausgabe / Rückgabe', 'searchHistory': 'Verlauf durchsuchen...',
      'alreadyIn2': 'Bereits vorhanden', 'enterInviteCode': 'Einladungscode eingeben',
      'employeeFirstName': 'Vorname', 'employeeLastName': 'Nachname',
      'employeePosition': 'Position', 'addToolBtn': 'Hinzufügen',
      'pendingRequests': 'Beitrittsanfragen', 'noMembers': 'Keine Mitglieder',
      'editRoles': 'Rollen bearbeiten', 'share': 'Teilen',
      'chooseCompany': 'Firma auswählen', 'searchingCompany': 'Firma wird gesucht...',
      'companyDeleted': 'Firma gelöscht',
      'removedFromCompany': 'Sie wurden entfernt. Geben Sie den Code erneut ein.',
      'enterPhone': 'Telefon eingeben', 'enterPassword': 'Passwort eingeben',
      'employeeRequests': 'Mitarbeiteranfragen', 'loginPc': 'PC-Login: Passwort verknüpfen',
      'myShift': 'Meine Schicht', 'startShift': 'Schicht beginnen', 'endShift': 'Schicht beenden',
      'currentShift': 'Aktuelle Schicht', 'shiftStarted': 'Schicht gestartet!', 'shiftEnded': 'Schicht beendet!',
      'selectSite': 'Baustelle auswählen', 'noSites': 'Keine Baustellen. Administrator kontaktieren.',
      'writeReport': 'Schichtbericht', 'whatDone': 'Was wurde gemacht', 'timesheets': 'Schichtprotokoll',
      'manageSites': 'Baustellen verwalten', 'sites': 'Baustellen', 'addSite': 'Baustelle hinzufügen',
      'editSite': 'Baustelle bearbeiten', 'siteName': 'Name der Baustelle', 'siteAddress': 'Adresse',
      'siteRadius': 'Check-in Radius (m)', 'gpsInterval': 'GPS-Intervall (Min)',
      'allTime': 'Gesamte Zeit',
      'allSites': 'Alle Baustellen',
      'allPeople': 'Alle Mitarbeiter',
      'exportXlsx': 'Excel exportieren',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'Lieferschein PDF',
      'cannotSetToolStatusOnHands': 'Status kann nicht geändert werden: Werkzeug ist vergeben',
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
      'gpsPermissionDenied': 'GPS nicht verfügbar — Schicht ohne Standortprüfung gestartet',
      'gpsWarningTitle': 'Außerhalb der Baustelle',
      'gpsWarningText': 'Ihr Standort stimmt nicht mit der Baustellenadresse überein.',
      'distance': 'Entfernung',
      'startAnyway': 'Trotzdem starten',
      'shiftTypeHourly': 'Stündlich',
      'shiftTypeAccord': 'Festpreis',
      'chooseShiftType': 'Schichttyp',
      'shiftType': 'Arbeitstyp',
      'reportRequired': 'Bericht ausfüllen — was wurde gemacht',
      'viewSites': 'Alle Baustellen',
      'navigateTo': 'Navigation',
      'linkUser': 'Benutzer verknüpfen',
      'linkedUser': 'Verknüpft mit',
      'unlinkUser': 'Verknüpfung lösen',
      'selectUserToLink': 'Benutzer auswählen',
      'notLinked': 'Konto ist nicht mit einem Profil verknüpft. Administrator kontaktieren.',
      'personTypePerson': 'Person',
      'personTypeObject': 'Objekt',
      'noObjects': 'Noch keine Objekte. + drücken',
      'objectCompleted': 'Abgeschlossen',
      'markObjectCompleted': 'Als abgeschlossen markieren',
      'personTab': 'Personen',
      'objectTab': 'Objekte',
      'cannotCompleteHasTools': 'Kann nicht abschließen: {n} Werkzeuge am Objekt',
      'cannotFireHasTools': 'Kann nicht entlassen: Mitarbeiter hat {n} Werkzeuge',
      'addObject': 'Objekt hinzufügen',
      'shiftReminder10hTitle': 'Schicht dauert 10 Stunden',
      'shiftReminder10hBody': 'Schicht ist seit über 10 Stunden aktiv. Nicht vergessen zu schließen.',
      'shiftReminder12hTitle': '⚠️ Schicht 12 Stunden!',
      'shiftReminder12hBody': 'Warnung: Schicht läuft seit über 12 Stunden. Schicht schließen.',
      'offlineBanner': 'Keine Verbindung • Daten aus Cache',
      'alreadyHaveActiveShift': 'Sie haben bereits eine aktive Schicht. Schließen Sie sie zuerst.',
      'forceCloseShift': 'Erzwungen schließen',
      'forceCloseShiftHint': 'Die Schicht wird jetzt geschlossen. Sie können einen Bericht hinzufügen.',
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
      'sortCountDesc': 'Große Gruppen zuerst',
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
      'logout': 'Déconnexion', 'people': 'Personnes', 'tools': 'Outils', 'tool': 'Outil',
      'deleteAccount': 'Supprimer le compte',
      'deleteAccountTitle': 'Supprimer le compte ?',
      'deleteAccountText': 'Toutes vos données seront supprimées. Cette action est irréversible.',
      'inv': 'N° inv.', 'issue': 'Émission', 'profile': 'Profil', 'chooseLang': 'Choisir la langue',
      'companyNotFound': 'Entreprise introuvable', 'noAccessCompany': 'Pas d accès à l entreprise',
      'leaveCompany': 'Quitter / autre entreprise', 'createCompany': 'Créer une équipe',
      'leaveCompanyConfirm': 'Êtes-vous sûr de vouloir quitter cette équipe ?',
      'joinCompany': 'Rejoindre', 'or': 'OU', 'companyName': 'Nom de l entreprise',
      'role': 'Rôle', 'role_owner': 'Propriétaire', 'role_admin': 'Administrateur',
      'role_foreman': 'Contremaître', 'role_employee': 'Employé',
      'save': 'Enregistrer', 'cancel': 'Annuler', 'add': 'Ajouter', 'delete': 'Supprimer',
      'noEmployees': 'Pas d employés', 'noTools': 'Pas d outils',
      'issued': 'Émis', 'returned': 'Retourné', 'history': 'Historique',
      'total': 'Total', 'pcs': 'pcs', 'loading': 'Chargement...', 'error': 'Erreur', 'ok': 'OK',
      'issueUpper': 'ÉMETTRE', 'returnUpper': 'RETOURNER', 'noName': 'Sans nom',
      'confirmReturn': 'Retourner', 'confirmIssue': 'Émettre',
      'issueTab': 'Émission', 'returnTab': 'Retour',
      'searchByNameOrPhone': 'Rechercher par nom ou téléphone...',
      'birthDate': 'Date de naissance', 'clothesSize': 'Taille', 'company': 'Entreprise',
      'continue': 'Continuer', 'done': 'Terminé', 'firstName': 'Prénom', 'lastName': 'Nom',
      'password': 'Mot de passe', 'position': 'Poste', 'reports': 'Rapports', 'welcome': 'Bienvenue',
      'email': 'E-mail', 'employee': 'Rejoindre une équipe', 'employees': 'Employés',
      'owner': 'Créer une équipe', 'admin': 'Admin', 'worker': 'Employé',
      'employeeStatus': 'Statut employé', 'empStatusActive': 'Actif', 'empStatusFired': 'Licencié',
      'toolStatus': 'Statut outil', 'toolStatusActive': 'Actif', 'toolStatusRepair': 'En réparation',
      'toolStatusDisposed': 'Mis au rebut', 'statusNote': 'Note',
      'warehouse': 'Entrepôt', 'where': 'Où', 'issuedAt': 'Émis le', 'noData': 'Pas de données',
      'subscriptionTitle': 'Abonnement', 'subscriptionActive': 'Actif', 'subscriptionInactive': 'Inactif',
      'buyRenew': 'Acheter / Renouveler', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Ajouter des personnes d abord', 'needToolsFirst': 'Ajouter des outils d abord',
      'noFreeTool': 'Pas d outil libre', 'person': 'Personne', 'returnTool': 'Retourner',
      'versionLabel': 'Version', 'lang': 'Langue', 'selectPerson': 'Sélectionner un employé',
      'onHandsTotal': 'En main: {n} pcs.', 'toolsCountLabel': 'Outils: {n}', 'whoLabel': 'Qui: {name}',
      'reportFilterHint': 'Filtre rapport...', 'reportsPeople': 'Qui a quoi (par personnes)',
      'reportsTools': 'Où est l outil (par outils)', 'searchByNameOrInv': 'Recherche par nom ou n°...',
      'noReturnTool': 'Pas d outil à retourner', 'noCompany': 'Pas d entreprise sélectionnée',
      'saveProfile': 'Enregistrer le profil', 'setRole': 'Définir le rôle', 'shoeSize': 'Pointure',
      'yourInviteCode': 'Votre code d invitation', 'repeatPassword': 'Répéter le mot de passe',
      'haveAccount': 'Déjà un compte?', 'historyEmpty': 'Pas encore d historique',
      'needAccount': 'Compte requis', 'newCompanyName': 'Nouveau nom d entreprise',
      'newPassword': 'Nouveau mot de passe', 'noPeople': 'Pas encore de personnes',
      'noneIssued': 'Rien émis', 'noneIssued2': 'Pas d outils en main',
      'onlyAdmin': 'Seulement propriétaire/admin', 'passwordsNotMatch': 'Mots de passe différents',
      'profileForm': 'Formulaire de profil', 'renameCompany': 'Renommer l entreprise',
      'changePlan': 'Changer de plan', 'planLabel': 'Plan', 'planSaved': 'Plan enregistré', 'gpsNotInPlan': 'Suivi GPS disponible à partir du plan Pro', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'Limite de personnes', 'perMonth': 'mois',
      'planChangeOnlyOwner': 'Seul le propriétaire peut changer le plan.',
      'selectPlan': 'Choisir un plan', 'supportTitle': 'Support',
      'supportDesc': 'Pour toute question, contactez-nous:',
      'tariffLimitsTitle': 'Tarif et limites', 'telegramLabel': 'Telegram',
      'usedActiveLabel': 'Utilisé (actifs)', 'inactiveNotCountedNote': 'Licenciés/inactifs non comptés.',
      'enterEmailPass': 'Entrer e-mail et mot de passe', 'google': 'Google',
      'linkPassword': 'Lier/définir le mot de passe', 'needProfile': 'Veuillez compléter le profil',
      'needReLogin': 'Reconnectez-vous', 'pendingText': 'Votre demande est en attente',
      'pendingTitle': 'En attente', 'sendReset': 'Envoyer le lien', 'sessionTitle': 'Session',
      'setPassword': 'Définir le mot de passe', 'toolNameHint': 'Nom (ex. Meuleuse)',
      'editProfile': 'Modifier le profil', 'editMyProfile': 'Modifier mon profil',
      'editCompany': 'Modifier l entreprise', 'chooseRole': 'Choisir un rôle',
      'codeNotFound': 'Code introuvable', 'copyCodeHint': 'Copier et envoyer à l employé',
      'deleteCompany': 'Supprimer l entreprise', 'inviteCode': 'Code d invitation',
      'requests': 'Demandes', 'approve': 'Approuver', 'addPerson': 'Ajouter une personne',
      'decline': 'Refuser', 'noIssued': 'Rien émis',
      'selectToolFirst': 'Sélectionner d abord un outil',
      'selectPersonFirst': 'Sélectionner d abord un employé',
      'reportsByTool': 'Par outil', 'reportsByPerson': 'Par employé',
      'markToolActive': 'Marquer comme actif', 'markToolRepair': 'Envoyer en réparation',
      'markToolDisposed': 'Mettre au rebut', 'alreadyIn': 'Déjà dans l entreprise',
      'archivedCompany': 'Entreprise archivée', 'noCompany2': 'Pas d entreprise',
      'subscriptionStatusLabel': 'Statut', 'subscriptionValidUntilLabel': 'Valide jusqu au',
      'subscriptionTest': 'Mode test', 'subscriptionLive': 'Mode payant',
      'buyRenewSoon': 'Paiement bientôt disponible. Contacter le support.',
      'billingModeLabel': 'Mode de paiement', 'emailLabel': 'E-mail',
      'name': 'Nom', 'join': 'Rejoindre', 'noRights': 'Pas de droits',
      'returnTitle': 'Confirmer le retour', 'switchAcc': 'Changer de compte',
      'addTool': 'Ajouter un outil', 'addEmployee': 'Ajouter un employé',
      'issueTo': 'Émettre à', 'returnFrom': 'Retourner de',
      'searchByToolOrLastName': 'Recherche par outil ou nom...',
      'myShift': 'Mon quart', 'startShift': 'Commencer le quart', 'endShift': 'Terminer le quart',
      'currentShift': 'Quart en cours', 'shiftStarted': 'Quart démarré!', 'shiftEnded': 'Quart terminé!',
      'selectSite': 'Sélectionner le site', 'noSites': 'Aucun site. Contacter l\'administrateur.',
      'writeReport': 'Rapport de quart', 'whatDone': 'Ce qui a été fait', 'timesheets': 'Feuilles de temps',
      'manageSites': 'Gérer les sites', 'sites': 'Sites', 'addSite': 'Ajouter un site',
      'editSite': 'Modifier le site', 'siteName': 'Nom du site', 'siteAddress': 'Adresse',
      'siteRadius': 'Rayon d\'enregistrement (m)', 'gpsInterval': 'Intervalle GPS (min)',
      'allTime': 'Toute la période',
      'allSites': 'Tous les sites',
      'allPeople': 'Tous les employés',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Acte PDF',
      'nakladnayaPdf': 'Bon de livraison PDF',
      'gpsTrack': 'Trace GPS',
      'noGpsData': 'Pas de données GPS',
      'shiftActive': 'Quart actif',
      'shiftStart': 'Début',
      'shiftEnd': 'Fin',
      'totalHours': 'Total heures',
      'shiftsCount': 'Quarts',
      'workReport': 'Rapport',
      'myTimesheets': 'Mes quarts',
      'allTimesheets': 'Tous les quarts',
      'gpsPermissionDenied': 'GPS indisponible — quart démarré sans vérification de localisation',
      'gpsWarningTitle': 'Hors de la zone du site',
      'gpsWarningText': 'Votre position ne correspond pas à l\'adresse du site.',
      'distance': 'Distance',
      'startAnyway': 'Démarrer quand même',
      'shiftTypeHourly': 'Horaire',
      'shiftTypeAccord': 'Prix fixe',
      'chooseShiftType': 'Type de quart',
      'shiftType': 'Type de travail',
      'reportRequired': 'Remplir le rapport — ce qui a été fait',
      'viewSites': 'Tous les sites',
      'navigateTo': 'Itinéraire',
      'linkUser': 'Lier l\'utilisateur',
      'linkedUser': 'Lié à',
      'unlinkUser': 'Délier',
      'selectUserToLink': 'Sélectionner l\'utilisateur',
      'notLinked': 'Compte non lié à un profil. Contacter l\'administrateur.',
      'personTypePerson': 'Personne',
      'personTypeObject': 'Objet',
      'noObjects': 'Pas encore d\'objets. Appuyer sur +',
      'objectCompleted': 'Terminé',
      'markObjectCompleted': 'Marquer comme terminé',
      'personTab': 'Personnes',
      'objectTab': 'Objets',
      'cannotCompleteHasTools': 'Impossible de terminer : {n} outils sur l\'objet',
      'cannotFireHasTools': 'Impossible de licencier : l\'employé a {n} outils',
      'addObject': 'Ajouter un objet',
      'shiftReminder10hTitle': 'Le quart dure 10 heures',
      'shiftReminder10hBody': 'Le quart est actif depuis plus de 10 heures. N\'oubliez pas de le fermer.',
      'shiftReminder12hTitle': '⚠️ Quart 12 heures !',
      'shiftReminder12hBody': 'Attention : le quart dure depuis plus de 12 heures. Fermez le quart.',
      'offlineBanner': 'Pas de connexion • données du cache',
      'alreadyHaveActiveShift': 'Vous avez déjà un quart actif. Fermez-le avant d\'en commencer un nouveau.',
      'forceCloseShift': 'Forcer la fermeture',
      'forceCloseShiftHint': 'Le quart sera fermé maintenant. Vous pouvez ajouter un rapport.',
      'shiftClosed': 'Quart fermé.',
      'archive': 'Archive',
      'noArchive': 'L\'archive est vide',
      'notifications': 'Notifications',
      'noNotifications': 'Pas de nouvelles notifications',
      'newMemberRequest': 'Nouvelle demande d\'adhésion',
      'markAllRead': 'Tout marquer comme lu',
      'copyTool': 'Copier',
      'toolCopied': 'Outil copié',
      'sortNameAZ': 'Nom A-Z',
      'sortCountDesc': 'Grands groupes d\'abord',
      'sortDateDesc': 'Les plus récents d\'abord',
      'darkTheme': 'Thème sombre',
      'lightTheme': 'Thème clair',
      'systemTheme': 'Thème système',
      'printQr': 'Imprimer QR',
      'saveAsPng': 'Enregistrer PNG',
      'thermalLabel': 'Étiquette thermique',
      'printAllQr': 'Tous les QR sur feuille',
      'noResults': 'Aucun résultat',
    },

    AppLang.es: {
      'appTitle': 'ToolKeeper', 'login': 'Iniciar sesión', 'register': 'Registrarse', 'enter': 'Entrar',
      'logout': 'Cerrar sesión', 'people': 'Personas', 'tools': 'Herramientas', 'tool': 'Herramienta',
      'deleteAccount': 'Eliminar cuenta',
      'deleteAccountTitle': '¿Eliminar cuenta?',
      'deleteAccountText': 'Todos sus datos serán eliminados. Esta acción no se puede deshacer.',
      'inv': 'N° inv.', 'issue': 'Entrega', 'profile': 'Perfil', 'chooseLang': 'Elegir idioma',
      'companyNotFound': 'Empresa no encontrada', 'noAccessCompany': 'Sin acceso a la empresa',
      'leaveCompany': 'Salir / elegir otra empresa', 'createCompany': 'Crear equipo',
      'leaveCompanyConfirm': '¿Está seguro de que desea salir de este equipo?',
      'joinCompany': 'Unirse', 'or': 'O', 'companyName': 'Nombre de empresa',
      'role': 'Rol', 'role_owner': 'Propietario', 'role_admin': 'Administrador',
      'role_foreman': 'Capataz', 'role_employee': 'Empleado',
      'save': 'Guardar', 'cancel': 'Cancelar', 'add': 'Agregar', 'delete': 'Eliminar',
      'noEmployees': 'Sin empleados', 'noTools': 'Sin herramientas',
      'issued': 'Entregado', 'returned': 'Devuelto', 'history': 'Historial',
      'total': 'Total', 'pcs': 'uds.', 'loading': 'Cargando...', 'error': 'Error', 'ok': 'OK',
      'issueUpper': 'ENTREGAR', 'returnUpper': 'DEVOLVER', 'noName': 'Sin nombre',
      'confirmReturn': 'Devolver', 'confirmIssue': 'Entregar',
      'issueTab': 'Entrega', 'returnTab': 'Devolución',
      'searchByNameOrPhone': 'Buscar por nombre o teléfono...',
      'birthDate': 'Fecha de nacimiento', 'clothesSize': 'Talla de ropa', 'company': 'Empresa',
      'continue': 'Continuar', 'done': 'Listo', 'firstName': 'Nombre', 'lastName': 'Apellido',
      'password': 'Contraseña', 'position': 'Cargo', 'reports': 'Informes', 'welcome': 'Bienvenido',
      'email': 'Correo electrónico', 'employee': 'Unirse al equipo', 'employees': 'Empleados',
      'owner': 'Crear equipo', 'admin': 'Admin', 'worker': 'Empleado',
      'employeeStatus': 'Estado del empleado', 'empStatusActive': 'Activo', 'empStatusFired': 'Despedido',
      'toolStatus': 'Estado de herramienta', 'toolStatusActive': 'Activo', 'toolStatusRepair': 'En reparación',
      'toolStatusDisposed': 'Dado de baja', 'statusNote': 'Nota',
      'warehouse': 'Almacén', 'where': 'Dónde', 'issuedAt': 'Entregado', 'noData': 'Sin datos',
      'subscriptionTitle': 'Suscripción', 'subscriptionActive': 'Activa', 'subscriptionInactive': 'Inactiva',
      'buyRenew': 'Comprar / Renovar', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Agregar personas primero', 'needToolsFirst': 'Agregar herramientas primero',
      'noFreeTool': 'Sin herramienta libre', 'person': 'Persona', 'returnTool': 'Devolver',
      'versionLabel': 'Versión', 'lang': 'Idioma', 'selectPerson': 'Seleccionar empleado',
      'onHandsTotal': 'En mano: {n} uds.', 'toolsCountLabel': 'Herramientas: {n}', 'whoLabel': 'Quién: {name}',
      'noReturnTool': 'Sin herramienta para devolver', 'noCompany': 'Sin empresa seleccionada',
      'reportFilterHint': 'Filtro...', 'reportsPeople': 'Quién tiene qué (por personas)',
      'reportsTools': 'Dónde está la herramienta', 'searchByNameOrInv': 'Buscar por nombre o n°...',
      'saveProfile': 'Guardar perfil', 'setRole': 'Establecer rol', 'shoeSize': 'Talla de zapato',
      'yourInviteCode': 'Su código de invitación', 'repeatPassword': 'Repetir contraseña',
      'haveAccount': 'Ya tiene cuenta?', 'historyEmpty': 'Sin historial aún',
      'newPassword': 'Nueva contraseña', 'noPeople': 'Sin personas aún', 'noneIssued': 'Nada entregado',
      'noneIssued2': 'Sin herramientas en mano', 'onlyAdmin': 'Solo propietario/admin',
      'passwordsNotMatch': 'Las contraseñas no coinciden',
      'profileForm': 'Formulario de perfil', 'changePlan': 'Cambiar plan',
      'planLabel': 'Plan', 'planSaved': 'Plan guardado', 'gpsNotInPlan': 'Seguimiento GPS disponible desde el plan Pro', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —', 'peopleLimitLabel': 'Límite de personas',
      'perMonth': 'mes', 'planChangeOnlyOwner': 'Solo el propietario puede cambiar el plan.',
      'selectPlan': 'Elegir plan', 'supportTitle': 'Soporte',
      'supportDesc': 'Para preguntas, contáctenos:', 'tariffLimitsTitle': 'Tarifa y límites',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Usado (activos)',
      'inactiveNotCountedNote': 'Despedidos/inactivos no cuentan en el límite.',
      'enterEmailPass': 'Ingresar correo y contraseña', 'google': 'Google',
      'linkPassword': 'Vincular/establecer contraseña', 'needProfile': 'Complete el perfil',
      'needReLogin': 'Inicie sesión nuevamente', 'pendingText': 'Su solicitud espera aprobación',
      'pendingTitle': 'Pendiente', 'sendReset': 'Enviar enlace', 'sessionTitle': 'Sesión',
      'setPassword': 'Establecer contraseña', 'toolNameHint': 'Nombre (ej. Amoladora)',
      'editProfile': 'Editar perfil', 'editMyProfile': 'Editar mi perfil',
      'editCompany': 'Editar empresa', 'chooseRole': 'Elegir rol',
      'codeNotFound': 'Código no encontrado', 'copyCodeHint': 'Copiar y enviar al empleado',
      'deleteCompany': 'Eliminar empresa', 'inviteCode': 'Código de invitación',
      'requests': 'Solicitudes', 'approve': 'Aprobar', 'addPerson': 'Agregar persona',
      'decline': 'Rechazar', 'noIssued': 'Nada entregado',
      'selectToolFirst': 'Primero seleccione herramienta',
      'selectPersonFirst': 'Primero seleccione empleado',
      'reportsByTool': 'Por herramienta', 'reportsByPerson': 'Por empleado',
      'markToolActive': 'Marcar como activo', 'markToolRepair': 'Enviar a reparación',
      'markToolDisposed': 'Dar de baja', 'alreadyIn': 'Ya en empresa',
      'archivedCompany': 'Empresa archivada',
      'subscriptionStatusLabel': 'Estado', 'subscriptionValidUntilLabel': 'Válida hasta',
      'subscriptionTest': 'Modo prueba', 'subscriptionLive': 'Modo pago',
      'buyRenewSoon': 'Pago pronto disponible. Contactar soporte.',
      'billingModeLabel': 'Modo de pago', 'emailLabel': 'Correo',
      'name': 'Nombre', 'join': 'Unirse', 'noRights': 'Sin derechos',
      'returnTitle': 'Confirmar devolución', 'needAccount': 'Necesita cuenta',
      'newCompanyName': 'Nuevo nombre de empresa', 'renameCompany': 'Renombrar empresa',
      'addTool': 'Agregar herramienta', 'addEmployee': 'Agregar empleado',
      'searchByToolOrLastName': 'Buscar por herramienta o apellido...',
      'switchAcc': 'Cambiar cuenta',
      'myShift': 'Mi turno', 'startShift': 'Iniciar turno', 'endShift': 'Terminar turno',
      'currentShift': 'Turno actual', 'shiftStarted': '¡Turno iniciado!', 'shiftEnded': '¡Turno terminado!',
      'selectSite': 'Seleccionar sitio', 'noSites': 'Sin sitios. Contacte al administrador.',
      'writeReport': 'Informe del turno', 'whatDone': 'Qué se hizo', 'timesheets': 'Registro de turnos',
      'manageSites': 'Gestionar sitios', 'sites': 'Sitios', 'addSite': 'Agregar sitio',
      'editSite': 'Editar sitio', 'siteName': 'Nombre del sitio', 'siteAddress': 'Dirección',
      'siteRadius': 'Radio de entrada (m)', 'gpsInterval': 'Intervalo GPS (min)',
      'allTime': 'Todo el período',
      'allSites': 'Todos los sitios',
      'allPeople': 'Todos los empleados',
      'exportPdf': 'Exportar PDF',
      'exportXlsx': 'Exportar Excel',
      'actPdf': 'Acta PDF',
      'nakladnayaPdf': 'Albarán PDF',
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
      'gpsPermissionDenied': 'GPS no disponible — turno iniciado sin verificación de ubicación',
      'gpsWarningTitle': 'Fuera de la zona del sitio',
      'gpsWarningText': 'Su ubicación no coincide con la dirección del sitio.',
      'distance': 'Distancia',
      'startAnyway': 'Iniciar de todas formas',
      'shiftTypeHourly': 'Por horas',
      'shiftTypeAccord': 'Precio fijo',
      'chooseShiftType': 'Tipo de turno',
      'shiftType': 'Tipo de trabajo',
      'reportRequired': 'Completar el informe — qué se hizo',
      'viewSites': 'Todos los sitios',
      'navigateTo': 'Navegar',
      'linkUser': 'Vincular usuario',
      'linkedUser': 'Vinculado a',
      'unlinkUser': 'Desvincular',
      'selectUserToLink': 'Seleccionar usuario',
      'notLinked': 'Cuenta no vinculada a un perfil. Contacte al administrador.',
      'personTypePerson': 'Persona',
      'personTypeObject': 'Objeto',
      'noObjects': 'Aún no hay objetos. Pulse +',
      'objectCompleted': 'Completado',
      'markObjectCompleted': 'Marcar como completado',
      'personTab': 'Personas',
      'objectTab': 'Objetos',
      'cannotCompleteHasTools': 'No se puede completar: {n} herramientas en el objeto',
      'cannotFireHasTools': 'No se puede despedir: el empleado tiene {n} herramientas',
      'addObject': 'Agregar objeto',
      'shiftReminder10hTitle': 'El turno dura 10 horas',
      'shiftReminder10hBody': 'El turno está activo más de 10 horas. No olvide cerrarlo.',
      'shiftReminder12hTitle': '⚠️ ¡Turno 12 horas!',
      'shiftReminder12hBody': 'Advertencia: el turno lleva más de 12 horas. Cierre el turno.',
      'offlineBanner': 'Sin conexión • datos del caché',
      'alreadyHaveActiveShift': 'Ya tiene un turno activo. Ciérrelo antes de iniciar uno nuevo.',
      'forceCloseShift': 'Forzar cierre',
      'forceCloseShiftHint': 'El turno se cerrará ahora. Puede agregar un informe.',
      'shiftClosed': 'Turno cerrado.',
      'archive': 'Archivo',
      'noArchive': 'El archivo está vacío',
      'notifications': 'Notificaciones',
      'noNotifications': 'No hay nuevas notificaciones',
      'newMemberRequest': 'Nueva solicitud de unión',
      'markAllRead': 'Marcar todo como leído',
      'copyTool': 'Copiar',
      'toolCopied': 'Herramienta copiada',
      'sortNameAZ': 'Nombre A-Z',
      'sortCountDesc': 'Grupos grandes primero',
      'sortDateDesc': 'Más recientes primero',
      'darkTheme': 'Tema oscuro',
      'lightTheme': 'Tema claro',
      'systemTheme': 'Tema del sistema',
      'printQr': 'Imprimir QR',
      'saveAsPng': 'Guardar PNG',
      'thermalLabel': 'Etiqueta térmica',
      'printAllQr': 'Todos los QR en hoja',
      'noResults': 'Sin resultados',
    },

    AppLang.it: {
      'appTitle': 'ToolKeeper', 'login': 'Accesso', 'register': 'Registrazione', 'enter': 'Accedi',
      'logout': 'Esci', 'people': 'Persone', 'tools': 'Strumenti', 'tool': 'Strumento',
      'deleteAccount': 'Elimina account',
      'deleteAccountTitle': 'Eliminare l’account?',
      'deleteAccountText': 'Tutti i tuoi dati verranno eliminati. Questa azione è irreversibile.',
      'inv': 'N° inv.', 'issue': 'Emissione', 'profile': 'Profilo', 'chooseLang': 'Scegli lingua',
      'companyNotFound': 'Azienda non trovata', 'noAccessCompany': 'Nessun accesso all azienda',
      'leaveCompany': 'Esci / scegli altra azienda', 'createCompany': 'Crea squadra',
      'leaveCompanyConfirm': 'Sei sicuro di voler lasciare questo team?',
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
      'email': 'Email', 'employee': 'Unisciti al team', 'employees': 'Dipendenti',
      'owner': 'Crea squadra', 'admin': 'Admin', 'worker': 'Dipendente',
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
      'reportsTools': 'Dove è lo strumento', 'searchByNameOrInv': 'Cerca per nome o n°...',
      'saveProfile': 'Salva profilo', 'setRole': 'Imposta ruolo', 'shoeSize': 'Numero scarpe',
      'yourInviteCode': 'Il tuo codice invito', 'repeatPassword': 'Ripeti password',
      'haveAccount': 'Hai già un account?', 'historyEmpty': 'Ancora nessuna cronologia',
      'newPassword': 'Nuova password', 'noPeople': 'Ancora nessuna persona',
      'noneIssued': 'Niente emesso', 'noneIssued2': 'Nessuno strumento in mano',
      'onlyAdmin': 'Solo proprietario/admin', 'passwordsNotMatch': 'Le password non corrispondono',
      'profileForm': 'Modulo profilo', 'changePlan': 'Cambia piano',
      'planLabel': 'Piano', 'planSaved': 'Piano salvato', 'gpsNotInPlan': 'Tracciamento GPS disponibile dal piano Pro in su', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —', 'peopleLimitLabel': 'Limite persone',
      'perMonth': 'mese', 'planChangeOnlyOwner': 'Solo il proprietario può cambiare il piano.',
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
      'markToolDisposed': 'Dismetti', 'alreadyIn': 'Già in azienda',
      'archivedCompany': 'Azienda archiviata',
      'subscriptionStatusLabel': 'Stato', 'subscriptionValidUntilLabel': 'Valido fino al',
      'subscriptionTest': 'Modalità test', 'subscriptionLive': 'Modalità a pagamento',
      'buyRenewSoon': 'Pagamento presto disponibile. Contatta il supporto.',
      'billingModeLabel': 'Modalità pagamento', 'emailLabel': 'Email',
      'name': 'Nome', 'join': 'Unisciti', 'noRights': 'Nessun diritto',
      'returnTitle': 'Conferma reso', 'needAccount': 'Account necessario',
      'newCompanyName': 'Nuovo nome azienda', 'renameCompany': 'Rinomina azienda',
      'addTool': 'Aggiungi strumento', 'addEmployee': 'Aggiungi dipendente',
      'searchByToolOrLastName': 'Cerca per strumento o cognome...',
      'switchAcc': 'Cambia account',
      'myShift': 'Il mio turno', 'startShift': 'Inizia turno', 'endShift': 'Termina turno',
      'currentShift': 'Turno attuale', 'shiftStarted': 'Turno iniziato!', 'shiftEnded': 'Turno terminato!',
      'selectSite': 'Seleziona cantiere', 'noSites': 'Nessun cantiere. Contatta l\'amministratore.',
      'writeReport': 'Rapporto turno', 'whatDone': 'Cosa è stato fatto', 'timesheets': 'Registro turni',
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
      'gpsPermissionDenied': 'GPS non disponibile — turno iniziato senza verifica posizione',
      'gpsWarningTitle': 'Fuori dalla zona del sito',
      'gpsWarningText': 'La tua posizione non corrisponde all\'indirizzo del sito.',
      'distance': 'Distanza',
      'startAnyway': 'Inizia comunque',
      'shiftTypeHourly': 'A ore',
      'shiftTypeAccord': 'Prezzo fisso',
      'chooseShiftType': 'Tipo di turno',
      'shiftType': 'Tipo di lavoro',
      'reportRequired': 'Compila il rapporto — cosa è stato fatto',
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
      'shiftReminder10hBody': 'Il turno è attivo da oltre 10 ore. Non dimenticare di chiuderlo.',
      'shiftReminder12hTitle': '⚠️ Turno 12 ore!',
      'shiftReminder12hBody': 'Attenzione: il turno è in corso da oltre 12 ore. Chiudi il turno.',
      'offlineBanner': 'Nessuna connessione • dati dalla cache',
      'alreadyHaveActiveShift': 'Hai già un turno attivo. Chiudilo prima di iniziarne uno nuovo.',
      'forceCloseShift': 'Forza chiusura',
      'forceCloseShiftHint': 'Il turno verrà chiuso ora. Puoi aggiungere un rapporto.',
      'shiftClosed': 'Turno chiuso.',
      'archive': 'Archivio',
      'noArchive': 'L\'archivio è vuoto',
      'notifications': 'Notifiche',
      'noNotifications': 'Nessuna nuova notifica',
      'newMemberRequest': 'Nuova richiesta di adesione',
      'markAllRead': 'Segna tutto come letto',
      'copyTool': 'Copia',
      'toolCopied': 'Strumento copiato',
      'sortNameAZ': 'Nome A-Z',
      'sortCountDesc': 'Gruppi grandi prima',
      'sortDateDesc': 'Più recenti prima',
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
      'deleteAccount': 'Excluir conta',
      'deleteAccountTitle': 'Excluir conta?',
      'deleteAccountText': 'Todos os seus dados serão excluídos. Esta ação não pode ser desfeita.',
      'inv': 'N° inv.', 'issue': 'Emissão', 'profile': 'Perfil', 'chooseLang': 'Escolher idioma',
      'companyNotFound': 'Empresa não encontrada', 'noAccessCompany': 'Sem acesso à empresa',
      'leaveCompany': 'Sair / escolher outra empresa', 'createCompany': 'Criar equipe',
      'leaveCompanyConfirm': 'Tem certeza que deseja sair desta equipe?',
      'joinCompany': 'Entrar', 'or': 'OU', 'companyName': 'Nome da empresa',
      'role': 'Função', 'role_owner': 'Proprietário', 'role_admin': 'Administrador',
      'role_foreman': 'Mestre de obras', 'role_employee': 'Funcionário',
      'save': 'Salvar', 'cancel': 'Cancelar', 'add': 'Adicionar', 'delete': 'Excluir',
      'noEmployees': 'Sem funcionários', 'noTools': 'Sem ferramentas',
      'issued': 'Emitido', 'returned': 'Devolvido', 'history': 'Histórico',
      'total': 'Total', 'pcs': 'pcs.', 'loading': 'Carregando...', 'error': 'Erro', 'ok': 'OK',
      'issueUpper': 'EMITIR', 'returnUpper': 'DEVOLVER', 'noName': 'Sem nome',
      'confirmReturn': 'Devolver', 'confirmIssue': 'Emitir',
      'issueTab': 'Emissão', 'returnTab': 'Devolução',
      'searchByNameOrPhone': 'Buscar por nome ou telefone...',
      'birthDate': 'Data de nascimento', 'clothesSize': 'Tamanho de roupa', 'company': 'Empresa',
      'continue': 'Continuar', 'done': 'Pronto', 'firstName': 'Nome', 'lastName': 'Sobrenome',
      'password': 'Senha', 'position': 'Cargo', 'reports': 'Relatórios', 'welcome': 'Bem-vindo',
      'email': 'E-mail', 'employee': 'Entrar na equipe', 'employees': 'Funcionários',
      'owner': 'Criar equipe', 'admin': 'Admin', 'worker': 'Funcionário',
      'employeeStatus': 'Status do funcionário', 'empStatusActive': 'Ativo', 'empStatusFired': 'Demitido',
      'toolStatus': 'Status da ferramenta', 'toolStatusActive': 'Ativo', 'toolStatusRepair': 'Em reparo',
      'toolStatusDisposed': 'Descartado', 'statusNote': 'Nota',
      'warehouse': 'Armazém', 'where': 'Onde', 'issuedAt': 'Emitido em', 'noData': 'Sem dados',
      'subscriptionTitle': 'Assinatura', 'subscriptionActive': 'Ativa', 'subscriptionInactive': 'Inativa',
      'buyRenew': 'Comprar / Renovar', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Adicionar pessoas primeiro', 'needToolsFirst': 'Adicionar ferramentas primeiro',
      'noFreeTool': 'Sem ferramenta livre', 'person': 'Pessoa', 'returnTool': 'Devolver',
      'versionLabel': 'Versão', 'lang': 'Idioma', 'selectPerson': 'Selecionar funcionário',
      'onHandsTotal': 'Em mãos: {n} pcs.', 'toolsCountLabel': 'Ferramentas: {n}', 'whoLabel': 'Quem: {name}',
      'noReturnTool': 'Sem ferramenta para devolver', 'noCompany': 'Sem empresa selecionada',
      'reportFilterHint': 'Filtro...', 'reportsPeople': 'Quem tem o quê (por pessoas)',
      'reportsTools': 'Onde está a ferramenta', 'searchByNameOrInv': 'Buscar por nome ou n°...',
      'saveProfile': 'Salvar perfil', 'setRole': 'Definir função', 'shoeSize': 'Número do sapato',
      'yourInviteCode': 'Seu código de convite', 'repeatPassword': 'Repetir senha',
      'haveAccount': 'Já tem conta?', 'historyEmpty': 'Ainda sem histórico',
      'newPassword': 'Nova senha', 'noPeople': 'Ainda sem pessoas',
      'noneIssued': 'Nada emitido', 'noneIssued2': 'Sem ferramentas em mãos',
      'onlyAdmin': 'Somente proprietário/admin', 'passwordsNotMatch': 'As senhas não correspondem',
      'profileForm': 'Formulário de perfil', 'changePlan': 'Alterar plano',
      'planLabel': 'Plano', 'planSaved': 'Plano salvo', 'gpsNotInPlan': 'Rastreamento GPS disponível a partir do plano Pro', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —', 'peopleLimitLabel': 'Limite de pessoas',
      'perMonth': 'mês', 'planChangeOnlyOwner': 'Somente o proprietário pode alterar o plano.',
      'selectPlan': 'Escolher plano', 'supportTitle': 'Suporte',
      'supportDesc': 'Para dúvidas, entre em contato:', 'tariffLimitsTitle': 'Tarifa e limites',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Usado (ativos)',
      'inactiveNotCountedNote': 'Demitidos/inativos não contam no limite.',
      'enterEmailPass': 'Digite e-mail e senha', 'google': 'Google',
      'linkPassword': 'Vincular/definir senha', 'needProfile': 'Complete o perfil',
      'needReLogin': 'Faça login novamente', 'pendingText': 'Solicitação aguarda aprovação',
      'pendingTitle': 'Pendente', 'sendReset': 'Enviar link', 'sessionTitle': 'Sessão',
      'setPassword': 'Definir senha', 'toolNameHint': 'Nome (ex. Esmerilhadeira)',
      'editProfile': 'Editar perfil', 'editMyProfile': 'Editar meu perfil',
      'editCompany': 'Editar empresa', 'chooseRole': 'Escolher função',
      'codeNotFound': 'Código não encontrado', 'copyCodeHint': 'Copiar e enviar ao funcionário',
      'deleteCompany': 'Excluir empresa', 'inviteCode': 'Código de convite',
      'requests': 'Solicitações', 'approve': 'Aprovar', 'addPerson': 'Adicionar pessoa',
      'decline': 'Recusar', 'noIssued': 'Nada emitido',
      'selectToolFirst': 'Primeiro selecione ferramenta',
      'selectPersonFirst': 'Primeiro selecione funcionário',
      'reportsByTool': 'Por ferramenta', 'reportsByPerson': 'Por funcionário',
      'markToolActive': 'Marcar como ativo', 'markToolRepair': 'Enviar para reparo',
      'markToolDisposed': 'Descartar', 'alreadyIn': 'Já na empresa',
      'archivedCompany': 'Empresa arquivada',
      'subscriptionStatusLabel': 'Status', 'subscriptionValidUntilLabel': 'Válida até',
      'subscriptionTest': 'Modo teste', 'subscriptionLive': 'Modo pago',
      'buyRenewSoon': 'Pagamento em breve. Contate o suporte.',
      'billingModeLabel': 'Modo de pagamento', 'emailLabel': 'E-mail',
      'name': 'Nome', 'join': 'Entrar', 'noRights': 'Sem direitos',
      'returnTitle': 'Confirmar devolução', 'needAccount': 'Conta necessária',
      'newCompanyName': 'Novo nome da empresa', 'renameCompany': 'Renomear empresa',
      'addTool': 'Adicionar ferramenta', 'addEmployee': 'Adicionar funcionário',
      'searchByToolOrLastName': 'Buscar por ferramenta ou sobrenome...',
      'switchAcc': 'Trocar conta',
      'myShift': 'Meu turno', 'startShift': 'Iniciar turno', 'endShift': 'Encerrar turno',
      'currentShift': 'Turno atual', 'shiftStarted': 'Turno iniciado!', 'shiftEnded': 'Turno encerrado!',
      'selectSite': 'Selecionar obra', 'noSites': 'Sem obras. Contate o administrador.',
      'writeReport': 'Relatório do turno', 'whatDone': 'O que foi feito', 'timesheets': 'Registro de turnos',
      'manageSites': 'Gerenciar obras', 'sites': 'Obras', 'addSite': 'Adicionar obra',
      'editSite': 'Editar obra', 'siteName': 'Nome da obra', 'siteAddress': 'Endereço',
      'siteRadius': 'Raio de check-in (m)', 'gpsInterval': 'Intervalo GPS (min)',
      'allTime': 'Todo o período',
      'allSites': 'Todas as obras',
      'allPeople': 'Todos os funcionários',
      'exportPdf': 'Exportar PDF',
      'exportXlsx': 'Exportar Excel',
      'actPdf': 'Ato PDF',
      'nakladnayaPdf': 'Guia de entrega PDF',
      'gpsTrack': 'Rastreio GPS',
      'noGpsData': 'Sem dados GPS',
      'shiftActive': 'Turno ativo',
      'shiftStart': 'Início',
      'shiftEnd': 'Fim',
      'totalHours': 'Total de horas',
      'shiftsCount': 'Turnos',
      'workReport': 'Relatório',
      'myTimesheets': 'Meus turnos',
      'allTimesheets': 'Todos os turnos',
      'gpsPermissionDenied': 'GPS indisponível — turno iniciado sem verificação de localização',
      'gpsWarningTitle': 'Fora da zona do local',
      'gpsWarningText': 'Sua localização não corresponde ao endereço do local.',
      'distance': 'Distância',
      'startAnyway': 'Iniciar mesmo assim',
      'shiftTypeHourly': 'Por hora',
      'shiftTypeAccord': 'Preço fixo',
      'chooseShiftType': 'Tipo de turno',
      'shiftType': 'Tipo de trabalho',
      'reportRequired': 'Preencha o relatório — o que foi feito',
      'viewSites': 'Todos os locais',
      'navigateTo': 'Navegar',
      'linkUser': 'Vincular usuário',
      'linkedUser': 'Vinculado a',
      'unlinkUser': 'Desvincular',
      'selectUserToLink': 'Selecionar usuário',
      'notLinked': 'Conta não vinculada a um perfil. Contate o administrador.',
      'personTypePerson': 'Pessoa',
      'personTypeObject': 'Objeto',
      'noObjects': 'Ainda sem objetos. Toque em +',
      'objectCompleted': 'Concluído',
      'markObjectCompleted': 'Marcar como concluído',
      'personTab': 'Pessoas',
      'objectTab': 'Objetos',
      'cannotCompleteHasTools': 'Não é possível concluir: {n} ferramentas no objeto',
      'cannotFireHasTools': 'Não é possível demitir: funcionário tem {n} ferramentas',
      'addObject': 'Adicionar objeto',
      'shiftReminder10hTitle': 'O turno dura 10 horas',
      'shiftReminder10hBody': 'O turno está ativo há mais de 10 horas. Não se esqueça de fechá-lo.',
      'shiftReminder12hTitle': '⚠️ Turno 12 horas!',
      'shiftReminder12hBody': 'Atenção: o turno está em andamento há mais de 12 horas. Feche o turno.',
      'offlineBanner': 'Sem conexão • dados do cache',
      'alreadyHaveActiveShift': 'Você já tem um turno ativo. Feche-o antes de iniciar um novo.',
      'forceCloseShift': 'Forçar fechamento',
      'forceCloseShiftHint': 'O turno será fechado agora. Você pode adicionar um relatório.',
      'shiftClosed': 'Turno encerrado.',
      'archive': 'Arquivo',
      'noArchive': 'O arquivo está vazio',
      'notifications': 'Notificações',
      'noNotifications': 'Sem novas notificações',
      'newMemberRequest': 'Nova solicitação de adesão',
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
      'thermalLabel': 'Etiqueta térmica',
      'printAllQr': 'Todos os QR na folha',
      'noResults': 'Sem resultados',
    },

    AppLang.cs: {
      'appTitle': 'ToolKeeper', 'login': 'Přihlášení', 'register': 'Registrace', 'enter': 'Přihlásit se',
      'logout': 'Odhlásit', 'people': 'Lidé', 'tools': 'Nástroje', 'tool': 'Nástroj',
      'deleteAccount': 'Smazat účet',
      'deleteAccountTitle': 'Smazat účet?',
      'deleteAccountText': 'Všechna vaše data budou smazána. Tuto akci nelze vrátit.',
      'inv': 'Inv. č.', 'issue': 'Výdej', 'profile': 'Profil', 'chooseLang': 'Vyberte jazyk',
      'companyNotFound': 'Firma nenalezena', 'noAccessCompany': 'Žádný přístup k firmě',
      'leaveCompany': 'Opustit / vybrat jinou firmu', 'createCompany': 'Vytvořit tým',
      'leaveCompanyConfirm': 'Opravdu chcete opustit tento tým?',
      'joinCompany': 'Připojit se', 'or': 'NEBO', 'companyName': 'Název firmy',
      'role': 'Role', 'role_owner': 'Majitel', 'role_admin': 'Administrátor',
      'role_foreman': 'Vedoucí', 'role_employee': 'Zaměstnanec',
      'save': 'Uložit', 'cancel': 'Zrušit', 'add': 'Přidat', 'delete': 'Smazat',
      'noEmployees': 'Žádní zaměstnanci', 'noTools': 'Žádné nástroje',
      'issued': 'Vydáno', 'returned': 'Vráceno', 'history': 'Historie',
      'total': 'Celkem', 'pcs': 'ks.', 'loading': 'Načítání...', 'error': 'Chyba', 'ok': 'OK',
      'issueUpper': 'VYDAT', 'returnUpper': 'VRÁTIT', 'noName': 'Bez jména',
      'confirmReturn': 'Vrátit', 'confirmIssue': 'Vydat',
      'issueTab': 'Výdej', 'returnTab': 'Vrácení',
      'searchByNameOrPhone': 'Hledat podle jména nebo telefonu...',
      'birthDate': 'Datum narození', 'clothesSize': 'Velikost oblečení', 'company': 'Firma',
      'continue': 'Pokračovat', 'done': 'Hotovo', 'firstName': 'Jméno', 'lastName': 'Příjmení',
      'password': 'Heslo', 'position': 'Pozice', 'reports': 'Zprávy', 'welcome': 'Vítejte',
      'email': 'E-mail', 'employee': 'Přidat se k týmu', 'employees': 'Zaměstnanci',
      'owner': 'Vytvořit tým', 'admin': 'Admin', 'worker': 'Zaměstnanec',
      'employeeStatus': 'Stav zaměstnance', 'empStatusActive': 'Aktivní', 'empStatusFired': 'Propuštěn',
      'toolStatus': 'Stav nástroje', 'toolStatusActive': 'Aktivní', 'toolStatusRepair': 'V opravě',
      'toolStatusDisposed': 'Vyřazen', 'statusNote': 'Poznámka',
      'warehouse': 'Sklad', 'where': 'Kde', 'issuedAt': 'Vydáno', 'noData': 'Žádná data',
      'subscriptionTitle': 'Předplatné', 'subscriptionActive': 'Aktivní', 'subscriptionInactive': 'Neaktivní',
      'buyRenew': 'Koupit / Prodloužit', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Nejprve přidejte lidi', 'needToolsFirst': 'Nejprve přidejte nástroje',
      'noFreeTool': 'Žádný volný nástroj', 'person': 'Osoba', 'returnTool': 'Vrátit',
      'versionLabel': 'Verze', 'lang': 'Jazyk', 'selectPerson': 'Vyberte zaměstnance',
      'onHandsTotal': 'V rukou: {n} ks.', 'toolsCountLabel': 'Nástrojů: {n}', 'whoLabel': 'U koho: {name}',
      'noReturnTool': 'Žádný nástroj k vrácení', 'noCompany': 'Žádná firma vybrána',
      'reportFilterHint': 'Filtr...', 'reportsPeople': 'Kdo má co (podle osob)',
      'reportsTools': 'Kde je nástroj', 'searchByNameOrInv': 'Hledat podle názvu nebo č...',
      'saveProfile': 'Uložit profil', 'setRole': 'Nastavit roli', 'shoeSize': 'Velikost bot',
      'yourInviteCode': 'Váš pozvánkový kód', 'repeatPassword': 'Opakovat heslo',
      'haveAccount': 'Již máte účet?', 'historyEmpty': 'Zatím žádná historie',
      'newPassword': 'Nové heslo', 'noPeople': 'Zatím žádní lidé', 'noneIssued': 'Nic nevydáno',
      'noneIssued2': 'Žádné nástroje v rukou', 'onlyAdmin': 'Pouze majitel/admin',
      'passwordsNotMatch': 'Hesla se neshodují', 'profileForm': 'Formulář profilu',
      'changePlan': 'Změnit plán', 'planLabel': 'Plán', 'planSaved': 'Plán uložen', 'gpsNotInPlan': 'GPS sledování dostupné od plánu Pro a výše', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'Limit osob', 'perMonth': 'měs.',
      'planChangeOnlyOwner': 'Pouze majitel může změnit plán.',
      'selectPlan': 'Vybrat plán', 'supportTitle': 'Podpora',
      'supportDesc': 'S dotazy nás kontaktujte:', 'tariffLimitsTitle': 'Tarif a limity',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Použito (aktivní)',
      'inactiveNotCountedNote': 'Propuštění/neaktivní se nepočítají do limitu.',
      'enterEmailPass': 'Zadejte e-mail a heslo', 'google': 'Google',
      'needProfile': 'Vyplňte prosím profil', 'needReLogin': 'Přihlaste se znovu',
      'pendingText': 'Vaše žádost čeká na schválení', 'pendingTitle': 'Čeká',
      'sendReset': 'Odeslat odkaz', 'sessionTitle': 'Relace', 'setPassword': 'Nastavit heslo',
      'toolNameHint': 'Název (např. Bruska)', 'editProfile': 'Upravit profil',
      'editMyProfile': 'Upravit můj profil', 'editCompany': 'Upravit firmu',
      'chooseRole': 'Vybrat roli', 'codeNotFound': 'Kód nenalezen',
      'copyCodeHint': 'Zkopírujte a pošlete zaměstnanci', 'deleteCompany': 'Smazat firmu',
      'inviteCode': 'Pozvánkový kód', 'requests': 'Žádosti', 'approve': 'Schválit',
      'addPerson': 'Přidat osobu', 'decline': 'Odmítnout', 'noIssued': 'Nic nevydáno',
      'selectToolFirst': 'Nejprve vyberte nástroj', 'selectPersonFirst': 'Nejprve vyberte zaměstnance',
      'reportsByTool': 'Podle nástroje', 'reportsByPerson': 'Podle zaměstnance',
      'markToolActive': 'Označit jako aktivní', 'markToolRepair': 'Odeslat k opravě',
      'markToolDisposed': 'Vyřadit', 'alreadyIn': 'Již ve firmě', 'archivedCompany': 'Firma archivována',
      'subscriptionStatusLabel': 'Stav', 'subscriptionValidUntilLabel': 'Platí do',
      'subscriptionTest': 'Testovací režim', 'subscriptionLive': 'Placený režim',
      'buyRenewSoon': 'Platba brzy dostupná. Kontaktujte podporu.',
      'billingModeLabel': 'Platební režim', 'emailLabel': 'E-mail',
      'name': 'Název', 'join': 'Připojit se', 'noRights': 'Žádná práva',
      'returnTitle': 'Potvrdit vrácení', 'needAccount': 'Potřebujete účet',
      'newCompanyName': 'Nový název firmy', 'renameCompany': 'Přejmenovat firmu',
      'addTool': 'Přidat nástroj', 'addEmployee': 'Přidat zaměstnance',
      'searchByToolOrLastName': 'Hledat podle nástroje nebo příjmení...',
      'linkPassword': 'Propojit/nastavit heslo', 'switchAcc': 'Změnit účet',
      'myShift': 'Moje směna', 'startShift': 'Začít směnu', 'endShift': 'Ukončit směnu',
      'currentShift': 'Aktuální směna', 'shiftStarted': 'Směna zahájena!', 'shiftEnded': 'Směna ukončena!',
      'selectSite': 'Vybrat pracoviště', 'noSites': 'Žádná pracoviště. Kontaktujte správce.',
      'writeReport': 'Zpráva ze směny', 'whatDone': 'Co bylo uděláno', 'timesheets': 'Docházka',
      'manageSites': 'Správa pracovišť', 'sites': 'Pracoviště', 'addSite': 'Přidat pracoviště',
      'editSite': 'Upravit pracoviště', 'siteName': 'Název pracoviště', 'siteAddress': 'Adresa',
      'siteRadius': 'Rádius check-in (m)', 'gpsInterval': 'Interval GPS (min)',
      'allTime': 'Celé období',
      'allSites': 'Všechna pracoviště',
      'allPeople': 'Všichni zaměstnanci',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Akt PDF',
      'nakladnayaPdf': 'Dodací list PDF',
      'gpsTrack': 'GPS trasa',
      'noGpsData': 'Žádná GPS data',
      'shiftActive': 'Směna aktivní',
      'shiftStart': 'Začátek',
      'shiftEnd': 'Konec',
      'totalHours': 'Celkem hodin',
      'shiftsCount': 'Směny',
      'workReport': 'Zpráva',
      'myTimesheets': 'Moje směny',
      'allTimesheets': 'Všechny směny',
      'gpsPermissionDenied': 'GPS nedostupné — směna zahájena bez ověření polohy',
      'gpsWarningTitle': 'Mimo zónu pracoviště',
      'gpsWarningText': 'Vaše poloha neodpovídá adrese pracoviště.',
      'distance': 'Vzdálenost',
      'startAnyway': 'Přesto zahájit',
      'shiftTypeHourly': 'Hodinová',
      'shiftTypeAccord': 'Pevná cena',
      'chooseShiftType': 'Typ směny',
      'shiftType': 'Typ práce',
      'reportRequired': 'Vyplňte zprávu — co bylo uděláno',
      'viewSites': 'Všechna pracoviště',
      'navigateTo': 'Navigace',
      'linkUser': 'Propojit uživatele',
      'linkedUser': 'Propojeno s',
      'unlinkUser': 'Odpojit',
      'selectUserToLink': 'Vybrat uživatele',
      'notLinked': 'Účet není propojen s profilem. Kontaktujte správce.',
      'personTypePerson': 'Osoba',
      'personTypeObject': 'Objekt',
      'noObjects': 'Zatím žádné objekty. Stiskněte +',
      'objectCompleted': 'Dokončeno',
      'markObjectCompleted': 'Označit jako dokončené',
      'personTab': 'Osoby',
      'objectTab': 'Objekty',
      'cannotCompleteHasTools': 'Nelze dokončit: {n} nástrojů na objektu',
      'cannotFireHasTools': 'Nelze propustit: zaměstnanec má {n} nástrojů',
      'addObject': 'Přidat objekt',
      'shiftReminder10hTitle': 'Směna trvá 10 hodin',
      'shiftReminder10hBody': 'Směna je aktivní déle než 10 hodin. Nezapomeňte ji uzavřít.',
      'shiftReminder12hTitle': '⚠️ Směna 12 hodin!',
      'shiftReminder12hBody': 'Varování: směna probíhá déle než 12 hodin. Uzavřete směnu.',
      'offlineBanner': 'Bez připojení • data z mezipaměti',
      'alreadyHaveActiveShift': 'Již máte aktivní směnu. Uzavřete ji před zahájením nové.',
      'forceCloseShift': 'Vynutit uzavření',
      'forceCloseShiftHint': 'Směna bude nyní uzavřena. Můžete přidat zprávu.',
      'shiftClosed': 'Směna uzavřena.',
      'archive': 'Archiv',
      'noArchive': 'Archiv je prázdný',
      'notifications': 'Oznámení',
      'noNotifications': 'Žádná nová oznámení',
      'newMemberRequest': 'Nová žádost o přijetí',
      'markAllRead': 'Označit vše jako přečtené',
      'copyTool': 'Kopírovat',
      'toolCopied': 'Nástroj zkopírován',
      'sortNameAZ': 'Název A-Z',
      'sortCountDesc': 'Velké skupiny napřed',
      'sortDateDesc': 'Nejnovější napřed',
      'darkTheme': 'Tmavý motiv',
      'lightTheme': 'Světlý motiv',
      'systemTheme': 'Systémový motiv',
      'printQr': 'Tisknout QR',
      'saveAsPng': 'Uložit PNG',
      'thermalLabel': 'Tepelný štítek',
      'printAllQr': 'Všechny QR na list',
      'noResults': 'Nic nenalezeno',
    },

    AppLang.ro: {
      'appTitle': 'ToolKeeper', 'login': 'Autentificare', 'register': 'Înregistrare', 'enter': 'Conectare',
      'logout': 'Deconectare', 'people': 'Oameni', 'tools': 'Scule', 'tool': 'Sculă',
      'deleteAccount': 'Şterge cont',
      'deleteAccountTitle': 'Şterge cont?',
      'deleteAccountText': 'Toate datele dvs. vor fi śterse. Această acţiune este ireversibilă.',
      'inv': 'Nr. inv.', 'issue': 'Eliberare', 'profile': 'Profil', 'chooseLang': 'Alegeți limba',
      'companyNotFound': 'Companie negăsită', 'noAccessCompany': 'Fără acces la companie',
      'leaveCompany': 'Ieși / alege altă companie', 'createCompany': 'Creaţi echipă',
      'leaveCompanyConfirm': 'Eşti sigur că vrei să părăseşti echipa?',
      'joinCompany': 'Alăturare', 'or': 'SAU', 'companyName': 'Numele companiei',
      'role': 'Rol', 'role_owner': 'Proprietar', 'role_admin': 'Administrator',
      'role_foreman': 'Șef de echipă', 'role_employee': 'Angajat',
      'save': 'Salvare', 'cancel': 'Anulare', 'add': 'Adăugare', 'delete': 'Ștergere',
      'noEmployees': 'Niciun angajat', 'noTools': 'Nicio sculă',
      'issued': 'Eliberat', 'returned': 'Returnat', 'history': 'Istoric',
      'total': 'Total', 'pcs': 'buc.', 'loading': 'Se încarcă...', 'error': 'Eroare', 'ok': 'OK',
      'issueUpper': 'ELIBEREAZĂ', 'returnUpper': 'RETURNEAZĂ', 'noName': 'Fără nume',
      'confirmReturn': 'Returnează', 'confirmIssue': 'Eliberează',
      'issueTab': 'Eliberare', 'returnTab': 'Returnare',
      'searchByNameOrPhone': 'Caută după nume sau telefon...',
      'birthDate': 'Data nașterii', 'clothesSize': 'Mărime îmbrăcăminte', 'company': 'Companie',
      'continue': 'Continuare', 'done': 'Gata', 'firstName': 'Prenume', 'lastName': 'Nume',
      'password': 'Parolă', 'position': 'Poziție', 'reports': 'Rapoarte', 'welcome': 'Bun venit',
      'email': 'E-mail', 'employee': 'Alăturaţi-vă echipei', 'employees': 'Angajați',
      'owner': 'Creaţi echipă', 'admin': 'Admin', 'worker': 'Angajat',
      'employeeStatus': 'Stare angajat', 'empStatusActive': 'Activ', 'empStatusFired': 'Concediat',
      'toolStatus': 'Stare sculă', 'toolStatusActive': 'Activă', 'toolStatusRepair': 'În reparație',
      'toolStatusDisposed': 'Casată', 'statusNote': 'Notă',
      'warehouse': 'Depozit', 'where': 'Unde', 'issuedAt': 'Eliberat', 'noData': 'Fără date',
      'subscriptionTitle': 'Abonament', 'subscriptionActive': 'Activ', 'subscriptionInactive': 'Inactiv',
      'buyRenew': 'Cumpărare / Prelungire', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Adăugați mai întâi persoane', 'needToolsFirst': 'Adăugați mai întâi scule',
      'noFreeTool': 'Nicio sculă liberă', 'person': 'Persoană', 'returnTool': 'Returnare',
      'versionLabel': 'Versiune', 'lang': 'Limbă', 'selectPerson': 'Selectați angajatul',
      'onHandsTotal': 'În mână: {n} buc.', 'toolsCountLabel': 'Scule: {n}', 'whoLabel': 'La cine: {name}',
      'noReturnTool': 'Nicio sculă de returnat', 'noCompany': 'Nicio companie selectată',
      'reportFilterHint': 'Filtre...', 'reportsPeople': 'Cine are ce (pe persoane)',
      'reportsTools': 'Unde e scula', 'searchByNameOrInv': 'Caută după nume sau nr...',
      'needAccount': 'Cont necesar', 'newPassword': 'Parolă nouă', 'noPeople': 'Nicio persoană încă',
      'onlyAdmin': 'Doar proprietar/admin', 'passwordsNotMatch': 'Parolele nu corespund',
      'changePlan': 'Schimbă planul', 'planLabel': 'Plan', 'planSaved': 'Plan salvat', 'gpsNotInPlan': 'Urmărire GPS disponibilă de la planul Pro', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'Limită persoane', 'perMonth': 'lună',
      'planChangeOnlyOwner': 'Doar proprietarul poate schimba planul.',
      'selectPlan': 'Alegeți planul', 'supportTitle': 'Suport',
      'supportDesc': 'Pentru întrebări contactați-ne:', 'tariffLimitsTitle': 'Tarif și limite',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Utilizat (activi)',
      'inactiveNotCountedNote': 'Concediații/inactivi nu sunt numărați în limită.',
      'google': 'Google', 'enterEmailPass': 'Introduceți e-mail și parolă',
      'addTool': 'Adăugare sculă', 'addEmployee': 'Adăugare angajat',
      'inviteCode': 'Cod de invitație', 'requests': 'Solicitări', 'approve': 'Aprobați',
      'addPerson': 'Adăugare persoană', 'decline': 'Respingeți',
      'selectToolFirst': 'Selectați mai întâi scula', 'selectPersonFirst': 'Selectați mai întâi angajatul',
      'reportsByTool': 'Pe sculă', 'reportsByPerson': 'Pe angajat',
      'alreadyIn': 'Deja în companie', 'archivedCompany': 'Companie arhivată',
      'subscriptionStatusLabel': 'Stare', 'subscriptionValidUntilLabel': 'Valabil până la',
      'subscriptionTest': 'Mod test', 'subscriptionLive': 'Mod plătit',
      'buyRenewSoon': 'Plata în curând disponibilă. Contactați suportul.',
      'billingModeLabel': 'Mod plată', 'emailLabel': 'E-mail',
      'returnTitle': 'Confirmați returnarea',
      'myShift': 'Tura mea', 'startShift': 'Începe tura', 'endShift': 'Termină tura',
      'currentShift': 'Tura curentă', 'shiftStarted': 'Tura a început!', 'shiftEnded': 'Tura s-a terminat!',
      'selectSite': 'Selectați șantierul', 'noSites': 'Fără șantiere. Contactați administratorul.',
      'writeReport': 'Raport tură', 'whatDone': 'Ce s-a făcut', 'timesheets': 'Condică ture',
      'manageSites': 'Gestionare șantiere', 'sites': 'Șantiere', 'addSite': 'Adăugați șantier',
      'editSite': 'Editați șantierul', 'siteName': 'Nume șantier', 'siteAddress': 'Adresă',
      'siteRadius': 'Raza check-in (m)', 'gpsInterval': 'Interval GPS (min)',
      'allTime': 'Toată perioada',
      'allSites': 'Toate șantierele',
      'allPeople': 'Toți angajații',
      'exportPdf': 'Export PDF',
      'exportXlsx': 'Export Excel',
      'actPdf': 'Act PDF',
      'nakladnayaPdf': 'Aviz PDF',
      'gpsTrack': 'Traseu GPS',
      'noGpsData': 'Fără date GPS',
      'shiftActive': 'Tură activă',
      'shiftStart': 'Început',
      'shiftEnd': 'Sfârșit',
      'totalHours': 'Total ore',
      'shiftsCount': 'Ture',
      'workReport': 'Raport',
      'myTimesheets': 'Turele mele',
      'allTimesheets': 'Toate turele',
      'gpsPermissionDenied': 'GPS indisponibil — tură pornită fără verificarea locației',
      'gpsWarningTitle': 'În afara zonei șantierului',
      'gpsWarningText': 'Locația dvs. nu corespunde adresei șantierului.',
      'distance': 'Distanță',
      'startAnyway': 'Pornește oricum',
      'shiftTypeHourly': 'Orar',
      'shiftTypeAccord': 'Preț fix',
      'chooseShiftType': 'Tip tură',
      'shiftType': 'Tip muncă',
      'reportRequired': 'Completați raportul — ce s-a făcut',
      'viewSites': 'Toate șantierele',
      'navigateTo': 'Navigare',
      'linkUser': 'Conectați utilizatorul',
      'linkedUser': 'Conectat la',
      'unlinkUser': 'Deconectați',
      'selectUserToLink': 'Selectați utilizatorul',
      'notLinked': 'Contul nu este conectat la un profil. Contactați administratorul.',
      'personTypePerson': 'Persoană',
      'personTypeObject': 'Obiect',
      'noObjects': 'Niciun obiect încă. Apăsați +',
      'objectCompleted': 'Finalizat',
      'markObjectCompleted': 'Marcați ca finalizat',
      'personTab': 'Persoane',
      'objectTab': 'Obiecte',
      'cannotCompleteHasTools': 'Nu se poate finaliza: {n} unelte pe obiect',
      'cannotFireHasTools': 'Nu se poate concedia: angajatul are {n} unelte',
      'addObject': 'Adăugați obiect',
      'shiftReminder10hTitle': 'Tura durează 10 ore',
      'shiftReminder10hBody': 'Tura este activă de peste 10 ore. Nu uitați să o închideți.',
      'shiftReminder12hTitle': '⚠️ Tură 12 ore!',
      'shiftReminder12hBody': 'Atenție: tura este în desfășurare de peste 12 ore. Închideți tura.',
      'offlineBanner': 'Fără conexiune • date din cache',
      'alreadyHaveActiveShift': 'Aveți deja o tură activă. Închideți-o înainte de a începe una nouă.',
      'forceCloseShift': 'Forțați închiderea',
      'forceCloseShiftHint': 'Tura va fi închisă acum. Puteți adăuga un raport.',
      'shiftClosed': 'Tură închisă.',
      'archive': 'Arhivă',
      'noArchive': 'Arhiva este goală',
      'notifications': 'Notificări',
      'noNotifications': 'Nicio notificare nouă',
      'newMemberRequest': 'Nouă cerere de aderare',
      'markAllRead': 'Marcați toate ca citite',
      'copyTool': 'Copiați',
      'toolCopied': 'Unealtă copiată',
      'sortNameAZ': 'Nume A-Z',
      'sortCountDesc': 'Grupuri mari întâi',
      'sortDateDesc': 'Cele mai noi întâi',
      'darkTheme': 'Temă închisă',
      'lightTheme': 'Temă deschisă',
      'systemTheme': 'Temă sistem',
      'printQr': 'Printați QR',
      'saveAsPng': 'Salvați PNG',
      'thermalLabel': 'Etichetă termică',
      'printAllQr': 'Toate QR pe foaie',
      'noResults': 'Nimic găsit',
    },

    AppLang.nl: {
      'appTitle': 'ToolKeeper', 'login': 'Inloggen', 'register': 'Registreren', 'enter': 'Inloggen',
      'logout': 'Uitloggen', 'people': 'Mensen', 'tools': 'Gereedschap', 'tool': 'Gereedschap',
      'deleteAccount': 'Account verwijderen',
      'deleteAccountTitle': 'Account verwijderen?',
      'deleteAccountText': 'Al uw gegevens worden verwijderd. Deze actie kan niet ongedaan worden gemaakt.',
      'inv': 'Inv. nr.', 'issue': 'Uitgifte', 'profile': 'Profiel', 'chooseLang': 'Taal kiezen',
      'companyNotFound': 'Bedrijf niet gevonden', 'noAccessCompany': 'Geen toegang tot bedrijf',
      'leaveCompany': 'Verlaten / ander bedrijf', 'createCompany': 'Team aanmaken',
      'leaveCompanyConfirm': 'Weet u zeker dat u dit team wilt verlaten?',
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
      'email': 'E-mail', 'employee': 'Lid worden van team', 'employees': 'Medewerkers',
      'owner': 'Team aanmaken', 'admin': 'Beheerder', 'worker': 'Medewerker',
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
      'changePlan': 'Plan wijzigen', 'planLabel': 'Plan', 'planSaved': 'Plan opgeslagen', 'gpsNotInPlan': 'GPS-tracking beschikbaar vanaf Pro plan', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
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
      'myShift': 'Mijn dienst', 'startShift': 'Dienst starten', 'endShift': 'Dienst beëindigen',
      'currentShift': 'Huidige dienst', 'shiftStarted': 'Dienst gestart!', 'shiftEnded': 'Dienst beëindigd!',
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
      'gpsPermissionDenied': 'GPS niet beschikbaar — dienst gestart zonder locatiecontrole',
      'gpsWarningTitle': 'Buiten de zone van de locatie',
      'gpsWarningText': 'Uw locatie komt niet overeen met het adres van de locatie.',
      'distance': 'Afstand',
      'startAnyway': 'Toch starten',
      'shiftTypeHourly': 'Per uur',
      'shiftTypeAccord': 'Vaste prijs',
      'chooseShiftType': 'Type dienst',
      'shiftType': 'Type werk',
      'reportRequired': 'Vul het rapport in — wat is er gedaan',
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
      'shiftReminder12hTitle': '⚠️ Dienst 12 uur!',
      'shiftReminder12hBody': 'Waarschuwing: dienst loopt al meer dan 12 uur. Sluit de dienst.',
      'offlineBanner': 'Geen verbinding • gegevens uit cache',
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
      'copyTool': 'Kopiëren',
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
      'appTitle': 'ToolKeeper', 'login': 'Giriş', 'register': 'Kayıt', 'enter': 'Giriş yap',
      'logout': 'Çıkış yap', 'people': 'Kişiler', 'tools': 'Aletler', 'tool': 'Alet',
      'deleteAccount': 'Hesabı sil',
      'deleteAccountTitle': 'Hesabı sil?',
      'deleteAccountText': 'Tüm verileriniz silinecek. Bu işlem geri alınamaz.',
      'inv': 'Env. no.', 'issue': 'Dağıtım', 'profile': 'Profil', 'chooseLang': 'Dil seçin',
      'companyNotFound': 'Şirket bulunamadı', 'noAccessCompany': 'Şirkete erişim yok',
      'leaveCompany': 'Çık / başka şirket seç', 'createCompany': 'Takım oluştur',
      'leaveCompanyConfirm': 'Bu takımdan ayrılmak istediğinizden emin misiniz?',
      'joinCompany': 'Katıl', 'or': 'VEYA', 'companyName': 'Şirket adı',
      'role': 'Rol', 'role_owner': 'Sahip', 'role_admin': 'Yönetici',
      'role_foreman': 'Ustabaşı', 'role_employee': 'Çalışan',
      'save': 'Kaydet', 'cancel': 'İptal', 'add': 'Ekle', 'delete': 'Sil',
      'noEmployees': 'Çalışan yok', 'noTools': 'Alet yok',
      'issued': 'Verildi', 'returned': 'İade edildi', 'history': 'Geçmiş',
      'total': 'Toplam', 'pcs': 'adet', 'loading': 'Yükleniyor...', 'error': 'Hata', 'ok': 'Tamam',
      'issueUpper': 'VER', 'returnUpper': 'İADE ET', 'noName': 'İsimsiz',
      'confirmReturn': 'İade et', 'confirmIssue': 'Ver',
      'issueTab': 'Dağıtım', 'returnTab': 'İade',
      'searchByNameOrPhone': 'Ad veya telefona göre ara...',
      'birthDate': 'Doğum tarihi', 'clothesSize': 'Kıyafet bedeni', 'company': 'Şirket',
      'continue': 'Devam et', 'done': 'Tamam', 'firstName': 'Ad', 'lastName': 'Soyad',
      'password': 'Şifre', 'position': 'Pozisyon', 'reports': 'Raporlar', 'welcome': 'Hoş geldiniz',
      'email': 'E-posta', 'employee': 'Takıma katıl', 'employees': 'Çalışanlar',
      'owner': 'Takım oluştur', 'admin': 'Yönetici', 'worker': 'Çalışan',
      'employeeStatus': 'Çalışan durumu', 'empStatusActive': 'Aktif', 'empStatusFired': 'İşten çıkarıldı',
      'toolStatus': 'Alet durumu', 'toolStatusActive': 'Aktif', 'toolStatusRepair': 'Tamirde',
      'toolStatusDisposed': 'Hurdaya çıkarıldı', 'statusNote': 'Not',
      'warehouse': 'Depo', 'where': 'Nerede', 'issuedAt': 'Verildi', 'noData': 'Veri yok',
      'subscriptionTitle': 'Abonelik', 'subscriptionActive': 'Aktif', 'subscriptionInactive': 'Aktif değil',
      'buyRenew': 'Satın al / Uzat', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Önce kişi ekleyin', 'needToolsFirst': 'Önce alet ekleyin',
      'noFreeTool': 'Serbest alet yok', 'person': 'Kişi', 'returnTool': 'İade et',
      'versionLabel': 'Sürüm', 'lang': 'Dil', 'selectPerson': 'Çalışan seçin',
      'onHandsTotal': 'Elde: {n} adet', 'toolsCountLabel': 'Aletler: {n}', 'whoLabel': 'Kimde: {name}',
      'noReturnTool': 'İade edilecek alet yok', 'noCompany': 'Şirket seçilmedi',
      'reportFilterHint': 'Filtre...', 'reportsPeople': 'Kimde ne var (kişilere göre)',
      'reportsTools': 'Alet nerede', 'searchByNameOrInv': 'Ada veya numaraya göre ara...',
      'needAccount': 'Hesap gerekli', 'newPassword': 'Yeni şifre', 'noPeople': 'Henüz kişi yok',
      'onlyAdmin': 'Sadece sahip/yönetici', 'passwordsNotMatch': 'Şifreler eşleşmiyor',
      'changePlan': 'Planı değiştir', 'planLabel': 'Plan', 'planSaved': 'Plan kaydedildi', 'gpsNotInPlan': 'GPS takibi Pro planından itibaren mevcut', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'Kişi limiti', 'perMonth': 'ay',
      'planChangeOnlyOwner': 'Yalnızca sahip planı değiştirebilir.',
      'selectPlan': 'Plan seçin', 'supportTitle': 'Destek',
      'supportDesc': 'Sorularınız için bize ulaşın:', 'tariffLimitsTitle': 'Tarife ve limitler',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Kullanılan (aktif)',
      'inactiveNotCountedNote': 'İşten çıkarılanlar/pasifler limite dahil değil.',
      'google': 'Google', 'enterEmailPass': 'E-posta ve şifre girin',
      'addTool': 'Alet ekle', 'addEmployee': 'Çalışan ekle',
      'inviteCode': 'Davet kodu', 'requests': 'İstekler', 'approve': 'Onayla',
      'addPerson': 'Kişi ekle', 'decline': 'Reddet',
      'selectToolFirst': 'Önce alet seçin', 'selectPersonFirst': 'Önce çalışan seçin',
      'reportsByTool': 'Alete göre', 'reportsByPerson': 'Çalışana göre',
      'alreadyIn': 'Zaten şirkette', 'archivedCompany': 'Şirket arşivlendi',
      'subscriptionStatusLabel': 'Durum', 'subscriptionValidUntilLabel': 'Şu tarihe kadar geçerli',
      'subscriptionTest': 'Test modu', 'subscriptionLive': 'Ücretli mod',
      'buyRenewSoon': 'Ödeme yakında mevcut olacak. Desteğe başvurun.',
      'billingModeLabel': 'Ödeme modu', 'emailLabel': 'E-posta',
      'returnTitle': 'İadeyi onayla', 'switchAcc': 'Hesap değiştir',
      'myShift': 'Vardiyam', 'startShift': 'Vardiya başlat', 'endShift': 'Vardiya bitir',
      'currentShift': 'Mevcut vardiya', 'shiftStarted': 'Vardiya başladı!', 'shiftEnded': 'Vardiya bitti!',
      'selectSite': 'Şantiye seç', 'noSites': 'Şantiye yok. Yöneticiye başvurun.',
      'writeReport': 'Vardiya raporu', 'whatDone': 'Ne yapıldı', 'timesheets': 'Vardiya kayıtları',
      'manageSites': 'Şantiyeleri yönet', 'sites': 'Şantiyeler', 'addSite': 'Şantiye ekle',
      'editSite': 'Şantiye düzenle', 'siteName': 'Şantiye adı', 'siteAddress': 'Adres',
      'siteRadius': 'Check-in yarıçapı (m)', 'gpsInterval': 'GPS aralığı (dak)',
      'allTime': 'Tüm dönem',
      'allSites': 'Tüm şantiyeler',
      'allPeople': 'Tüm çalışanlar',
      'exportPdf': 'PDF dışa aktar',
      'exportXlsx': 'Excel dışa aktar',
      'actPdf': 'Belge PDF',
      'nakladnayaPdf': 'İrsaliye PDF',
      'gpsTrack': 'GPS izi',
      'noGpsData': 'GPS verisi yok',
      'shiftActive': 'Vardiya aktif',
      'shiftStart': 'Başlangıç',
      'shiftEnd': 'Bitiş',
      'totalHours': 'Toplam saat',
      'shiftsCount': 'Vardiyalar',
      'workReport': 'Rapor',
      'myTimesheets': 'Vardiyalarım',
      'allTimesheets': 'Tüm vardiyalar',
      'gpsPermissionDenied': 'GPS kullanılamıyor — vardiya konum doğrulaması olmadan başlatıldı',
      'gpsWarningTitle': 'Saha bölgesi dışında',
      'gpsWarningText': 'Konumunuz saha adresiyle eşleşmiyor.',
      'distance': 'Mesafe',
      'startAnyway': 'Yine de başlat',
      'shiftTypeHourly': 'Saatlik',
      'shiftTypeAccord': 'Sabit fiyat',
      'chooseShiftType': 'Vardiya türü',
      'shiftType': 'İş türü',
      'reportRequired': 'Raporu doldurun — ne yapıldı',
      'viewSites': 'Tüm sahalar',
      'navigateTo': 'Rota',
      'linkUser': 'Kullanıcı bağla',
      'linkedUser': 'Bağlı',
      'unlinkUser': 'Bağlantıyı kes',
      'selectUserToLink': 'Kullanıcı seç',
      'notLinked': 'Hesap bir profile bağlı değil. Yöneticiyle iletişime geçin.',
      'personTypePerson': 'Kişi',
      'personTypeObject': 'Nesne',
      'noObjects': 'Henüz nesne yok. + tuşuna basın',
      'objectCompleted': 'Tamamlandı',
      'markObjectCompleted': 'Tamamlandı olarak işaretle',
      'personTab': 'Kişiler',
      'objectTab': 'Nesneler',
      'cannotCompleteHasTools': 'Tamamlanamıyor: nesnede {n} alet var',
      'cannotFireHasTools': 'İşten çıkarılamıyor: çalışanın {n} aleti var',
      'addObject': 'Nesne ekle',
      'shiftReminder10hTitle': 'Vardiya 10 saattir sürüyor',
      'shiftReminder10hBody': 'Vardiya 10 saatten fazla aktif. Kapatmayı unutmayın.',
      'shiftReminder12hTitle': '⚠️ Vardiya 12 saat!',
      'shiftReminder12hBody': 'Uyarı: vardiya 12 saatten fazla sürüyor. Vardiyayı kapatın.',
      'offlineBanner': 'Bağlantı yok • önbellekten veri',
      'alreadyHaveActiveShift': 'Zaten aktif bir vardiyanz var. Yeni başlatmadan önce kapatın.',
      'forceCloseShift': 'Zorla kapat',
      'forceCloseShiftHint': 'Vardiya şimdi kapatılacak. Rapor ekleyebilirsiniz.',
      'shiftClosed': 'Vardiya kapatıldı.',
      'archive': 'Arşiv',
      'noArchive': 'Arşiv boş',
      'notifications': 'Bildirimler',
      'noNotifications': 'Yeni bildirim yok',
      'newMemberRequest': 'Yeni katılım isteği',
      'markAllRead': 'Tümünü okundu işaretle',
      'copyTool': 'Kopyala',
      'toolCopied': 'Alet kopyalandı',
      'sortNameAZ': 'Ad A-Z',
      'sortCountDesc': 'Büyük gruplar önce',
      'sortDateDesc': 'En yeniler önce',
      'darkTheme': 'Koyu tema',
      'lightTheme': 'Açık tema',
      'systemTheme': 'Sistem teması',
      'printQr': 'QR yazdır',
      'saveAsPng': 'PNG kaydet',
      'thermalLabel': 'Termal etiket',
      'printAllQr': 'Tüm QR sayfaya',
      'noResults': 'Sonuç yok',
    },

    AppLang.ar: {
      'appTitle': 'ToolKeeper', 'login': 'تسجيل الدخول', 'register': 'التسجيل', 'enter': 'دخول',
      'logout': 'تسجيل الخروج', 'people': 'أشخاص', 'tools': 'أدوات', 'tool': 'أداة',
      'deleteAccount': 'حذف الحساب',
      'deleteAccountTitle': 'حذف الحساب؟',
      'deleteAccountText': 'سيتم حذف جميع بياناتك. لا يمكن التراجع عن هذا الإجراء.',
      'inv': 'رقم الجرد', 'issue': 'إصدار', 'profile': 'الملف الشخصي', 'chooseLang': 'اختر اللغة',
      'companyNotFound': 'الشركة غير موجودة', 'noAccessCompany': 'لا يوجد وصول للشركة',
      'leaveCompany': 'خروج / اختيار شركة أخرى', 'createCompany': 'إنشاء فريق',
      'leaveCompanyConfirm': 'هل أنت متأكد من رغبتك في مغادرة هذا الفريق؟',
      'joinCompany': 'انضمام', 'or': 'أو', 'companyName': 'اسم الشركة',
      'role': 'الدور', 'role_owner': 'المالك', 'role_admin': 'المسؤول',
      'role_foreman': 'المشرف', 'role_employee': 'الموظف',
      'save': 'حفظ', 'cancel': 'إلغاء', 'add': 'إضافة', 'delete': 'حذف',
      'noEmployees': 'لا يوجد موظفون', 'noTools': 'لا توجد أدوات',
      'issued': 'تم الإصدار', 'returned': 'تم الإرجاع', 'history': 'السجل',
      'total': 'المجموع', 'pcs': 'قطعة', 'loading': 'تحميل...', 'error': 'خطأ', 'ok': 'موافق',
      'issueUpper': 'إصدار', 'returnUpper': 'إرجاع', 'noName': 'بدون اسم',
      'confirmReturn': 'إرجاع', 'confirmIssue': 'إصدار',
      'issueTab': 'إصدار', 'returnTab': 'إرجاع',
      'searchByNameOrPhone': 'بحث بالاسم أو الهاتف...',
      'birthDate': 'تاريخ الميلاد', 'clothesSize': 'مقاس الملابس', 'company': 'الشركة',
      'continue': 'متابعة', 'done': 'تم', 'firstName': 'الاسم الأول', 'lastName': 'اسم العائلة',
      'password': 'كلمة المرور', 'position': 'المنصب', 'reports': 'التقارير', 'welcome': 'مرحباً',
      'email': 'البريد الإلكتروني', 'employee': 'انضم إلى فريق', 'employees': 'موظفون',
      'owner': 'إنشاء فريق', 'admin': 'المسؤول', 'worker': 'عامل',
      'employeeStatus': 'حالة الموظف', 'empStatusActive': 'نشط', 'empStatusFired': 'مفصول',
      'toolStatus': 'حالة الأداة', 'toolStatusActive': 'نشطة', 'toolStatusRepair': 'في الإصلاح',
      'toolStatusDisposed': 'ملغاة', 'statusNote': 'ملاحظة',
      'warehouse': 'المستودع', 'where': 'أين', 'issuedAt': 'صدر في', 'noData': 'لا توجد بيانات',
      'subscriptionTitle': 'الاشتراك', 'subscriptionActive': 'نشط', 'subscriptionInactive': 'غير نشط',
      'buyRenew': 'شراء / تجديد', 'billingLive': 'مباشر', 'billingTest': 'اختبار',
      'needPeopleFirst': 'أضف أشخاصاً أولاً', 'needToolsFirst': 'أضف أدوات أولاً',
      'noFreeTool': 'لا توجد أداة حرة', 'person': 'شخص', 'returnTool': 'إرجاع',
      'versionLabel': 'الإصدار', 'lang': 'اللغة', 'selectPerson': 'اختر موظفاً',
      'onHandsTotal': 'في اليد: {n} قطعة', 'toolsCountLabel': 'الأدوات: {n}', 'whoLabel': 'عند من: {name}',
      'noReturnTool': 'لا توجد أداة للإعادة', 'noCompany': 'لم يتم اختيار الشركة',
      'reportFilterHint': 'تصفية...', 'reportsPeople': 'من لديه ماذا (حسب الأشخاص)',
      'reportsTools': 'أين الأداة', 'searchByNameOrInv': 'بحث بالاسم أو الرقم...',
      'needAccount': 'حساب مطلوب', 'newPassword': 'كلمة مرور جديدة', 'noPeople': 'لا يوجد أشخاص بعد',
      'onlyAdmin': 'للمالك/المسؤول فقط', 'passwordsNotMatch': 'كلمات المرور غير متطابقة',
      'changePlan': 'تغيير الخطة', 'planLabel': 'الخطة', 'planSaved': 'تم حفظ الخطة', 'gpsNotInPlan': 'تتبع GPS متاح من خطة Pro وما فوق', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'حد الأشخاص', 'perMonth': 'شهر',
      'planChangeOnlyOwner': 'المالك فقط يمكنه تغيير الخطة.',
      'selectPlan': 'اختر الخطة', 'supportTitle': 'الدعم',
      'supportDesc': 'للأسئلة تواصل معنا:', 'tariffLimitsTitle': 'التعرفة والحدود',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'مستخدم (نشطون)',
      'inactiveNotCountedNote': 'المفصولون/الغير نشطين لا يحسبون في الحد.',
      'google': 'Google', 'enterEmailPass': 'أدخل البريد وكلمة المرور',
      'addTool': 'إضافة أداة', 'addEmployee': 'إضافة موظف',
      'inviteCode': 'رمز الدعوة', 'requests': 'الطلبات', 'approve': 'موافقة',
      'addPerson': 'إضافة شخص', 'decline': 'رفض',
      'selectToolFirst': 'اختر أداة أولاً', 'selectPersonFirst': 'اختر موظفاً أولاً',
      'reportsByTool': 'حسب الأداة', 'reportsByPerson': 'حسب الموظف',
      'alreadyIn': 'موجود بالفعل في الشركة', 'archivedCompany': 'الشركة مؤرشفة',
      'subscriptionStatusLabel': 'الحالة', 'subscriptionValidUntilLabel': 'صالح حتى',
      'subscriptionTest': 'وضع تجريبي', 'subscriptionLive': 'وضع مدفوع',
      'buyRenewSoon': 'الدفع قريباً. تواصل مع الدعم.',
      'billingModeLabel': 'وضع الدفع', 'emailLabel': 'البريد الإلكتروني',
      'returnTitle': 'تأكيد الإرجاع',
      'myShift': 'وردیتي', 'startShift': 'بدء الوردية', 'endShift': 'إنهاء الوردية',
      'currentShift': 'الوردية الحالية', 'shiftStarted': 'بدأت الوردية!', 'shiftEnded': 'انتهت الوردية!',
      'selectSite': 'اختر الموقع', 'noSites': 'لا توجد مواقع. اتصل بالمسؤول.',
      'writeReport': 'تقرير الوردية', 'whatDone': 'ما تم إنجازه', 'timesheets': 'سجل الورديات',
      'manageSites': 'إدارة المواقع', 'sites': 'المواقع', 'addSite': 'إضافة موقع',
      'editSite': 'تعديل الموقع', 'siteName': 'اسم الموقع', 'siteAddress': 'العنوان',
      'siteRadius': 'نطاق تسجيل الحضور (م)', 'gpsInterval': 'فترة GPS (دقيقة)',
      'allTime': 'كل الوقت',
      'allSites': 'جميع المواقع',
      'allPeople': 'جميع الموظفين',
      'exportPdf': 'تصدير PDF',
      'exportXlsx': 'تصدير Excel',
      'actPdf': 'وثيقة PDF',
      'nakladnayaPdf': 'سند تسليم PDF',
      'gpsTrack': 'مسار GPS',
      'noGpsData': 'لا توجد بيانات GPS',
      'shiftActive': 'الوردية نشطة',
      'shiftStart': 'البداية',
      'shiftEnd': 'النهاية',
      'totalHours': 'إجمالي الساعات',
      'shiftsCount': 'الورديات',
      'workReport': 'تقرير',
      'myTimesheets': 'ورديتي',
      'allTimesheets': 'جميع الورديات',
      'gpsPermissionDenied': 'GPS غير متاح — بدأت الوردية بدون التحقق من الموقع',
      'gpsWarningTitle': 'خارج منطقة الموقع',
      'gpsWarningText': 'موقعك لا يتطابق مع عنوان الموقع.',
      'distance': 'المسافة',
      'startAnyway': 'ابدأ على أي حال',
      'shiftTypeHourly': 'بالساعة',
      'shiftTypeAccord': 'سعر ثابت',
      'chooseShiftType': 'نوع الوردية',
      'shiftType': 'نوع العمل',
      'reportRequired': 'أكمل التقرير — ما الذي تم إنجازه',
      'viewSites': 'جميع المواقع',
      'navigateTo': 'التنقل',
      'linkUser': 'ربط مستخدم',
      'linkedUser': 'مرتبط بـ',
      'unlinkUser': 'فصل الارتباط',
      'selectUserToLink': 'اختر مستخدم',
      'notLinked': 'الحساب غير مرتبط بملف شخصي. تواصل مع المسؤول.',
      'personTypePerson': 'شخص',
      'personTypeObject': 'كائن',
      'noObjects': 'لا توجد كائنات حتى الآن. اضغط +',
      'objectCompleted': 'مكتمل',
      'markObjectCompleted': 'وضع علامة مكتمل',
      'personTab': 'الأشخاص',
      'objectTab': 'الكائنات',
      'cannotCompleteHasTools': 'لا يمكن الإكمال: {n} أدوات على الكائن',
      'cannotFireHasTools': 'لا يمكن الفصل: الموظف لديه {n} أدوات',
      'addObject': 'إضافة كائن',
      'shiftReminder10hTitle': 'الوردية تستمر 10 ساعات',
      'shiftReminder10hBody': 'الوردية نشطة لأكثر من 10 ساعات. لا تنسَ إغلاقها.',
      'shiftReminder12hTitle': '⚠️ وردية 12 ساعة!',
      'shiftReminder12hBody': 'تحذير: الوردية جارية منذ أكثر من 12 ساعة. أغلق الوردية.',
      'offlineBanner': 'لا يوجد اتصال • بيانات من الذاكرة المؤقتة',
      'alreadyHaveActiveShift': 'لديك بالفعل وردية نشطة. أغلقها قبل بدء وردية جديدة.',
      'forceCloseShift': 'إغلاق قسري',
      'forceCloseShiftHint': 'ستُغلق الوردية الآن. يمكنك إضافة تقرير.',
      'shiftClosed': 'تم إغلاق الوردية.',
      'archive': 'أرشيف',
      'noArchive': 'الأرشيف فارغ',
      'notifications': 'الإشعارات',
      'noNotifications': 'لا توجد إشعارات جديدة',
      'newMemberRequest': 'طلب انضمام جديد',
      'markAllRead': 'تحديد الكل كمقروء',
      'copyTool': 'نسخ',
      'toolCopied': 'تم نسخ الأداة',
      'sortNameAZ': 'الاسم أ-ي',
      'sortCountDesc': 'المجموعات الكبيرة أولاً',
      'sortDateDesc': 'الأحدث أولاً',
      'darkTheme': 'المظهر الداكن',
      'lightTheme': 'المظهر الفاتح',
      'systemTheme': 'مظهر النظام',
      'printQr': 'طباعة QR',
      'saveAsPng': 'حفظ PNG',
      'thermalLabel': 'ملصق حراري',
      'printAllQr': 'كل QR على ورقة',
      'noResults': 'لا نتائج',
    },

    AppLang.hi: {
      'appTitle': 'ToolKeeper', 'login': 'लॉगिन', 'register': 'रजिस्टर', 'enter': 'साइन इन करें',
      'logout': 'लॉगआउट', 'people': 'लोग', 'tools': 'औज़ार', 'tool': 'औज़ार',
      'deleteAccount': 'खाता हटाएं',
      'deleteAccountTitle': 'खाता हटाएं?',
      'deleteAccountText': 'आपका सारा डेटा हटा दिया जाएगा। यह क्रिया अवापस नहीं हो सकती।',
      'inv': 'इन्व. नं.', 'issue': 'जारी करना', 'profile': 'प्रोफ़ाइल', 'chooseLang': 'भाषा चुनें',
      'companyNotFound': 'कंपनी नहीं मिली', 'noAccessCompany': 'कंपनी तक पहुंच नहीं',
      'leaveCompany': 'छोड़ें / दूसरी कंपनी', 'createCompany': 'टीम बनाएं',
      'leaveCompanyConfirm': 'क्या आप वाकई इस टीम से निकलना चाहते हैं?',
      'joinCompany': 'जुड़ें', 'or': 'या', 'companyName': 'कंपनी का नाम',
      'role': 'भूमिका', 'role_owner': 'मालिक', 'role_admin': 'व्यवस्थापक',
      'role_foreman': 'फोरमैन', 'role_employee': 'कर्मचारी',
      'save': 'सहेजें', 'cancel': 'रद्द करें', 'add': 'जोड़ें', 'delete': 'हटाएं',
      'noEmployees': 'कोई कर्मचारी नहीं', 'noTools': 'कोई औज़ार नहीं',
      'issued': 'जारी किया', 'returned': 'वापस किया', 'history': 'इतिहास',
      'total': 'कुल', 'pcs': 'पीस', 'loading': 'लोड हो रहा है...', 'error': 'त्रुटि', 'ok': 'ठीक है',
      'issueUpper': 'जारी करें', 'returnUpper': 'वापस करें', 'noName': 'नाम नहीं',
      'confirmReturn': 'वापस करें', 'confirmIssue': 'जारी करें',
      'issueTab': 'जारी करना', 'returnTab': 'वापसी',
      'searchByNameOrPhone': 'नाम या फोन से खोजें...',
      'birthDate': 'जन्म तिथि', 'clothesSize': 'कपड़ों का साइज़', 'company': 'कंपनी',
      'continue': 'जारी रखें', 'done': 'हो गया', 'firstName': 'नाम', 'lastName': 'उपनाम',
      'password': 'पासवर्ड', 'position': 'पद', 'reports': 'रिपोर्ट', 'welcome': 'स्वागत है',
      'email': 'ईमेल', 'employee': 'टीम से जुड़ें', 'employees': 'कर्मचारी',
      'owner': 'टीम बनाएं', 'admin': 'व्यवस्थापक', 'worker': 'कर्मचारी',
      'employeeStatus': 'कर्मचारी स्थिति', 'empStatusActive': 'सक्रिय', 'empStatusFired': 'बर्खास्त',
      'toolStatus': 'औज़ार स्थिति', 'toolStatusActive': 'सक्रिय', 'toolStatusRepair': 'मरम्मत में',
      'toolStatusDisposed': 'बंद', 'statusNote': 'नोट',
      'warehouse': 'गोदाम', 'where': 'कहाँ', 'issuedAt': 'जारी किया', 'noData': 'कोई डेटा नहीं',
      'subscriptionTitle': 'सब्सक्रिप्शन', 'subscriptionActive': 'सक्रिय', 'subscriptionInactive': 'निष्क्रिय',
      'buyRenew': 'खरीदें / नवीनीकरण', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'पहले लोगों को जोड़ें', 'needToolsFirst': 'पहले औज़ार जोड़ें',
      'noFreeTool': 'कोई मुफ़्त औज़ार नहीं', 'person': 'व्यक्ति', 'returnTool': 'वापस करें',
      'versionLabel': 'संस्करण', 'lang': 'भाषा', 'selectPerson': 'कर्मचारी चुनें',
      'onHandsTotal': 'हाथ में: {n} पीस', 'toolsCountLabel': 'औज़ार: {n}', 'whoLabel': 'किसके पास: {name}',
      'noReturnTool': 'वापस करने के लिए कोई औज़ार नहीं', 'noCompany': 'कोई कंपनी नहीं चुनी',
      'reportFilterHint': 'फ़िल्टर...', 'reportsPeople': 'किसके पास क्या (लोगों के अनुसार)',
      'reportsTools': 'औज़ार कहाँ है', 'searchByNameOrInv': 'नाम या नं. से खोजें...',
      'needAccount': 'खाता आवश्यक', 'newPassword': 'नया पासवर्ड', 'noPeople': 'अभी कोई लोग नहीं',
      'onlyAdmin': 'केवल मालिक/एडमिन', 'passwordsNotMatch': 'पासवर्ड मेल नहीं खाते',
      'changePlan': 'प्लान बदलें', 'planLabel': 'प्लान', 'planSaved': 'प्लान सहेजा', 'gpsNotInPlan': 'GPS ट्रैकिंग Pro प्लान से उपलब्ध', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'लोगों की सीमा', 'perMonth': 'महीना',
      'planChangeOnlyOwner': 'केवल मालिक प्लान बदल सकते हैं।',
      'selectPlan': 'प्लान चुनें', 'supportTitle': 'सहायता',
      'supportDesc': 'प्रश्नों के लिए हमसे संपर्क करें:', 'tariffLimitsTitle': 'टैरिफ और सीमाएं',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'उपयोग किया (सक्रिय)',
      'inactiveNotCountedNote': 'बर्खास्त/निष्क्रिय सीमा में नहीं गिने जाते।',
      'google': 'Google', 'enterEmailPass': 'ईमेल और पासवर्ड दर्ज करें',
      'addTool': 'औज़ार जोड़ें', 'addEmployee': 'कर्मचारी जोड़ें',
      'inviteCode': 'आमंत्रण कोड', 'requests': 'अनुरोध', 'approve': 'स्वीकृत करें',
      'addPerson': 'व्यक्ति जोड़ें', 'decline': 'अस्वीकार करें',
      'selectToolFirst': 'पहले औज़ार चुनें', 'selectPersonFirst': 'पहले कर्मचारी चुनें',
      'reportsByTool': 'औज़ार के अनुसार', 'reportsByPerson': 'कर्मचारी के अनुसार',
      'alreadyIn': 'पहले से कंपनी में', 'archivedCompany': 'कंपनी संग्रहीत',
      'subscriptionStatusLabel': 'स्थिति', 'subscriptionValidUntilLabel': 'तक वैध',
      'subscriptionTest': 'परीक्षण मोड', 'subscriptionLive': 'भुगतान मोड',
      'buyRenewSoon': 'भुगतान जल्द उपलब्ध। सहायता से संपर्क करें।',
      'billingModeLabel': 'भुगतान मोड', 'emailLabel': 'ईमेल',
      'returnTitle': 'वापसी की पुष्टि करें',
      'myShift': 'मेरी पाली', 'startShift': 'पाली शुरू करें', 'endShift': 'पाली समाप्त करें',
      'currentShift': 'वर्तमान पाली', 'shiftStarted': 'पाली शुरू हो गई!', 'shiftEnded': 'पाली समाप्त हो गई!',
      'selectSite': 'साइट चुनें', 'noSites': 'कोई साइट नहीं। व्यवस्थापक से संपर्क करें।',
      'writeReport': 'पाली रिपोर्ट', 'whatDone': 'क्या किया गया', 'timesheets': 'पाली रिकॉर्ड',
      'manageSites': 'साइट प्रबंधन', 'sites': 'साइटें', 'addSite': 'साइट जोड़ें',
      'editSite': 'साइट संपादित करें', 'siteName': 'साइट का नाम', 'siteAddress': 'पता',
      'siteRadius': 'चेक-इन त्रिज्या (मी)', 'gpsInterval': 'GPS अंतराल (मिनट)',
      'allTime': 'पूरी अवधि',
      'allSites': 'सभी साइटें',
      'allPeople': 'सभी कर्मचारी',
      'exportPdf': 'PDF निर्यात',
      'exportXlsx': 'Excel निर्यात',
      'actPdf': 'अधिनियम PDF',
      'nakladnayaPdf': 'डिलीवरी नोट PDF',
      'gpsTrack': 'GPS ट्रैक',
      'noGpsData': 'कोई GPS डेटा नहीं',
      'shiftActive': 'शिफ्ट सक्रिय',
      'shiftStart': 'शुरुआत',
      'shiftEnd': 'समाप्ति',
      'totalHours': 'कुल घंटे',
      'shiftsCount': 'शिफ्टें',
      'workReport': 'रिपोर्ट',
      'myTimesheets': 'मेरी शिफ्टें',
      'allTimesheets': 'सभी शिफ्टें',
      'gpsPermissionDenied': 'GPS उपलब्ध नहीं — शिफ्ट स्थान सत्यापन के बिना शुरू हुई',
      'gpsWarningTitle': 'साइट क्षेत्र से बाहर',
      'gpsWarningText': 'आपका स्थान साइट के पते से मेल नहीं खाता।',
      'distance': 'दूरी',
      'startAnyway': 'फिर भी शुरू करें',
      'shiftTypeHourly': 'प्रति घंटा',
      'shiftTypeAccord': 'निश्चित मूल्य',
      'chooseShiftType': 'शिफ्ट प्रकार',
      'shiftType': 'कार्य प्रकार',
      'reportRequired': 'रिपोर्ट भरें — क्या किया गया',
      'viewSites': 'सभी साइटें',
      'navigateTo': 'नेविगेट करें',
      'linkUser': 'उपयोगकर्ता लिंक करें',
      'linkedUser': 'से लिंक',
      'unlinkUser': 'अनलिंक करें',
      'selectUserToLink': 'उपयोगकर्ता चुनें',
      'notLinked': 'खाता प्रोफ़ाइल से लिंक नहीं है। व्यवस्थापक से संपर्क करें।',
      'personTypePerson': 'व्यक्ति',
      'personTypeObject': 'वस्तु',
      'noObjects': 'अभी कोई वस्तु नहीं। + दबाएं',
      'objectCompleted': 'पूर्ण',
      'markObjectCompleted': 'पूर्ण के रूप में चिह्नित करें',
      'personTab': 'लोग',
      'objectTab': 'वस्तुएं',
      'cannotCompleteHasTools': 'पूरा नहीं कर सकते: वस्तु पर {n} उपकरण हैं',
      'cannotFireHasTools': 'बर्खास्त नहीं कर सकते: कर्मचारी के पास {n} उपकरण हैं',
      'addObject': 'वस्तु जोड़ें',
      'shiftReminder10hTitle': 'शिफ्ट 10 घंटे चल रही है',
      'shiftReminder10hBody': 'शिफ्ट 10 घंटे से अधिक सक्रिय है। बंद करना न भूलें।',
      'shiftReminder12hTitle': '⚠️ शिफ्ट 12 घंटे!',
      'shiftReminder12hBody': 'चेतावनी: शिफ्ट 12 घंटे से अधिक चल रही है। शिफ्ट बंद करें।',
      'offlineBanner': 'कोई कनेक्शन नहीं • कैश से डेटा',
      'alreadyHaveActiveShift': 'आपके पास पहले से एक सक्रिय शिफ्ट है। नई शुरू करने से पहले बंद करें।',
      'forceCloseShift': 'जबरदस्ती बंद करें',
      'forceCloseShiftHint': 'शिफ्ट अभी बंद होगी। आप रिपोर्ट जोड़ सकते हैं।',
      'shiftClosed': 'शिफ्ट बंद हो गई।',
      'archive': 'संग्रह',
      'noArchive': 'संग्रह खाली है',
      'notifications': 'सूचनाएं',
      'noNotifications': 'कोई नई सूचना नहीं',
      'newMemberRequest': 'नया शामिल होने का अनुरोध',
      'markAllRead': 'सभी को पढ़ा हुआ चिह्नित करें',
      'copyTool': 'कॉपी करें',
      'toolCopied': 'उपकरण कॉपी किया गया',
      'sortNameAZ': 'नाम अ-ज़',
      'sortCountDesc': 'बड़े समूह पहले',
      'sortDateDesc': 'नवीनतम पहले',
      'darkTheme': 'डार्क थीम',
      'lightTheme': 'लाइट थीम',
      'systemTheme': 'सिस्टम थीम',
      'printQr': 'QR प्रिंट करें',
      'saveAsPng': 'PNG सहेजें',
      'thermalLabel': 'थर्मल लेबल',
      'printAllQr': 'सभी QR शीट पर',
      'noResults': 'कुछ नहीं मिला',
    },

    AppLang.ko: {
      'appTitle': 'ToolKeeper', 'login': '로그인', 'register': '회원가입', 'enter': '로그인',
      'logout': '로그아웃', 'people': '사람들', 'tools': '도구', 'tool': '도구',
      'deleteAccount': '계정 삭제',
      'deleteAccountTitle': '계정을 삭제하시겠습니까?',
      'deleteAccountText': '모든 데이터가 삭제됩니다. 이 작업은 실도할 수 없습니다.',
      'inv': '재고 번호', 'issue': '대출', 'profile': '프로필', 'chooseLang': '언어 선택',
      'companyNotFound': '회사를 찾을 수 없음', 'noAccessCompany': '회사에 접근 불가',
      'leaveCompany': '나가기 / 다른 회사', 'createCompany': '팀 만들기',
      'leaveCompanyConfirm': '이 팀에서 나가시겠습니까?',
      'joinCompany': '참가', 'or': '또는', 'companyName': '회사 이름',
      'role': '역할', 'role_owner': '소유자', 'role_admin': '관리자',
      'role_foreman': '현장 감독', 'role_employee': '직원',
      'save': '저장', 'cancel': '취소', 'add': '추가', 'delete': '삭제',
      'noEmployees': '직원 없음', 'noTools': '도구 없음',
      'issued': '대출됨', 'returned': '반납됨', 'history': '기록',
      'total': '합계', 'pcs': '개', 'loading': '로딩 중...', 'error': '오류', 'ok': '확인',
      'issueUpper': '대출', 'returnUpper': '반납', 'noName': '이름 없음',
      'confirmReturn': '반납', 'confirmIssue': '대출',
      'issueTab': '대출', 'returnTab': '반납',
      'searchByNameOrPhone': '이름 또는 전화번호로 검색...',
      'birthDate': '생년월일', 'clothesSize': '의류 사이즈', 'company': '회사',
      'continue': '계속', 'done': '완료', 'firstName': '이름', 'lastName': '성',
      'password': '비밀번호', 'position': '직위', 'reports': '보고서', 'welcome': '환영합니다',
      'email': '이메일', 'employee': '팀 참가하기', 'employees': '직원들',
      'owner': '팀 만들기', 'admin': '관리자', 'worker': '직원',
      'employeeStatus': '직원 상태', 'empStatusActive': '활성', 'empStatusFired': '해고됨',
      'toolStatus': '도구 상태', 'toolStatusActive': '활성', 'toolStatusRepair': '수리 중',
      'toolStatusDisposed': '폐기됨', 'statusNote': '메모',
      'warehouse': '창고', 'where': '어디', 'issuedAt': '대출일', 'noData': '데이터 없음',
      'subscriptionTitle': '구독', 'subscriptionActive': '활성', 'subscriptionInactive': '비활성',
      'buyRenew': '구매 / 갱신', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': '먼저 사람을 추가하세요', 'needToolsFirst': '먼저 도구를 추가하세요',
      'noFreeTool': '사용 가능한 도구 없음', 'person': '사람', 'returnTool': '반납',
      'versionLabel': '버전', 'lang': '언어', 'selectPerson': '직원 선택',
      'onHandsTotal': '보유 중: {n}개', 'toolsCountLabel': '도구: {n}개', 'whoLabel': '소지자: {name}',
      'noReturnTool': '반납할 도구 없음', 'noCompany': '선택된 회사 없음',
      'reportFilterHint': '필터...', 'reportsPeople': '누가 무엇을 (사람별)',
      'reportsTools': '도구 위치', 'searchByNameOrInv': '이름 또는 번호로 검색...',
      'needAccount': '계정 필요', 'newPassword': '새 비밀번호', 'noPeople': '아직 사람 없음',
      'onlyAdmin': '소유자/관리자만', 'passwordsNotMatch': '비밀번호가 일치하지 않습니다',
      'changePlan': '플랜 변경', 'planLabel': '플랜', 'planSaved': '플랜 저장됨', 'gpsNotInPlan': 'GPS 추적은 Pro 플랜부터 이용 가능', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': '인원 한도', 'perMonth': '월',
      'planChangeOnlyOwner': '소유자만 플랜을 변경할 수 있습니다.',
      'selectPlan': '플랜 선택', 'supportTitle': '지원',
      'supportDesc': '문의사항은 연락주세요:', 'tariffLimitsTitle': '요금 및 한도',
      'telegramLabel': 'Telegram', 'usedActiveLabel': '사용됨 (활성)',
      'inactiveNotCountedNote': '해고/비활성은 한도에 포함되지 않습니다.',
      'google': 'Google', 'enterEmailPass': '이메일과 비밀번호 입력',
      'addTool': '도구 추가', 'addEmployee': '직원 추가',
      'inviteCode': '초대 코드', 'requests': '요청', 'approve': '승인',
      'addPerson': '사람 추가', 'decline': '거절',
      'selectToolFirst': '먼저 도구를 선택하세요', 'selectPersonFirst': '먼저 직원을 선택하세요',
      'reportsByTool': '도구별', 'reportsByPerson': '직원별',
      'alreadyIn': '이미 회사에 있음', 'archivedCompany': '회사 보관됨',
      'subscriptionStatusLabel': '상태', 'subscriptionValidUntilLabel': '유효기간',
      'subscriptionTest': '테스트 모드', 'subscriptionLive': '유료 모드',
      'buyRenewSoon': '결제 곧 가능. 지원팀에 문의하세요.',
      'billingModeLabel': '결제 모드', 'emailLabel': '이메일',
      'returnTitle': '반납 확인',
      'myShift': '내 근무', 'startShift': '근무 시작', 'endShift': '근무 종료',
      'currentShift': '현재 근무', 'shiftStarted': '근무가 시작되었습니다!', 'shiftEnded': '근무가 종료되었습니다!',
      'selectSite': '현장 선택', 'noSites': '현장이 없습니다. 관리자에게 문의하세요.',
      'writeReport': '근무 보고서', 'whatDone': '수행한 작업', 'timesheets': '근무 기록',
      'manageSites': '현장 관리', 'sites': '현장', 'addSite': '현장 추가',
      'editSite': '현장 편집', 'siteName': '현장 이름', 'siteAddress': '주소',
      'siteRadius': '체크인 반경 (m)', 'gpsInterval': 'GPS 간격 (분)',
      'allTime': '전체 기간',
      'allSites': '모든 현장',
      'allPeople': '모든 직원',
      'exportPdf': 'PDF 내보내기',
      'exportXlsx': 'Excel 내보내기',
      'actPdf': '증서 PDF',
      'nakladnayaPdf': '인도장 PDF',
      'gpsTrack': 'GPS 추적',
      'noGpsData': 'GPS 데이터 없음',
      'shiftActive': '교대 진행 중',
      'shiftStart': '시작',
      'shiftEnd': '종료',
      'totalHours': '총 시간',
      'shiftsCount': '교대',
      'workReport': '보고서',
      'myTimesheets': '내 교대',
      'allTimesheets': '모든 교대',
      'gpsPermissionDenied': 'GPS 사용 불가 — 위치 확인 없이 교대 시작됨',
      'gpsWarningTitle': '현장 구역 밖',
      'gpsWarningText': '현재 위치가 현장 주소와 일치하지 않습니다.',
      'distance': '거리',
      'startAnyway': '그래도 시작',
      'shiftTypeHourly': '시간제',
      'shiftTypeAccord': '고정 가격',
      'chooseShiftType': '교대 유형',
      'shiftType': '작업 유형',
      'reportRequired': '보고서를 작성하세요 — 무엇을 했는지',
      'viewSites': '모든 현장',
      'navigateTo': '길 안내',
      'linkUser': '사용자 연결',
      'linkedUser': '연결된',
      'unlinkUser': '연결 해제',
      'selectUserToLink': '사용자 선택',
      'notLinked': '계정이 프로필에 연결되지 않았습니다. 관리자에게 문의하세요.',
      'personTypePerson': '사람',
      'personTypeObject': '개체',
      'noObjects': '아직 개체 없음. + 누르기',
      'objectCompleted': '완료',
      'markObjectCompleted': '완료로 표시',
      'personTab': '사람',
      'objectTab': '개체',
      'cannotCompleteHasTools': '완료할 수 없음: 개체에 {n}개 도구 있음',
      'cannotFireHasTools': '해고할 수 없음: 직원에게 {n}개 도구 있음',
      'addObject': '개체 추가',
      'shiftReminder10hTitle': '교대 10시간 진행 중',
      'shiftReminder10hBody': '교대가 10시간 이상 활성화되었습니다. 닫는 것을 잊지 마세요.',
      'shiftReminder12hTitle': '⚠️ 교대 12시간!',
      'shiftReminder12hBody': '경고: 교대가 12시간 이상 진행 중입니다. 교대를 닫으세요.',
      'offlineBanner': '연결 없음 • 캐시 데이터',
      'alreadyHaveActiveShift': '이미 활성 교대가 있습니다. 새 교대를 시작하기 전에 닫으세요.',
      'forceCloseShift': '강제 종료',
      'forceCloseShiftHint': '교대가 지금 종료됩니다. 보고서를 추가할 수 있습니다.',
      'shiftClosed': '교대가 종료되었습니다.',
      'archive': '보관함',
      'noArchive': '보관함이 비어 있습니다',
      'notifications': '알림',
      'noNotifications': '새 알림 없음',
      'newMemberRequest': '새 가입 요청',
      'markAllRead': '모두 읽음으로 표시',
      'copyTool': '복사',
      'toolCopied': '도구가 복사되었습니다',
      'sortNameAZ': '이름 가-힣',
      'sortCountDesc': '큰 그룹 먼저',
      'sortDateDesc': '최신 순',
      'darkTheme': '어두운 테마',
      'lightTheme': '밝은 테마',
      'systemTheme': '시스템 테마',
      'printQr': 'QR 인쇄',
      'saveAsPng': 'PNG 저장',
      'thermalLabel': '열 라벨',
      'printAllQr': '모든 QR 시트에',
      'noResults': '결과 없음',
    },

    AppLang.ja: {
      'appTitle': 'ToolKeeper', 'login': 'ログイン', 'register': '登録', 'enter': 'ログイン',
      'logout': 'ログアウト', 'people': '人員', 'tools': '工具', 'tool': '工具',
      'deleteAccount': 'アカウント値除',
      'deleteAccountTitle': 'アカウントを削除しますか？',
      'deleteAccountText': 'すべてのデータが削除されます。この操作は元に戻せません。',
      'inv': '在庫番号', 'issue': '貸出', 'profile': 'プロフィール', 'chooseLang': '言語を選択',
      'companyNotFound': '会社が見つかりません', 'noAccessCompany': '会社へのアクセスなし',
      'leaveCompany': '退出 / 別の会社', 'createCompany': 'チームを作る',
      'leaveCompanyConfirm': 'このチームを退出しますか？',
      'joinCompany': '参加', 'or': 'または', 'companyName': '会社名',
      'role': '役割', 'role_owner': 'オーナー', 'role_admin': '管理者',
      'role_foreman': '現場監督', 'role_employee': '従業員',
      'save': '保存', 'cancel': 'キャンセル', 'add': '追加', 'delete': '削除',
      'noEmployees': '従業員なし', 'noTools': '工具なし',
      'issued': '貸出済', 'returned': '返却済', 'history': '履歴',
      'total': '合計', 'pcs': '個', 'loading': '読み込み中...', 'error': 'エラー', 'ok': 'OK',
      'issueUpper': '貸出', 'returnUpper': '返却', 'noName': '名前なし',
      'confirmReturn': '返却', 'confirmIssue': '貸出',
      'issueTab': '貸出', 'returnTab': '返却',
      'searchByNameOrPhone': '名前または電話番号で検索...',
      'birthDate': '生年月日', 'clothesSize': '服のサイズ', 'company': '会社',
      'continue': '続ける', 'done': '完了', 'firstName': '名', 'lastName': '姓',
      'password': 'パスワード', 'position': '役職', 'reports': 'レポート', 'welcome': 'ようこそ',
      'email': 'メール', 'employee': 'チームに参加', 'employees': '従業員',
      'owner': 'チームを作る', 'admin': '管理者', 'worker': '従業員',
      'employeeStatus': '従業員ステータス', 'empStatusActive': 'アクティブ', 'empStatusFired': '解雇済',
      'toolStatus': '工具ステータス', 'toolStatusActive': 'アクティブ', 'toolStatusRepair': '修理中',
      'toolStatusDisposed': '廃棄済', 'statusNote': 'メモ',
      'warehouse': '倉庫', 'where': 'どこ', 'issuedAt': '貸出日', 'noData': 'データなし',
      'subscriptionTitle': 'サブスク', 'subscriptionActive': 'アクティブ', 'subscriptionInactive': '非アクティブ',
      'buyRenew': '購入 / 更新', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'まず人員を追加', 'needToolsFirst': 'まず工具を追加',
      'noFreeTool': '利用可能な工具なし', 'person': '人', 'returnTool': '返却',
      'versionLabel': 'バージョン', 'lang': '言語', 'selectPerson': '従業員を選択',
      'onHandsTotal': '保有中: {n}個', 'toolsCountLabel': '工具: {n}個', 'whoLabel': '保有者: {name}',
      'noReturnTool': '返却する工具がありません', 'noCompany': '会社が選択されていません',
      'reportFilterHint': 'フィルター...', 'reportsPeople': '誰が何を持っているか',
      'reportsTools': '工具の場所', 'searchByNameOrInv': '名前または番号で検索...',
      'needAccount': 'アカウントが必要', 'newPassword': '新しいパスワード', 'noPeople': 'まだ人員なし',
      'onlyAdmin': 'オーナー/管理者のみ', 'passwordsNotMatch': 'パスワードが一致しません',
      'changePlan': 'プランを変更', 'planLabel': 'プラン', 'planSaved': 'プランを保存しました', 'gpsNotInPlan': 'GPS追跡はProプラン以上で利用可能', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': '人員上限', 'perMonth': '月',
      'planChangeOnlyOwner': 'オーナーのみプランを変更できます。',
      'selectPlan': 'プランを選択', 'supportTitle': 'サポート',
      'supportDesc': 'ご質問はお問い合わせください:', 'tariffLimitsTitle': '料金と上限',
      'telegramLabel': 'Telegram', 'usedActiveLabel': '使用中（アクティブ）',
      'inactiveNotCountedNote': '解雇/非アクティブは上限に含まれません。',
      'google': 'Google', 'enterEmailPass': 'メールとパスワードを入力',
      'addTool': '工具を追加', 'addEmployee': '従業員を追加',
      'inviteCode': '招待コード', 'requests': 'リクエスト', 'approve': '承認',
      'addPerson': '人員を追加', 'decline': '拒否',
      'selectToolFirst': 'まず工具を選択', 'selectPersonFirst': 'まず従業員を選択',
      'reportsByTool': '工具別', 'reportsByPerson': '従業員別',
      'alreadyIn': '既に会社にいます', 'archivedCompany': '会社をアーカイブしました',
      'subscriptionStatusLabel': 'ステータス', 'subscriptionValidUntilLabel': '有効期限',
      'subscriptionTest': 'テストモード', 'subscriptionLive': '有料モード',
      'buyRenewSoon': '間もなく利用可能。サポートへお問い合わせください。',
      'billingModeLabel': '支払いモード', 'emailLabel': 'メール',
      'returnTitle': '返却を確認',
      'myShift': '私のシフト', 'startShift': 'シフト開始', 'endShift': 'シフト終了',
      'currentShift': '現在のシフト', 'shiftStarted': 'シフトが始まりました!', 'shiftEnded': 'シフトが終了しました!',
      'selectSite': '現場を選択', 'noSites': '現場がありません。管理者に連絡してください。',
      'writeReport': 'シフトレポート', 'whatDone': '行ったこと', 'timesheets': 'シフト記録',
      'manageSites': '現場管理', 'sites': '現場', 'addSite': '現場を追加',
      'editSite': '現場を編集', 'siteName': '現場名', 'siteAddress': '住所',
      'siteRadius': 'チェックイン半径 (m)', 'gpsInterval': 'GPS間隔（分）',
      'allTime': '全期間',
      'allSites': '全現場',
      'allPeople': '全従業員',
      'exportPdf': 'PDF出力',
      'exportXlsx': 'Excel出力',
      'actPdf': '証書 PDF',
      'nakladnayaPdf': '納品書 PDF',
      'gpsTrack': 'GPS追跡',
      'noGpsData': 'GPSデータなし',
      'shiftActive': 'シフト中',
      'shiftStart': '開始',
      'shiftEnd': '終了',
      'totalHours': '合計時間',
      'shiftsCount': 'シフト',
      'workReport': '報告書',
      'myTimesheets': '自分のシフト',
      'allTimesheets': '全シフト',
      'gpsPermissionDenied': 'GPS利用不可 — 位置確認なしでシフト開始',
      'gpsWarningTitle': '現場ゾーン外',
      'gpsWarningText': '現在地が現場の住所と一致しません。',
      'distance': '距離',
      'startAnyway': 'とにかく開始',
      'shiftTypeHourly': '時間制',
      'shiftTypeAccord': '固定価格',
      'chooseShiftType': 'シフトタイプ',
      'shiftType': '作業タイプ',
      'reportRequired': '報告書を入力してください — 何をしたか',
      'viewSites': '全現場',
      'navigateTo': 'ナビ',
      'linkUser': 'ユーザーをリンク',
      'linkedUser': 'リンク先',
      'unlinkUser': 'リンク解除',
      'selectUserToLink': 'ユーザーを選択',
      'notLinked': 'アカウントはプロファイルにリンクされていません。管理者に連絡してください。',
      'personTypePerson': '人物',
      'personTypeObject': 'オブジェクト',
      'noObjects': 'まだオブジェクトなし。+ を押してください',
      'objectCompleted': '完了',
      'markObjectCompleted': '完了としてマーク',
      'personTab': '人物',
      'objectTab': 'オブジェクト',
      'cannotCompleteHasTools': '完了できません：オブジェクトに{n}個の工具があります',
      'cannotFireHasTools': '解雇できません：従業員に{n}個の工具があります',
      'addObject': 'オブジェクト追加',
      'shiftReminder10hTitle': 'シフトが10時間続いています',
      'shiftReminder10hBody': 'シフトが10時間以上アクティブです。閉じることを忘れないでください。',
      'shiftReminder12hTitle': '⚠️ シフト12時間！',
      'shiftReminder12hBody': '警告：シフトが12時間以上続いています。シフトを閉じてください。',
      'offlineBanner': '接続なし • キャッシュデータ',
      'alreadyHaveActiveShift': 'アクティブなシフトがすでにあります。新しいシフトを開始する前に閉じてください。',
      'forceCloseShift': '強制終了',
      'forceCloseShiftHint': 'シフトは今すぐ終了します。報告書を追加できます。',
      'shiftClosed': 'シフトが終了しました。',
      'archive': 'アーカイブ',
      'noArchive': 'アーカイブは空です',
      'notifications': '通知',
      'noNotifications': '新しい通知なし',
      'newMemberRequest': '新しい参加リクエスト',
      'markAllRead': 'すべて既読にする',
      'copyTool': 'コピー',
      'toolCopied': '工具がコピーされました',
      'sortNameAZ': '名前 ア-ン',
      'sortCountDesc': '大グループを先に',
      'sortDateDesc': '新しい順',
      'darkTheme': 'ダークテーマ',
      'lightTheme': 'ライトテーマ',
      'systemTheme': 'システムテーマ',
      'printQr': 'QR印刷',
      'saveAsPng': 'PNG保存',
      'thermalLabel': '热敏标签',
      'printAllQr': '全部QR打印到纸',
      'noResults': '結果なし',
    },

    AppLang.zh: {
      'appTitle': 'ToolKeeper', 'login': '登录', 'register': '注册', 'enter': '登录',
      'logout': '退出', 'people': '人员', 'tools': '工具', 'tool': '工具',
      'deleteAccount': '删除账户',
      'deleteAccountTitle': '删除账户？',
      'deleteAccountText': '您的所有数据将被删除。此操作无法恢复。',
      'inv': '库存编号', 'issue': '发放', 'profile': '个人资料', 'chooseLang': '选择语言',
      'companyNotFound': '找不到公司', 'noAccessCompany': '无法访问公司',
      'leaveCompany': '退出 / 选择其他公司', 'createCompany': '创建团队',
      'leaveCompanyConfirm': '您确定要离开这个团队吗？',
      'joinCompany': '加入', 'or': '或', 'companyName': '公司名称',
      'role': '角色', 'role_owner': '所有者', 'role_admin': '管理员',
      'role_foreman': '工头', 'role_employee': '员工',
      'save': '保存', 'cancel': '取消', 'add': '添加', 'delete': '删除',
      'noEmployees': '没有员工', 'noTools': '没有工具',
      'issued': '已发放', 'returned': '已归还', 'history': '历史记录',
      'total': '总计', 'pcs': '件', 'loading': '加载中...', 'error': '错误', 'ok': '确定',
      'issueUpper': '发放', 'returnUpper': '归还', 'noName': '无名称',
      'confirmReturn': '归还', 'confirmIssue': '发放',
      'issueTab': '发放', 'returnTab': '归还',
      'searchByNameOrPhone': '按姓名或电话搜索...',
      'birthDate': '出生日期', 'clothesSize': '服装尺码', 'company': '公司',
      'continue': '继续', 'done': '完成', 'firstName': '名', 'lastName': '姓',
      'password': '密码', 'position': '职位', 'reports': '报告', 'welcome': '欢迎',
      'email': '电子邮件', 'employee': '加入团队', 'employees': '员工',
      'owner': '创建团队', 'admin': '管理员', 'worker': '员工',
      'employeeStatus': '员工状态', 'empStatusActive': '活跃', 'empStatusFired': '已解雇',
      'toolStatus': '工具状态', 'toolStatusActive': '活跃', 'toolStatusRepair': '维修中',
      'toolStatusDisposed': '已报废', 'statusNote': '备注',
      'warehouse': '仓库', 'where': '在哪', 'issuedAt': '发放日期', 'noData': '无数据',
      'subscriptionTitle': '订阅', 'subscriptionActive': '活跃', 'subscriptionInactive': '非活跃',
      'buyRenew': '购买 / 续费', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': '请先添加人员', 'needToolsFirst': '请先添加工具',
      'noFreeTool': '没有可用工具', 'person': '人员', 'returnTool': '归还',
      'versionLabel': '版本', 'lang': '语言', 'selectPerson': '选择员工',
      'onHandsTotal': '持有: {n}件', 'toolsCountLabel': '工具: {n}件', 'whoLabel': '持有者: {name}',
      'noReturnTool': '没有可归还的工具', 'noCompany': '未选择公司',
      'reportFilterHint': '筛选...', 'reportsPeople': '谁持有什么（按人员）',
      'reportsTools': '工具在哪里', 'searchByNameOrInv': '按名称或编号搜索...',
      'needAccount': '需要账户', 'newPassword': '新密码', 'noPeople': '还没有人员',
      'onlyAdmin': '仅所有者/管理员', 'passwordsNotMatch': '密码不匹配',
      'changePlan': '更改计划', 'planLabel': '计划', 'planSaved': '计划已保存', 'gpsNotInPlan': 'GPS追踪适用于Pro及以上套餐', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': '人员限制', 'perMonth': '月',
      'planChangeOnlyOwner': '只有所有者才能更改计划。',
      'selectPlan': '选择计划', 'supportTitle': '支持',
      'supportDesc': '如有问题请联系我们:', 'tariffLimitsTitle': '资费和限制',
      'telegramLabel': 'Telegram', 'usedActiveLabel': '已使用（活跃）',
      'inactiveNotCountedNote': '离职/非活跃不计入限制。',
      'google': 'Google', 'enterEmailPass': '输入邮箱和密码',
      'addTool': '添加工具', 'addEmployee': '添加员工',
      'inviteCode': '邀请码', 'requests': '请求', 'approve': '批准',
      'addPerson': '添加人员', 'decline': '拒绝',
      'selectToolFirst': '请先选择工具', 'selectPersonFirst': '请先选择员工',
      'reportsByTool': '按工具', 'reportsByPerson': '按员工',
      'alreadyIn': '已在公司中', 'archivedCompany': '公司已归档',
      'subscriptionStatusLabel': '状态', 'subscriptionValidUntilLabel': '有效期至',
      'subscriptionTest': '测试模式', 'subscriptionLive': '付费模式',
      'buyRenewSoon': '付款即将开放。请联系支持。',
      'billingModeLabel': '付款模式', 'emailLabel': '邮箱',
      'returnTitle': '确认归还',
      'myShift': '我的班次', 'startShift': '开始班次', 'endShift': '结束班次',
      'currentShift': '当前班次', 'shiftStarted': '班次已开始！', 'shiftEnded': '班次已结束！',
      'selectSite': '选择工地', 'noSites': '没有工地。请联系管理员。',
      'writeReport': '班次报告', 'whatDone': '完成了什么', 'timesheets': '班次记录',
      'manageSites': '管理工地', 'sites': '工地', 'addSite': '添加工地',
      'editSite': '编辑工地', 'siteName': '工地名称', 'siteAddress': '地址',
      'siteRadius': '打卡半径 (m)', 'gpsInterval': 'GPS间隔（分钟）',
      'allTime': '全部时间',
      'allSites': '所有工地',
      'allPeople': '所有员工',
      'exportPdf': '导出PDF',
      'exportXlsx': '导出Excel',
      'actPdf': '凭证 PDF',
      'nakladnayaPdf': '送货单 PDF',
      'gpsTrack': 'GPS轨迹',
      'noGpsData': '无GPS数据',
      'shiftActive': '班次进行中',
      'shiftStart': '开始',
      'shiftEnd': '结束',
      'totalHours': '总小时数',
      'shiftsCount': '班次',
      'workReport': '报告',
      'myTimesheets': '我的班次',
      'allTimesheets': '所有班次',
      'gpsPermissionDenied': 'GPS不可用 — 班次在没有位置验证的情况下开始',
      'gpsWarningTitle': '在工地区域外',
      'gpsWarningText': '您的位置与工地地址不符。',
      'distance': '距离',
      'startAnyway': '仍然开始',
      'shiftTypeHourly': '按小时',
      'shiftTypeAccord': '固定价格',
      'chooseShiftType': '班次类型',
      'shiftType': '工作类型',
      'reportRequired': '填写报告 — 完成了什么',
      'viewSites': '所有工地',
      'navigateTo': '导航',
      'linkUser': '关联用户',
      'linkedUser': '关联到',
      'unlinkUser': '取消关联',
      'selectUserToLink': '选择用户',
      'notLinked': '账户未关联到个人资料。请联系管理员。',
      'personTypePerson': '人员',
      'personTypeObject': '对象',
      'noObjects': '还没有对象。点击 +',
      'objectCompleted': '已完成',
      'markObjectCompleted': '标记为完成',
      'personTab': '人员',
      'objectTab': '对象',
      'cannotCompleteHasTools': '无法完成：对象上有 {n} 件工具',
      'cannotFireHasTools': '无法解雇：员工有 {n} 件工具',
      'addObject': '添加对象',
      'shiftReminder10hTitle': '班次已持续10小时',
      'shiftReminder10hBody': '班次已活跃超过10小时。别忘了关闭。',
      'shiftReminder12hTitle': '⚠️ 班次12小时！',
      'shiftReminder12hBody': '警告：班次已持续超过12小时。请关闭班次。',
      'offlineBanner': '无连接 • 来自缓存的数据',
      'alreadyHaveActiveShift': '您已经有一个活跃班次。在开始新班次之前请先关闭它。',
      'forceCloseShift': '强制关闭',
      'forceCloseShiftHint': '班次将立即关闭。您可以添加报告。',
      'shiftClosed': '班次已关闭。',
      'archive': '档案',
      'noArchive': '档案为空',
      'notifications': '通知',
      'noNotifications': '没有新通知',
      'newMemberRequest': '新加入请求',
      'markAllRead': '全部标记为已读',
      'copyTool': '复制',
      'toolCopied': '工具已复制',
      'sortNameAZ': '名称 A-Z',
      'sortCountDesc': '大组优先',
      'sortDateDesc': '最新优先',
      'darkTheme': '深色主题',
      'lightTheme': '浅色主题',
      'systemTheme': '系统主题',
      'printQr': '打印QR',
      'saveAsPng': '保存PNG',
      'thermalLabel': '热敏标签',
      'printAllQr': '所有QR到页面',
      'noResults': '无结果',
    },

    AppLang.id: {
      'appTitle': 'ToolKeeper', 'login': 'Masuk', 'register': 'Daftar', 'enter': 'Masuk',
      'logout': 'Keluar', 'people': 'Orang', 'tools': 'Alat', 'tool': 'Alat',
      'deleteAccount': 'Hapus akun',
      'deleteAccountTitle': 'Hapus akun?',
      'deleteAccountText': 'Semua data Anda akan dihapus. Tindakan ini tidak dapat dibatalkan.',
      'inv': 'No. inv.', 'issue': 'Pengeluaran', 'profile': 'Profil', 'chooseLang': 'Pilih bahasa',
      'companyNotFound': 'Perusahaan tidak ditemukan', 'noAccessCompany': 'Tidak ada akses ke perusahaan',
      'leaveCompany': 'Keluar / pilih lain', 'createCompany': 'Buat tim',
      'leaveCompanyConfirm': 'Apakah Anda yakin ingin meninggalkan tim ini?',
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
      'email': 'Email', 'employee': 'Bergabung dengan tim', 'employees': 'Karyawan',
      'owner': 'Buat tim', 'admin': 'Admin', 'worker': 'Karyawan',
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
      'changePlan': 'Ubah paket', 'planLabel': 'Paket', 'planSaved': 'Paket disimpan', 'gpsNotInPlan': 'Pelacakan GPS tersedia dari paket Pro ke atas', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
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
      'gpsPermissionDenied': 'GPS tidak tersedia — shift dimulai tanpa verifikasi lokasi',
      'gpsWarningTitle': 'Di luar zona lokasi',
      'gpsWarningText': 'Lokasi Anda tidak sesuai dengan alamat lokasi.',
      'distance': 'Jarak',
      'startAnyway': 'Mulai tetap saja',
      'shiftTypeHourly': 'Per jam',
      'shiftTypeAccord': 'Harga tetap',
      'chooseShiftType': 'Jenis shift',
      'shiftType': 'Jenis pekerjaan',
      'reportRequired': 'Isi laporan — apa yang telah dilakukan',
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
      'shiftReminder12hTitle': '⚠️ Shift 12 jam!',
      'shiftReminder12hBody': 'Peringatan: shift berjalan lebih dari 12 jam. Tutup shift.',
      'offlineBanner': 'Tidak ada koneksi • data dari cache',
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
      'appTitle': 'ToolKeeper', 'login': 'Đăng nhập', 'register': 'Đăng ký', 'enter': 'Đăng nhập',
      'logout': 'Đăng xuất', 'people': 'Mọi người', 'tools': 'Dụng cụ', 'tool': 'Dụng cụ',
      'deleteAccount': 'Xóa tài khoản',
      'deleteAccountTitle': 'Xóa tài khoản?',
      'deleteAccountText': 'Tất cả dữ liệu của bạn sẽ bị xóa. Hành động này không thể hoàn tác.',
      'inv': 'Mã kiểm kê', 'issue': 'Cấp phát', 'profile': 'Hồ sơ', 'chooseLang': 'Chọn ngôn ngữ',
      'companyNotFound': 'Không tìm thấy công ty', 'noAccessCompany': 'Không có quyền truy cập',
      'leaveCompany': 'Thoát / chọn công ty khác', 'createCompany': 'Tạo nhóm',
      'leaveCompanyConfirm': 'Bạn có chắc chắn muốn rời khỏi nhóm này không?',
      'joinCompany': 'Tham gia', 'or': 'HOẶC', 'companyName': 'Tên công ty',
      'role': 'Vai trò', 'role_owner': 'Chủ sở hữu', 'role_admin': 'Quản trị viên',
      'role_foreman': 'Đốc công', 'role_employee': 'Nhân viên',
      'save': 'Lưu', 'cancel': 'Hủy', 'add': 'Thêm', 'delete': 'Xóa',
      'noEmployees': 'Không có nhân viên', 'noTools': 'Không có dụng cụ',
      'issued': 'Đã cấp', 'returned': 'Đã trả', 'history': 'Lịch sử',
      'total': 'Tổng cộng', 'pcs': 'cái', 'loading': 'Đang tải...', 'error': 'Lỗi', 'ok': 'OK',
      'issueUpper': 'CẤP PHÁT', 'returnUpper': 'TRẢ LẠI', 'noName': 'Không có tên',
      'confirmReturn': 'Trả lại', 'confirmIssue': 'Cấp phát',
      'issueTab': 'Cấp phát', 'returnTab': 'Trả lại',
      'searchByNameOrPhone': 'Tìm theo tên hoặc số điện thoại...',
      'birthDate': 'Ngày sinh', 'clothesSize': 'Cỡ quần áo', 'company': 'Công ty',
      'continue': 'Tiếp tục', 'done': 'Xong', 'firstName': 'Tên', 'lastName': 'Họ',
      'password': 'Mật khẩu', 'position': 'Chức vụ', 'reports': 'Báo cáo', 'welcome': 'Chào mừng',
      'email': 'Email', 'employee': 'Tham gia nhóm', 'employees': 'Nhân viên',
      'owner': 'Tạo nhóm', 'admin': 'Quản trị', 'worker': 'Công nhân',
      'employeeStatus': 'Trạng thái nhân viên', 'empStatusActive': 'Hoạt động', 'empStatusFired': 'Đã sa thải',
      'toolStatus': 'Trạng thái dụng cụ', 'toolStatusActive': 'Hoạt động', 'toolStatusRepair': 'Đang sửa chữa',
      'toolStatusDisposed': 'Đã thanh lý', 'statusNote': 'Ghi chú',
      'warehouse': 'Kho', 'where': 'Ở đâu', 'issuedAt': 'Đã cấp', 'noData': 'Không có dữ liệu',
      'subscriptionTitle': 'Đăng ký', 'subscriptionActive': 'Hoạt động', 'subscriptionInactive': 'Không hoạt động',
      'buyRenew': 'Mua / Gia hạn', 'billingLive': 'LIVE', 'billingTest': 'TEST',
      'needPeopleFirst': 'Thêm người trước', 'needToolsFirst': 'Thêm dụng cụ trước',
      'noFreeTool': 'Không có dụng cụ trống', 'person': 'Người', 'returnTool': 'Trả lại',
      'versionLabel': 'Phiên bản', 'lang': 'Ngôn ngữ', 'selectPerson': 'Chọn nhân viên',
      'onHandsTotal': 'Đang giữ: {n} cái', 'toolsCountLabel': 'Dụng cụ: {n}', 'whoLabel': 'Người giữ: {name}',
      'noReturnTool': 'Không có dụng cụ để trả', 'noCompany': 'Chưa chọn công ty',
      'reportFilterHint': 'Lọc...', 'reportsPeople': 'Ai giữ gì (theo người)',
      'reportsTools': 'Dụng cụ ở đâu', 'searchByNameOrInv': 'Tìm theo tên hoặc mã...',
      'needAccount': 'Cần tài khoản', 'newPassword': 'Mật khẩu mới', 'noPeople': 'Chưa có người',
      'onlyAdmin': 'Chỉ chủ sở hữu/admin', 'passwordsNotMatch': 'Mật khẩu không khớp',
      'changePlan': 'Đổi gói', 'planLabel': 'Gói', 'planSaved': 'Đã lưu gói', 'gpsNotInPlan': 'Theo dõi GPS khả dụng từ gói Pro trở lên', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
      'peopleLimitLabel': 'Giới hạn người', 'perMonth': 'tháng',
      'planChangeOnlyOwner': 'Chỉ chủ sở hữu mới có thể đổi gói.',
      'selectPlan': 'Chọn gói', 'supportTitle': 'Hỗ trợ',
      'supportDesc': 'Để được hỗ trợ, liên hệ chúng tôi:', 'tariffLimitsTitle': 'Giá và giới hạn',
      'telegramLabel': 'Telegram', 'usedActiveLabel': 'Đã dùng (hoạt động)',
      'inactiveNotCountedNote': 'Đã sa thải/không hoạt động không tính vào giới hạn.',
      'google': 'Google', 'enterEmailPass': 'Nhập email và mật khẩu',
      'addTool': 'Thêm dụng cụ', 'addEmployee': 'Thêm nhân viên',
      'inviteCode': 'Mã mời', 'requests': 'Yêu cầu', 'approve': 'Phê duyệt',
      'addPerson': 'Thêm người', 'decline': 'Từ chối',
      'selectToolFirst': 'Chọn dụng cụ trước', 'selectPersonFirst': 'Chọn nhân viên trước',
      'reportsByTool': 'Theo dụng cụ', 'reportsByPerson': 'Theo nhân viên',
      'alreadyIn': 'Đã trong công ty', 'archivedCompany': 'Công ty đã lưu trữ',
      'subscriptionStatusLabel': 'Trạng thái', 'subscriptionValidUntilLabel': 'Có hiệu lực đến',
      'subscriptionTest': 'Chế độ thử', 'subscriptionLive': 'Chế độ trả phí',
      'buyRenewSoon': 'Thanh toán sắp có. Liên hệ hỗ trợ.',
      'billingModeLabel': 'Chế độ thanh toán', 'emailLabel': 'Email',
      'returnTitle': 'Xác nhận trả lại',
      'myShift': 'Ca làm của tôi', 'startShift': 'Bắt đầu ca', 'endShift': 'Kết thúc ca',
      'currentShift': 'Ca hiện tại', 'shiftStarted': 'Ca đã bắt đầu!', 'shiftEnded': 'Ca đã kết thúc!',
      'selectSite': 'Chọn công trình', 'noSites': 'Không có công trình. Liên hệ quản trị viên.',
      'writeReport': 'Báo cáo ca làm', 'whatDone': 'Đã làm gì', 'timesheets': 'Chấm công',
      'manageSites': 'Quản lý công trình', 'sites': 'Công trình', 'addSite': 'Thêm công trình',
      'editSite': 'Sửa công trình', 'siteName': 'Tên công trình', 'siteAddress': 'Địa chỉ',
      'siteRadius': 'Bán kính check-in (m)', 'gpsInterval': 'Khoảng GPS (phút)',
      'allTime': 'Toàn bộ thời gian',
      'allSites': 'Tất cả công trình',
      'allPeople': 'Tất cả nhân viên',
      'exportPdf': 'Xuất PDF',
      'exportXlsx': 'Xuất Excel',
      'actPdf': 'Biên bản PDF',
      'nakladnayaPdf': 'Phiếu xuất kho PDF',
      'gpsTrack': 'Theo dõi GPS',
      'noGpsData': 'Không có dữ liệu GPS',
      'shiftActive': 'Ca làm việc đang hoạt động',
      'shiftStart': 'Bắt đầu',
      'shiftEnd': 'Kết thúc',
      'totalHours': 'Tổng giờ',
      'shiftsCount': 'Ca',
      'workReport': 'Báo cáo',
      'myTimesheets': 'Ca của tôi',
      'allTimesheets': 'Tất cả ca',
      'gpsPermissionDenied': 'GPS không khả dụng — ca bắt đầu mà không xác minh vị trí',
      'gpsWarningTitle': 'Ngoài vùng công trường',
      'gpsWarningText': 'Vị trí của bạn không khớp với địa chỉ công trường.',
      'distance': 'Khoảng cách',
      'startAnyway': 'Vẫn bắt đầu',
      'shiftTypeHourly': 'Theo giờ',
      'shiftTypeAccord': 'Giá cố định',
      'chooseShiftType': 'Loại ca',
      'shiftType': 'Loại công việc',
      'reportRequired': 'Điền báo cáo — những gì đã làm',
      'viewSites': 'Tất cả công trường',
      'navigateTo': 'Dẫn đường',
      'linkUser': 'Liên kết người dùng',
      'linkedUser': 'Liên kết đến',
      'unlinkUser': 'Hủy liên kết',
      'selectUserToLink': 'Chọn người dùng',
      'notLinked': 'Tài khoản chưa liên kết hồ sơ. Liên hệ quản trị viên.',
      'personTypePerson': 'Người',
      'personTypeObject': 'Đối tượng',
      'noObjects': 'Chưa có đối tượng. Nhấn +',
      'objectCompleted': 'Hoàn thành',
      'markObjectCompleted': 'Đánh dấu hoàn thành',
      'personTab': 'Người',
      'objectTab': 'Đối tượng',
      'cannotCompleteHasTools': 'Không thể hoàn thành: {n} công cụ trên đối tượng',
      'cannotFireHasTools': 'Không thể sa thải: nhân viên có {n} công cụ',
      'addObject': 'Thêm đối tượng',
      'shiftReminder10hTitle': 'Ca làm việc kéo dài 10 giờ',
      'shiftReminder10hBody': 'Ca đã hoạt động hơn 10 giờ. Đừng quên đóng lại.',
      'shiftReminder12hTitle': '⚠️ Ca 12 giờ!',
      'shiftReminder12hBody': 'Cảnh báo: ca đang kéo dài hơn 12 giờ. Đóng ca.',
      'offlineBanner': 'Không có kết nối • dữ liệu từ bộ nhớ đệm',
      'alreadyHaveActiveShift': 'Bạn đã có ca làm việc đang hoạt động. Đóng nó trước khi bắt đầu ca mới.',
      'forceCloseShift': 'Buộc đóng',
      'forceCloseShiftHint': 'Ca sẽ đóng ngay bây giờ. Bạn có thể thêm báo cáo.',
      'shiftClosed': 'Ca đã đóng.',
      'archive': 'Lưu trữ',
      'noArchive': 'Lưu trữ trống',
      'notifications': 'Thông báo',
      'noNotifications': 'Không có thông báo mới',
      'newMemberRequest': 'Yêu cầu tham gia mới',
      'markAllRead': 'Đánh dấu tất cả đã đọc',
      'copyTool': 'Sao chép',
      'toolCopied': 'Công cụ đã sao chép',
      'sortNameAZ': 'Tên A-Z',
      'sortCountDesc': 'Nhóm lớn trước',
      'sortDateDesc': 'Mới nhất trước',
      'darkTheme': 'Giao diện tối',
      'lightTheme': 'Giao diện sáng',
      'systemTheme': 'Giao diện hệ thống',
      'printQr': 'In QR',
      'saveAsPng': 'Lưu PNG',
      'thermalLabel': 'Nhãn nhiệt',
      'printAllQr': 'Tất cả QR ra trang',
      'noResults': 'Không tìm thấy',
    },

    AppLang.tl: {
      'appTitle': 'ToolKeeper', 'login': 'Mag-login', 'register': 'Mag-register', 'enter': 'Pumasok',
      'logout': 'Mag-logout', 'people': 'Mga Tao', 'tools': 'Mga Kagamitan', 'tool': 'Kagamitan',
      'deleteAccount': 'Burahin ang account',
      'deleteAccountTitle': 'Burahin ang account?',
      'deleteAccountText': 'Lahat ng iyong data ay mabubura. Hindi maaaring i-undo ang aksyong ito.',
      'inv': 'Inv. no.', 'issue': 'Pag-isyu', 'profile': 'Profile', 'chooseLang': 'Pumili ng wika',
      'companyNotFound': 'Hindi nahanap ang kumpanya', 'noAccessCompany': 'Walang access sa kumpanya',
      'leaveCompany': 'Umalis / pumili ng iba', 'createCompany': 'Gumawa ng koponan',
      'leaveCompanyConfirm': 'Sigurado ka bang gusto mong umalis sa koponang ito?',
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
      'email': 'Email', 'employee': 'Sumali sa koponan', 'employees': 'Mga Empleyado',
      'owner': 'Gumawa ng koponan', 'admin': 'Admin', 'worker': 'Manggagawa',
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
      'changePlan': 'Baguhin ang plano', 'planLabel': 'Plano', 'planSaved': 'Nai-save ang plano', 'gpsNotInPlan': 'Available ang GPS tracking mula sa Pro plan pataas', 'gpsIncluded': 'GPS ✓', 'gpsNotIncluded': 'GPS —',
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
      'gpsPermissionDenied': 'Hindi available ang GPS — nagsimula ang shift nang walang location check',
      'gpsWarningTitle': 'Labas ng zone ng site',
      'gpsWarningText': 'Hindi tumutugma ang iyong lokasyon sa address ng site.',
      'distance': 'Distansya',
      'startAnyway': 'Magsimula pa rin',
      'shiftTypeHourly': 'Per oras',
      'shiftTypeAccord': 'Naayos na presyo',
      'chooseShiftType': 'Uri ng shift',
      'shiftType': 'Uri ng trabaho',
      'reportRequired': 'Punan ang ulat — ano ang nagawa',
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
      'shiftReminder12hTitle': '⚠️ Shift 12 oras!',
      'shiftReminder12hBody': 'Babala: tumatagal na ng mahigit 12 oras ang shift. Isara ang shift.',
      'offlineBanner': 'Walang koneksyon • data mula sa cache',
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
  if (u == null) throw Exception('Нет пользователя');
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
  // ✅ для алфавита: "ё" считаем как "е"
  return lower.replaceAll('ё', 'е');
}

String normalizeRole(String role) {
  final r = role.toLowerCase().trim();
  if (r == 'owner') return 'owner';
  if (r == 'admin') return 'admin';

  // Прораб / Brygadzista (поддержка старых/ошибочных значений)
  if (r == 'foreman' || r == 'foramen' || r == '4man' || r == 'brygadzista' || r == 'прораб') {
    return 'foreman';
  }

  // поддержка старых/ошибочных значений для сотрудника
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
    _initWidgetLaunch();
  }

  Future<void> _initWidgetLaunch() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null) _handleWidgetUri(uri);
    } catch (_) {}
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) _handleWidgetUri(uri);
    });
  }

  void _handleWidgetUri(Uri uri) {
    final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    if (action == 'start') {
      pendingWidgetAction.value = 'start';
    } else if (action == 'end') {
      pendingWidgetAction.value = 'end';
    }
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
      // First launch — detect from system locale
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
            title: i18n.t('appTitle'), locale: localeForAppLang(lang), localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate], supportedLocales: AppLang.values.map(localeForAppLang).toList(),
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

// Баннер "нет интернета" — показывается поверх всего приложения
class _OfflineBanner extends StatefulWidget {
  final I18n i18n;
  final Widget child;
  const _OfflineBanner({required this.i18n, required this.child});
  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  bool _isOffline = false;
  late final StreamSubscription<ConnectivityResult> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Connectivity().onConnectivityChanged.listen((result) {
      final offline = result == ConnectivityResult.none;
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

/// Экран выбора: продолжить / сменить аккаунт / выйти
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
            'Google вход на Windows не используем.\n'
            'Если аккаунт создавался через Google на телефоне — привяжи пароль в профиле на телефоне,\n'
            'и потом заходи на ПК по Email+Пароль.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final GoogleSignIn googleSignIn = GoogleSignIn(
      clientId: Platform.isIOS ? '242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n.apps.googleusercontent.com' : null,
      scopes: const ['email'],
    );

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

        // Анкета должна быть заполнена, но теперь её можно редактировать в любой момент (в профиле)
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

      // ✅ 1) Если пользователь владелец — находим фирмы по ownerUid (это безопасный запрос)
      try {
        final ownerSnap = await companiesRef()
            .where('ownerUid', isEqualTo: uid)
            .where('deleted', isEqualTo: false)
            .get();
        for (final d in ownerSnap.docs) {
          ids.add(d.id);
        }
      } catch (_) {}

      // ✅ 2) Если в members хранится поле uid — можно восстановить и для сотрудников
      // (мы добавили 'uid' в members при создании/вступлении/подтверждении)
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

      // 3) Если нашли хотя бы одну фирму — НЕ ставим activeCompanyId автоматически.
/// Показываем список фирм, чтобы пользователь сам выбрал (или создал новую).
if (myCompanyIds.isNotEmpty) {
  if (!mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => ChooseMyCompanyPage(companyIds: myCompanyIds)),
    (_) => false,
  );
  return;
}

// 4) Если фирм нет — тогда уже даём выбор создать/войти по коду
      if (myCompanyIds.isEmpty) {
        if (!mounted) return;
        setState(() => done = true);
        return;
      }

      // 5) Если фирм несколько — покажем список выбора
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
              'Ошибка восстановления фирмы:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (done) {
      // фирм нет — показываем обычный выбор
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
      appBar: AppBar(title: const Text('Выберите вашу фирму')),
      body: ListView.builder(
        itemCount: companyIds.length,
        itemBuilder: (_, i) {
          final id = companyIds[i];
          return ListTile(
            title: Text('Фирма: $id'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _select(context, id),
          );
        },
      ),
    );
  }
}
/// ===================
/// AUTO RESTORE COMPANY (если activeCompanyId пустой)
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

      // Ищем фирму, где этот uid состоит в members и status == active
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

      // Если нашли — НЕ записываем activeCompanyId автоматически.
/// Показываем выбор фирм (даже если она одна), чтобы избежать циклов.
if (foundCompanyId.isNotEmpty) {
  if (!mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => ChooseMyCompanyPage(companyIds: [foundCompanyId])),
    (_) => false,
  );
  return;
}

// Не нашли — показываем выбор (создать/войти по коду)
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
                    Text('Ищу вашу фирму...'),
                  ],
                )
              : Text('Ошибка восстановления фирмы:\n$error', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// ===================
/// PROFILE FORM (create/edit)
/// ===================
/// ===================
/// PROFILE FORM (create/edit)  ✅ FIX PREFILL
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

  bool _loadedOnce = false; // ✅ важно

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
        _prefillOnce(data); // ✅ вот оно

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
      setState(() => error = 'Нет email у пользователя');
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
      if (email == null || email.isEmpty) throw Exception('Нет email у пользователя');

      final hasPasswordProvider = u.providerData.any((p) => p.providerId == 'password');

      if (hasPasswordProvider) {
        // смена пароля
        await u.updatePassword(p1);
      } else {
        // привязка пароля к Google-аккаунту
        final cred = EmailAuthProvider.credential(email: email, password: p1);
        await u.linkWithCredential(cred);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('done'))));
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      // часто нужно "recent login"
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

Future<void> _deleteAccountFromRoleChoice(BuildContext context) async {
  final i18n = I18n(AppState.of(context).lang.value);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(i18n.t('deleteAccountTitle')),
      content: Text(i18n.t('deleteAccountText')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(i18n.t('deleteAccount')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final uid = user.uid;
  try {
    await userDoc(uid).delete();
  } catch (_) {}
  try {
    await user.delete();
  } catch (_) {}
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AppRouter()),
    (_) => false,
  );
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
                icon: const Icon(Icons.group_add),
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
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => _deleteAccountFromRoleChoice(context),
              child: Text(
                i18n.t('deleteAccount'),
                style: const TextStyle(color: Colors.red),
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

      // 1) Создаём заранее companyId (вместо add)
      final companyDoc = companiesRef().doc();
      final companyId = companyDoc.id;

      // 2) Генерим invite code (потом сохраним как doc id)
      final code = _genCode();

      // 3) Batch: фирма + inviteCode + member(owner) + activeCompanyId
      final batch = FirebaseFirestore.instance.batch();

      // COMPANY
      batch.set(companyDoc, {
        'name': name,
        'ownerUid': uid,
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,

        // ✅ поля тарифа для твоей фирмы (бесплатно и безлимит)
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
/// COMPANY GATE  ✅ FIX: НЕ СБРАСЫВАЕМ activeCompanyId САМИ
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
    // ТОЛЬКО по кнопке пользователя, а не автоматически
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
        // 1) Ждём
        if (companySnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2) Ошибка чтения фирмы — НЕ СБРАСЫВАЕМ, просто показываем
        if (companySnap.hasError) {
  return Scaffold(
    appBar: AppBar(title: Text(i18n.t('errCompanyRead'))),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Ошибка доступа к фирме:\n${companySnap.error}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    ),
  );
}

        // 3) Фирмы нет — НЕ СБРАСЫВАЕМ, просто показываем
        if (!companySnap.hasData || !companySnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Фирма не найдена')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => _leaveToRoleChoice(context),
                  child: const Text('Выйти / выбрать другую фирму'),
                ),
              ),
            ),
          );
        }

        final cData = companySnap.data!.data() ?? {};
        if ((cData['deleted'] ?? false) == true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Фирма удалена')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => _leaveToRoleChoice(context),
                  child: const Text('Выйти / выбрать другую фирму'),
                ),
              ),
            ),
          );
        }

        // 4) Теперь проверяем участника
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: companyMemberDoc(companyId, uid).snapshots(),
          builder: (c2, memberSnap) {
            if (memberSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // Ошибка чтения участника — НЕ СБРАСЫВАЕМ
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

            
// Если документа участника нет — автоматически выходим на выбор фирмы
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
  final Set<int> _visitedTabs = {1};

  void _onPendingWidgetAction() {
    if (pendingWidgetAction.value != null && mounted) {
      setState(() { index = 3; _visitedTabs.add(3); });
    }
  }
  int _toolsOnHandsCount = 0;
  int _pendingCount = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _toolsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;

  @override
  void initState() {
    super.initState();
    pendingWidgetAction.addListener(_onPendingWidgetAction);
    _onPendingWidgetAction();
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
    pendingWidgetAction.removeListener(_onPendingWidgetAction);
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
      _visitedTabs.contains(0) ? PeoplePage(companyId: widget.companyId, role: widget.role) : const SizedBox.shrink(),
      _visitedTabs.contains(1) ? ToolsPage(companyId: widget.companyId, role: widget.role) : const SizedBox.shrink(),
      _visitedTabs.contains(2) ? MovesPage(companyId: widget.companyId, role: widget.role) : const SizedBox.shrink(),
      _visitedTabs.contains(3) ? CompanyProfilePage(companyId: widget.companyId, role: widget.role, onLogout: _logout) : const SizedBox.shrink(),
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
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() { index = i; _visitedTabs.add(i); }),
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
      // ✅ В лимит считаем ТОЛЬКО active (уволенные/неактивные — не считаем)
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
                final title = '${Plans.uiName(p)}${usd > 0 ? ' — \$$usd / ${i18n.t('perMonth')}' : ' — Free'}';
                final gps = Plans.gpsEnabled(p) ? i18n.t('gpsIncluded') : i18n.t('gpsNotIncluded');
                final subtitle = '${i18n.t('peopleLimitLabel')}: ${Plans.peopleLimit(p)}  ·  $gps';
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
    return '—';
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
        final String validUntilText = validUntil == null ? '—' : _fmtDate(validUntil);

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
                Text('${i18n.t('planLabel')}: $planName${priceUsd > 0 ? ' — \$$priceUsd / ${i18n.t('perMonth')}' : ' — Free'}'),
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
                    final usedText = used == null ? '…' : '$used / $limit';
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
    final i18n = I18n(AppState.of(context).lang.value);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('leaveCompany')),
        content: Text(i18n.t('leaveCompanyConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.t('leaveCompany')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      await companyMemberDoc(companyId, u.uid).set({
        'status': 'left',
        'leftAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await userDoc().set({'activeCompanyId': FieldValue.delete()}, SetOptions(merge: true));
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

  Future<void> _deleteMyAccount(BuildContext context) async {
    final i18n = I18n(AppState.of(context).lang.value);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('deleteAccountTitle')),
        content: Text(i18n.t('deleteAccountText')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.t('deleteAccount')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    try {
      await userDoc(uid).delete();
    } catch (_) {}
    try {
      await user.delete();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
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

        // ✅ РЕДАКТИРОВАТЬ МОЙ ПРОФИЛЬ (в любой момент)
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileFormPage(isEdit: true)),
          ),
          icon: const Icon(Icons.edit),
          label: Text(i18n.t('editMyProfile')),
        ),

        const SizedBox(height: 8),

        // ✅ ПРИВЯЗАТЬ / СМЕНИТЬ ПАРОЛЬ ДЛЯ ПК
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

        // ✅ ЗАЯВКИ (OWNER/ADMIN)
        if (isAdmin) ...[
          Text(i18n.t('requests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          JoinRequestsCard(companyId: companyId),
          const SizedBox(height: 12),
        ],

        // ✅ СПИСОК СОТРУДНИКОВ (OWNER/ADMIN) — сворачиваемый
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

        // --- КНОПКА НАЧАЛА/ЗАВЕРШЕНИЯ СМЕНЫ (все пользователи) ---
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

        // --- МОИ СМЕНЫ (все пользователи) ---
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

        // --- ВСЕ ОБЪЕКТЫ (все пользователи) — сворачиваемый инлайн ---
        WorkSitesInlineCard(companyId: companyId),
        const SizedBox(height: 8),

        // --- ВСЕ СМЕНЫ + УПРАВЛЕНИЕ ОБЪЕКТАМИ (только admin/owner) ---
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
          // Управление объектами — сворачиваемый инлайн
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
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _deleteMyAccount(context),
          icon: const Icon(Icons.delete_forever),
          label: Text(i18n.t('deleteAccount')),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async => onLogout(),
          child: Text(i18n.t('logout')),
        ),
      ],
    );
  }
}

/// ✅ Список сотрудников (для владельца/админа) с поиском и сортировкой
class EmployeesListCard extends StatefulWidget {
  final String companyId;
  const EmployeesListCard({super.key, required this.companyId});

  @override
  State<EmployeesListCard> createState() => _EmployeesListCardState();
}

class _EmployeesListCardState extends State<EmployeesListCard> { Stream<QuerySnapshot<Map<String, dynamic>>>? _membersStream;
  String _searchQuery = "";

  Future<List<Map<String, dynamic>>>? _profilesFuture;
  String _profilesFutureKey = '';

  Future<List<Map<String, dynamic>>> _loadProfiles(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs) {
    final key = memberDocs.map((m) => m.id).join(',');
    if (_profilesFuture != null && _profilesFutureKey == key) {
      return _profilesFuture!;
    }
    _profilesFutureKey = key;
    _profilesFuture = () async {
      final peopleSnap = await companyPeopleRef(widget.companyId).get();
      final linkedUids = <String>{};
      for (final p in peopleSnap.docs) {
        final uid = (p.data()['linkedUserId'] ?? '').toString();
        if (uid.isNotEmpty) linkedUids.add(uid);
      }

      final out = await Future.wait(memberDocs.map((m) async {
        final uid = m.id;
        final roleRaw = (m.data()['role'] ?? 'employee').toString();
        final role = normalizeRole(roleRaw);

        final u = await userDoc(uid).get();
        final ud = u.data() ?? {};

        final first = (ud['firstName'] ?? '').toString();
        final last = (ud['lastName'] ?? '').toString();
        final phone = (ud['phone'] ?? '').toString();
        final position = (ud['position'] ?? '').toString();

        final name = (first + ' ' + last).trim().isEmpty ? uid : (first + ' ' + last).trim();

        return <String, dynamic>{
          'uid': uid,
          'roleRaw': roleRaw,
          'role': role,
          'name': name,
          'phone': phone,
          'position': position,
          'isLinked': linkedUids.contains(uid),
        };
      }));

      out.sort((a, b) => normText(a['name']).compareTo(normText(b['name'])));
      return out;
    }();
    return _profilesFuture!;
  }

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
        final canEditProfiles = isOwner || isAdmin; // ✅ анкеты редактирует владелец и админ

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _membersStream ??= companyMembersRef(widget.companyId).where('status', isEqualTo: 'active').limit(200).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final memberDocs = snapshot.data!.docs;

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadProfiles(memberDocs),
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
                              // ✅ владелец назначает роль
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
      _toast(context, 'Сотрудник подтверждён');
    } catch (e) {
      _toast(context, 'Ошибка подтверждения: $e');
    }
  }

  Future<void> _decline(BuildContext context, String uid) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.delete(companyJoinRequestsRef(companyId).doc(uid));
      batch.delete(companyMemberDoc(companyId, uid));

      await batch.commit();
      _toast(context, 'Заявка отклонена');
    } catch (e) {
      _toast(context, 'Ошибка отклонения: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: companyJoinRequestsRef(companyId)
          .orderBy('createdAt', descending: true)
          .limit(50).snapshots(),
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
                            fullName.isEmpty ? 'Без имени' : fullName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            phone.isEmpty ? 'Телефон не указан' : phone,
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

class _PeoplePageState extends State<PeoplePage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _peopleStream;
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
          title: const Text('Лимит'),
          content: Text('В вашем тарифе максимум $limit записей. Перейдите на тариф выше.'),
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
      stream: _peopleStream ??= companyPeopleRef(widget.companyId).limit(200).snapshots(),
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
                ? '${docType == 'object' ? i18n.t('personTypeObject') : i18n.t('personTypePerson')} • ${status == 'fired' ? i18n.t('empStatusFired') : i18n.t('objectCompleted')}'
                : (type == 'object'
                    ? (status == 'completed' ? i18n.t('objectCompleted') : i18n.t('empStatusActive'))
                    : (status == 'fired' ? i18n.t('empStatusFired') : i18n.t('empStatusActive')));

            return ListTile(
              title: Text('${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim()),
              subtitle: Text(pos.isEmpty ? statusLabel : '$pos • $statusLabel'),
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
                        ? FloatingActionButton(heroTag: 'fab_people', onPressed: _addPersonDialog, child: const Icon(Icons.add))
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
              // Тип — можно переключить между человеком и объектом
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

class _ToolsPageState extends State<ToolsPage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _toolsStream;
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

    final doc = pw.Document(theme: await _pdfTheme());
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

  // PNG — share QR as image file
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
                        subject: inv.isNotEmpty ? '$toolName — $inv' : toolName,
                        sharePositionOrigin: Rect.fromLTWH(0, 400, 100, 50),
                      );
  }

  // Thermal label PDF — 57×32mm (Brother QL / Zebra format)
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
    final doc = pw.Document(theme: await _pdfTheme());
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

  // A4 grid — all tools, 3 per row
  Future<void> _printAllQrA4(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final doc = pw.Document(theme: await _pdfTheme());
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
                '$toolName${inv.isNotEmpty ? ' — $inv' : ''}',
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
                Expanded(child: Text('Внешний QR: $customQr',
                    style: const TextStyle(fontSize: 12, color: Colors.green))),
                IconButton(
                  icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
                  tooltip: 'Отвязать QR',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await companyToolsRef(widget.companyId).doc(toolId).update(
                        {'customQr': FieldValue.delete()});
                    _toast('Внешний QR отвязан');
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
                    _qrActionBtn(Icons.qr_code_scanner, customQr != null && customQr.isNotEmpty ? '↺ QR' : '+ QR', () { Navigator.pop(ctx); _linkCustomQr(toolId, toolName, inv); }),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
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
        hint: 'Наведите на существующую наклейку инструмента',
      )),
    );
    if (rawValue == null || !mounted) return;

    if (rawValue.startsWith('toolkeeper:')) {
      _toast('Это уже QR-код ToolKeeper — внешняя наклейка не нужна');
      return;
    }

    // Проверяем не занят ли код другим инструментом
    final existing = await companyToolsRef(widget.companyId)
        .where('customQr', isEqualTo: rawValue)
        .limit(1)
        .get();
    if (!mounted) return;
    if (existing.docs.isNotEmpty && existing.docs.first.id != toolId) {
      _toast('Этот QR уже привязан к инструменту "${existing.docs.first.data()['name'] ?? ''}"');
      return;
    }

    await companyToolsRef(widget.companyId).doc(toolId).set(
      {'customQr': rawValue},
      SetOptions(merge: true),
    );
    _toast('QR-наклейка привязана к $toolName — $inv');
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
                    ? FloatingActionButton(heroTag: 'fab_tools', onPressed: _addToolDialog, child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          // 🔍 ПОЛЕ ПОИСКА (ИНСТРУМЕНТЫ)
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
          // Строка сортировки + печать всех QR
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
              FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: companyToolsRef(widget.companyId).get(),
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
                      stream: _toolsStream ??= companyToolsRef(widget.companyId).orderBy('createdAt', descending: true).limit(5000).snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final docs = s.data!.docs;
                if (docs.isEmpty) return Center(child: Text(i18n.t('noTools')));

                // Группировка с фильтрацией
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groups = {};
                for (final d in docs) {
                  final name = (d.data()['name'] ?? 'Без названия').toString();
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
                // 'date' — уже отсортировано потоком (createdAt desc), порядок групп сохраняется
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
                        initiallyExpanded: _searchQuery.isNotEmpty, // Раскрываем при поиске
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
                          final subtitleText = note.isEmpty ? statusLabel : '$statusLabel • $note';

                          return ListTile(
                            title: Row(children: [
                              Text(inv),
                              if (hasCustomQr) ...[
                                const SizedBox(width: 6),
                                const Tooltip(
                                  message: 'Внешний QR привязан',
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
                                    IconButton(icon: const Icon(Icons.qr_code, size: 20), tooltip: 'QR-код', onPressed: () => _showQrDialog(d.id, (d.data()['name'] ?? '').toString(), inv, hasCustomQr ? customQr : null)),
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


  String _normTools(String s) => s.toLowerCase().replaceAll('ё', 'е').trim();

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

class _HistoryTabState extends State<HistoryTab> { Stream<QuerySnapshot<Map<String, dynamic>>>? _movesStream;
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
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], sharePositionOrigin: Rect.fromLTWH(0, 400, 100, 50));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл сохранён: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
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
    final actTitle = isIssue ? 'АКТ ВЫДАЧИ ИНСТРУМЕНТА' : 'АКТ ВОЗВРАТА ИНСТРУМЕНТА';

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
                pw.Text('№ $shortId  от  $dd', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 32),
          _actRow('Инструмент:', toolName),
          _actRow('Инвентарный №:', inv.isNotEmpty ? inv : '—'),
          pw.SizedBox(height: 16),
          _actRow(isIssue ? 'Передаёт:' : 'Сдаёт:', transferrer),
          _actRow(isIssue ? 'Получает:' : 'Принимает:', receiver),
          pw.SizedBox(height: 16),
          _actRow('Состояние при передаче:', '______________________________'),
          pw.SizedBox(height: 40),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(isIssue ? 'Передал:' : 'Принял:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(isIssue ? 'Получил:' : 'Сдал:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
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
            stream: _movesStream ??= companyMovesRef(widget.companyId).orderBy('createdAt', descending: true).limit(200).snapshots(),
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
                    title: Text('$title: $tool — $inv'),
                    subtitle: Text('$person${pos.isNotEmpty ? " ($pos)" : ""}${dateStr.isNotEmpty ? " · $dateStr" : ""}'),
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

/// ---------- TAB: Reports (ОТЧЕТЫ)
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
    x = x.replaceAll('ё', 'е');
    // UA
    x = x.replaceAll('є', 'е');
    x = x.replaceAll('і', 'и');
    x = x.replaceAll('ї', 'и');
    // PL diacritics (basic)
    x = x.replaceAll('ą', 'a').replaceAll('ć', 'c').replaceAll('ę', 'e')
         .replaceAll('ł', 'l').replaceAll('ń', 'n').replaceAll('ó', 'o')
         .replaceAll('ś', 's').replaceAll('ż', 'z').replaceAll('ź', 'z');
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
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], sharePositionOrigin: Rect.fromLTWH(0, 400, 100, 50));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл сохранён: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
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
    // Получаем название компании
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
    // Получаем название компании
    String companyName = 'ToolKeeper';
    try {
      final companySnap = await companyDoc(widget.companyId).get();
      if (companySnap.exists) {
        companyName = (companySnap.data()?['name'] ?? 'ToolKeeper').toString();
      }
    } catch (_) {}

    final excel = Excel.createExcel();
    final sheet = excel['Report'];

    // Добавляем заголовок с названием компании
    sheet.appendRow([TextCellValue('$companyName — $toolName')]);
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
            'НАКЛАДНАЯ НА ВЫДАЧУ ИНСТРУМЕНТА',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('от $dd', style: const pw.TextStyle(fontSize: 11))),
        pw.SizedBox(height: 16),
        pw.Text(
          'Получатель: $personName${personPos.isNotEmpty ? " ($personPos)" : ""}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 16),
        pw.Table.fromTextArray(
          headers: ['№', 'Инструмент', 'Инв. №', 'Дата выдачи'],
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
          'Итого единиц: ${rows.length}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
        ),
        pw.SizedBox(height: 40),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Выдал:', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 24),
                  pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Получил:', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 24),
                  pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
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
                    // Экспорт склада
                    final rows = <Map<String, dynamic>>[];
                    for (final e in last.entries) {
                      final m = e.value;
                      if ((m['type'] ?? '') == 'out') continue; // Пропускаем выданные
                      rows.add({
                        'toolName': m['toolName'] ?? '',
                        'inv': m['inv'] ?? '',
                        'where': i18n.t('warehouse'),
                        'issuedAt': '',
                      });
                    }
                    // Добавляем инструменты без движений
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
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
                    // Экспорт склада PDF
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
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
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: companyToolsRef(widget.companyId).get(),
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
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: companyPeopleRef(widget.companyId).get(),
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
                        title: Text('$toolName • ${i18n.t('inv')}: $inv'),
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
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: companyToolsRef(widget.companyId).get(),
      builder: (c, toolsSnap) {
        if (!toolsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: companyMovesRef(widget.companyId).get(),
          builder: (c, movesSnap) {
            if (!movesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Вычисляем последнее движение по каждому инструменту
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

            // Фильтруем свободные инструменты
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
                // Нет движений — свободен
                freeTools.add({
                  'toolId': toolId,
                  'toolName': toolName,
                  'inv': inv,
                });
              } else {
                final lastType = (lastMove['type'] ?? '').toString();
                if (lastType != 'out') {
                  // Последнее движение — возврат, значит свободен
                  freeTools.add({
                    'toolId': toolId,
                    'toolName': toolName,
                    'inv': inv,
                  });
                }
              }
            }

            // Группируем по названию
            final Map<String, List<Map<String, dynamic>>> grouped = {};
            for (final t in freeTools) {
              final name = t['toolName'] as String;
              grouped.putIfAbsent(name, () => []).add(t);
            }

            // Сортируем названия
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
                    // Сортируем инвентарные номера внутри группы
                    items.sort((a, b) => _invSort(a['inv'] as String, b['inv'] as String));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                          '$name  ×${items.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        children: items.map((t) {
                          final inv = t['inv'] as String;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined, size: 20),
                            title: Text(inv.isNotEmpty ? inv : '—'),
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

// Страница управления объектами (для админа)
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
        stream: companySitesRef(widget.companyId).limit(100).snapshots(),
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
                subtitle: Text('$address\nGPS: $interval мин'),
                onTap: () async {
              final lat = (data['latitude'] as num?)?.toDouble();
              final lng = (data['longitude'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=' + lat.toString() + ',' + lng.toString());
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              }
            },
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
            floatingActionButton: FloatingActionButton(heroTag: 'fab_sites',
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
                  child: Text('$v мин'),
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
                    setDlg(() => err = '${i18n.t('siteName')} — обязательное поле');
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

// Виджет кнопки начала/конца смены
class ShiftButton extends StatefulWidget {
  final String companyId;
  final String userId;
  final String userName;
  
  const ShiftButton({super.key, required this.companyId, required this.userId, required this.userName});
  
  @override
  State<ShiftButton> createState() => _ShiftButtonState();
}

class _ShiftButtonState extends State<ShiftButton> {
  // ID анкеты, к которой привязан пользователь (null = не привязан)
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

  // Реальный ID для поиска смен: анкета (если привязан) или uid
  String get _queryPersonId => _linkedPersonId ?? widget.userId;

  bool? _lastWidgetActive;
  String? _lastWidgetSiteName;
  int? _lastWidgetStartMillis;

  void _syncShiftWidget(List<QueryDocumentSnapshot<Map<String, dynamic>>> activeShifts) {
    try {
      final active = activeShifts.isNotEmpty;
      final data = active ? activeShifts.first.data() : null;
      final siteName = (data?['siteName'] ?? '').toString();
      final startTs = data?['startTime'];
      final startMillis = startTs is Timestamp ? startTs.millisecondsSinceEpoch : 0;
      if (_lastWidgetActive == active && _lastWidgetSiteName == siteName && _lastWidgetStartMillis == startMillis) {
        return;
      }
      _lastWidgetActive = active;
      _lastWidgetSiteName = siteName;
      _lastWidgetStartMillis = startMillis;
      HomeWidget.saveWidgetData<bool>('shiftActive', active);
      HomeWidget.saveWidgetData<String>('shiftSiteName', siteName);
      HomeWidget.saveWidgetData<int>('shiftStartMillis', startMillis);
      HomeWidget.updateWidget(qualifiedAndroidName: 'com.toolkeeper.tooltrack_app.ShiftWidgetProvider', iOSName: 'ShiftWidget');
    } catch (_) {}
  }

  void _handlePendingWidgetAction(List<QueryDocumentSnapshot<Map<String, dynamic>>> activeShifts) {
    final action = pendingWidgetAction.value;
    if (action == null || !mounted) return;
    if (action == 'start' && activeShifts.isEmpty) {
      pendingWidgetAction.value = null;
      _startShift();
    } else if (action == 'end' && activeShifts.isNotEmpty) {
      pendingWidgetAction.value = null;
      _endShift(activeShifts.first.id);
    }
  }

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
        _syncShiftWidget(activeShifts);
        WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingWidgetAction(activeShifts));

        if (activeShifts.isEmpty) {
          return ElevatedButton(
            onPressed: _startShift,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(i18n.t('startShift')),
          );
        }

        // Одна или несколько активных смен — показываем все с кнопками завершения
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
                    'Активных смен: ${activeShifts.length}',
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
    try {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);

    // Одноразовое предупреждение об оптимизации батареи (Samsung/Xiaomi)
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('battery_tip_shown') ?? false;
      if (!shown && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('GPS-трекинг'),
            content: const Text(
              'Для стабильной работы GPS отключите оптимизацию батареи:\n\n'
              'Настройки → Приложения → ToolKeeper → Батарея → Без ограничений\n\n'
              'Без этого Samsung/Xiaomi может отключить GPS через несколько минут.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Понятно'),
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

    // 1. Последняя известная позиция (без задержки) для фильтрации объектов
    Position? lastPos;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        lastPos = await Geolocator.getLastKnownPosition();
      }
    } catch (_) {}
    if (!mounted) return;

    // 2. Показываем только объекты в радиусе 5000 м (или все, если GPS недоступен)
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

    // 3. Выбрать объект
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

    // Lookup linked person record — required to start a shift
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
      // v23: removed alreadyHaveActiveShift guard (allow new shift)
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

    // 4. GPS — запрашиваем разрешение БЕЗУСЛОВНО (Android 14+: без разрешения foreground service с типом location крашит нативно)
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
        if (!(await Geolocator.isLocationServiceEnabled())) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Включите GPS (геолокацию) на устройстве')));
          return;
        } else if (gpsPermission == LocationPermission.denied || gpsPermission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('gpsPermissionDenied'))));
          return;
        } else {
          final pos = await Geolocator.getCurrentPosition(
                                                desiredAccuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 25),
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
                  '${i18n.t('distance')}: ${distance.toStringAsFixed(0)} м\n'
                  '${i18n.t('siteRadius')}: ${siteRadius.toStringAsFixed(0)} м',
                ),
                actions: [
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('ok'))),
                ],
              ),
            );
            return; // жёсткий блок
          }
        }
      } catch (e) {
                try {
                            final lastPos = await Geolocator.getLastKnownPosition();
                            if (lastPos != null) {
                                          userLat = lastPos.latitude;
                                          userLng = lastPos.longitude;
                            }
                } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS: ' + e.toString())));
        }
      }
    }

    // 5. Записать смену
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

    // Запланировать уведомления — через 10ч и 12ч если смена не закрыта
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

    // Запустить foreground service GPS-трекинга (только если разрешение выдано)
    if (gpsPermission != LocationPermission.denied &&
        gpsPermission != LocationPermission.denied &&
        gpsPermission != LocationPermission.deniedForever) {

      // Проверяем тариф — GPS только с Про и выше
      String companyPlan = Plans.free;
      bool gpsPlanOverride = false;
      try {
        final compSnap = await companyDoc(widget.companyId).get();
        final compData = compSnap.data();
        companyPlan = (compData?['plan'] as String?) ?? (compData?['planId'] as String?) ?? Plans.free;
        if ((compData?['billingMode'] as String?) == 'free_unlimited' || companyPlan == 'unlimited') {
          gpsPlanOverride = true;
        }
      } catch (_) {}
      if (!Plans.gpsEnabled(companyPlan) && !gpsPlanOverride) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(i18n.t('gpsNotInPlan')),
            duration: const Duration(seconds: 4),
          ));
        }
        // GPS не запускаем, смена уже создана
      } else {

      // Проверяем уведомления — без них startForeground() крашит весь процесс (Android 14+)
      final androidNotifImpl = _localNotifs.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      var notifEnabled = await androidNotifImpl?.areNotificationsEnabled() ?? true; if (!notifEnabled) { try { await androidNotifImpl?.requestNotificationsPermission(); } catch (_) {} await Future.delayed(const Duration(milliseconds: 400)); notifEnabled = await androidNotifImpl?.areNotificationsEnabled() ?? true; }

      if (!notifEnabled && mounted) { try { FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': 'android', 'tag': 'GPS_START', 'msg': 'blocked_notif_disabled', 'err': ''}); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('GPS-трекинг недоступен: включи уведомления для ToolKeeper в настройках'),
          duration: Duration(seconds: 5),
        ));
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('shift_companyId', widget.companyId);
        await prefs.setString('shift_shiftId', shiftRef.id);

        // Запуск сервиса — fire-and-forget, не блокирует UI
        final capturedCompany = widget.companyId;
        final capturedShift = shiftRef.id;
        final capturedInterval = siteGpsInterval;
        await prefs.setInt('shift_gpsInterval', capturedInterval);
        // Save Firebase auth token for GPS background service
        String? capturedIdToken;
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            capturedIdToken = await user.getIdToken(true);
            if (capturedIdToken != null) await prefs.setString('shift_idToken', capturedIdToken!);
          }
        } catch (e) {
          print('[GPS] Token save error: $e');
        }
        Future(() async {
          try {
try { FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': 'android', 'tag': 'GPS_START', 'msg': 'attempt_start_service', 'err': ''}); } catch (_) {}             await _initBackgroundService();
            final bgService = FlutterBackgroundService();
            await bgService.startService();
            await Future.delayed(const Duration(milliseconds: 2000));
            bgService.invoke('startTracking', {
              'companyId': capturedCompany,
              'shiftId': capturedShift,
              'interval': capturedInterval,
              'idToken': capturedIdToken ?? '',
            });
                        try {
                                        final running = await bgService.isRunning();
                                        await FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': Platform.isAndroid ? 'android' : 'ios', 'tag': 'GPS_ISRUNNING', 'msg': running.toString(), 'err': ''});
                        } catch (e) { try { FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': Platform.isAndroid ? 'android' : 'ios', 'tag': 'GPS_ISRUNNING_ERR', 'msg': e.toString(), 'err': ''}); } catch (_) {} }
          } catch (e) {
            FirebaseCrashlytics.instance.recordError(e, StackTrace.current, fatal: false);
                        try { FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': Platform.isAndroid ? 'android' : 'ios', 'tag': 'GPS_START_ERROR2', 'msg': e.toString(), 'err': ''}); } catch (_) {}
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка запуска GPS-сервиса: $e')));
            }
          }
        });
      }
      } // end else gpsEnabled
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(i18n.t('shiftStarted'))));
    }
  
    } catch (e, st) {
      try { FirebaseCrashlytics.instance.recordError(e, st, fatal: false); } catch (_) {}      try { FirebaseFirestore.instance.collection('ios_debug_logs').add({'ts': DateTime.now().toIso8601String(), 'platform': Platform.isAndroid ? 'android' : 'ios', 'tag': 'GPS_START_ERROR', 'msg': e.toString(), 'err': st.toString()}); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка запуска смены: ' + e.toString())));
      }
    }
  }
  
  Future<void> _endShift(String shiftId) async {
    final appState = AppState.of(context);
    final i18n = I18n(appState.lang.value);

    // Загружаем данные смены и объекта заранее
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
                                  desiredAccuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 25),
                    );
                    endLat = pos.latitude;
                    endLng = pos.longitude;
                    if ((siteLat != 0.0 || siteLng != 0.0) && siteRadius > 0) {
                      distFromSite = Geolocator.distanceBetween(
                          endLat, endLng, siteLat, siteLng);
                    }
                  } catch (_) {
                            try {
                                        final lastPos = await Geolocator.getLastKnownPosition();
                                        if (lastPos != null) {
                                                      endLat = lastPos.latitude;
                                                      endLng = lastPos.longitude;
                                        }
                            } catch (_) {}
                  }

                  String report = reportController.text.trim();

                  // Отчёт обязателен
                  if (report.isEmpty) {
                    setDlg(() => saving = false);
                    if (ctx2.mounted) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(i18n.t('reportRequired'))),
                      );
                    }
                    return;
                  }

                  // Предупреждение если за пределами зоны (не блокируем)
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
                            '${i18n.t('distance')}: $dist м\n'
                            '${i18n.t('siteRadius')}: $rad м',
                          ),
                          actions: [
                            FilledButton(
                                onPressed: () => Navigator.pop(c),
                                child: Text(i18n.t('ok'))),
                          ],
                        ),
                      );
                    }
                    // Автоматически добавляем метку в отчёт
                    final note =
                        '⚠️ ${i18n.t('distance')}: $dist м (${endLat.toStringAsFixed(5)}, ${endLng.toStringAsFixed(5)})';
                    report = report.isEmpty ? note : '$report\n$note';
                  }

                  await companyTimesheetsRef(widget.companyId).doc(shiftId).update({
                    'endTime': Timestamp.now(),
                    'endLocation': {'lat': endLat, 'lng': endLng},
                    'totalHours': hours,
                    'workReport': report,
                  });

                  // Отменить запланированные напоминания
                  await _localNotifs.cancel(101);
                  await _localNotifs.cancel(102);

                  // Остановить foreground service GPS-трекинга
                  
                  try {
                    FlutterBackgroundService().invoke(
                      Platform.isAndroid ? 'stopService' : 'stopTracking');
                    await Future.delayed(const Duration(milliseconds: 500));
                  } catch (_) {}
                  // Очистить prefs смены (iOS + Android)
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('shift_companyId');
                    await prefs.remove('shift_shiftId'); try { await HomeWidget.saveWidgetData<bool>('shiftActive', false); await HomeWidget.updateWidget(qualifiedAndroidName: 'com.toolkeeper.tooltrack_app.ShiftWidgetProvider', iOSName: 'ShiftWidget'); _lastWidgetActive = false; } catch (_) {}
                  } catch (_) {}

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(i18n.t('shiftEnded'))));
                  }
                } catch (e) {
                  setDlg(() => saving = false);
                  try { Navigator.pop(ctx); } catch (_) {}
                  if (ctx2.mounted) {
                    ScaffoldMessenger.of(ctx2)
                        .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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

// Страница истории смен
class TimesheetsPage extends StatefulWidget {
  final String companyId;
  final String? personId;
  final bool isAdmin;

  const TimesheetsPage({super.key, required this.companyId, this.personId, this.isAdmin = false});

  @override
  State<TimesheetsPage> createState() => _TimesheetsPageState();
}

class _TimesheetsPageState extends State<TimesheetsPage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedStream;
  String? _monthFilter;
  String? _siteFilter;
  String? _personFilter;
  List<Map<String, dynamic>> _sites = [];
  bool _exporting = false; DateTime? _dayFilter; String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadSites(); _dayFilter = DateTime.now();
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

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream => _cachedStream ??= _computeStream(); Stream<QuerySnapshot<Map<String, dynamic>>> _computeStream() {
    // For personId queries avoid orderBy — it requires a composite Firestore index.
    // Sort client-side instead.
    if (widget.personId != null) {
      return companyTimesheetsRef(widget.companyId)
          .where('personId', isEqualTo: widget.personId)
          .snapshots();
    }
    return companyTimesheetsRef(widget.companyId)
      .orderBy('startTime', descending: true)
        .limit(100) // v25: sorted server-side by startTime so newest shifts are always included
      .snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var result = docs.toList();
        if (true) { // v25: sort applies to all views now (was: only when personId != null) so admin "Все табели" view is sorted too
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
    if (_dayFilter != null) { result = result.where((d) { final dt = (d.data()['startTime'] as Timestamp?)?.toDate(); return dt != null && dt.year == _dayFilter!.year && dt.month == _dayFilter!.month && dt.day == _dayFilter!.day; }).toList(); } if (_statusFilter != null) { result = result.where((d) { final isActive = d.data()['endTime'] == null; return _statusFilter == 'active' ? isActive : !isActive; }).toList(); } if (_personFilter != null) {
      result = result.where((d) => d.data()['personId'] == _personFilter).toList();
    }
    return result;
  }

  String _fmtDay(DateTime d, I18n i18n) { final now = DateTime.now(); if (d.year == now.year && d.month == now.month && d.day == now.day) return i18n.t('today'); String p(int n) => n.toString().padLeft(2, '0'); return p(d.day) + '.' + p(d.month) + '.' + d.year.toString(); } String _fmtMonth(String ym) {
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
    if (h == 0) return '${m}мин';
    if (m == 0) return '${h}ч';
    return '${h}ч ${m}мин';
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
        await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], sharePositionOrigin: Rect.fromLTWH(0, 400, 100, 50));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл сохранён: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
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
      DateTime? dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is String) {
        dt = DateTime.tryParse(ts);
      }
      if (dt != null) {
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

    int violations = 0;
    for (int vi = 1; vi < pings.length; vi++) {
            if (pings[vi]['outside'] == true && pings[vi - 1]['outside'] != true) violations++;
    }

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
              Text('⚠ Выходов из зоны: $violations',
                  style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
            if (hasSite && violations == 0 && pings.isNotEmpty)
              const Text('✓ Всё время в зоне',
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
              final distStr = dist != null ? '  •  ${dist.toStringAsFixed(0)} м' : '';
              return ListTile(
                dense: true,
                leading: Icon(
                  outside ? Icons.warning_amber_rounded : Icons.check_circle,
                  size: 20,
                  color: outside ? Colors.red : Colors.green,
                ),
                title: Text(
                  '$timeStr  ±${acc.toStringAsFixed(0)} м',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка GPS: $e')));
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
          pw.Text('ОТЧЁТ GPS-ТРЕКИНГА',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.SizedBox(height: 12),
          pw.Text('Сотрудник: $personName', style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Объект: $siteName', style: const pw.TextStyle(fontSize: 11)),
          if (dateStr.isNotEmpty)
            pw.Text('Дата: $dateStr', style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Радиус зоны: ${siteRadius.toStringAsFixed(0)} м',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 6),
          pw.Text(
            'Точек: ${pings.length}   •   Выходов из зоны: $violations',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: violations > 0 ? PdfColors.red700 : PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['№', 'Время', 'Широта', 'Долгота', 'До объекта (м)', 'Статус'],
            data: pings.asMap().entries.map((e) {
              final p = e.value;
              final dist = p['dist'] as double?;
              final outside = p['outside'] as bool;
              return [
                '${e.key + 1}',
                p['timeStr'] as String,
                (p['lat'] as double).toStringAsFixed(5),
                (p['lng'] as double).toStringAsFixed(5),
                dist != null ? dist.toStringAsFixed(0) : '—',
                outside ? '⚠ Вне зоны' : '✓ В зоне',
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
            .showSnackBar(SnackBar(content: Text('Ошибка PDF: $e')));
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
      sheet.appendRow([TextCellValue('Сотрудник'), TextCellValue(personName)]);
      sheet.appendRow([TextCellValue('Объект'), TextCellValue(siteName)]);
      sheet.appendRow([TextCellValue('Радиус зоны (м)'), TextCellValue(siteRadius.toStringAsFixed(0))]);
      final violations = pings.where((p) => p['outside'] == true).length;
      sheet.appendRow([
        TextCellValue('Точек: ${pings.length}'),
        TextCellValue('Выходов из зоны: $violations'),
      ]);
      sheet.appendRow([TextCellValue('')]);
      // Table header
      sheet.appendRow([
        TextCellValue('№'),
        TextCellValue('Время'),
        TextCellValue('Широта'),
        TextCellValue('Долгота'),
        TextCellValue('До объекта (м)'),
        TextCellValue('Статус'),
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
          TextCellValue(dist != null ? dist.toStringAsFixed(0) : '—'),
          TextCellValue(outside ? 'Вне зоны' : 'В зоне'),
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
            .showSnackBar(SnackBar(content: Text('Ошибка Excel: $e')));
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
            // Sync home screen widget if this shift belongs to current user
            try {
                      final closedPersonId = (doc.data()['personId'] ?? '').toString();
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      bool isOwnShift = uid.isNotEmpty && uid == closedPersonId;
                      if (!isOwnShift && uid.isNotEmpty) {
                                  try {
                                                final peopleSnap = await companyPeopleRef(widget.companyId)
                                                                  .where('linkedUserId', isEqualTo: uid)
                                                                  .limit(1)
                                                                  .get();
                                                if (peopleSnap.docs.isNotEmpty && peopleSnap.docs.first.id == closedPersonId) {
                                                                isOwnShift = true;
                                                }
                                  } catch (_) {}
                      }
                      if (isOwnShift) {
                                  await HomeWidget.saveWidgetData<bool>('shiftActive', false);
                                  await HomeWidget.updateWidget(qualifiedAndroidName: 'com.toolkeeper.tooltrack_app.ShiftWidgetProvider', iOSName: 'ShiftWidget');
                      }
            } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('shiftClosed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
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
              : '${fmtDate(minDate)} — ${fmtDate(maxDate)}')
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
            pw.Text('Период: $periodStr', style: const pw.TextStyle(fontSize: 11)),
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
              'Итого часов: ${totalHours.toStringAsFixed(2)}',
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
                    pw.Text('Составил:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Утвердил:', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 24),
                    pw.Text('______________________', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('(подпись / Ф.И.О.)', style: const pw.TextStyle(fontSize: 8)),
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
            .showSnackBar(SnackBar(content: Text('Ошибка PDF: $e')));
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
            .showSnackBar(SnackBar(content: Text('Ошибка Excel: $e')));
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
            return Center(child: Text('Ошибка: ${snapshot.error}'));
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
                    onChanged: (v) => setState(() { _monthFilter = v; _dayFilter = null; }),
                  ),
                  const SizedBox(width: 12), OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 16), label: Text(_dayFilter == null ? i18n.t('allDays') : _fmtDay(_dayFilter!, i18n)), onPressed: () async { final picked = await showDatePicker(context: context, initialDate: _dayFilter ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 1), locale: localeForAppLang(AppState.of(context).lang.value)); if (picked != null) { setState(() { _dayFilter = picked; _monthFilter = null; }); } }), if (_dayFilter != null) IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: i18n.t('allDays'), onPressed: () => setState(() => _dayFilter = null)), const SizedBox(width: 12), DropdownButton<String?>(value: _statusFilter, isDense: true, hint: Text(i18n.t('allStatuses')), items: [DropdownMenuItem(value: null, child: Text(i18n.t('allStatuses'))), DropdownMenuItem(value: 'active', child: Text(i18n.t('filterActive'))), DropdownMenuItem(value: 'completed', child: Text(i18n.t('shiftCompleted')))], onChanged: (v) => setState(() => _statusFilter = v)), const SizedBox(width: 12), if (_sites.isNotEmpty) ...[
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
                      '${i18n.t('totalHours')}: ${totalHours.toStringAsFixed(1)} ч (${_fmtDuration(totalHours)})  •  ${i18n.t('shiftsCount')}: ${filtered.length}',
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
                              ? '$personName — $siteName'
                              : siteName),
                          subtitle: Text(isActive
                              ? i18n.t('shiftActive')
                              : '${hours.toStringAsFixed(1)} ч · ${_fmtDuration(hours.toDouble())}  •  ${startTime != null ? _fmt(startTime).substring(0, 10) : ''}'),
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
                                          '${i18n.t('totalHours')}: ${hours.toStringAsFixed(2)} ч (${_fmtDuration(hours.toDouble())})'),
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

// ─────────────────────────────────────────────────────────────
// Диалог добавления / редактирования объекта (shared)
// ─────────────────────────────────────────────────────────────
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
                items: [5, 15, 30, 60].map((v) => DropdownMenuItem(value: v, child: Text('$v мин'))).toList(),
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
                    setDlg(() => err = '${i18n.t('siteName')} — обязательное поле');
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

// ─────────────────────────────────────────────────────────────
// Все объекты — инлайн карточка с поиском (все пользователи)
// ─────────────────────────────────────────────────────────────
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
                  stream: companySitesRef(widget.companyId).limit(100).snapshots(),
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
                                  '${radius > 0 ? '  •  R: ${radius.toStringAsFixed(0)} м' : ''}',
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

// ─────────────────────────────────────────────────────────────
// Управление объектами — инлайн карточка с поиском (admin)
// ─────────────────────────────────────────────────────────────
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
                  stream: companySitesRef(widget.companyId).limit(100).snapshots(),
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
                                  '${address.isNotEmpty ? '$address  •  ' : ''}GPS: $interval мин',
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

// Read-only sites page — visible to ALL users with Google Maps navigation
class WorkSitesReadOnlyPage extends StatelessWidget {
  final String companyId;
  const WorkSitesReadOnlyPage({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('sites'))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: companySitesRef(companyId).limit(100).snapshots(),
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
                          '${radius > 0 ? '  •  ${i18n.t('siteRadius')}: ${radius.toStringAsFixed(0)} м' : ''}',
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
