#!/usr/bin/env python3
"""
patch_apple_signin.py  v16 – DIAGNOSTIC: show context around _google() call button
to understand the full widget tree structure
"""

import subprocess, sys

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

# Find _LoginPageState and build()
login_pos = src.find("class _LoginPageState")
build_pos = src.find("Widget build", login_pos)
build_section = src[build_pos:]

# Find _google() call in build section (not method definition)
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

print(f"_google() references in build section: {google_call_offsets}")

if not google_call_offsets:
    print("No references found"); sys.exit(1)

gcall_offset = google_call_offsets[0]
gcall_abs = build_pos + gcall_offset

print(f"Found _google() call at abs pos {gcall_abs}")

# Show 2000 chars BEFORE and 1000 chars AFTER
print("\n=== 2000 chars BEFORE _google() call ===")
print(repr(src[max(0, gcall_abs - 2000):gcall_abs]))
print("=== END BEFORE ===")

print("\n=== 1000 chars AFTER _google() call ===")
print(repr(src[gcall_abs:gcall_abs + 1000]))
print("=== END AFTER ===")

print("DIAGNOSTIC COMPLETE")
