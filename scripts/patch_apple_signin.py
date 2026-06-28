#!/usr/bin/env python3
"""
patch_apple_signin.py  v15
- Fix: find correct closing of Google button (indent STRICTLY LESS than _google line)
- Find button by _google() call in build(), find line at indent < gcall_indent ending with ),
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

# ── Step 3: Find Google button by _google() call in build() ──────────────────
login_pos2 = src.find("class _LoginPageState")
build_pos2 = src.find("Widget build", login_pos2)
if build_pos2 == -1:
    print("ERROR: Widget build not found"); sys.exit(1)

build_section = src[build_pos2:]

# Find _google() call in build section (not the method definition)
idx = 0
google_call_offsets = []
while True:
    pos = build_section.find("_google", idx)
    if pos == -1:
        break
    context_before = build_section[max(0,pos-30):pos]
    context_after = build_section[pos:pos+30]
    # Skip: method definitions containing "Future<void> _google()"
    if "Future" not in context_before and "void" not in context_before:
        google_call_offsets.append(pos)
    idx = pos + 1

print(f"_google() references in build section: {google_call_offsets}")

APPLE_BUTTON_MARKER = "_signInWithApple"
if APPLE_BUTTON_MARKER in src[build_pos2:]:
    print("Apple button already in build section, skipping")
elif not google_call_offsets:
    print("ERROR: No _google() call found in build section"); sys.exit(1)
else:
    gcall_offset = google_call_offsets[0]
    gcall_abs = build_pos2 + gcall_offset

    print(f"Found _google() call at abs pos {gcall_abs}")
    print(f"Context: {repr(src[gcall_abs-50:gcall_abs+80])}")

    # Find the line containing _google() call
    line_start = src.rfind("\n", 0, gcall_abs) + 1
    line_end = src.find("\n", gcall_abs)
    gcall_line = src[line_start:line_end]
    print(f"_google() call line: {repr(gcall_line)}")
    gcall_indent = len(gcall_line) - len(gcall_line.lstrip())
    print(f"Indent of _google() line: {gcall_indent}")

    # Find the closing of the widget containing _google()
    # Walk forward from end of gcall line to find a line with STRICTLY LESS indent
    # that ends with ), or ), - this would be the closing paren of the button widget
    search_from = line_end + 1
    closing_pos = None
    lines_after = src[search_from:search_from + 5000].split("\n")
    abs_pos = search_from
    print(f"Searching for closing at indent < {gcall_indent}...")
    for i, ln in enumerate(lines_after):
        ln_indent = len(ln) - len(ln.lstrip()) if ln.strip() else 999
        stripped = ln.strip()
        # Looking for a line at indent STRICTLY LESS than gcall_indent
        # that ends the widget (closing paren with comma or just closing paren)
        if stripped and ln_indent < gcall_indent:
            print(f"  Line {i}: indent={ln_indent}: {repr(ln[:80])}")
            if stripped.endswith("),") or stripped.endswith(")") or stripped == ")," or stripped == ")":
                closing_pos = abs_pos + len(ln)
                print(f"  -> SELECTED as closing!")
                break
            # If it's a property line at lower indent, keep looking
            # (the closing paren should come soon)
        abs_pos += len(ln) + 1

    if closing_pos is None:
        print("ERROR: Could not find closing of Google button widget"); sys.exit(1)

    # The Apple button - use 8-space indent (standard Flutter Column child indent)
    apple_indent = " " * 8

    APPLE_BTN = f"""
{apple_indent}const SizedBox(height: 12),
{apple_indent}SignInWithAppleButton(
{apple_indent}  onPressed: _signInWithApple,
{apple_indent}),"""

    src = src[:closing_pos + 1] + APPLE_BTN + src[closing_pos + 1:]
    print(f"Inserted Apple button after Google button closing at pos {closing_pos}")

# ── Write result ──────────────────────────────────────────────────────────────
with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print(f"Written {len(src)} chars")
print("Apple Sign-In patch complete")
