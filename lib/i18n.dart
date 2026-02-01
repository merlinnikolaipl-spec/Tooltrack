class I18n {
  static const Map<String, String> languageNames = {
    'uk': 'Українська',
    'ru': 'Русский',
    'pl': 'Polski',
    'en': 'English',
  };

  static const Map<String, String> supported = {
    'uk': 'uk',
    'ru': 'ru',
    'pl': 'pl',
    'en': 'en',
  };

  static const Map<String, Map<String, String>> _t = {
    'app_title': {
      'uk': 'ToolTrack',
      'ru': 'ToolTrack',
      'pl': 'ToolTrack',
      'en': 'ToolTrack',
    },
    'choose_language': {
      'uk': 'Оберіть мову',
      'ru': 'Выберите язык',
      'pl': 'Wybierz język',
      'en': 'Choose language',
    },
    'continue': {
      'uk': 'Продовжити',
      'ru': 'Продолжить',
      'pl': 'Dalej',
      'en': 'Continue',
    },

    'login_title': {
      'uk': 'Вхід',
      'ru': 'Вход',
      'pl': 'Logowanie',
      'en': 'Sign in',
    },
    'email': {
      'uk': 'Email',
      'ru': 'Email',
      'pl': 'Email',
      'en': 'Email',
    },
    'password': {
      'uk': 'Пароль',
      'ru': 'Пароль',
      'pl': 'Hasło',
      'en': 'Password',
    },
    'login': {
      'uk': 'Увійти',
      'ru': 'Войти',
      'pl': 'Zaloguj',
      'en': 'Login',
    },
    'register': {
      'uk': 'Реєстрація',
      'ru': 'Регистрация',
      'pl': 'Rejestracja',
      'en': 'Register',
    },
    'or': {
      'uk': 'або',
      'ru': 'или',
      'pl': 'lub',
      'en': 'or',
    },
    'sign_in_google': {
      'uk': 'Увійти через Google',
      'ru': 'Войти через Google',
      'pl': 'Zaloguj przez Google',
      'en': 'Sign in with Google',
    },

    'logout': {
      'uk': 'Вийти',
      'ru': 'Выйти',
      'pl': 'Wyloguj',
      'en': 'Logout',
    },

    'searchByNameOrPhone': {
      'uk': 'Пошук по імені або телефону...',
      'ru': 'Поиск по имени или телефону...',
      'pl': 'Szukaj po imieniu lub telefonie...',
      'en': 'Search by name or phone...',
    },

    'editProfile': {
      'uk': 'Редагувати профіль',
      'ru': 'Редактировать профиль',
      'pl': 'Edytuj profil',
      'en': 'Edit profile',
    },

    'setRole': {
      'uk': 'Призначити роль',
      'ru': 'Назначить роль',
      'pl': 'Ustaw rolę',
      'en': 'Set role',
    },

    'role_owner': {
      'uk': 'Власник',
      'ru': 'Владелец',
      'pl': 'Właściciel',
      'en': 'Owner',
    },

    'role_admin': {
      'uk': 'Адміністратор',
      'ru': 'Администратор',
      'pl': 'Administrator',
      'en': 'Admin',
    },

    'role_employee': {
      'uk': 'Працівник',
      'ru': 'Работник',
      'pl': 'Pracownik',
      'en': 'Employee',
    },


    'you_are_logged_in_as': {
      'uk': 'Ви увійшли як:',
      'ru': 'Ты вошёл как:',
      'pl': 'Jesteś zalogowany jako:',
      'en': 'You are signed in as:',
    },

    // --- МЕНЮ ---
    'tab_people': {
      'uk': 'Люди',
      'ru': 'Люди',
      'pl': 'Ludzie',
      'en': 'People',
    },
    'tab_issue': {
      'uk': 'Видача',
      'ru': 'Выдача',
      'pl': 'Wydanie',
      'en': 'Issue',
    },
    'tab_tools': {
      'uk': 'Інструмент',
      'ru': 'Инструмент',
      'pl': 'Narzędzia',
      'en': 'Tools',
    },
    'tab_profile': {
      'uk': 'Профіль',
      'ru': 'Профиль',
      'pl': 'Profil',
      'en': 'Profile',
    },

    'screen_stub': {
      'uk': 'Це заглушка. Далі зробимо функції.',
      'ru': 'Это заглушка. Дальше сделаем функции.',
      'pl': 'To jest wersja testowa. Dalej dodamy funkcje.',
      'en': 'This is a stub. Next we will add features.',
    },

    // =========================
    // ✅ ISSUE / MOVES (для IssueTab)
    // =========================
    'only_admin_issue': {
      'uk': 'Тільки власник/адмін може видавати та приймати інструмент.',
      'ru': 'Только владелец/админ может выдавать и принимать инструмент.',
      'pl': 'Tylko właściciel/admin może wydawać i przyjmować narzędzia.',
      'en': 'Only owner/admin can issue and accept tools.',
    },

    'need_people_first': {
      'uk': 'Спочатку додайте людей',
      'ru': 'Сначала добавь людей',
      'pl': 'Najpierw dodaj ludzi',
      'en': 'Add people first',
    },
    'need_tools_first': {
      'uk': 'Спочатку додайте інструменти',
      'ru': 'Сначала добавь инструменты',
      'pl': 'Najpierw dodaj narzędzia',
      'en': 'Add tools first',
    },

    'no_free_tool': {
      'uk': 'Немає вільного інструмента',
      'ru': 'Нет свободного инструмента',
      'pl': 'Brak wolnego narzędzia',
      'en': 'No free tool available',
    },
    'no_return_tool': {
      'uk': 'Немає інструмента для повернення',
      'ru': 'Нет инструмента для возврата',
      'pl': 'Brak narzędzia do zwrotu',
      'en': 'No tool available to return',
    },

    'issue_title': {
      'uk': 'Видати інструмент',
      'ru': 'Выдать инструмент',
      'pl': 'Wydać narzędzie',
      'en': 'Issue tool',
    },
    'return_title': {
      'uk': 'Прийняти повернення',
      'ru': 'Принять возврат',
      'pl': 'Przyjąć zwrot',
      'en': 'Accept return',
    },

    'person': {
      'uk': 'Людина',
      'ru': 'Человек',
      'pl': 'Osoba',
      'en': 'Person',
    },
    'tool_inv': {
      'uk': 'Інструмент (інв. №)',
      'ru': 'Инструмент (инв. №)',
      'pl': 'Narzędzie (nr inw.)',
      'en': 'Tool (inv. no.)',
    },

    'cancel': {
      'uk': 'Скасувати',
      'ru': 'Отмена',
      'pl': 'Anuluj',
      'en': 'Cancel',
    },
    'save': {
      'uk': 'Зберегти',
      'ru': 'Сохранить',
      'pl': 'Zapisz',
      'en': 'Save',
    },

    'issue_tool': {
      'uk': 'Видати',
      'ru': 'Выдать',
      'pl': 'Wydać',
      'en': 'Issue',
    },
    'return_tool': {
      'uk': 'Повернути',
      'ru': 'Вернуть',
      'pl': 'Zwrócić',
      'en': 'Return',
    },

    'issue_auto_time': {
      'uk': 'Дата і час ставляться автоматично.',
      'ru': 'Дата и время ставятся автоматически.',
      'pl': 'Data i godzina ustawiają się automatycznie.',
      'en': 'Date and time are set automatically.',
    },

    'worker_issue_info': {
      'uk': 'Видача/повернення доступні лише власнику/адміну.\n\n'
          'Але ти можеш дивитися:\n'
          '— весь інструмент\n'
          '— у кого що на руках\n'
          '— всю історію видач',
      'ru': 'Выдача/возврат доступны только владельцу/админу.\n\n'
          'Но ты можешь смотреть:\n'
          '— весь инструмент\n'
          '— у кого что на руках\n'
          '— всю историю выдач',
      'pl': 'Wydawanie/zwrot dostępne tylko dla właściciela/admina.\n\n'
          'Ale możesz podglądać:\n'
          '— wszystkie narzędzia\n'
          '— kto co ma na rękach\n'
          '— całą historię wydań',
      'en': 'Issue/return is available only for owner/admin.\n\n'
          'But you can view:\n'
          '— all tools\n'
          '— who has what\n'
          '— full issue history',
    },
  
    'cannotFireHasTools': {
      'ru': 'Нельзя уволить: у сотрудника на руках {n} инструмент(ов)',
      'uk': 'Не можна звільнити: у працівника на руках {n} інструмент(ів)',
      'pl': 'Nie można zwolnić: pracownik ma {n} narzędzie(a) na stanie',
      'en': 'Cannot fire: employee has {n} tool(s) on hands',
    },
    'cannotIssueFired': {
      'ru': 'Нельзя выдать инструмент уволенному сотруднику',
      'uk': 'Не можна видати інструмент звільненому працівнику',
      'pl': 'Nie można wydać narzędzia zwolnionemu pracownikowi',
      'en': 'Cannot issue tools to a fired employee',
    },
    'cannotSetToolStatusOnHands': {
      'ru': 'Нельзя менять статус инструмента, пока он на руках',
      'uk': 'Не можна змінювати статус інструмента, поки він на руках',
      'pl': 'Nie można zmienić statusu narzędzia, gdy jest na rękach',
      'en': 'Cannot change tool status while it is on hands',
    },

};

  static String tr(String lang, String key) {
    final map = _t[key];
    if (map == null) return key;
    return map[lang] ?? map['ru'] ?? key;
  }
}
