# ToolKeeper iOS App — Project Status

## Критические правила (НИКОГДА НЕ НАРУШАТЬ)
- Restore SHA: `2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3` — старая чистая база main.dart (историческая точка отсчёта, для новых правок больше не используется как обязательный шаг)
- Текущий процесс правок: main.dart редактируется напрямую (GitHub web editor / raw fetch + diff), с обязательной проверкой структурной целостности (кол-во фигурных/круглых скобок и точек с запятой) до коммита
- НЕ использовать Bitrise (кредиты закончились)
- НЕ использовать Codemagic (кредиты закончились)
- Использовать ТОЛЬКО GitHub Actions `.github/workflows/ios-appstore.yml`
- Поддержка ВСЕХ 21 языков — обязательна для любых UI-правок
- Firestore security rules правятся напрямую в Firebase Console (публикуются мгновенно, без пересборки приложения)

## Параметры проекта
| Параметр | Значение |
|---|---|
| Firebase | `tooltrack-ee0aa` |
| Apple Team ID | `VHF76Z663B` |
| Bundle ID | `com.toolkeeper.app` |
| GitHub repo | `merlinnikolaipl-spec/Tooltrack` |
| Секрет профиля | `BUILD_PROVISION_PROFILE_BASE64` |
| Актуальная сборка | #210 (main.dart commit `0ae1d8c`) |

## Статус задач (05.07.2026)
| Задача | Статус | Build |
|---|---|---|
| Кириллица/акценты в UI (двойной mojibake в main.dart) | Исправлено | #208 (подтверждено пользователем) |
| Sign in with Apple — CODE_SIGN_ENTITLEMENTS в Xcode проекте | Исправлено | #208 (подтверждено пользователем) |
| Sign in with Apple — провайдер в Firebase Console | Включён и настроен | - |
| Выход из фирмы (leave company) | Исправлено (Firestore rule: update status в left разрешён самому участнику) | live rules, без пересборки |
| Повторный вход по коду после выхода из фирмы | Исправлено (Firestore rule: update left в pending разрешён самому участнику, роль фиксирована как worker) | live rules, без пересборки |
| Удаление аккаунта — не завершало логаут (requires-recent-login глотался silently) | Исправлено (принудительный FirebaseAuth.instance.signOut после попыток удаления) | #209 |
| Удаление аккаунта — кнопка недоступна без активной фирмы | Исправлено (кнопка добавлена на RoleChoicePage — экран без фирмы) | #210 |
| GPS данные с iPhone | Требует диагностики, следующая итерация | - |

## Firestore Security Rules — история важных изменений
- users: allow delete изменено с "if false" на "if signedIn() && uid() == userId" — для поддержки удаления аккаунта
- members: allow delete — добавлено "|| memberId == uid()" (позже выяснилось, что leaveCompany использует update, а не delete, реальный фикс — следующий пункт)
- members: allow update — теперь разрешает самому участнику менять status между active-left (выход) и left-pending (повторный вход по коду), с проверкой role == worker, чтобы исключить самоповышение роли

## Как вносятся правки в main.dart (текущий метод)
- Через fetch() в контексте открытой github.com страницы получаем сырой файл с raw.githubusercontent.com
- Ищем нужный участок кода по уникальным якорным строкам
- Строим новую версию файла, сверяем количество скобок и точек с запятой до/после правки — числа должны совпадать с учётом добавленного кода
- Копируем итоговый текст в буфер обмена, открываем github.com/.../edit/main/lib/main.dart, Ctrl+A -> Ctrl+V, проверяем через поиск (Ctrl+F) точное попадание правки
- Commit changes (сообщение на английском, с описанием сути правки)
- Actions -> ios-appstore.yml -> Run workflow -> main

## История сборок (актуальные)
| Build | Commit | Результат | Примечание |
|---|---|---|---|
| #207 | 0522758 | Success, но содержал баг | mojibake + отсутствие entitlements (подтверждено анализом исходников) |
| #208 | 5fc2bf0 | Success | Кириллица ОК, Apple Sign-In ОК (подтверждено пользователем) |
| #209 | efb2991 | Success | fix: signOut после попыток удаления аккаунта |
| #210 | 0ae1d8c | In progress | fix: кнопка удаления аккаунта на RoleChoicePage |

## Открытые вопросы
- Ожидается тест пользователем сборки #210 (кнопка удаления аккаунта без фирмы) и live-фикса Firestore rules (leave/rejoin company)
- GPS данные с iPhone — не собраны, нужна отдельная диагностика (permissions/background mode)
