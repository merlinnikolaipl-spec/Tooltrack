#!/usr/bin/env python3
"""
patch_apple_signin.py v20
Fixes:
1. Removed restore() - workflow already restores pubspec.yaml and bumps version BEFORE this script
2. Adds sign_in_with_apple to pubspec.yaml dependencies (fixes MissingPluginException)
3. Renames font family 'Roboto' -> 'RobotoPDF' in pubspec.yaml (fixes hieroglyphs on iOS)
4. Adds Apple Sign-In button + method to main.dart (confirmed working v18 structure)
"""

import sys, re

MAIN_DART = "lib/main.dart"
PUBSPEC = "pubspec.yaml"

# ── Read pubspec.yaml ─────────────────────────────────────────────────────────
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

# ── Read main.dart ────────────────────────────────────────────────────────────
with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()
print(f"main.dart length: {len(src)} chars")

# ── Step 1: Add import ────────────────────────────────────────────────────────
APPLE_IMPORT = "import 'package:sign_in_with_apple/sign_in_with_apple.dart';"
if APPLE_IMPORT not in src:
    last_import = src.rfind("\nimport ")
    end_of_last_import = src.find(";", last_import) + 1
    src = src[:end_of_last_import] + "\n" + APPLE_IMPORT + src[end_of_last_import:]
    print("Added Apple import")
else:
    print("Apple import already present")

# ── Step 2: Add _signInWithApple() method before Widget build ─────────────────
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

# ── Step 3: Insert Apple button after Google SizedBox ─────────────────────────
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

# ── Save main.dart ────────────────────────────────────────────────────────────
with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print("main.dart saved successfully")
print("PATCH v20 COMPLETE")
