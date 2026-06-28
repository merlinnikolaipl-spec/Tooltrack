# ToolKeeper iOS App — Project Status

## Критические правила (НИКОГДА НЕ НАРУШАТЬ)
- **Restore SHA:** `2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3` — неизменен навсегда
- **ВСЕ правки main.dart — ТОЛЬКО через `scripts/patch_apple_signin.py` ПОСЛЕ restore шага**
- **НЕ использовать Bitrise** (кредиты до июля 2026)
- **НЕ использовать Codemagic** (осталось 7 минут)
- **Использовать ТОЛЬКО** GitHub Actions `.github/workflows/ios-appstore.yml`

---

## Параметры проекта
| Параметр | Значение |
|----------|----------|
| Firebase | `tooltrack-ee0aa` |
| Apple Team ID | `VHF76Z663B` |
| Bundle ID | `com.toolkeeper.app` |
| GitHub repo | `merlinnikolaipl-spec/Tooltrack` |
| Секрет профиля | `BUILD_PROVISION_PROFILE_BASE64` |
| Текущая версия | 1.1.0+179 (build #179) |

---

## Статус задач (28.06.2026)

| Задача | Статус | Build |
|--------|--------|-------|
| GPS даты на iOS | ✅ Исправлено | #159 |
| Иероглифы в UI | ✅ Исправлено | ранее |
| Sign in with Apple (кнопка в UI) | ✅ Кнопка отображается | #179 |
| Sign in with Apple (нативный плагин) | ❌ MissingPluginException | #180 fix |
| GPS данные с iPhone (нет данных) | ❌ В работе | следующая итерация |
| Upload в TestFlight | ✅ Автоматически | #179 |

---

## Текущие баги

### 1. MissingPluginException для sign_in_with_apple
**Симптом:** При нажатии кнопки "Sign in with Apple" появляется ошибка:
`MissingPluginException(No implementation found for method performAuthorizationRequest on channel com.aboutyou.dart_packages.sign_in_with_apple)`

**Причина:** Пакет `sign_in_with_apple` добавлен в `pubspec_overrides.yaml` как dependency_override, но отсутствует в основных `dependencies` в `pubspec.yaml`. Flutter не генерирует регистрацию нативного плагина для overrides-only пакетов.

**Fix (v19 скрипт):** Добавить `sign_in_with_apple: ^6.1.4` в `dependencies` секцию `pubspec.yaml` через patch-скрипт.

### 2. Нет GPS данных с iPhone
**Симптом:** GPS-трек показывает пустой список на iPhone, данные не записываются.
**Причина:** Требует диагностики — возможно проблема с разрешениями Location (NSLocationAlwaysAndWhenInUseUsageDescription) или background mode.
**Статус:** В работе, следующая итерация.

### 3. Лишние сборки в TestFlight (#174, #177, #178)
**Причина:** Диагностические скрипты (v13, v16, v17) не делали патча main.dart, но весь workflow продолжал выполняться включая Upload to TestFlight. Они загружали нетронутую (restore SHA) версию — т.е. приложение БЕЗ Sign in with Apple кнопки.
**Fix:** Скрипты теперь используют `sys.exit(1)` при ошибке, что останавливает workflow.

---

## Архитектура patch-скрипта

### `scripts/patch_apple_signin.py` (v19)
1. Restore `main.dart` и `pubspec.yaml` из SHA `2c64927`
2. Добавить `sign_in_with_apple: ^6.1.4` в `pubspec.yaml dependencies`
3. Добавить import `sign_in_with_apple` в `main.dart`
4. Вставить метод `_signInWithApple()` в `_LoginPageState` (перед `Widget build`)
   - Использует поля `loading` и `error` (без underscore prefix)
5. Вставить Apple кнопку в Column после SizedBox с Google button
   - Google button: `SizedBox(width: double.infinity, child: FilledButton.icon(..._google...))` 
   - Находим `_google` в build() (indent 16), ищем закрывающую `),` при indent ≤ 12
   - Apple кнопка вставляется на indent 12 (уровень Column children)

### Структура виджетов в _LoginPageState (line ~4713)
```
Line 4713 [12]: SizedBox(width: double.infinity,
Line 4714 [14]:   child: FilledButton.icon(
Line 4715 [16]:     icon: const Icon(Icons.login),
Line 4716 [16]: >>> onPressed: loading ? null : _google,
Line 4717 [16]:     label: Text(i18n.t('google')),
Line 4718 [14]:   ),  ← closes FilledButton.icon
Line 4719 [12]: ),    ← closes SizedBox ← INSERT AFTER THIS
Line 4720 [10]: ],    ← closes Column children
```

---

## История сборок (последние)

| Build | Script | Результат | Примечание |
|-------|--------|-----------|------------|
| #166-168 | v6-v8 | ❌ | IndentationError / button not found |
| #169 | v9 | ❌ | Button в wrong class |
| #170 | v10 | ❌ | No ElevatedButton with GoogleSignIn |
| #171 | diag | ✅ | Структура main.dart выявлена |
| #172 | v11 | ❌ | No button containing signIn found |
| #173 | v12 | ❌ | _loading not defined |
| #174 | v13 diag | ✅ | Выявлены имена полей: loading/error |
| #175 | v14 | ❌ | Too many positional args (SizedBox) |
| #176 | v15 | ❌ | Too many positional args (indent 14) |
| #177 | v16 diag | ✅ | 2000 chars context |
| #178 | v17 diag | ✅ | Line numbers + indent map |
| #179 | v18 | ✅ | **Dart compile OK, TestFlight!** |
| #180 | v19 | 🔄 | Fix MissingPluginException |

---

## Метод вставки скриптов в GitHub Editor

```javascript
const content = document.querySelector('.cm-content');
content.focus();
document.execCommand('selectAll');
document.execCommand('insertText', false, scriptText);
// Затем коммит:
const b = document.querySelector('button');
for (let b of document.querySelectorAll('button')) {
  if (b.textContent.includes('Commit changes')) { b.click(); break; }
}
```
