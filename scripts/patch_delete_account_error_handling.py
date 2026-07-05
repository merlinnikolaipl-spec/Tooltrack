import sys
path = "lib/main.dart"
f = open(path, "r", encoding="utf-8"); content = f.read(); f.close()

anchor1 = "  if (ok != true) return;\n  final user = FirebaseAuth.instance.currentUser;\n  if (user == null) return;\n  final uid = user.uid;\n  try {\n    await userDoc(uid).delete();\n  } catch (_) {}\n  try {\n    await user.delete();\n  } catch (_) {}\n  try {\n    await FirebaseAuth.instance.signOut();\n  } catch (_) {}\n  if (!context.mounted) return;\n  Navigator.of(context).pushAndRemoveUntil(\n    MaterialPageRoute(builder: (_) => const AppRouter()),\n    (_) => false,\n  );\n}"
replacement1 = "  if (ok != true) return;\n  final user = FirebaseAuth.instance.currentUser;\n  if (user == null) return;\n  final uid = user.uid;\n  try {\n    await user.delete();\n  } catch (e) {\n    if (!context.mounted) return;\n    final i18nErr = AppState.of(context).i18n;\n    await showDialog<void>(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        title: Text(i18nErr.t('deleteAccountTitle')),\n        content: Text(i18nErr.t('deleteAccountRecentLoginError')),\n        actions: [\n          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18nErr.t('ok'))),\n        ],\n      ),\n    );\n    return;\n  }\n  try {\n    await userDoc(uid).delete();\n  } catch (_) {}\n  try {\n    await FirebaseAuth.instance.signOut();\n  } catch (_) {}\n  if (!context.mounted) return;\n  Navigator.of(context).pushAndRemoveUntil(\n    MaterialPageRoute(builder: (_) => const AppRouter()),\n    (_) => false,\n  );\n}"
cnt1 = content.count(anchor1)
content = content.replace(anchor1, replacement1) if cnt1 == 1 else sys.exit("anchor1 not found, count=" + str(cnt1))

anchor2 = "    if (ok != true) return;\n    final user = FirebaseAuth.instance.currentUser;\n    if (user == null) return;\n    final uid = user.uid;\n    try {\n      await userDoc(uid).delete();\n    } catch (_) {}\n    try {\n      await user.delete();\n    } catch (_) {}\n    try {\n      await FirebaseAuth.instance.signOut();\n    } catch (_) {}\n    if (!context.mounted) return;\n    Navigator.of(context).pushAndRemoveUntil(\n      MaterialPageRoute(builder: (_) => const AppRouter()),\n      (_) => false,\n    );\n  }"
replacement2 = "    if (ok != true) return;\n    final user = FirebaseAuth.instance.currentUser;\n    if (user == null) return;\n    final uid = user.uid;\n    try {\n      await user.delete();\n    } catch (e) {\n      if (!context.mounted) return;\n      final i18nErr = AppState.of(context).i18n;\n      await showDialog<void>(\n        context: context,\n        builder: (ctx) => AlertDialog(\n          title: Text(i18nErr.t('deleteAccountTitle')),\n          content: Text(i18nErr.t('deleteAccountRecentLoginError')),\n          actions: [\n            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18nErr.t('ok'))),\n          ],\n        ),\n      );\n      return;\n    }\n    try {\n      await userDoc(uid).delete();\n    } catch (_) {}\n    try {\n      await FirebaseAuth.instance.signOut();\n    } catch (_) {}\n    if (!context.mounted) return;\n    Navigator.of(context).pushAndRemoveUntil(\n      MaterialPageRoute(builder: (_) => const AppRouter()),\n      (_) => false,\n    );\n  }"
cnt2 = content.count(anchor2)
content = content.replace(anchor2, replacement2) if cnt2 == 1 else sys.exit("anchor2 not found, count=" + str(cnt2))

a_ru = "'deleteAccountText': 'Все ваши данные будут удалены. Это действие нельзя отменить.',"; n_ru = "      'deleteAccountRecentLoginError': 'Пожалуйста, войдите заново и повторите попытку удаления аккаунта.',"
c_ru = content.count(a_ru)
content = content.replace(a_ru, a_ru + "\n" + n_ru) if c_ru == 1 else sys.exit("ru not found, count=" + str(c_ru))

a_uk = "'deleteAccountText': 'Усі ваші дані будуть видалені. Цю дію неможливо скасувати.',"; n_uk = "      'deleteAccountRecentLoginError': 'Будь ласка, увійдіть знову і повторіть спробу видалення облікового запису.',"
c_uk = content.count(a_uk)
content = content.replace(a_uk, a_uk + "\n" + n_uk) if c_uk == 1 else sys.exit("uk not found, count=" + str(c_uk))

a_pl = "'deleteAccountText': 'Wszystkie Twoje dane zostaną usunięte. Tej operacji nie można cofnąć.',"; n_pl = "      'deleteAccountRecentLoginError': 'Zaloguj się ponownie i spróbuj ponownie usunąć konto.',"
c_pl = content.count(a_pl)
content = content.replace(a_pl, a_pl + "\n" + n_pl) if c_pl == 1 else sys.exit("pl not found, count=" + str(c_pl))

a_en = "'deleteAccountText': 'All your data will be deleted. This action cannot be undone.',"; n_en = "      'deleteAccountRecentLoginError': 'Please sign in again and retry deleting your account.',"
c_en = content.count(a_en)
content = content.replace(a_en, a_en + "\n" + n_en) if c_en == 1 else sys.exit("en not found, count=" + str(c_en))

a_de = "'deleteAccountText': 'Alle Ihre Daten werden gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',"; n_de = "      'deleteAccountRecentLoginError': 'Bitte melden Sie sich erneut an und versuchen Sie erneut, Ihr Konto zu löschen.',"
c_de = content.count(a_de)
content = content.replace(a_de, a_de + "\n" + n_de) if c_de == 1 else sys.exit("de not found, count=" + str(c_de))

a_fr = "'deleteAccountText': 'Toutes vos données seront supprimées. Cette action est irréversible.',"; n_fr = "      'deleteAccountRecentLoginError': 'Veuillez vous reconnecter puis réessayer de supprimer votre compte.',"
c_fr = content.count(a_fr)
content = content.replace(a_fr, a_fr + "\n" + n_fr) if c_fr == 1 else sys.exit("fr not found, count=" + str(c_fr))

a_es = "'deleteAccountText': 'Todos sus datos serán eliminados. Esta acción no se puede deshacer.',"; n_es = "      'deleteAccountRecentLoginError': 'Por favor, inicia sesión de nuevo e intenta eliminar tu cuenta otra vez.',"
c_es = content.count(a_es)
content = content.replace(a_es, a_es + "\n" + n_es) if c_es == 1 else sys.exit("es not found, count=" + str(c_es))

a_it = "'deleteAccountText': 'Tutti i tuoi dati verranno eliminati. Questa azione è irreversibile.',"; n_it = "      'deleteAccountRecentLoginError': 'Accedi di nuovo e riprova a eliminare il tuo account.',"
c_it = content.count(a_it)
content = content.replace(a_it, a_it + "\n" + n_it) if c_it == 1 else sys.exit("it not found, count=" + str(c_it))

a_pt = "'deleteAccountText': 'Todos os seus dados serão excluídos. Esta ação não pode ser desfeita.',"; n_pt = "      'deleteAccountRecentLoginError': 'Faça login novamente e tente excluir sua conta outra vez.',"
c_pt = content.count(a_pt)
content = content.replace(a_pt, a_pt + "\n" + n_pt) if c_pt == 1 else sys.exit("pt not found, count=" + str(c_pt))

a_cs = "'deleteAccountText': 'Všechna vaše data budou smazána. Tuto akci nelze vrátit.',"; n_cs = "      'deleteAccountRecentLoginError': 'Přihlaste se prosím znovu a zkuste účet smazat znovu.',"
c_cs = content.count(a_cs)
content = content.replace(a_cs, a_cs + "\n" + n_cs) if c_cs == 1 else sys.exit("cs not found, count=" + str(c_cs))

a_ro = "'deleteAccountText': 'Toate datele dvs. vor fi śterse. Această acţiune este ireversibilă.',"; n_ro = "      'deleteAccountRecentLoginError': 'Vă rugăm să vă conectați din nou și să încercați să ștergeți contul din nou.',"
c_ro = content.count(a_ro)
content = content.replace(a_ro, a_ro + "\n" + n_ro) if c_ro == 1 else sys.exit("ro not found, count=" + str(c_ro))

a_nl = "'deleteAccountText': 'Al uw gegevens worden verwijderd. Deze actie kan niet ongedaan worden gemaakt.',"; n_nl = "      'deleteAccountRecentLoginError': 'Log opnieuw in en probeer je account opnieuw te verwijderen.',"
c_nl = content.count(a_nl)
content = content.replace(a_nl, a_nl + "\n" + n_nl) if c_nl == 1 else sys.exit("nl not found, count=" + str(c_nl))

a_tr = "'deleteAccountText': 'Tüm verileriniz silinecek. Bu işlem geri alınamaz.',"; n_tr = "      'deleteAccountRecentLoginError': 'Lütfen tekrar giriş yapın ve hesabınızı silmeyi tekrar deneyin.',"
c_tr = content.count(a_tr)
content = content.replace(a_tr, a_tr + "\n" + n_tr) if c_tr == 1 else sys.exit("tr not found, count=" + str(c_tr))

a_ar = "'deleteAccountText': 'سيتم حذف جميع بياناتك. لا يمكن التراجع عن هذا الإجراء.',"; n_ar = "      'deleteAccountRecentLoginError': 'يرجى تسجيل الدخول مرة أخرى ثم إعادة محاولة حذف حسابك.',"
c_ar = content.count(a_ar)
content = content.replace(a_ar, a_ar + "\n" + n_ar) if c_ar == 1 else sys.exit("ar not found, count=" + str(c_ar))

a_hi = "'deleteAccountText': 'आपका सारा डेटा हटा दिया जाएगा। यह क्रिया अवापस नहीं हो सकती।',"; n_hi = "      'deleteAccountRecentLoginError': 'कृपया फिर से लॉगिन करें और अपना खाता हटाने का पुनः प्रयास करें।',"
c_hi = content.count(a_hi)
content = content.replace(a_hi, a_hi + "\n" + n_hi) if c_hi == 1 else sys.exit("hi not found, count=" + str(c_hi))

a_ko = "'deleteAccountText': '모든 데이터가 삭제됩니다. 이 작업은 실도할 수 없습니다.',"; n_ko = "      'deleteAccountRecentLoginError': '다시 로그인한 후 계정 삭제를 다시 시도해 주세요.',"
c_ko = content.count(a_ko)
content = content.replace(a_ko, a_ko + "\n" + n_ko) if c_ko == 1 else sys.exit("ko not found, count=" + str(c_ko))

a_ja = "'deleteAccountText': 'すべてのデータが削除されます。この操作は元に戻せません。',"; n_ja = "      'deleteAccountRecentLoginError': 'もう一度サインインしてから、アカウントの削除を再試行してください。',"
c_ja = content.count(a_ja)
content = content.replace(a_ja, a_ja + "\n" + n_ja) if c_ja == 1 else sys.exit("ja not found, count=" + str(c_ja))

a_zh = "'deleteAccountText': '您的所有数据将被删除。此操作无法恢复。',"; n_zh = "      'deleteAccountRecentLoginError': '请重新登录后再尝试删除您的账户。',"
c_zh = content.count(a_zh)
content = content.replace(a_zh, a_zh + "\n" + n_zh) if c_zh == 1 else sys.exit("zh not found, count=" + str(c_zh))

a_id = "'deleteAccountText': 'Semua data Anda akan dihapus. Tindakan ini tidak dapat dibatalkan.',"; n_id = "      'deleteAccountRecentLoginError': 'Silakan masuk lagi lalu coba hapus akun Anda kembali.',"
c_id = content.count(a_id)
content = content.replace(a_id, a_id + "\n" + n_id) if c_id == 1 else sys.exit("id not found, count=" + str(c_id))

a_vi = "'deleteAccountText': 'Tất cả dữ liệu của bạn sẽ bị xóa. Hành động này không thể hoàn tác.',"; n_vi = "      'deleteAccountRecentLoginError': 'Vui lòng đăng nhập lại rồi thử xóa tài khoản lại.',"
c_vi = content.count(a_vi)
content = content.replace(a_vi, a_vi + "\n" + n_vi) if c_vi == 1 else sys.exit("vi not found, count=" + str(c_vi))

a_tl = "'deleteAccountText': 'Lahat ng iyong data ay mabubura. Hindi maaaring i-undo ang aksyong ito.',"; n_tl = "      'deleteAccountRecentLoginError': 'Mangyaring mag-sign in muli at subukang burahin ulit ang iyong account.',"
c_tl = content.count(a_tl)
content = content.replace(a_tl, a_tl + "\n" + n_tl) if c_tl == 1 else sys.exit("tl not found, count=" + str(c_tl))

f = open(path, "w", encoding="utf-8"); f.write(content); f.close()
print("Patch applied successfully")
