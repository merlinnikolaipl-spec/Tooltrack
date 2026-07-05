#!/usr/bin/env python3
"""
patch_account_deletion.py v1
Adds account deletion capability (Apple Guideline 5.1.1(v)):
1. Adds a top-level _deleteAccount(BuildContext) function (confirmation dialog +
   Firestore user doc cleanup + Firebase Auth account deletion + sign-out + navigation).
2. Adds a "Delete account" button to RoleChoicePage (shown when the user has no company).
3. Adds a "Delete account" button to CompanyProfilePage (shown when the user has a company).
4. Adds translations for 4 new keys across all 21 supported languages inside the
   in-file I18n._dict map.

This script runs AFTER the workflow's "Restore original main.dart from git history" step
and AFTER patch_gps_dialog.py / patch_apple_signin.py, so its changes survive every build.
Direct edits to lib/main.dart on the main branch do NOT survive, since that file is
restored from a fixed git SHA before every build.
"""

import sys, re

MAIN_DART = "lib/main.dart"

with open(MAIN_DART, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- Step 1: add _deleteAccount() top-level function ----------

SIGNOUT_ANCHOR = (
    "Future<void> signOutAll() async {\n"
    "  try {\n"
    "    await GoogleSignIn().signOut();\n"
    "  } catch (_) {}\n"
    "  await FirebaseAuth.instance.signOut();\n"
    "}"
)

DELETE_ACCOUNT_FN = '''

Future<void> _deleteAccount(BuildContext context) async {
  final i18n = I18n(AppState.of(context).lang.value);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(i18n.t('deleteAccountTitle')),
      content: Text(i18n.t('deleteAccountText')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(i18n.t('delete')),
        ),
      ],
    ),
  );

  if (ok != true) return;

  final u = FirebaseAuth.instance.currentUser;
  bool needsReauth = false;
  if (u != null) {
    try {
      await userDoc().delete();
    } catch (_) {}
    try {
      await u.delete();
    } catch (e) {
      needsReauth = true;
    }
  }

  if (needsReauth) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(i18n.t('deleteAccountReauthRequired'))),
    );
    return;
  }

  await signOutAll();

  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (_) => false,
  );
}'''

pos = src.find(SIGNOUT_ANCHOR)
if pos == -1:
    print("ERROR: signOutAll() anchor not found (step 1)"); sys.exit(1)
insert_pos = pos + len(SIGNOUT_ANCHOR)
src = src[:insert_pos] + DELETE_ACCOUNT_FN + src[insert_pos:]
print("Step 1 OK: _deleteAccount() function added")

# ---------- Step 2: add button to RoleChoicePage ----------

ROLE_ANCHOR = (
    "label: Text(i18n.t('employee')),\n"
    "              ),\n"
    "            ),\n"
    "          ],"
)

ROLE_BUTTON = '''label: Text(i18n.t('employee')),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _deleteAccount(context),
              child: Text(
                i18n.t('deleteAccount'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],'''

if ROLE_ANCHOR not in src:
    print("ERROR: RoleChoicePage anchor not found (step 2)"); sys.exit(1)
src = src.replace(ROLE_ANCHOR, ROLE_BUTTON, 1)
print("Step 2 OK: RoleChoicePage delete-account button added")

# ---------- Step 3: add button to CompanyProfilePage ----------

PROFILE_ANCHOR = (
    "onPressed: () async => onLogout(),\n"
    "          child: Text(i18n.t('logout')),\n"
    "        ),"
)

PROFILE_BUTTON = '''onPressed: () async => onLogout(),
          child: Text(i18n.t('logout')),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _deleteAccount(context),
          child: Text(
            i18n.t('deleteAccount'),
            style: const TextStyle(color: Colors.red),
          ),
        ),'''

if PROFILE_ANCHOR not in src:
    print("ERROR: CompanyProfilePage anchor not found (step 3)"); sys.exit(1)
src = src.replace(PROFILE_ANCHOR, PROFILE_BUTTON, 1)
print("Step 3 OK: CompanyProfilePage delete-account button added")

# ---------- Step 4: add translations for all 21 languages ----------

LANGS = ['ru','uk','pl','en','de','fr','es','it','pt','cs','ro','nl',
         'tr','ar','hi','ko','ja','zh','id','vi','tl']

NEW_KEYS = {
    'deleteAccount': {
        'ru': "Удалить аккаунт", 'uk': "Видалити акаунт", 'pl': "Usuń konto",
        'en': "Delete account", 'de': "Konto löschen", 'fr': "Supprimer le compte",
        'es': "Eliminar cuenta", 'it': "Elimina account", 'pt': "Excluir conta",
        'cs': "Smazat účet", 'ro': "Șterge contul", 'nl': "Account verwijderen",
        'tr': "Hesabı sil", 'ar': "حذف الحساب", 'hi': "खाता हटाएं",
        'ko': "계정 삭제", 'ja': "アカウントを削除", 'zh': "删除账户",
        'id': "Hapus akun", 'vi': "Xóa tài khoản", 'tl': "Burahin ang account",
    },
    'deleteAccountTitle': {
        'ru': "Удалить аккаунт?", 'uk': "Видалити акаунт?", 'pl': "Usunąć konto?",
        'en': "Delete account?", 'de': "Konto löschen?", 'fr': "Supprimer le compte ?",
        'es': "¿Eliminar cuenta?", 'it': "Eliminare l'account?", 'pt': "Excluir conta?",
        'cs': "Smazat účet?", 'ro': "Ștergeți contul?", 'nl': "Account verwijderen?",
        'tr': "Hesap silinsin mi?", 'ar': "هل تريد حذف الحساب؟", 'hi': "क्या खाता हटाना है?",
        'ko': "계정을 삭제하시겠습니까?", 'ja': "アカウントを削除しますか?", 'zh': "删除账户吗?",
        'id': "Hapus akun?", 'vi': "Xóa tài khoản?", 'tl': "Burahin ang account?",
    },
    'deleteAccountText': {
        'ru': "Это навсегда удалит ваш аккаунт и все связанные данные. Действие необратимо.",
        'uk': "Це назавжди видалить ваш акаунт і всі пов'язані дані. Дію неможливо скасувати.",
        'pl': "Spowoduje to trwałe usunięcie konta i wszystkich powiązanych danych. Tej czynności nie można cofnąć.",
        'en': "This will permanently delete your account and all associated data. This action cannot be undone.",
        'de': "Dadurch werden Ihr Konto und alle zugehörigen Daten dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.",
        'fr': "Cela supprimera définitivement votre compte et toutes les données associées. Cette action est irréversible.",
        'es': "Esto eliminará permanentemente tu cuenta y todos los datos asociados. Esta acción no se puede deshacer.",
        'it': "Questo eliminerà definitivamente il tuo account e tutti i dati associati. Questa azione non può essere annullata.",
        'pt': "Isso excluirá permanentemente sua conta e todos os dados associados. Esta ação não pode ser desfeita.",
        'cs': "Tímto dojde k trvalému smazání vašeho účtu a všech souvisejících dat. Tuto akci nelze vrátit zpět.",
        'ro': "Aceasta va șterge definitiv contul dvs. și toate datele asociate. Această acțiune nu poate fi anulată.",
        'nl': "Hierdoor worden uw account en alle bijbehorende gegevens permanent verwijderd. Deze actie kan niet ongedaan worden gemaakt.",
        'tr': "Bu işlem hesabınızı ve ilişkili tüm verileri kalıcı olarak silecektir. Bu işlem geri alınamaz.",
        'ar': "سيؤدي هذا إلى حذف حسابك وجميع البيانات المرتبطة به نهائيًا. لا يمكن التراجع عن هذا الإجراء.",
        'hi': "इससे आपका खाता और सभी संबंधित डेटा स्थायी रूप से हट जाएगा। यह क्रिया वापस नहीं ली जा सकती।",
        'ko': "계정과 관련된 모든 데이터가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.",
        'ja': "アカウントと関連するすべてのデータが完全に削除されます。この操作は元に戻せません。",
        'zh': "这将永久删除您的账户及所有相关数据。此操作无法撤销。",
        'id': "Ini akan menghapus akun Anda dan semua data terkait secara permanen. Tindakan ini tidak dapat dibatalkan.",
        'vi': "Thao tác này sẽ xóa vĩnh viễn tài khoản của bạn và toàn bộ dữ liệu liên quan. Không thể hoàn tác.",
        'tl': "Permanenteng mabubura nito ang iyong account at lahat ng kaugnay na data. Hindi na ito maaaring bawiin.",
    },
    'deleteAccountReauthRequired': {
        'ru': "В целях безопасности выйдите из аккаунта, войдите снова и повторите удаление.",
        'uk': "З міркувань безпеки вийдіть з акаунта, увійдіть знову і повторіть видалення.",
        'pl': "Ze względów bezpieczeństwa wyloguj się, zaloguj ponownie i spróbuj usunąć konto jeszcze raz.",
        'en': "For security, please sign out, sign in again, and retry deleting your account.",
        'de': "Aus Sicherheitsgründen melden Sie sich bitte ab, erneut an und versuchen Sie es dann erneut mit dem Löschen.",
        'fr': "Pour des raisons de sécurité, déconnectez-vous, reconnectez-vous puis réessayez de supprimer votre compte.",
        'es': "Por seguridad, cierra sesión, vuelve a iniciarla y reintenta eliminar tu cuenta.",
        'it': "Per motivi di sicurezza, esci, accedi di nuovo e riprova a eliminare l'account.",
        'pt': "Por segurança, saia, entre novamente e tente excluir sua conta de novo.",
        'cs': "Z bezpečnostních důvodů se odhlaste, znovu přihlaste a zkuste účet smazat znovu.",
        'ro': "Din motive de securitate, deconectați-vă, autentificați-vă din nou și reîncercați ștergerea contului.",
        'nl': "Log voor de veiligheid uit, log opnieuw in en probeer het account opnieuw te verwijderen.",
        'tr': "Güvenlik nedeniyle lütfen çıkış yapıp tekrar giriş yapın ve hesabı silmeyi yeniden deneyin.",
        'ar': "لأسباب أمنية، يرجى تسجيل الخروج ثم تسجيل الدخول مرة أخرى وإعادة محاولة حذف حسابك.",
        'hi': "सुरक्षा कारणों से कृपया साइन आउट करें, फिर से साइन इन करें और खाता हटाने का पुनः प्रयास करें।",
        'ko': "보안을 위해 로그아웃 후 다시 로그인하여 계정 삭제를 다시 시도해 주세요.",
        'ja': "セキュリティのため、一度サインアウトして再度サインインしてから、アカウント削除をもう一度お試しください。",
        'zh': "出于安全考虑,请先退出登录,重新登录后再重试删除账户。",
        'id': "Demi keamanan, silakan keluar, masuk kembali, lalu coba hapus akun Anda lagi.",
        'vi': "Vì lý do bảo mật, vui lòng đăng xuất, đăng nhập lại và thử xóa tài khoản một lần nữa.",
        'tl': "Para sa seguridad, mangyaring mag-sign out, mag-sign in muli, at subukan ulit burahin ang account.",
    },
}

close_re = re.compile(r'\n[ ]{0,4}\},\n')

for lang in LANGS:
    anchor = f"AppLang.{lang}: {{"
    pos = src.find(anchor)
    if pos == -1:
        print(f"ERROR: language block start not found for {lang}"); sys.exit(1)
    m = close_re.search(src, pos)
    if not m:
        print(f"ERROR: language block end not found for {lang}"); sys.exit(1)
    end_pos = m.start() + 1  # right after the preceding newline, before the closing brace line
    insertion = ""
    for key, translations in NEW_KEYS.items():
        val = translations[lang].replace("'", "\\'")
        insertion += f"      '{key}': '{val}',\n"
    src = src[:end_pos] + insertion + src[end_pos:]
print("Step 4 OK: translations added for all 21 languages")

with open(MAIN_DART, "w", encoding="utf-8") as f:
    f.write(src)
print("main.dart saved successfully")
print("PATCH account_deletion COMPLETE")
