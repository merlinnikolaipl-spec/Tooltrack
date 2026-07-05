#!/usr/bin/env python3
"""
patch_role_labels.py v1
Fixes Apple Guideline 3.1.1 rejection: renames the "Owner"/"Employee" role-choice
button labels (shown on RoleChoicePage when picking "create a company" vs
"join a company by code") to neutral, action-based wording, across all 21
supported languages, inside the in-file I18n._dict map in lib/main.dart.

Reuses the exact wording already used elsewhere in the app for
'createCompany' / 'joinCompany' so the terminology stays consistent.

Note: this does NOT touch the separate 'role_owner' / 'role_admin' /
'role_foreman' / 'role_employee' keys, which are used elsewhere to display a
team member's role (e.g. in employee lists) and are unrelated to this
onboarding-screen rejection.

This script runs AFTER the workflow's "Restore original main.dart from git history"
step, so its changes survive every build. Direct edits to lib/main.dart on the
main branch do NOT survive, since that file is restored from a fixed git SHA
before every build.
"""

import sys, re

MAIN_DART = "lib/main.dart"

with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()

LANGS = ['ru','uk','pl','en','de','fr','es','it','pt','cs','ro','nl',
         'tr','ar','hi','ko','ja','zh','id','vi','tl']

# New values = the app's existing 'createCompany' / 'joinCompany' wording,
# reused here so the RoleChoicePage buttons read as actions, not job titles.
NEW_OWNER = {
    'ru': "Создать фирму", 'uk': "Створити фірму", 'pl': "Utwórz firmę",
    'en': "Create company", 'de': "Firma erstellen", 'fr': "Créer une entreprise",
    'es': "Crear empresa", 'it': "Crea azienda", 'pt': "Criar empresa",
    'cs': "Vytvořit firmu", 'ro': "Creare companie", 'nl': "Bedrijf aanmaken",
    'tr': "Şirket oluştur", 'ar': "إنشاء شركة", 'hi': "कंपनी बनाएं",
    'ko': "회사 만들기", 'ja': "会社を作成", 'zh': "创建公司",
    'id': "Buat perusahaan", 'vi': "Tạo công ty", 'tl': "Lumikha ng kumpanya",
}

NEW_EMPLOYEE = {
    'ru': "Войти в фирму по коду", 'uk': "Приєднатися", 'pl': "Dołącz",
    'en': "Join", 'de': "Beitreten", 'fr': "Rejoindre",
    'es': "Unirse", 'it': "Unisciti", 'pt': "Entrar",
    'cs': "Připojit se", 'ro': "Alăturare", 'nl': "Aansluiten",
    'tr': "Katıl", 'ar': "انضمام", 'hi': "जुड़ें",
    'ko': "참가", 'ja': "参加", 'zh': "加入",
    'id': "Bergabung", 'vi': "Tham gia", 'tl': "Sumali",
}

owner_re = re.compile(r"'owner':\s*'[^']*'")
employee_re = re.compile(r"'employee':\s*'[^']*'")

for lang in LANGS:
    anchor = f"AppLang.{lang}: {{"
    pos = src.find(anchor)
    if pos == -1:
        print(f"ERROR: language block start not found for {lang}"); sys.exit(1)

    next_pos = src.find("AppLang.", pos + len(anchor))
    block_end = next_pos if next_pos != -1 else len(src)

    m_owner = owner_re.search(src, pos, block_end)
    if not m_owner:
        print(f"ERROR: owner key not found for {lang}"); sys.exit(1)
    new_owner_val = NEW_OWNER[lang].replace("'", "\\'")
    src = src[:m_owner.start()] + f"'owner': '{new_owner_val}'" + src[m_owner.end():]

    next_pos2 = src.find("AppLang.", pos + len(anchor))
    block_end2 = next_pos2 if next_pos2 != -1 else len(src)
    m_employee = employee_re.search(src, pos, block_end2)
    if not m_employee:
        print(f"ERROR: employee key not found for {lang}"); sys.exit(1)
    new_employee_val = NEW_EMPLOYEE[lang].replace("'", "\\'")
    src = src[:m_employee.start()] + f"'employee': '{new_employee_val}'" + src[m_employee.end():]

    print(f"OK: {lang} owner/employee relabeled")

with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print("PATCH role_labels COMPLETE")
