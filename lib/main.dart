import 'admin_employee_pages.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'admin_employee_pages.dart';


import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// ✅ ОДИН main()
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

/// ===================
/// SIMPLE LANG
/// ===================
enum AppLang { ru, uk, pl, en }

class I18n {
  final AppLang lang;
  const I18n(this.lang);

  static const _dict = <AppLang, Map<String, String>>{
    AppLang.ru: {
      'appTitle': 'ToolTrack',
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
      'owner': 'Владелец фирмы',
      'employee': 'Сотрудник',
      'createCompany': 'Создать фирму',
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
},    AppLang.uk: {
      'appTitle': 'ToolTrack',
      'login': 'Вхід',
      'register': 'Реєстрація',
      'enter': 'Увійти',
      'logout': 'Вийти',
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
      'leaveCompany': 'Вийти / обрати іншу фірму',
      'createCompany': 'Створити фірму',
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
    'employee': 'Працівник',
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
    'owner': 'Власник',
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
},
    AppLang.pl: {
      'appTitle': 'ToolTrack',
      'login': 'Logowanie',
      'register': 'Rejestracja',
      'enter': 'Zaloguj',
      'logout': 'Wyloguj',
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
      'leaveCompany': 'Wyjdź / wybierz inną firmę',
      'createCompany': 'Utwórz firmę',
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
    'employee': 'Pracownik',
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
    'owner': 'Właściciel',
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
},
    AppLang.en: {
      'appTitle': 'ToolTrack',
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
            home: const AuthGate(),
          );
        },
      ),
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

    final GoogleSignIn googleSignIn = GoogleSignIn(scopes: const ['email']);

    try {
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
            onSelected: (v) => AppState.of(context).lang.value = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppLang.ru, child: Text('Русский')),
              PopupMenuItem(value: AppLang.uk, child: Text('Українська')),
              PopupMenuItem(value: AppLang.pl, child: Text('Polski')),
              PopupMenuItem(value: AppLang.en, child: Text('English')),
            ],
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

      // 3) Если нашли ровно одну — ставим activeCompanyId и идём в фирму
      if (myCompanyIds.length == 1) {
        final companyId = myCompanyIds.first;

        await userDoc().set({
          'activeCompanyId': companyId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => CompanyGate(companyId: companyId)),
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

      // Если нашли — записываем activeCompanyId и идём в фирму
      if (foundCompanyId.isNotEmpty) {
        await userDoc().set(
          {'activeCompanyId': foundCompanyId, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => CompanyGate(companyId: foundCompanyId)),
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
    clothesCtrl.text = (data['clothesSize'] ?? '').toString();
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
            onSelected: (v) => AppState.of(context).lang.value = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppLang.ru, child: Text('Русский')),
              PopupMenuItem(value: AppLang.uk, child: Text('Українська')),
              PopupMenuItem(value: AppLang.pl, child: Text('Polski')),
              PopupMenuItem(value: AppLang.en, child: Text('English')),
            ],
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
      final code = _genCode();

      final doc = await companiesRef().add({
        'name': name,
        'ownerUid': uid,
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
      });

      await inviteCodesRef().doc(code).set({
        'companyId': doc.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await companyMemberDoc(doc.id, uid).set({
        'uid': uid,
        'role': 'owner',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
      });

      await userDoc().set({
        'activeCompanyId': doc.id,
      }, SetOptions(merge: true));

      setState(() => createdCode = code);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => CompanyGate(companyId: doc.id)),
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
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            if (createdCode != null) ...[
              const SizedBox(height: 12),
              Text('${i18n.t('yourInviteCode')}: $createdCode', style: const TextStyle(fontSize: 16)),
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

      final cSnap = await companyDoc(companyId).get();
      if (!cSnap.exists) throw Exception(i18n.t('codeNotFound'));
      final cData = cSnap.data() ?? {};
      if ((cData['deleted'] ?? false) == true) throw Exception(i18n.t('codeNotFound'));

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

            // Если документа участника нет — показываем кнопку выйти
            if (!memberSnap.hasData || !memberSnap.data!.exists) {
              return Scaffold(
                appBar: AppBar(title: const Text('Нет доступа к фирме')),
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

            final m = memberSnap.data!.data() ?? {};
            final status = (m['status'] ?? '').toString();

            if (status != 'active') {
              return PendingPage(companyId: companyId);
            }

            final role = (m['role'] ?? 'worker').toString();
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
          NavigationDestination(icon: const Icon(Icons.swap_horiz), label: i18n.t('issue')),
          NavigationDestination(icon: const Icon(Icons.person), label: i18n.t('profile')),
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
          items: const [
            DropdownMenuItem(value: AppLang.ru, child: Text('Русский')),
            DropdownMenuItem(value: AppLang.uk, child: Text('Українська')),
            DropdownMenuItem(value: AppLang.pl, child: Text('Polski')),
            DropdownMenuItem(value: AppLang.en, child: Text('English')),
          ],
        ),

        const SizedBox(height: 12),

        // ✅ ЗАЯВКИ (OWNER/ADMIN)
        if (isAdmin) ...[
          Text(i18n.t('requests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          JoinRequestsCard(companyId: companyId),
          const SizedBox(height: 12),
        ],

        // ✅ СПИСОК СОТРУДНИКОВ (OWNER/ADMIN)
        if (isAdmin) ...[
          Text(i18n.t('employees'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          EmployeesListCard(companyId: companyId),
          const SizedBox(height: 12),
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

/// ✅ Список сотрудников (для владельца/админа) с поиском и сортировкой
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
        final canEditProfiles = isOwner; // ✅ как раньше: анкеты редактирует владелец

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: companyMembersRef(widget.companyId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final memberDocs = snapshot.data!.docs;

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: () async {
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
                  });
                }

                // ✅ алфавит (с учетом ё -> е)
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

                        final roleText = roleLabel(i18n, roleRaw);

                        return ListTile(
                          leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                          title: Text(position.isNotEmpty ? '$name ($position)' : name),
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

class _PeoplePageState extends State<PeoplePage> {
  String _normPeople(String s) => s.replaceAll('ё','е').trim();
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  String get _role => widget.role.trim();
  bool get isOwner => _role == 'owner';

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _addPersonDialog() async {
    final i18n = I18n(AppState.of(context).lang.value);
    if (!isOwner) {
      _toast(i18n.t('onlyAdmin'));
      return;
    }

    String first = '';
    String last = '';
    String pos = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('addPerson')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    );

    if (ok != true) return;
    if (first.trim().isEmpty || last.trim().isEmpty || pos.trim().isEmpty) return;

    await companyPeopleRef(widget.companyId).add({
      'firstName': first.trim(),
      'lastName': last.trim(),
      'position': pos.trim(),
      'status': 'active',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deletePerson(String id) async {
    if (!isOwner) return;
    await companyPeopleRef(widget.companyId).doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      floatingActionButton: isOwner
          ? FloatingActionButton(onPressed: _addPersonDialog, child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          // 🔍 ПОЛЕ ПОИСКА (ЛЮДИ)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: i18n.t('searchByNameOrPhone'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      setState(() { _searchQuery = ""; _searchController.clear(); });
                    }) 
                  : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: companyPeopleRef(widget.companyId).snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                
                final docs = s.data!.docs.where((d) {
                  final data = d.data();
                  final full = "${data['firstName']} ${data['lastName']}";
                  return full.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) return Center(child: Text(i18n.t('noPeople')));

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final status = (data['status'] ?? 'active').toString();
                    final pos = (data['position'] ?? '').toString();
                    final statusLabel = status == 'fired' ? i18n.t('empStatusFired') : i18n.t('empStatusActive');
                    final subtitleText = pos.isEmpty ? statusLabel : '$pos • $statusLabel';

                    return ListTile(
                      title: Text('${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim()),
                      subtitle: Text(subtitleText),
                      onTap: isOwner ? () => _editPersonDialog(docs[i].id, data) : null,
                      trailing: isOwner
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              PopupMenuButton<String>(
                                tooltip: i18n.t('employeeStatus'),
                                onSelected: (v) async {
                                  if (v == 'fired') {
                                    final cnt = await employeeToolsOnHandsCount(widget.companyId, docs[i].id);
                                    if (cnt > 0) {
                                      _toast(i18n.t('cannotFireHasTools').replaceAll('{n}', '$cnt'));
                                      return;
                                    }
                                  }
                                  await companyPeopleRef(widget.companyId).doc(docs[i].id).set(
                                    {'status': v, 'statusUpdatedAt': FieldValue.serverTimestamp()},
                                    SetOptions(merge: true),
                                  );
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'active', child: Text(i18n.t('empStatusActive'))),
                                  PopupMenuItem(value: 'fired', child: Text(i18n.t('empStatusFired'))),
                                ],
                              ),
                              IconButton(icon: const Icon(Icons.edit), onPressed: () => _editPersonDialog(docs[i].id, data)),
                              IconButton(icon: const Icon(Icons.delete), onPressed: () => _deletePerson(docs[i].id)),
                            ])
                          : null,
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


  Future<void> _editPersonDialog(String personId, Map<String, dynamic> data) async {
    final i18n = I18n(AppState.of(context).lang.value);
    final firstCtrl = TextEditingController(text: (data['firstName'] ?? '').toString());
    final lastCtrl = TextEditingController(text: (data['lastName'] ?? '').toString());
    final posCtrl = TextEditingController(text: (data['position'] ?? '').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.t('editEmployee')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: firstCtrl, decoration: InputDecoration(labelText: i18n.t('firstName'))),
            TextField(controller: lastCtrl, decoration: InputDecoration(labelText: i18n.t('lastName'))),
            TextField(controller: posCtrl, decoration: InputDecoration(labelText: i18n.t('position'))),
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
        .collection('people')
        .doc(personId)
        .set({
      'firstName': firstCtrl.text.trim(),
      'lastName': lastCtrl.text.trim(),
      'position': posCtrl.text.trim(),
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
  String get _role => widget.role.trim().toLowerCase();
  bool get isOwner => _role == 'owner';

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _addToolDialog() async {
    final i18n = I18n(AppState.of(context).lang.value);
    if (!isOwner) {
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
    if (!isOwner) return;
    await companyToolsRef(widget.companyId).doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n(AppState.of(context).lang.value);

    return Scaffold(
      floatingActionButton: isOwner
          ? FloatingActionButton(onPressed: _addToolDialog, child: const Icon(Icons.add))
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
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: companyToolsRef(widget.companyId).orderBy('createdAt', descending: true).snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final docs = s.data!.docs;
                if (docs.isEmpty) return Center(child: Text(i18n.t('noTools')));

                // Группировка с фильтрацией
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groups = {};
                for (final d in docs) {
                  final name = (d.data()['name'] ?? 'Без названия').toString();
                  final inv = (d.data()['inv'] ?? '').toString();
                  
                  // Проверяем совпадение либо в названии, либо в инвентарнике
                  final q = _normTools(_searchQuery);
                  if (q.isEmpty || _normTools(name).contains(q) || _normTools(inv).contains(q)) {
                    groups.putIfAbsent(name, () => []).add(d);
                  }
                }

                final names = groups.keys.toList();
                names.sort((a, b) => _normTools(a).compareTo(_normTools(b)));
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
                          final statusLabel = status == 'disposed'
                              ? i18n.t('toolStatusDisposed')
                              : (status == 'repair' ? i18n.t('toolStatusRepair') : i18n.t('toolStatusActive'));
                          final subtitleText = note.isEmpty ? statusLabel : '$statusLabel • $note';

                          return ListTile(
                            title: Text(inv),
                            subtitle: Text(subtitleText),
                            onTap: isOwner ? () => _editToolDialog(d.id, d.data()) : null,
                            trailing: isOwner
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

class _HistoryTabState extends State<HistoryTab> {
  String _searchQuery = "";

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
                  return ListTile(
                    leading: Icon(
                      type == 'out' ? Icons.arrow_upward : Icons.arrow_downward,
                      color: type == 'out' ? Colors.orange : Colors.green,
                    ),
                    title: Text('$title: $tool — $inv'),
                    subtitle: Text('$person — $pos'),
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
    _tab = TabController(length: 2, vsync: this);
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
          SnackBar(content: Text('Saved: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
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
    // MultiPage fixes: long tables get paginated (no cut-off rows).
    // Embedded Roboto fixes: Cyrillic renders correctly in PDF viewers.
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
            'ToolTrack — $toolName',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
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
    final excel = Excel.createExcel();
    final sheet = excel['Report'];

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
                  } else {
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
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
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
                  } else {
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
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
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
                else
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
              ],
            );
          },
        );
      },
    );
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
    // Load a system font that supports Cyrillic (Android/Windows) to avoid "squares" in PDF.
    final candidates = <String>[];
    if (Platform.isAndroid) {
      candidates.addAll([
        '/system/fonts/Roboto-Regular.ttf',
        '/system/fonts/Roboto-Medium.ttf',
        '/system/fonts/NotoSans-Regular.ttf',
        '/system/fonts/DroidSans.ttf',
      ]);
    } else if (Platform.isWindows) {
      candidates.addAll([
        r'C:\\Windows\\Fonts\\arial.ttf',
        r'C:\\Windows\\Fonts\\segoeui.ttf',
      ]);
    }
    Uint8List? bytes;
    for (final p in candidates) {
      try {
        final f = File(p);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
          break;
        }
      } catch (_) {}
    }
    if (bytes == null) return pw.ThemeData.base();
    final font = pw.Font.ttf(ByteData.view(bytes.buffer));
    return pw.ThemeData.withFont(base: font, bold: font);
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
    clothesCtrl.text = (data['clothesSize'] ?? '').toString();
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