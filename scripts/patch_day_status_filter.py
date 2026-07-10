import sys

PATH = "lib/main.dart"

with open(PATH, "r", encoding="utf-8") as f:
    content = f.read()

PAIRS = []
PAIRS.append(("bool _exporting = false;", "bool _exporting = false; DateTime? _dayFilter; String? _statusFilter;"))
PAIRS.append(("_loadSites();", "_loadSites(); _dayFilter = DateTime.now();"))
PAIRS.append(("String _fmtMonth(String ym) {", "String _fmtDay(DateTime d, I18n i18n) { final now = DateTime.now(); if (d.year == now.year && d.month == now.month && d.day == now.day) return i18n.t('today'); String p(int n) => n.toString().padLeft(2, '0'); return p(d.day) + '.' + p(d.month) + '.' + d.year.toString(); } String _fmtMonth(String ym) {"))
PAIRS.append(("if (_personFilter != null) {", "if (_dayFilter != null) { result = result.where((d) { final dt = (d.data()['startTime'] as Timestamp?)?.toDate(); return dt != null && dt.year == _dayFilter!.year && dt.month == _dayFilter!.month && dt.day == _dayFilter!.day; }).toList(); } if (_statusFilter != null) { result = result.where((d) { final isActive = d.data()['endTime'] == null; return _statusFilter == 'active' ? isActive : !isActive; }).toList(); } if (_personFilter != null) {"))
PAIRS.append(("onChanged: (v) => setState(() => _monthFilter = v),", "onChanged: (v) => setState(() { _monthFilter = v; _dayFilter = null; }),"))
PAIRS.append(("if (_sites.isNotEmpty) ...[", "const SizedBox(width: 12), OutlinedButton.icon(icon: const Icon(Icons.calendar_today, size: 16), label: Text(_dayFilter == null ? i18n.t('allDays') : _fmtDay(_dayFilter!, i18n)), onPressed: () async { final picked = await showDatePicker(context: context, initialDate: _dayFilter ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 1)); if (picked != null) { setState(() { _dayFilter = picked; _monthFilter = null; }); } }), if (_dayFilter != null) IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: i18n.t('allDays'), onPressed: () => setState(() => _dayFilter = null)), const SizedBox(width: 12), DropdownButton<String?>(value: _statusFilter, isDense: true, hint: Text(i18n.t('allStatuses')), items: [DropdownMenuItem(value: null, child: Text(i18n.t('allStatuses'))), DropdownMenuItem(value: 'active', child: Text(i18n.t('filterActive'))), DropdownMenuItem(value: 'completed', child: Text(i18n.t('shiftCompleted')))], onChanged: (v) => setState(() => _statusFilter = v)), const SizedBox(width: 12), if (_sites.isNotEmpty) ...["))
PAIRS.append(("'allTime': 'Всё время',", "'allTime': 'Всё время', 'allDays': 'Все дни', 'today': 'Сегодня', 'allStatuses': 'Все статусы', 'filterActive': 'Активна', 'shiftCompleted': 'Завершена',"))

for old, new in PAIRS:
    count = content.count(old)
    ok = count == 1
    if not ok:
        print("ERROR: expected exactly 1 occurrence, found " + str(count) + ": " + old[:60])
    if not ok:
        sys.exit(1)
    content = content.replace(old, new, 1)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: day/status filters for timesheets patch applied")
