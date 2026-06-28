#!/usr/bin/env python3
"""
patch_apple_signin.py  v14
- Fix variable names: loading, error (no underscore)
- Find Google button by _google() call in build(), insert Apple button after it
"""

import subprocess, sys, re

MAIN_DART = "lib/main.dart"

def run(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)

def restore():
    sha = "2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3"
    r = run(f"git checkout {sha} -- {MAIN_DART}")
    if r.returncode != 0:
        print("RESTORE FAILED:", r.stderr); sys.exit(1)
    print("Restored main.dart from", sha)

restore()

with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()

print(f"File length: {len(src)} chars")

# ── Step 1: Add imports ───────────────────────────────────────────────────────
APPLE_IMPORT = "import 'package:sign_in_with_apple/sign_in_with_apple.dart';"
if APPLE_IMPORT not in src:
    # Insert after last existing import
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
    # Find _LoginPageState
    login_pos = src.find("class _LoginPageState")
    if login_pos == -1:
        print("ERROR: _LoginPageState not found"); sys.exit(1)
    # Find Widget build after _LoginPageState
    build_pos = src.find("Widget build", login_pos)
    if build_pos == -1:
        print("ERROR: Widget build not found"); sys.exit(1)
    # Find the @override before Widget build
    override_pos = src.rfind("@override", login_pos, build_pos)
    if override_pos == -1:
        override_pos = build_pos
    src = src[:override_pos] + APPLE_METHOD + "  " + src[override_pos:]
    print(f"Inserted _signInWithApple() method at pos {override_pos}")
else:
    print("_signInWithApple() already present")

# ── Step 3: Find Google button by _google() call and insert Apple button after ─
# Strategy: find "_google()" in build() section, find the closing of the widget
# that contains it, then insert Apple button after it.

login_pos2 = src.find("class _LoginPageState")
build_pos2 = src.find("Widget build", login_pos2)
if build_pos2 == -1:
    print("ERROR: Widget build not found after insert"); sys.exit(1)

build_section = src[build_pos2:]

# Find _google() call in build section (not the method definition)
# _google() is called as onPressed: _google (no parentheses) or onPressed: () => _google()
# Let's find all occurrences
idx = 0
google_call_offsets = []
while True:
    pos = build_section.find("_google", idx)
    if pos == -1:
        break
    # Skip "Future<void> _google() async {" - the method definition
    context = build_section[max(0,pos-10):pos+30]
    if "Future" not in context and "void" not in context and "async" not in build_section[pos:pos+20]:
        google_call_offsets.append(pos)
    idx = pos + 1

print(f"_google() references in build section: {google_call_offsets}")

APPLE_BUTTON_MARKER = "_signInWithApple"
if APPLE_BUTTON_MARKER in src[build_pos2:] and "SignInWithApple" in src[build_pos2:]:
    print("Apple button already in build section, skipping")
elif not google_call_offsets:
    print("ERROR: No _google() call found in build section"); sys.exit(1)
else:
    # Use the first occurrence (there might be multiple)
    gcall_offset = google_call_offsets[0]
    gcall_abs = build_pos2 + gcall_offset

    print(f"Found _google() call at abs pos {gcall_abs}")
    print(f"Context: {repr(src[gcall_abs-50:gcall_abs+50])}")

    # Find the line containing _google() call
    line_start = src.rfind("\n", 0, gcall_abs) + 1
    line_end = src.find("\n", gcall_abs)
    gcall_line = src[line_start:line_end]
    print(f"_google() call line: {repr(gcall_line)}")
    indent = len(gcall_line) - len(gcall_line.lstrip())
    print(f"Indent of _google() line: {indent}")

    # Find the closing of the widget containing _google()
    # Walk forward from gcall_abs to find a line at same or lower indent ending with ","
    # This would be the closing paren of the Google button widget
    search_from = line_end + 1
    closing_pos = None
    lines_after = src[search_from:search_from + 3000].split("\n")
    abs_pos = search_from
    for ln in lines_after:
        ln_indent = len(ln) - len(ln.lstrip()) if ln.strip() else 999
        stripped = ln.strip()
        # Looking for a line at indent <= (indent - 2) ending with , or ), or ),
        if ln_indent <= indent and stripped and (stripped.endswith(",") or stripped == ")" or stripped == ")," or stripped == "]," or stripped == "]"):
            closing_pos = abs_pos + len(ln)
            print(f"Found closing at indent {ln_indent}: {repr(ln)}")
            break
        abs_pos += len(ln) + 1

    if closing_pos is None:
        print("ERROR: Could not find closing of Google button widget"); sys.exit(1)

    # The Apple button to insert
    # We need to figure out the correct indentation for the Apple button
    # It should be at indent=4 (same level as other top-level widgets in column)
    apple_indent = " " * 8  # typical Flutter widget indent in Column children

    APPLE_BTN = f"""
{apple_indent}const SizedBox(height: 12),
{apple_indent}SignInWithAppleButton(
{apple_indent}  onPressed: _signInWithApple,
{apple_indent}),"""

    # Insert after closing of Google button
    src = src[:closing_pos + 1] + APPLE_BTN + src[closing_pos + 1:]
    print(f"Inserted Apple button after Google button closing at pos {closing_pos}")

# ── Write result ──────────────────────────────────────────────────────────────
with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print(f"Written {len(src)} chars")
print("Apple Sign-In patch complete")
