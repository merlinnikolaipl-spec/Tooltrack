import sys

PATH = "lib/main.dart"

with open(PATH, "r", encoding="utf-8") as f:
    content = f.read()

PAIRS = []
PAIRS.append(("class _ToolsPageState extends State<ToolsPage> {", "class _ToolsPageState extends State<ToolsPage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _toolsStream;"))
PAIRS.append(("stream: companyToolsRef(widget.companyId).orderBy('createdAt', descending: true).snapshots(),", "stream: _toolsStream ??= companyToolsRef(widget.companyId).orderBy('createdAt', descending: true).limit(200).snapshots(),"))
PAIRS.append(("class _PeoplePageState extends State<PeoplePage> {", "class _PeoplePageState extends State<PeoplePage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _peopleStream;"))
PAIRS.append(("  Widget _buildList(I18n i18n, {String? type, bool activeOnly = true}) {\n    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(\n      stream: companyPeopleRef(widget.companyId).snapshots(),", "  Widget _buildList(I18n i18n, {String? type, bool activeOnly = true}) {\n    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(\n      stream: _peopleStream ??= companyPeopleRef(widget.companyId).limit(200).snapshots(),"))
PAIRS.append(("class _EmployeesListCardState extends State<EmployeesListCard> {", "class _EmployeesListCardState extends State<EmployeesListCard> { Stream<QuerySnapshot<Map<String, dynamic>>>? _membersStream;"))
PAIRS.append(("stream: companyMembersRef(widget.companyId).where('status', isEqualTo: 'active').snapshots(),", "stream: _membersStream ??= companyMembersRef(widget.companyId).where('status', isEqualTo: 'active').limit(200).snapshots(),"))
PAIRS.append(("class _HistoryTabState extends State<HistoryTab> {", "class _HistoryTabState extends State<HistoryTab> { Stream<QuerySnapshot<Map<String, dynamic>>>? _movesStream;"))
PAIRS.append(("stream: companyMovesRef(widget.companyId).orderBy('createdAt', descending: true).snapshots(),", "stream: _movesStream ??= companyMovesRef(widget.companyId).orderBy('createdAt', descending: true).limit(200).snapshots(),"))
PAIRS.append(("class _TimesheetsPageState extends State<TimesheetsPage> {", "class _TimesheetsPageState extends State<TimesheetsPage> { Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedStream;"))
PAIRS.append(("Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {", "Stream<QuerySnapshot<Map<String, dynamic>>> get _stream => _cachedStream ??= _computeStream(); Stream<QuerySnapshot<Map<String, dynamic>>> _computeStream() {"))

for old, new in PAIRS:
    count = content.count(old)
    if count != 1:
        print(f"ERROR: expected 1 occurrence, found {count} for: {old[:70]}")
        sys.exit(1)
    content = content.replace(old, new)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("Firestore read optimization patch applied successfully")
