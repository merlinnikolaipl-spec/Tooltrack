#!/usr/bin/env python3
"""
patch_apple_signin.py  v13 – DIAGNOSTIC: find _LoginPageState fields & Google button widget
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

# ── 1. Find _LoginPageState boundaries ──────────────────────────────────────
login_pos = src.find("class _LoginPageState")
if login_pos == -1:
    print("ERROR: _LoginPageState not found"); sys.exit(1)
print(f"_LoginPageState at pos {login_pos}")

# Find the build method
build_pos = src.find("Widget build", login_pos)
print(f"Widget build at pos {build_pos}")

# Extract the class fields section (between class declaration and build)
class_section = src[login_pos:build_pos]
print(f"\n=== Fields in _LoginPageState (first 3000 chars) ===")
print(class_section[:3000])
print("=== END FIELDS ===")

# ── 2. Find all bool/String/var/int fields ───────────────────────────────────
field_patterns = [
    r'bools+(_w+)',
    r'Strings+(_w+)',
    r'ints+(_w+)',
    r'vars+(_w+)',
    r'doubles+(_w+)',
    r'lates+w+s+(_w+)',
]
print("\n=== Detected state fields ===")
for pat in field_patterns:
    matches = re.findall(pat, class_section)
    if matches:
        print(f"  {pat}: {matches}")

# ── 3. Find googleSignIn.signIn() and surrounding context ───────────────────
gsignin_pos = src.find("googleSignIn.signIn()")
if gsignin_pos == -1:
    gsignin_pos = src.find("googleSignIn.signIn(")
print(f"\ngoogleSignIn.signIn() at pos {gsignin_pos}")

# Show 800 chars around it
ctx_start = max(0, gsignin_pos - 400)
ctx_end = min(len(src), gsignin_pos + 400)
print("\n=== Context around googleSignIn.signIn() ===")
print(repr(src[ctx_start:ctx_end]))
print("=== END CONTEXT ===")

# ── 4. Find the line with googleSignIn.signIn() ──────────────────────────────
line_start = src.rfind("\n", 0, gsignin_pos) + 1
line_end = src.find("\n", gsignin_pos)
gsignin_line = src[line_start:line_end]
print(f"\nLine with googleSignIn.signIn(): {repr(gsignin_line)}")
indent = len(gsignin_line) - len(gsignin_line.lstrip())
print(f"Indent: {indent} spaces")

# ── 5. Search backwards from googleSignIn for all widget types ───────────────
search_area = src[login_pos:gsignin_pos]
widget_keywords = [
    "ElevatedButton", "OutlinedButton", "TextButton", "FilledButton",
    "GestureDetector", "InkWell", "InkResponse", "MaterialButton",
    "CupertinoButton", "IconButton", "FloatingActionButton",
    "onTap:", "onPressed:", "SignInButton",
    "GoogleSignInButton", "google_sign_in",
]
print("\n=== Widget occurrences before googleSignIn.signIn() (from _LoginPageState) ===")
for kw in widget_keywords:
    positions = [i for i in range(len(search_area)) if search_area.startswith(kw, i)]
    if positions:
        print(f"  {kw}: {len(positions)} occurrences, last at offset {positions[-1]}")
        # Show last occurrence context
        last = positions[-1]
        print(f"    Context: {repr(search_area[max(0,last-20):last+60])}")

# ── 6. Show 1500 chars before googleSignIn.signIn() ─────────────────────────
print("\n=== 1500 chars before googleSignIn.signIn() ===")
print(repr(src[max(0, gsignin_pos - 1500):gsignin_pos]))
print("=== END ===")

print("\nDIAGNOSTIC COMPLETE")
