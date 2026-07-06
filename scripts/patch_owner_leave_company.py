import sys

path = "lib/main.dart"
f = open(path, "r", encoding="utf-8")
content = f.read()
f.close()

pairs = [
    ("""'leaveCompanyConfirm': 'Вы уверены, что хотите выйти из этой команды?',""", """'leaveCompanyConfirm': 'Вы уверены, что хотите выйти из этой команды?',
      'ownerCannotLeaveCompany': 'Как владелец компании вы не можете её покинуть. Используйте вместо этого «Удалить компанию» или сначала передайте права владельца другому человеку.',"""),
    ("""'leaveCompanyConfirm': 'Ви впевнені, що хочете вийти з цієї команди?',""", """'leaveCompanyConfirm': 'Ви впевнені, що хочете вийти з цієї команди?',
      'ownerCannotLeaveCompany': 'Як власник компанії ви не можете її покинути. Скористайтеся замість цього «Видалити компанію» або спочатку передайте права власника іншій особі.',"""),
    ("""'leaveCompanyConfirm': 'Czy na pewno chcesz opuścić ten zespół?',""", """'leaveCompanyConfirm': 'Czy na pewno chcesz opuścić ten zespół?',
      'ownerCannotLeaveCompany': 'Jako właściciel firmy nie możesz jej opuścić. Użyj zamiast tego opcji „Usuń firmę” lub najpierw przekaż prawa właściciela innej osobie.',"""),
    ("""'leaveCompanyConfirm': 'Are you sure you want to leave this team?',""", """'leaveCompanyConfirm': 'Are you sure you want to leave this team?',
      'ownerCannotLeaveCompany': 'As the owner of the company, you cannot leave it. Use Delete company instead, or transfer ownership to someone else first.',"""),
    ("""'leaveCompanyConfirm': 'Möchten Sie dieses Team wirklich verlassen?',""", """'leaveCompanyConfirm': 'Möchten Sie dieses Team wirklich verlassen?',
      'ownerCannotLeaveCompany': 'Als Eigentümer des Unternehmens können Sie es nicht verlassen. Verwenden Sie stattdessen die Funktion Unternehmen löschen, oder übertragen Sie zuerst die Eigentümerschaft an eine andere Person.',"""),
    ("""'leaveCompanyConfirm': 'Êtes-vous sûr de vouloir quitter cette équipe ?',""", """'leaveCompanyConfirm': 'Êtes-vous sûr de vouloir quitter cette équipe ?',
      'ownerCannotLeaveCompany': 'En tant que propriétaire de la société, vous ne pouvez pas la quitter. Utilisez à la place Supprimer la société, ou transférez la propriété à une autre personne en premier.',"""),
    ("""'leaveCompanyConfirm': '¿Está seguro de que desea salir de este equipo?',""", """'leaveCompanyConfirm': '¿Está seguro de que desea salir de este equipo?',
      'ownerCannotLeaveCompany': 'Como propietario de la empresa, no puede abandonarla. Use en su lugar Eliminar empresa, o transfiera la propiedad a otra persona primero.',"""),
    ("""'leaveCompanyConfirm': 'Sei sicuro di voler lasciare questo team?',""", """'leaveCompanyConfirm': 'Sei sicuro di voler lasciare questo team?',
      'ownerCannotLeaveCompany': 'Essendo il proprietario, non puoi lasciare questa azienda. Usa invece la funzione Elimina azienda, oppure trasferisci prima la proprietà a qualcun altro.',"""),
    ("""'leaveCompanyConfirm': 'Tem certeza que deseja sair desta equipe?',""", """'leaveCompanyConfirm': 'Tem certeza que deseja sair desta equipe?',
      'ownerCannotLeaveCompany': 'Como proprietário da empresa, você não pode sair dela. Use em vez disso Excluir empresa, ou transfira a propriedade para outra pessoa primeiro.',"""),
    ("""'leaveCompanyConfirm': 'Opravdu chcete opustit tento tým?',""", """'leaveCompanyConfirm': 'Opravdu chcete opustit tento tým?',
      'ownerCannotLeaveCompany': 'Jako vlastník firmy ji nemůžete opustit. Místo toho použijte možnost Smazat firmu, nebo nejprve převeďte vlastnictví na jinou osobu.',"""),
    ("""'leaveCompanyConfirm': 'Eşti sigur că vrei să părăseşti echipa?',""", """'leaveCompanyConfirm': 'Eşti sigur că vrei să părăseşti echipa?',
      'ownerCannotLeaveCompany': 'Fiind proprietarul companiei, nu o poți părăsi. Folosește în schimb opțiunea Șterge compania, sau transferă mai întâi proprietatea altei persoane.',"""),
    ("""'leaveCompanyConfirm': 'Weet u zeker dat u dit team wilt verlaten?',""", """'leaveCompanyConfirm': 'Weet u zeker dat u dit team wilt verlaten?',
      'ownerCannotLeaveCompany': 'Als eigenaar van het bedrijf kunt u het niet verlaten. Gebruik in plaats daarvan Bedrijf verwijderen, of draag eerst het eigendom over aan iemand anders.',"""),
    ("""'leaveCompanyConfirm': 'Bu takımdan ayrılmak istediğinizden emin misiniz?',""", """'leaveCompanyConfirm': 'Bu takımdan ayrılmak istediğinizden emin misiniz?',
      'ownerCannotLeaveCompany': 'Şirketin sahibi olarak şirketten ayrılamazsınız. Bunun yerine Şirketi Sil seçeneğini kullanın veya önce sahipliği başka birine devredin.',"""),
    ("""'leaveCompanyConfirm': 'هل أنت متأكد من رغبتك في مغادرة هذا الفريق؟',""", """'leaveCompanyConfirm': 'هل أنت متأكد من رغبتك في مغادرة هذا الفريق؟',
      'ownerCannotLeaveCompany': 'بصفتك مالك الشركة، لا يمكنك مغادرتها. استخدم بدلاً من ذلك خيار حذف الشركة، أو انقل الملكية إلى شخص آخر أولاً.',"""),
    ("""'leaveCompanyConfirm': 'क्या आप वाकई इस टीम से निकलना चाहते हैं?',""", """'leaveCompanyConfirm': 'क्या आप वाकई इस टीम से निकलना चाहते हैं?',
      'ownerCannotLeaveCompany': 'कंपनी के मालिक होने के नाते, आप इसे नहीं छोड़ सकते। इसके बजाय कंपनी हटाएं विकल्प का उपयोग करें, या पहले स्वामित्व किसी और को स्थानांतरित करें।',"""),
    ("""'leaveCompanyConfirm': '이 팀에서 나가시겠습니까?',""", """'leaveCompanyConfirm': '이 팀에서 나가시겠습니까?',
      'ownerCannotLeaveCompany': '회사의 소유자로서 회사를 떠날 수 없습니다. 대신 회사 삭제 기능을 사용하거나 먼저 소유권을 다른 사람에게 이전하세요.',"""),
    ("""'leaveCompanyConfirm': 'このチームを退出しますか？',""", """'leaveCompanyConfirm': 'このチームを退出しますか？',
      'ownerCannotLeaveCompany': '会社のオーナーは会社を退出できません。代わりに会社を削除の機能を使用するか、先に所有権を他の人に譲渡してください。',"""),
    ("""'leaveCompanyConfirm': '您确定要离开这个团队吗？',""", """'leaveCompanyConfirm': '您确定要离开这个团队吗？',
      'ownerCannotLeaveCompany': '作为公司所有者,您不能离开公司。请改用删除公司功能,或先将所有权转让给他人。',"""),
    ("""'leaveCompanyConfirm': 'Apakah Anda yakin ingin meninggalkan tim ini?',""", """'leaveCompanyConfirm': 'Apakah Anda yakin ingin meninggalkan tim ini?',
      'ownerCannotLeaveCompany': 'Sebagai pemilik perusahaan, Anda tidak dapat meninggalkannya. Gunakan fitur Hapus perusahaan sebagai gantinya, atau alihkan kepemilikan ke orang lain terlebih dahulu.',"""),
    ("""'leaveCompanyConfirm': 'Bạn có chắc chắn muốn rời khỏi nhóm này không?',""", """'leaveCompanyConfirm': 'Bạn có chắc chắn muốn rời khỏi nhóm này không?',
      'ownerCannotLeaveCompany': 'Là chủ sở hữu công ty, bạn không thể rời khỏi công ty. Hãy sử dụng chức năng Xóa công ty thay vào đó, hoặc chuyển quyền sở hữu cho người khác trước.',"""),
    ("""'leaveCompanyConfirm': 'Sigurado ka bang gusto mong umalis sa koponang ito?',""", """'leaveCompanyConfirm': 'Sigurado ka bang gusto mong umalis sa koponang ito?',
      'ownerCannotLeaveCompany': 'Bilang may-ari ng kumpanya, hindi ka maaaring umalis dito. Gamitin ang tampok na Tanggalin ang kumpanya sa halip, o ilipat muna ang pagmamay-ari sa iba.',"""),
]

for anchor, replacement in pairs:
    cnt = content.count(anchor)
    if cnt != 1:
        sys.exit("i18n anchor not found or duplicated, count=" + str(cnt))
    content = content.replace(anchor, replacement)

func_anchor = """Future<void> _leaveCompany(BuildContext context) async {
    final i18n = AppState.of(context).i18n;
    final ok = await showDialog<bool>("""
func_replacement = """Future<void> _leaveCompany(BuildContext context) async {
    final i18n = AppState.of(context).i18n;
    if (isOwner) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(i18n.t('leaveCompany')),
          content: Text(i18n.t('ownerCannotLeaveCompany')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.t('ok'))),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>("""

cnt2 = content.count(func_anchor)
if cnt2 != 1:
    sys.exit("function anchor not found, count=" + str(cnt2))
content = content.replace(func_anchor, func_replacement)

f = open(path, "w", encoding="utf-8")
f.write(content)
f.close()

print("Patch applied: company owner can no longer silently leave the company; added ownerCannotLeaveCompany translations for 21 languages")
