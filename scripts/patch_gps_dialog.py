import sys, re

# Patch main.dart: add String timestamp support in GPS dialog
# Strategy: find unique GPS anchor, then do ONE replace of the exact multi-line block
# Fix v4: use line_start as region start so indent prefix matches correctly

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# Unique GPS anchor
anchor = "final ts = d['createdAt'];"
anchor_idx = src.find(anchor)
if anchor_idx < 0:
    print('ERROR: GPS anchor not found!')
    sys.exit(1)
print(f'GPS anchor at {anchor_idx}')

# Find "String timeStr" after anchor
search = src[anchor_idx:anchor_idx+500]
rel = search.find("String timeStr = '';")
if rel < 0:
    print('ERROR: String timeStr not found after anchor!')
    sys.exit(1)
timestr_idx = anchor_idx + rel
print(f'String timeStr at {timestr_idx}')

# Detect indentation
line_start = src.rfind('\n', 0, timestr_idx) + 1
indent = src[line_start:timestr_idx]
inner = indent + '  '
print(f'indent={repr(indent)}({len(indent)}sp) inner={repr(inner)}({len(inner)}sp)')

# Build the EXACT old block to find and replace
# IMPORTANT: search from line_start (includes indent prefix), not timestr_idx
old_block = (indent + "String timeStr = '';\n" +
             indent + "if (ts is Timestamp) {\n" +
             inner + "final dt = ts.toDate();\n" +
             inner + "timeStr =\n")

# Find old_block in full source starting from line_start
region = src[line_start:]
blk_idx = region.find(old_block)
if blk_idx < 0:
    print('ERROR: old_block not found!')
    print('Looking for:', repr(old_block))
    print('Actual content:', repr(src[line_start:line_start+200]))
    sys.exit(1)

abs_blk_idx = line_start + blk_idx
print(f'old_block found at {abs_blk_idx}')

# Find end of old block: the closing "}" of "if (ts is Timestamp) {"
# After "timeStr =" there is a multi-line string ending with ";"
# Then the closing "}"
after_blk = src[abs_blk_idx + len(old_block):]

# Find the closing "}" that ends if (ts is Timestamp)
close = "\n" + indent + "}"
close_rel = after_blk.find(close)
if close_rel < 0:
    print('ERROR: closing brace not found!')
    sys.exit(1)

# Full old text = old_block + the timeStr value lines + closing brace
old_full = src[abs_blk_idx : abs_blk_idx + len(old_block) + close_rel + len(close)]
print(f'old_full ({len(old_full)} chars):', repr(old_full[:80]))

# Extract the timeStr value lines (the actual string content)
timestr_value = after_blk[:close_rel]
print(f'timeStr value: {repr(timestr_value[:60])}')

# Build new block
new_block = (indent + "String timeStr = '';\n" +
             indent + "DateTime? dt;\n" +
             indent + "if (ts is Timestamp) {\n" +
             inner + "dt = ts.toDate();\n" +
             indent + "} else if (ts is String) {\n" +
             inner + "dt = DateTime.tryParse(ts);\n" +
             indent + "}\n" +
             indent + "if (dt != null) {\n" +
             inner + "timeStr =\n" +
             timestr_value +
             "\n" + indent + "}")

# Replace in full source
if old_full not in src:
    print('ERROR: old_full not in src!')
    sys.exit(1)

new_src = src.replace(old_full, new_block, 1)

if 'else if (ts is String)' not in new_src:
    print('ERROR: patch verification failed!')
    sys.exit(1)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(new_src)

print('SUCCESS: GPS dialog patch applied!')
print(f'  Added DateTime? dt + else if (ts is String) branch')
