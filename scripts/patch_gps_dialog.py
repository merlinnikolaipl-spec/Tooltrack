import sys

# Patch main.dart to add String timestamp support in GPS dialog
# Uses "final ts = d['createdAt'];" as unique anchor for GPS dialog context
# This ensures we patch the right location (not other similar code)

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Find GPS-specific anchor: "final ts = d['createdAt'];"
anchor = "final ts = d['createdAt'];"
anchor_idx = src.find(anchor)
if anchor_idx < 0:
    print('ERROR: GPS anchor not found in main.dart!')
    sys.exit(1)

print(f'Found GPS anchor at position {anchor_idx}')

# Find "String timeStr = '';" AFTER the anchor (within 500 chars)
search_region = src[anchor_idx:anchor_idx + 500]
timestr_rel = search_region.find("String timeStr = '';")
if timestr_rel < 0:
    print('ERROR: String timeStr not found after GPS anchor!')
    sys.exit(1)

timestr_idx = anchor_idx + timestr_rel
print(f'Found String timeStr at position {timestr_idx}')

# Detect indentation from the timeStr line
line_start = src.rfind('\n', 0, timestr_idx) + 1
indent = src[line_start:timestr_idx]
inner = indent + '  '

print(f'Detected indentation: {repr(indent)} ({len(indent)} spaces)')
print(f'Inner indentation:    {repr(inner)} ({len(inner)} spaces)')

# Find "final dt = ts.toDate();" AFTER timestr_idx (within 300 chars)
region2 = src[timestr_idx:timestr_idx + 300]
old_dt_rel = region2.find(inner + "final dt = ts.toDate();")
if old_dt_rel < 0:
    print(f'ERROR: final dt pattern not found! Searching nearby...')
    idx2 = src.find('final dt = ts.toDate', timestr_idx)
    if idx2 >= 0:
        print(f'Found at: {repr(src[max(0,idx2-50):idx2+80])}')
    sys.exit(1)

print(f'Found final dt at relative position {old_dt_rel}')

# Build exact old and new strings
old1 = indent + "String timeStr = '';"
new1 = indent + "String timeStr = '';\n" + indent + "DateTime? dt;"

old2 = inner + "final dt = ts.toDate();"
new2 = (inner + "dt = ts.toDate();\n" +
        indent + "} else if (ts is String) {\n" +
        inner + "  dt = DateTime.tryParse(ts);\n" +
        indent + "}\n" +
        indent + "if (dt != null) {")

# Apply patch 1: add DateTime? dt;
after_timestr = src[timestr_idx:].replace(old1, new1, 1)
src = src[:timestr_idx] + after_timestr

# Apply patch 2: replace final dt = ts.toDate(); with new block
# Re-find the position after patch1 (timestr_idx shifted by len(indent + "DateTime? dt;\n"))
region3 = src[timestr_idx:timestr_idx + 500]
if old2 not in region3:
    print(f'ERROR: old2 not found in region after patch1! old2={repr(old2[:50])}')
    sys.exit(1)

src = src[:timestr_idx] + region3.replace(old2, new2, 1) + src[timestr_idx + 500:]

# Verify
if 'else if (ts is String)' in src:
    print('SUCCESS: else if (ts is String) branch added!')
else:
    print('ERROR: verification failed!')
    sys.exit(1)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('GPS dialog patch complete!')
