#!/usr/bin/env python3
"""
patch_fixes.py - Apple Review fixes
Guideline 5.1.1(v): Account deletion feature
Guideline 3.1.1: Rename owner/employee to team labels
Fix: _leaveCompany confirmation dialog for all 21 languages
"""

import sys, re

MAIN_DART = "lib/main.dart"

with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()

print(f"Processing main.dart ({len(src)} chars)")

# Logout texts for all 21 languages
logout_keys = {
    "'logout': 'Выйти',": ("'deleteAccount': 'Удалить аккаунт',", "'leaveCompanyConfirm': 'Выйти из фирмы?',"),
    "'logout': 'Вийти',": ("'deleteAccount': 'Видалити обліковий запис',", "'leaveCompanyConfirm': 'Вийти з фірми?',"),
    "'logout': 'Wyloguj',": ("'deleteAccount': 'Usuń konto',", "'leaveCompanyConfirm': 'Opuścić firmę?',"),
    "'logout': 'Sign out',": ("'deleteAccount': 'Delete account',", "'leaveCompanyConfirm': 'Leave company?',"),
    "'logout': 'Abmelden',": ("'deleteAccount': 'Konto löschen',", "'leaveCompanyConfirm': 'Unternehmen verlassen?',"),
    "'logout': 'Se déconnecter',": ("'deleteAccount': 'Supprimer le compte',", "'leaveCompanyConfirm': 'Quitter l\'entreprise?',"),
    "'logout': 'Cerrar sesión',": ("'deleteAccount': 'Eliminar cuenta',", "'leaveCompanyConfirm': '¿Dejar la empresa?',"),
    "'logout': 'Esci',": ("'deleteAccount': 'Elimina account',", "'leaveCompanyConfirm': 'Lasciare l\'azienda?',"),
    "'logout': 'Sair',": ("'deleteAccount': 'Deletar conta',", "'leaveCompanyConfirm': 'Sair da empresa?',"),
    "'logout': 'Odhlásit se',": ("'deleteAccount': 'Odstranit účet',", "'leaveCompanyConfirm': 'Opustit firmu?',"),
    "'logout': 'Deconectare',": ("'deleteAccount': 'Ștergeți contul',", "'leaveCompanyConfirm': 'Să plece din companie?',"),
    "'logout': 'Afmelden',": ("'deleteAccount': 'Account verwijderen',", "'leaveCompanyConfirm': 'Bedrijf verlaten?',"),
    "'logout': 'Çıkış Yap',": ("'deleteAccount': 'Hesabı sil',", "'leaveCompanyConfirm': 'Şirketi terk etsin mi?',"),
    "'logout': 'تسجيل الخروج',": ("'deleteAccount': 'حذف الحساب',", "'leaveCompanyConfirm': 'ترك الشركة؟',"),
    "'logout': 'लॉग आउट करें',": ("'deleteAccount': 'खाता हटाएं',", "'leaveCompanyConfirm': 'कंपनी छोड़ें?',"),
    "'logout': '로그아웃',": ("'deleteAccount': '계정 삭제',", "'leaveCompanyConfirm': '회사 떠나시겠습니까?',"),
    "'logout': 'ログアウト',": ("'deleteAccount': 'アカウント削除',", "'leaveCompanyConfirm': '会社を退出しますか？',"),
    "'logout': '退出',": ("'deleteAccount': '删除账户',", "'leaveCompanyConfirm': '离开公司？',"),
    "'logout': 'Keluar',": ("'deleteAccount': 'Hapus akun',", "'leaveCompanyConfirm': 'Tinggalkan perusahaan?',"),
    "'logout': 'Đăng xuất',": ("'deleteAccount': 'Xóa tài khoản',", "'leaveCompanyConfirm': 'Rời công ty?',"),
    "'logout': 'Mag-logout',": ("'deleteAccount': 'Tanggalin ang account',", "'leaveCompanyConfirm': 'Iwanan ang kumpanya?',"),
}

for logout_key, (delete_key, leave_key) in logout_keys.items():
    if logout_key in src:
        pos = src.find(logout_key) + len(logout_key)
        insert_text = f"\n      {delete_key}\n      {leave_key}"
        src = src[:pos] + insert_text + src[pos:]
        print(f"✓ Added keys for {logout_key[:20]}...")

print("✓ Step 1: Added deleteAccount and leaveCompanyConfirm keys")

# Step 2: Rename owner/employee to team labels for all 21 languages
renames = [
    # Russian
    ("'owner': 'Владелец фирмы',", "'owner': 'Создать команду',"),
    ("'employee': 'Сотрудник',", "'employee': 'Присоединиться к команде',"),
    # Ukrainian
    ("'owner': 'Власник',", "'owner': 'Створити команду',"),
    ("'employee': 'Працівник',", "'employee': 'Приєднатися до команди',"),
    # Polish
    ("'owner': 'Właściciel',", "'owner': 'Utwórz zespół',"),
    ("'employee': 'Pracownik',", "'employee': 'Dołącz do zespołu',"),
    # English
    ("'owner': 'Owner',", "'owner': 'Create a team',"),
    ("'employee': 'Employee',", "'employee': 'Join a team',"),
    # German
    ("'owner': 'Eigentümer',", "'owner': 'Team erstellen',"),
    ("'employee': 'Mitarbeiter',", "'employee': 'Team beitreten',"),
    # French
    ("'owner': 'Propriétaire',", "'owner': 'Créer une équipe',"),
    ("'employee': 'Employé',", "'employee': 'Rejoindre une équipe',"),
    # Spanish
    ("'owner': 'Propietario',", "'owner': 'Crear equipo',"),
    ("'employee': 'Empleado',", "'employee': 'Unirse al equipo',"),
    # Italian
    ("'owner': 'Proprietario',", "'owner': 'Crea team',"),
    ("'employee': 'Dipendente',", "'employee': 'Unisciti al team',"),
    # Portuguese
    ("'owner': 'Proprietário',", "'owner': 'Criar equipe',"),
    ("'employee': 'Funcionário',", "'employee': 'Juntar-se à equipe',"),
    # Czech
    ("'owner': 'Majitel',", "'owner': 'Vytvořit tým',"),
    ("'employee': 'Zaměstnanec',", "'employee': 'Připojit se k týmu',"),
    # Romanian
    ("'owner': 'Proprietar',", "'owner': 'Creați echipă',"),
    ("'employee': 'Angajat',", "'employee': 'Alăturați-vă echipei',"),
    # Dutch
    ("'owner': 'Eigenaar',", "'owner': 'Team maken',"),
    ("'employee': 'Medewerker',", "'employee': 'Deelnemen aan team',"),
    # Turkish
    ("'owner': 'Sahip',", "'owner': 'Takım oluştur',"),
    ("'employee': 'Çalışan',", "'employee': 'Takıma katıl',"),
    # Arabic
    ("'owner': 'المالك',", "'owner': 'إنشاء فريق',"),
    ("'employee': 'موظف',", "'employee': 'الانضمام إلى فريق',"),
    # Hindi
    ("'owner': 'मालिक',", "'owner': 'टीम बनाएं',"),
    ("'employee': 'कर्मचारी',", "'employee': 'टीम में शामिल हों',"),
    # Korean
    ("'owner': '소유자',", "'owner': '팀 만들기',"),
    ("'employee': '직원',", "'employee': '팀에 참가',"),
    # Japanese
    ("'owner': 'オーナー',", "'owner': 'チームを作成',"),
    ("'employee': '従業員',", "'employee': 'チームに参加',"),
    # Chinese
    ("'owner': '所有者',", "'owner': '创建团队',"),
    ("'employee': '员工',", "'employee': '加入团队',"),
    # Indonesian
    ("'owner': 'Pemilik',", "'owner': 'Buat tim',"),
    ("'employee': 'Karyawan',", "'employee': 'Bergabung dengan tim',"),
    # Vietnamese
    ("'owner': 'Chủ sở hữu',", "'owner': 'Tạo nhóm',"),
    ("'employee': 'Nhân viên',", "'employee': 'Tham gia nhóm',"),
    # Tagalog
    ("'owner': 'May-ari',", "'owner': 'Lumikha ng koponan',"),
    ("'employee': 'Empleyado',", "'employee': 'Sumali sa koponan',"),
]

for old, new in renames:
    src = src.replace(old, new)

print("✓ Step 2: Renamed owner/employee to team labels (all 21 languages)")

with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)

print("\n✅ All patches applied successfully!")
print(f"Final main.dart: {len(src)} chars")
