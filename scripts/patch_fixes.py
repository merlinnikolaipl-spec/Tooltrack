#!/usr/bin/env python3
# patch_fixes.py - Apple Review fixes (all 21 languages)
# Adds: deleteAccount keys, leaveCompanyConfirm dialog, rename owner/employee to team

import sys, re

with open("lib/main.dart", "r", encoding="utf-8") as f:
        src = f.read()

print(f"Processing main.dart ({len(src)} chars)")

# Step 1: Add deleteAccount and leaveCompanyConfirm i18n keys after each logout entry
# Dictionary: logout_key -> (deleteAccount_value, leaveCompanyConfirm_value)
trans = {
        "'logout': 'Выйти',": ("'deleteAccount': 'Удалить аккаунт',", "'leaveCompanyConfirm': 'Выйти?',"),
        "'logout': 'Вийти',": ("'deleteAccount': 'Видалити запис',", "'leaveCompanyConfirm': 'Вийти?',"),
        "'logout': 'Wyloguj',": ("'deleteAccount': 'Usuń',", "'leaveCompanyConfirm': 'Wyloguj?',"),
        "'logout': 'Sign out',": ("'deleteAccount': 'Delete',", "'leaveCompanyConfirm': 'Leave?',"),
        "'logout': 'Abmelden',": ("'deleteAccount': 'Löschen',", "'leaveCompanyConfirm': 'Abmelden?',"),
        "'logout': 'Se déconnecter',": ("'deleteAccount': 'Supprimer',", "'leaveCompanyConfirm': 'Déconnecter?',"),
        "'logout': 'Cerrar sesión',": ("'deleteAccount': 'Eliminar',", "'leaveCompanyConfirm': 'Cerrar?',"),
        "'logout': 'Esci',": ("'deleteAccount': 'Elimina',", "'leaveCompanyConfirm': 'Esci?',"),
        "'logout': 'Sair',": ("'deleteAccount': 'Deletar',", "'leaveCompanyConfirm': 'Sair?',"),
        "'logout': 'Odhlásit se',": ("'deleteAccount': 'Odstranit',", "'leaveCompanyConfirm': 'Odhlásit?',"),
        "'logout': 'Deconectare',": ("'deleteAccount': 'Șterge',", "'leaveCompanyConfirm': 'Deconectare?',"),
        "'logout': 'Afmelden',": ("'deleteAccount': 'Verwijderen',", "'leaveCompanyConfirm': 'Afmelden?',"),
        "'logout': 'Çıkış Yap',": ("'deleteAccount': 'Sil',", "'leaveCompanyConfirm': 'Çıkış?',"),
        "'logout': 'تسجيل الخروج',": ("'deleteAccount': 'حذف',", "'leaveCompanyConfirm': 'الخروج?',"),
        "'logout': 'लॉग आउट करें',": ("'deleteAccount': 'हटाएं',", "'leaveCompanyConfirm': 'आउट?',"),
        "'logout': '로그아웃',": ("'deleteAccount': '삭제',", "'leaveCompanyConfirm': '아웃?',"),
        "'logout': 'ログアウト',": ("'deleteAccount': '削除',", "'leaveCompanyConfirm': 'ログ?',"),
        "'logout': '退出',": ("'deleteAccount': '删除',", "'leaveCompanyConfirm': '退出?',"),
        "'logout': 'Keluar',": ("'deleteAccount': 'Hapus',", "'leaveCompanyConfirm': 'Keluar?',"),
        "'logout': 'Đăng xuất',": ("'deleteAccount': 'Xóa',", "'leaveCompanyConfirm': 'Đăng?',"),
        "'logout': 'Mag-logout',": ("'deleteAccount': 'Tanggalin',", "'leaveCompanyConfirm': 'Logout?',"),
}

for logout_k, (del_k, leave_k) in trans.items():
        if logout_k in src:
                    pos = src.find(logout_k) + len(logout_k)
                    insert = f"\n      {del_k}\n      {leave_k}"
                    src = src[:pos] + insert + src[pos:]

    print("✓ Added i18n keys")

# Step 2: Rename owner/employee to team labels
renames = [
        ("'owner': 'Владелец фирмы',", "'owner': 'Создать команду',"),
        ("'employee': 'Сотрудник',", "'employee': 'Присоединиться',"),
        ("'owner': 'Owner',", "'owner': 'Create team',"),
        ("'employee': 'Employee',", "'employee': 'Join team',"),
]

for old, new in renames:
        src = src.replace(old, new)

print("✓ Renamed owner/employee")

with open("lib/main.dart", "w", encoding="utf-8") as f:
        f.write(src)

print("✅ Done!")
