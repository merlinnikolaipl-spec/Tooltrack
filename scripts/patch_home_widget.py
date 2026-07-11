import pathlib

MAIN_PATH = pathlib.Path('lib/main.dart')
PUBSPEC_PATH = pathlib.Path('pubspec.yaml')


def apply(path, replacements):
    text = path.read_text(encoding='utf-8')
    for find, replace, label in replacements:
        count = text.count(find)
        if count != 1:
            raise SystemExit(
                f"[patch_home_widget] Anchor not unique ({count} occurrences) for: {label}"
            )
        text = text.replace(find, replace)
    path.write_text(text, encoding='utf-8')


main_replacements = [
    (
        "import 'gps_foreground_service.dart';",
        "import 'gps_foreground_service.dart';\nimport 'package:home_widget/home_widget.dart';",
        "import home_widget package",
    ),
    (
        "final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();",
        "final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();\nfinal ValueNotifier<String?> pendingWidgetAction = ValueNotifier<String?>(null);",
        "global pendingWidgetAction notifier",
    ),
    (
        "  await _initLocalNotifications();\n  runApp(const MyApp());",
        "  await _initLocalNotifications();\n  await HomeWidget.setAppGroupId('group.com.toolkeeper.app.widget');\n  runApp(const MyApp());",
        "setAppGroupId call in main()",
    ),
    (
        "    super.initState();\n    _loadLang();\n  }",
        "    super.initState();\n    _loadLang();\n    _initWidgetLaunch();\n  }",
        "_MyAppState.initState wiring",
    ),
    (
        "  @override\n  void dispose() {\n    _lang.dispose();\n    super.dispose();\n  }",
        (
            "  @override\n  void dispose() {\n    _widgetClickSub?.cancel();\n    _lang.dispose();\n    super.dispose();\n  }\n\n"
            "  StreamSubscription<Uri?>? _widgetClickSub;\n\n"
            "  Future<void> _initWidgetLaunch() async {\n"
            "    try {\n"
            "      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();\n"
            "      if (uri != null) _handleWidgetUri(uri);\n"
            "      _widgetClickSub = HomeWidget.widgetClicked.listen((uri) {\n"
            "        if (uri != null) _handleWidgetUri(uri);\n"
            "      });\n"
            "    } catch (_) {}\n"
            "  }\n\n"
            "  void _handleWidgetUri(Uri uri) {\n"
            "    if (uri.host == 'start') {\n"
            "      pendingWidgetAction.value = 'start';\n"
            "    } else if (uri.host == 'end') {\n"
            "      pendingWidgetAction.value = 'end';\n"
            "    }\n"
            "  }"
        ),
        "_MyAppState widget launch handling methods",
    ),
    (
        "  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;\n",
        "  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;\n  VoidCallback? _pendingWidgetActionListener;\n",
        "_HomeCompanyPageState field for widget listener",
    ),
    (
        (
            "      });\n    }\n  }\n\n  @override\n  void dispose() {\n"
            "    _toolsSub?.cancel();\n    _pendingSub?.cancel();\n    super.dispose();\n  }"
        ),
        (
            "      });\n    }\n"
            "    _pendingWidgetActionListener = () {\n"
            "      if (pendingWidgetAction.value != null && mounted) {\n"
            "        setState(() => index = 3);\n"
            "      }\n"
            "    };\n"
            "    pendingWidgetAction.addListener(_pendingWidgetActionListener!);\n"
            "  }\n\n"
            "  @override\n  void dispose() {\n"
            "    _toolsSub?.cancel();\n    _pendingSub?.cancel();\n"
            "    if (_pendingWidgetActionListener != null) {\n"
            "      pendingWidgetAction.removeListener(_pendingWidgetActionListener!);\n"
            "    }\n"
            "    super.dispose();\n  }"
        ),
        "_HomeCompanyPageState initState/dispose wiring",
    ),
    (
        "  String get _queryPersonId => _linkedPersonId ?? widget.userId;\n",
        (
            "  String get _queryPersonId => _linkedPersonId ?? widget.userId;\n\n"
            "  bool _handlingPendingWidgetAction = false;\n\n"
            "  Future<void> _syncShiftWidget(List<QueryDocumentSnapshot<Map<String, dynamic>>> activeShifts) async {\n"
            "    try {\n"
            "      final active = activeShifts.isNotEmpty;\n"
            "      await HomeWidget.saveWidgetData<bool>('shiftActive', active);\n"
            "      if (active) {\n"
            "        final shift = activeShifts.first.data();\n"
            "        final siteName = (shift['siteName'] ?? '').toString();\n"
            "        final startTime = (shift['startTime'] as Timestamp?)?.toDate();\n"
            "        await HomeWidget.saveWidgetData<String>('shiftSiteName', siteName);\n"
            "        await HomeWidget.saveWidgetData<int>('shiftStartMillis', startTime?.millisecondsSinceEpoch ?? 0);\n"
            "      } else {\n"
            "        await HomeWidget.saveWidgetData<String>('shiftSiteName', '');\n"
            "        await HomeWidget.saveWidgetData<int>('shiftStartMillis', 0);\n"
            "      }\n"
            "      await HomeWidget.updateWidget(iOSName: 'ShiftWidget', androidName: 'ShiftWidgetProvider');\n"
            "    } catch (_) {}\n"
            "  }\n\n"
            "  Future<void> _handlePendingWidgetAction(List<QueryDocumentSnapshot<Map<String, dynamic>>> activeShifts) async {\n"
            "    final action = pendingWidgetAction.value;\n"
            "    if (action == null || _handlingPendingWidgetAction) return;\n"
            "    _handlingPendingWidgetAction = true;\n"
            "    pendingWidgetAction.value = null;\n"
            "    try {\n"
            "      if (action == 'start' && activeShifts.isEmpty) {\n"
            "        await _startShift();\n"
            "      } else if (action == 'end' && activeShifts.isNotEmpty) {\n"
            "        await _endShift(activeShifts.first.id);\n"
            "      }\n"
            "    } finally {\n"
            "      _handlingPendingWidgetAction = false;\n"
            "    }\n"
            "  }\n"
        ),
        "_ShiftButtonState widget sync/action handling methods",
    ),
    (
        "        final activeShifts = snapshot.data!.docs;\n",
        (
            "        final activeShifts = snapshot.data!.docs;\n"
            "        _syncShiftWidget(activeShifts);\n"
            "        _handlePendingWidgetAction(activeShifts);\n"
        ),
        "_ShiftButtonState builder widget sync calls",
    ),
]

pubspec_replacements = [
    (
        "  flutter_launcher_icons: ^0.13.1\n",
        "  flutter_launcher_icons: ^0.13.1\n  home_widget: ^0.9.2\n",
        "add home_widget dependency",
    ),
]

apply(MAIN_PATH, main_replacements)
apply(PUBSPEC_PATH, pubspec_replacements)
print("[patch_home_widget] main.dart and pubspec.yaml patched successfully")
