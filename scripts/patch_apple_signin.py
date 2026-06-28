#!/usr/bin/env python3
"""
patch_apple_signin.py  v17 – DIAGNOSTIC: print actual code lines around _google() call
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
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Find the line with _google() call
google_lines = []
for i, line in enumerate(lines):
    if "_google" in line and "Future" not in line and "void" not in line and "async" not in line:
        google_lines.append((i + 1, line.rstrip()))

print(f"Lines referencing _google (not in method def): {len(google_lines)}")
for ln, txt in google_lines:
    print(f"  Line {ln}: {repr(txt)}")

# Show the range around each _google line
for ln, txt in google_lines:
    print(f"\n=== Context around line {ln} (lines {ln-30} to {ln+30}) ===")
    start = max(0, ln - 31)
    end = min(len(lines), ln + 30)
    for i in range(start, end):
        marker = ">>>" if (i + 1) == ln else "   "
        indent = len(lines[i]) - len(lines[i].lstrip())
        print(f"  {marker} {i+1:4d} [{indent:2d}]: {lines[i].rstrip()}")
    print(f"=== END CONTEXT ===")

print("DIAGNOSTIC COMPLETE")
