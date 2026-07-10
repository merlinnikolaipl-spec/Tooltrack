import sys

PATH = "lib/main.dart"

with open(PATH, "r", encoding="utf-8") as f:
    content = f.read()

PAIRS = []
PAIRS.append(("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart'; import 'package:flutter_localizations/flutter_localizations.dart';"))
PAIRS.append(("enum AppLang { ru, uk, pl, en, de, fr, es, it, pt, cs, ro, nl, tr, ar, hi, ko, ja, zh, id, vi, tl }", "enum AppLang { ru, uk, pl, en, de, fr, es, it, pt, cs, ro, nl, tr, ar, hi, ko, ja, zh, id, vi, tl } Locale localeForAppLang(AppLang l) { if (l == AppLang.tl) return const Locale('fil'); return Locale(l.name); }"))
PAIRS.append(("title: i18n.t('appTitle'),", "title: i18n.t('appTitle'), locale: localeForAppLang(lang), localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate], supportedLocales: AppLang.values.map(localeForAppLang).toList(),"))
PAIRS.append(("lastDate: DateTime(DateTime.now().year + 1))", "lastDate: DateTime(DateTime.now().year + 1), locale: localeForAppLang(AppState.of(context).lang.value))"))

for old, new in PAIRS:
    count = content.count(old)
    if count != 1:
        print(f"ERROR: expected 1 occurrence, found {count} for: {old[:60]}")
        sys.exit(1)
    content = content.replace(old, new)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("Calendar locale patch applied successfully")
