import re
content = open("lib/main.dart", encoding="utf-8").read()

print("LEN=" + str(len(content)))

count_func = content.count("_leaveCompany(BuildContext")
print("FUNC_COUNT=" + str(count_func))

idx2 = content.find("bool get isOwner")
print("IS_OWNER_GETTER_IDX=" + str(idx2))
if idx2 >= 0:
    print("OWNER_CTX_START")
    print(content[idx2-400:idx2+50])
    print("OWNER_CTX_END")

idxLC = content.find("'leaveCompany':")
print("LEAVECOMPANY_KEY_IDX=" + str(idxLC))
if idxLC >= 0:
    print("LC_CTX_START")
    print(content[idxLC:idxLC+150])
    print("LC_CTX_END")

idxI18n = content.find("class I18n")
print("I18N_CLASS_IDX=" + str(idxI18n))

idxDeleteCompany = content.find("_deleteCompany(BuildContext")
print("DELETE_COMPANY_FUNC_IDX=" + str(idxDeleteCompany))

idxLeaveBtn = content.find("_leaveCompany(context)")
print("LEAVE_BTN_IDX=" + str(idxLeaveBtn))
if idxLeaveBtn >= 0:
    print("BTN_CTX_START")
    print(content[idxLeaveBtn-300:idxLeaveBtn+400])
    print("BTN_CTX_END")
