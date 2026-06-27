import sys

# Patch main.dart to add String timestamp support in GPS dialog
# This adds "else if (ts is String) { dt = DateTime.tryParse(ts); }"
# branch alongside the existing "if (ts is Timestamp) { dt = ts.toDate(); }"

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Find "String timeStr = '';" marker
marker = "String timeStr = '';"
idx = src.find(marker)
if idx < 0:
    print('ERROR: marker not found in main.dart!')
    sys.exit(1)

# Detect indentation from context
line_start = src.rfind('\n', 0, idx) + 1
indent = src[line_start:idx]   # spaces before "String timeStr"
inner = indent + '  '           # 2 more spaces for inside if block

print(f'Detected indentation: {repr(indent)} ({len(indent)} spaces)')
print(f'Inner indentation:    {repr(inner)} ({len(inner)} spaces)')

# Build old and new code strings
old1 = indent + "String timeStr = '';"
new1 = indent + "String timeStr = '';\n" + indent + "DateTime? dt;"

old2 = inner + "final dt = ts.toDate();"
new2 = (inner + "dt = ts.toDate();\n" +
        indent + "} else if (ts is String) {\n" +
        inner + "  dt = DateTime.tryParse(ts);\n" +
        indent + "}\n" +
        indent + "if (dt != null) {")

# Verify old2 exists
if old2 not in src:
    print(f'ERROR: inner pattern not found!')
    i2 = src.find('final dt = ts.toDate')
    if i2 >= 0:
        print(f'Similar found: {repr(src[max(0,i2-80):i2+80])}')
    sys.exit(1)

# Apply patches
src = src.replace(old1, new1, 1)
src = src.replace(old2, new2, 1)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('GPS dialog patch applied successfully!')
print(f'Added DateTime? dt + else if (ts is String) branch')
