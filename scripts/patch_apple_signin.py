#!/usr/bin/env python3
"""
patch_apple_signin.py v22
Fixes:
1. Removed restore() - workflow already restores pubspec.yaml and bumps version BEFORE this script
2. Adds sign_in_with_apple to pubspec.yaml dependencies (fixes MissingPluginException)
3. Renames font family 'Roboto' -> 'RobotoPDF' in pubspec.yaml (fixes hieroglyphs on iOS)
4. Adds Apple Sign-In button + method to main.dart (confirmed working v18 structure)
"""

import sys, re

MAIN_DART = "lib/main.dart"
PUBSPEC = "pubspec.yaml"

# Ã¢ÂÂÃ¢ÂÂ Read pubspec.yaml Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ
with open(PUBSPEC, "r", encoding="utf-8") as f:
    pubspec = f.read()

print("Current pubspec version:", [l for l in pubspec.split("\n") if l.startswith("version:")])

# Fix 1: Add sign_in_with_apple to dependencies
SIWA_DEP = "  sign_in_with_apple: ^6.1.4"
if "sign_in_with_apple" not in pubspec:
    gsignin_lines = [l for l in pubspec.split("\n") if "google_sign_in:" in l and "override" not in l.lower()]
    if gsignin_lines:
        insert_after = gsignin_lines[0]
        pubspec = pubspec.replace(insert_after, insert_after + "\n" + SIWA_DEP, 1)
        print(f"Added sign_in_with_apple after: {insert_after.strip()}")
    else:
        # fallback
        pubspec = pubspec.replace("dependency_overrides:", SIWA_DEP + "\ndependency_overrides:", 1)
        print("Added sign_in_with_apple (fallback before dependency_overrides)")
else:
    print("sign_in_with_apple already in pubspec.yaml")

# Fix 2: Rename font family 'Roboto' -> 'RobotoPDF' to avoid overriding system Roboto
if "family: Roboto" in pubspec and "family: RobotoPDF" not in pubspec:
    pubspec = pubspec.replace("family: Roboto", "family: RobotoPDF")
    print("Renamed font family: Roboto -> RobotoPDF (fixes iOS hieroglyphs)")
else:
    print("Font family already fixed or not found")

with open(PUBSPEC, "w", encoding="utf-8") as f:
    f.write(pubspec)

print("pubspec.yaml updated")
print("Version in pubspec:", [l for l in pubspec.split("\n") if l.startswith("version:")])

# Ã¢ÂÂÃ¢ÂÂ Read main.dart Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ
with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()
print(f"main.dart length: {len(src)} chars")

# Ã¢ÂÂÃ¢ÂÂ Step 1: Add import Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ
APPLE_IMPORT = "import 'package:sign_in_with_apple/sign_in_with_apple.dart';"
if APPLE_IMPORT not in src:
    last_import = src.rfind("\nimport ")
    end_of_last_import = src.find(";", last_import) + 1
    src = src[:end_of_last_import] + "\n" + APPLE_IMPORT + src[end_of_last_import:]
    print("Added Apple import")
else:
    print("Apple import already present")

# Ã¢ÂÂÃ¢ÂÂ Step 2: Add _signInWithApple() method before Widget build Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ
APPLE_METHOD = '''
  Future<void> _signInWithApple() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider(\'apple.com\').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
'''

METHOD_MARKER = "Future<void> _signInWithApple()"
if METHOD_MARKER not in src:
    login_pos = src.find("class _LoginPageState")
    if login_pos == -1:
        print("ERROR: _LoginPageState not found"); sys.exit(1)
    build_pos = src.find("Widget build", login_pos)
    if build_pos == -1:
        print("ERROR: Widget build not found"); sys.exit(1)
    override_pos = src.rfind("@override", login_pos, build_pos)
    if override_pos == -1:
        override_pos = build_pos
    src = src[:override_pos] + APPLE_METHOD + "  " + src[override_pos:]
    print(f"Inserted _signInWithApple() method at pos {override_pos}")
else:
    print("_signInWithApple() already present")

# Ã¢ÂÂÃ¢ÂÂ Step 3: Insert Apple button after Google SizedBox Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ
APPLE_BUTTON = """
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  icon: const Icon(Icons.apple, size: 20),
                  onPressed: loading ? null : _signInWithApple,
                  label: const Text('Sign in with Apple'),
                ),
              ),"""

BUTTON_MARKER = "onPressed: loading ? null : _signInWithApple"
if BUTTON_MARKER not in src:
    login_pos2 = src.find("class _LoginPageState")
    build_pos2 = src.find("Widget build", login_pos2)
    if build_pos2 == -1:
        print("ERROR: Widget build not found (step 3)"); sys.exit(1)

    build_section = src[build_pos2:]

    # Find the Google button call: onPressed: loading ? null : _google
    gcall_match = re.search(r'([ \t]+)onPressed: loading \? null : _google', build_section)
    if not gcall_match:
        print("ERROR: Google button onPressed not found"); sys.exit(1)
    gcall_indent = len(gcall_match.group(1))
    gcall_pos = gcall_match.start()
    print(f"Found Google onPressed at build_section pos {gcall_pos}, indent={gcall_indent}")

    # Find the closing ); of the SizedBox (first line with indent <= gcall_indent-4 after gcall)
    target_indent = gcall_indent - 4  # 12 if gcall_indent=16
    search_from = gcall_pos
    lines = build_section[search_from:].split("\n")
    insert_offset = search_from
    for i, line in enumerate(lines):
        stripped = line.rstrip()
        if stripped == "":
            insert_offset += len(line) + 1
            continue
        line_indent = len(line) - len(line.lstrip())
        # We want the closing ), of the outer SizedBox
        if i > 0 and line_indent <= target_indent and stripped.lstrip().startswith("),"):
            insert_offset += len(line) + 1  # include this line
            print(f"Found SizedBox closing at line {i}: {repr(stripped)}, indent={line_indent}")
            break
        insert_offset += len(line) + 1

    abs_insert = build_pos2 + insert_offset
    src = src[:abs_insert] + APPLE_BUTTON + "\n" + src[abs_insert:]
    print(f"Inserted Apple button at absolute pos {abs_insert}")
else:
    print("Apple button already present")

# Ã¢ÂÂÃ¢ÂÂ Save main.dart Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ

# âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
# PATCH v21 ADDITIONS: Fix _endShift hang + Fix alreadyHaveActiveShift block
# âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

# Fix A: null-safe startTime cast in _endShift (prevents NullPointerException hang)
OLD_START_CAST = "final startTime = (shiftData['startTime'] as Timestamp).toDate();"
NEW_START_CAST = "final startTime = (shiftData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();"
if OLD_START_CAST in src:
    src = src.replace(OLD_START_CAST, NEW_START_CAST, 1)
    print("v21: Fixed startTime null-safe cast in _endShift")
else:
    print("v21 WARNING: startTime cast not found")

# Fix B: add Navigator.pop(ctx) in _endShift catch block (so dialog always closes)
OLD_ENDSHIFT_CATCH = """        } catch (e) {
          setDlg(() => saving = false);
          if (ctx2.mounted) {
            ScaffoldMessenger.of(ctx2)
                .showSnackBar(SnackBar(content: Text("""
NEW_ENDSHIFT_CATCH = """        } catch (e) {
          setDlg(() => saving = false);
          try { Navigator.pop(ctx); } catch (_) {}
          if (ctx2.mounted) {
            ScaffoldMessenger.of(ctx2)
                .showSnackBar(SnackBar(content: Text("""
if OLD_ENDSHIFT_CATCH in src:
    src = src.replace(OLD_ENDSHIFT_CATCH, NEW_ENDSHIFT_CATCH, 1)
    print("v21: Fixed _endShift catch - added Navigator.pop(ctx)")
else:
    print("v21 WARNING: _endShift catch block not found exactly")

# Fix C: remove alreadyHaveActiveShift block (blocks new shift after app restart)
OLD_ACTIVE_CHECK = """    // Block starting a new shift if one is already active for this person
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
    if (!mounted) return;"""
NEW_ACTIVE_CHECK = "    // [v21] Active-shift duplicate check removed - allow restart after app reboot\n    if (!mounted) return;"
if OLD_ACTIVE_CHECK in src:
    src = src.replace(OLD_ACTIVE_CHECK, NEW_ACTIVE_CHECK, 1)
    print("v21: Removed alreadyHaveActiveShift duplicate block")
else:
    print("v21 WARNING: alreadyHaveActiveShift block not found - may differ in whitespace")



# ─────────────────────────────────────────────────────────────────────────────
# PATCH v22 FIXES (exact indentation from file analysis)
# ─────────────────────────────────────────────────────────────────────────────

# Fix A (v22): null-safe startTime in _endShift (18-space indent)
OLD_ST = "                  final startTime = (shiftData['startTime'] as Timestamp).toDate();"
NEW_ST = "                  final startTime = (shiftData['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();"
if OLD_ST in src:
    src = src.replace(OLD_ST, NEW_ST, 1)
    print("v22 Fix A OK: startTime null-safe")
else:
    print("v22 Fix A SKIP")

# Fix B (v22): Navigator.pop in _endShift catch (exact 16-space indent)
OLD_CATCH = "                } catch (e) {\n                  setDlg(() => saving = false);\n                  if (ctx2.mounted) {"
NEW_CATCH = "                } catch (e) {\n                  setDlg(() => saving = false);\n                  try { Navigator.pop(ctx); } catch (_) {}\n                  if (ctx2.mounted) {"
if OLD_CATCH in src:
    src = src.replace(OLD_CATCH, NEW_CATCH, 1)
    print("v22 Fix B OK: Navigator.pop in catch")
else:
    print("v22 Fix B SKIP")

# Fix C (v22): remove alreadyHaveActiveShift block (exact 4-space indent)
OLD_ACTIVE = "    // Block starting a new shift if one is already active for this person\n    try {\n      final activeSnap = await companyTimesheetsRef(widget.companyId)\n          .where('personId', isEqualTo: personIdForShift)\n          .where('endTime', isNull: true)\n          .limit(1)\n          .get();\n      if (!mounted) return;\n      if (activeSnap.docs.isNotEmpty) {\n        ScaffoldMessenger.of(context).showSnackBar(\n          SnackBar(content: Text(i18n.t('alreadyHaveActiveShift'))),\n        );\n        return;\n      }\n    } catch (_) {}\n    if (!mounted) return;"
NEW_ACTIVE = "    // v22: removed duplicate-shift block\n    if (!mounted) return;"
if OLD_ACTIVE in src:
    src = src.replace(OLD_ACTIVE, NEW_ACTIVE, 1)
    print("v22 Fix C OK: alreadyHaveActiveShift removed")
else:
    print("v22 Fix C SKIP")

# Fix D (v23): restore orderBy on admin stream + add limit(100) to cap Firestore reads
OLD_STREAM = "    return companyTimesheetsRef(widget.companyId)\n        .orderBy('startTime', descending: true)\n        .snapshots();"
NEW_STREAM = "    return companyTimesheetsRef(widget.companyId)\n        .orderBy('startTime', descending: true)\n        .limit(100)\n        .snapshots(); // v23: orderBy restored + limit(100) to cap reads"
if OLD_STREAM in src:
    src = src.replace(OLD_STREAM, NEW_STREAM, 1)
    print("v23 Fix D OK: orderBy + limit(100) applied to admin stream")
else:
    print("v23 Fix D SKIP")


with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print("main.dart saved successfully")
print("PATCH v22 COMPLETE")
