import re
import sys

path = "lib/main.dart"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

translations = [
    """Как владелец компании вы не можете её покинуть. Используйте вместо этого «Удалить компанию» или сначала передайте права владельца другому человеку.""",
    """Як власник компанії ви не можете її покинути. Скористайтеся замість цього «Видалити компанію» або спочатку передайте права власника іншій особі.""",
    """Jako właściciel firmy nie możesz jej opuścić. Użyj zamiast tego opcji „Usuń firmę” lub najpierw przekaż prawa właściciela innej osobie.""",
    """As the owner of the company, you cannot leave it. Use Delete company instead, or transfer ownership to someone else first.""",
    """Als Eigentümer des Unternehmens können Sie es nicht verlassen. Verwenden Sie stattdessen die Funktion Unternehmen löschen, oder übertragen Sie zuerst die Eigentümerschaft an eine andere Person.""",
    """En tant que propriétaire de la société, vous ne pouvez pas la quitter. Utilisez à la place Supprimer la société, ou transférez la propriété à une autre personne en premier.""",
    """Como propietario de la empresa, no puede abandonarla. Use en su lugar Eliminar empresa, o transfiera la propiedad a otra persona primero.""",
    """Essendo il proprietario, non puoi lasciare questa azienda. Usa invece la funzione Elimina azienda, oppure trasferisci prima la proprietà a qualcun altro.""",
    """Como proprietário da empresa, você não pode sair dela. Use em vez disso Excluir empresa, ou transfira a propriedade para outra pessoa primeiro.""",
    """Jako vlastník firmy ji nemůžete opustit. Místo toho použijte možnost Smazat firmu, nebo nejprve převeďte vlastnictví na jinou osobu.""",
    """Fiind proprietarul companiei, nu o poți părăsi. Folosește în schimb opțiunea Șterge compania, sau transferă mai întâi proprietatea altei persoane.""",
    """Als eigenaar van het bedrijf kunt u het niet verlaten. Gebruik in plaats daarvan Bedrijf verwijderen, of draag eerst het eigendom over aan iemand anders.""",
    """Şirketin sahibi olarak şirketten ayrılamazsınız. Bunun yerine Şirketi Sil seçeneğini kullanın veya önce sahipliği başka birine devredin.""",
    """بصفتك مالك الشركة، لا يمكنك مغادرتها. استخدم بدلاً من ذلك خيار حذف الشركة، أو انقل الملكية إلى شخص آخر أولاً.""",
    """कंपनी के मालिक होने के नाते, आप इसे नहीं छोड़ सकते। इसके बजाय कंपनी हटाएं विकल्प का उपयोग करें, या पहले स्वामित्व किसी और को स्थानांतरित करें।""",
    """회사의 소유자로서 회사를 떠날 수 없습니다. 대신 회사 삭제 기능을 사용하거나 먼저 소유권을 다른 사람에게 이전하세요.""",
    """会社のオーナーは会社を退出できません。代わりに会社を削除の機能を使用するか、先に所有権を他の人に譲渡してください。""",
    """作为公司所有者,您不能离开公司。请改用删除公司功能,或先将所有权转让给他人。""",
    """Sebagai pemilik perusahaan, Anda tidak dapat meninggalkannya. Gunakan fitur Hapus perusahaan sebagai gantinya, atau alihkan kepemilikan ke orang lain terlebih dahulu.""",
    """Là chủ sở hữu công ty, bạn không thể rời khỏi công ty. Hãy sử dụng chức năng Xóa công ty thay vào đó, hoặc chuyển quyền sở hữu cho người khác trước.""",
    """Bilang may-ari ng kumpanya, hindi ka maaaring umalis dito. Gamitin ang tampok na Tanggalin ang kumpanya sa halip, o ilipat muna ang pagmamay-ari sa iba.""",
]

pattern = re.compile(r"'leaveCompany':\s*'[^']*',")
matches = list(pattern.finditer(content))
if len(matches) != 21:
    sys.exit("Expected 21 leaveCompany keys, found " + str(len(matches)))

parts = []
last_end = 0
for i, m in enumerate(matches):
    parts.append(content[last_end:m.end()])
    parts.append("\n      'ownerCannotLeaveCompany': '" + translations[i] + "',")
    last_end = m.end()
parts.append(content[last_end:])
content = "".join(parts)

func_sig = "_leaveCompany(BuildContext context) async {"
sig_idx = content.find(func_sig)
if sig_idx == -1:
    sys.exit("_leaveCompany function signature not found")
if content.find(func_sig, sig_idx + 1) != -1:
    sys.exit("_leaveCompany function signature is not unique")

insert_pos = sig_idx + len(func_sig)
owner_check = (
    "\n    final _ownerCheckI18n = I18n(AppState.of(context).lang.value);"
    "\n    if (isOwner) {"
    "\n      await showDialog<void>("
    "\n        context: context,"
    "\n        builder: (ctx) => AlertDialog("
    "\n          title: Text(_ownerCheckI18n.t('leaveCompany')),"
    "\n          content: Text(_ownerCheckI18n.t('ownerCannotLeaveCompany')),"
    "\n          actions: ["
    "\n            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_ownerCheckI18n.t('ok'))),"
    "\n          ],"
    "\n        ),"
    "\n      );"
    "\n      return;"
    "\n    }"
)
content = content[:insert_pos] + owner_check + content[insert_pos:]

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("Patch applied: company owner can no longer silently leave the company; added ownerCannotLeaveCompany translations for 21 languages")
