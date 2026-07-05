import re
import sys

PATH = "lib/main.dart"

with open(PATH, "r", encoding="utf-8") as f:
    content = f.read()

OLD_BLOCK = "var result = docs.toList();\n    if (widget.personId != null) {\n      result.sort((a, b) {\n        final ta = (a.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);\n        final tb = (b.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);\n        return tb.compareTo(ta);\n      });\n    }"

NEW_BLOCK = "var result = docs.toList();\n    result.sort((a, b) {\n      final aActive = a.data()['endTime'] == null;\n      final bActive = b.data()['endTime'] == null;\n      if (aActive != bActive) return aActive ? -1 : 1;\n      final ta = (a.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);\n      final tb = (b.data()['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);\n      return tb.compareTo(ta);\n    });"

count = content.count(OLD_BLOCK)
if count != 1:
    print(f"ERROR: expected exactly 1 occurrence of OLD_BLOCK in {PATH}, found {count}")
    sys.exit(1)

content = content.replace(OLD_BLOCK, NEW_BLOCK, 1)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: timesheets sort patch applied (active shifts now sorted to top for all views, including admin 'All shifts').")
