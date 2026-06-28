#!/usr/bin/env python3
"""
patch_apple_signin.py  v19
PRODUCTION patch (confirmed working v18 structure + fix MissingPluginException):
- Adds sign_in_with_apple to pubspec.yaml dependencies (fixes MissingPluginException)
- Adds import to main.dart
- Inserts _signInWithApple() method in _LoginPageState (uses loading/error fields)
- Inserts Apple button after Google SizedBox (indent=12, SizedBox closing at indent<=12)
"""

import subprocess, sys, re

MAIN_DART = "lib/main.dart"
PUBSPEC = "pubspec.yaml"

def run(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)

def restore():
    sha = "2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3"
    r = run(f"git checkout {sha} -- {MAIN_DART} {PUBSPEC}")
    if r.returncode != 0:
        print("RESTORE FAILED:", r.stderr); sys.exit(1)
    print("Restored main.dart and pubspec.yaml from", sha)

restore()

# ── Fix pubspec.yaml: add sign_in_with_apple to dependencies ──────────────────
with open(PUBSPEC, "r", encoding="utf-8") as f:
    pubspec = f.read()

SIWA_DEP = "  sign_in_with_apple: ^6.1.4"
if "sign_in_with_apple" not in pubspec:
    # Insert after google_sign_in line
    gsignin_line = [l for l in pubspec.split("\n") if "google_sign_in:" in l and "platform" not in l]
    if gsignin_line:
        insert_after = gsignin_line[0]
        pubspec = pubspec.replace(insert_after, insert_after + "\n" + SIWA_DEP)
        print(f"Added sign_in_with_apple to pubspec.yaml after: {insert_after.strip()}")
    else:
        # fallback: insert before dependency_overrides
        pubspec = pubspec.replace("dependency_overrides:", SIWA_DEP + "\ndependency_overrides:")
        print("Added sign_in_with_apple to pubspec.yaml (fallback)")
    with open(PUBSPEC, "w", encoding="utf-8") as f:
        f.write(pubspec)
else:
    print("sign_in_with_apple already in pubspec.yaml")

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
      final oauthCredential = OAuthProvider('apple.com').credential(
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
# Confirmed structure (v17 diagnostic, line numbers from original):
#   Line 4713 [12]: SizedBox(width: double.infinity, child: FilledButton.icon(
#   Line 4717 [16]:   onPressed: loading ? null : _google,
#   Line 4719 [14]:   ),   <- closes FilledButton.icon
#   Line 4720 [12]: ),     <- closes SizedBox <- INSERT AFTER THIS
#   Line 4721 [10]: ],     <- closes Column children

login_pos2 = src.find("class _LoginPageState")
build_pos2 = src.find("Widget build", login_pos2)
if build_pos2 == -1:
    print("ERROR: Widget build not found"); sys.exit(1)

build_section = src[build_pos2:]

# Find _google() call in build section (not method def)
idx = 0
google_call_offsets = []
while True:
    pos = build_section.find("_google", idx)
    if pos == -1:
        break
    context_before = build_section[max(0,pos-30):pos]
    if "Future" not in context_before and "void" not in context_before:
        google_call_offsets.append(pos)
    idx = pos + 1

print(f"_google() refs in build: {google_call_offsets}")

APPLE_BTN_MARKER = "_signInWithApple"
if APPLE_BTN_MARKER in src[build_pos2:]:
    print("Apple button already in build section, skipping")
elif not google_call_offsets:
    print("ERROR: No _google() call found"); sys.exit(1)
else:
    gcall_offset = google_call_offsets[0]
    gcall_abs = build_pos2 + gcall_offset

    line_start = src.rfind("\n", 0, gcall_abs) + 1
    line_end = src.find("\n", gcall_abs)
    gcall_line = src[line_start:line_end]
    gcall_indent = len(gcall_line) - len(gcall_line.lstrip())
    print(f"_google() at indent {gcall_indent}: {repr(gcall_line.strip()[:60])}")

    # Find SizedBox closing: indent <= gcall_indent - 4 (12 = 16-4)
    target_max_indent = gcall_indent - 4
    print(f"Looking for SizedBox closing at indent <= {target_max_indent}...")

    search_from = line_end + 1
    closing_pos = None
    lines_after = src[search_from:search_from + 5000].split("\n")
    abs_pos = search_from
    for i, ln in enumerate(lines_after):
        ln_indent = len(ln) - len(ln.lstrip()) if ln.strip() else 999
        stripped = ln.strip()
        if stripped and ln_indent <= target_max_indent:
            print(f"  Line {i}: indent={ln_indent}: {repr(ln[:50])}")
            if stripped.endswith("),") or stripped == "),":
                closing_pos = abs_pos + len(ln)
                print(f"  -> SizedBox closing selected!")
                break
            elif stripped.endswith("],") or stripped == "]:":
                print(f"  -> Reached children ], stopping"); break
        abs_pos += len(ln) + 1

    if closing_pos is None:
        print("ERROR: SizedBox closing not found"); sys.exit(1)

    apple_indent = " " * target_max_indent
    APPLE_BTN = f"""
{apple_indent}const SizedBox(height: 12),
{apple_indent}SizedBox(
{apple_indent}  width: double.infinity,
{apple_indent}  child: SignInWithAppleButton(
{apple_indent}    onPressed: _signInWithApple,
{apple_indent}  ),
{apple_indent}),"""

    src = src[:closing_pos + 1] + APPLE_BTN + src[closing_pos + 1:]
    print(f"Apple button inserted at pos {closing_pos}")

# ── Write main.dart ───────────────────────────────────────────────────────────
with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print(f"Written {len(src)} chars to main.dart")
print("PATCH COMPLETE - Sign in with Apple ready")
