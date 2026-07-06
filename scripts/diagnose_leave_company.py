import re
content = open("lib/main.dart", encoding="utf-8").read()

idxs = [m.start() for m in re.finditer("leaveCompanyConfirm", content)]
print("LEAVE_CONFIRM_COUNT=" + str(len(idxs)))
for i in idxs[:2]:
    snippet = content[i-10:i+100]
    print("SNIPPET_START")
    print(snippet)
    print("SNIPPET_END")

fidx = content.find("_leaveCompany(BuildContext")
print("FUNC_IDX=" + str(fidx))
if fidx >= 0:
    print("FUNC_START")
    print(content[fidx:fidx+900])
    print("FUNC_END")

idx2 = content.find("isOwner")
print("IS_OWNER_IDX=" + str(idx2))
