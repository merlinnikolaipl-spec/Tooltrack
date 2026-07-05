import sys
path = "lib/main.dart"
f = open(path, "r", encoding="utf-8"); content = f.read(); f.close()
anchor = "  if (ok != true) return;\n\n  final u = FirebaseAuth.instance.currentUser;\n  bool needsReauth = false;\n  if (u != null) {\n    try {\n      await userDoc().delete();\n    } catch (_) {}\n    try {\n      await u.delete();\n    } catch (e) {\n      needsReauth = true;\n    }\n  }\n\n  if (needsReauth) {"
replacement = "  if (ok != true) return;\n\n  final u = FirebaseAuth.instance.currentUser;\n  bool needsReauth = false;\n  if (u != null) {\n    try {\n      await u.delete();\n      try {\n        await userDoc().delete();\n      } catch (_) {}\n    } catch (e) {\n      needsReauth = true;\n    }\n  }\n\n  if (needsReauth) {"
cnt = content.count(anchor)
content = content.replace(anchor, replacement) if cnt == 1 else sys.exit("anchor not found, count=" + str(cnt))
f = open(path, "w", encoding="utf-8"); f.write(content); f.close()
print("Patch applied successfully: auth account deletion now attempted before removing user profile document")
