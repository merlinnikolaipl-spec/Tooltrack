import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'qr_scanner.dart';

CollectionReference<Map<String, dynamic>> companiesRef =
    FirebaseFirestore.instance.collection('companies');

CollectionReference<Map<String, dynamic>> peopleRef(String cid) =>
    companiesRef.doc(cid).collection('people');

CollectionReference<Map<String, dynamic>> toolsRef(String cid) =>
    companiesRef.doc(cid).collection('tools');

CollectionReference<Map<String, dynamic>> movesRef(String cid) =>
    companiesRef.doc(cid).collection('moves');

typedef I18nText = String Function(String key);

class IssueTab extends StatefulWidget {
  final String companyId;
  final String role;
  final I18nText t;

  const IssueTab({
    super.key,
    required this.companyId,
    required this.role,
    required this.t,
  });

  @override
  State<IssueTab> createState() => _IssueTabState();
}

class _IssueTabState extends State<IssueTab> {
  bool _isIssue = true;
  String? _personId;
  String? _selectedGroupName;
  final Set<String> _checkedToolIds = {};
  bool _submitting = false;

  bool _personExpanded = true;
  bool _toolExpanded = false;

  Map<String, Map<String, dynamic>> _lastByToolId = {};
  bool _movesLoaded = false;

  final TextEditingController _personSearch = TextEditingController();
  final TextEditingController _toolSearch = TextEditingController();

  bool get canOperateTools =>
      widget.role == 'owner' || widget.role == 'admin' || widget.role == 'foreman';

  CollectionReference<Map<String, dynamic>> get _moves => movesRef(widget.companyId);
  CollectionReference<Map<String, dynamic>> get _people => peopleRef(widget.companyId);
  CollectionReference<Map<String, dynamic>> get _tools => toolsRef(widget.companyId);

  // Цвет текущего режима
  Color get _modeColor => _isIssue ? Colors.green : Colors.red;

  @override
  void initState() {
    super.initState();
    _refreshMoves();
    _personSearch.addListener(() => setState(() {}));
    _toolSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _personSearch.dispose();
    _toolSearch.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _refreshMoves() async {
    final snap = await _moves.orderBy('createdAt', descending: true).get();
    final Map<String, Map<String, dynamic>> result = {};
    for (final d in snap.docs) {
      final data = d.data();
      final toolId = (data['toolId'] ?? '').toString();
      if (toolId.isEmpty) continue;
      result.putIfAbsent(toolId, () => data);
    }
    if (mounted) setState(() { _lastByToolId = result; _movesLoaded = true; });
  }

  void _switchMode(bool isIssue) {
    setState(() {
      _isIssue = isIssue;
      _personId = null;
      _selectedGroupName = null;
      _checkedToolIds.clear();
      _personSearch.clear();
      _toolSearch.clear();
      _personExpanded = true;
      _toolExpanded = false;
    });
  }

  void _selectPerson(String id) {
    setState(() {
      _personId = id;
      _selectedGroupName = null;
      _checkedToolIds.clear();
      _personSearch.clear();
      _toolSearch.clear();
      _personExpanded = false;
      _toolExpanded = true;
    });
  }

  void _selectGroup(String name, Map<String, List<Map<String, String>>> grouped) {
    setState(() {
      _selectedGroupName = name;
      _checkedToolIds.clear();
      final items = grouped[name] ?? [];
      if (items.isNotEmpty) _checkedToolIds.add(items.first['toolId']!);
      _toolExpanded = false;
    });
  }

  List<Map<String, String>> _getFilteredTools(
      String personId, List<QueryDocumentSnapshot<Map<String, dynamic>>> toolsDocs) {
    final result = <Map<String, String>>[];
    for (final d in toolsDocs) {
      final data = d.data();
      final toolId = d.id;
      final toolName = (data['name'] ?? '').toString().trim();
      final inv = (data['inv'] ?? '').toString().trim();
      final status = (data['status'] ?? 'active').toString();
      if (_isIssue && status != 'active') continue;
      final lastMove = _lastByToolId[toolId];
      if (lastMove == null) {
        if (_isIssue) result.add({'toolId': toolId, 'toolName': toolName, 'inv': inv});
        continue;
      }
      final lastType = (lastMove['type'] ?? '').toString();
      final lastPersonId = (lastMove['personId'] ?? '').toString();
      if (_isIssue) {
        if (lastType != 'out') result.add({'toolId': toolId, 'toolName': toolName, 'inv': inv});
      } else {
        if (lastType == 'out' && lastPersonId == personId) {
          result.add({'toolId': toolId, 'toolName': toolName, 'inv': inv});
        }
      }
    }
    return result;
  }

  Map<String, List<Map<String, String>>> _buildGroupedTools(List<Map<String, String>> items) {
    final Map<String, List<Map<String, String>>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item['toolName']!, () => []).add(item);
    }
    return grouped;
  }

  Future<void> _submit(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> peopleDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> toolsDocs,
    String personId,
    List<Map<String, String>> allTools,
  ) async {
    if (_checkedToolIds.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final personDoc = peopleDocs.firstWhere((d) => d.id == personId);
      final pd = personDoc.data();
      final personName = '${pd['firstName'] ?? ''} ${pd['lastName'] ?? ''}'.trim();
      final personPos = (pd['position'] ?? '').toString();

      final batch = FirebaseFirestore.instance.batch();
      for (final tid in _checkedToolIds) {
        Map<String, String>? found;
        try { found = allTools.firstWhere((x) => x['toolId'] == tid); } catch (_) {}
        if (found == null) continue;
        batch.set(_moves.doc(), {
          'type': _isIssue ? 'out' : 'in',
          'personId': personId,
          'personName': personName,
          'personPos': personPos,
          'toolId': tid,
          'toolName': found['toolName'],
          'inv': found['inv'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      final count = _checkedToolIds.length;
      _toast(count > 1
          ? '${_isIssue ? widget.t('issued') : widget.t('returned')}: $count'
          : (_isIssue ? widget.t('issued') : widget.t('returned')));

      setState(() {
        _checkedToolIds.clear();
        _selectedGroupName = null;
        _toolSearch.clear();
        _personExpanded = true;
        _toolExpanded = false;
      });
      await _refreshMoves();
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canOperateTools) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(widget.t('askAdminIssueReturn'), textAlign: TextAlign.center),
      ));
    }

    return Column(
      children: [
        // Переключатель Выдача / Возврат
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: _modeBtn(isIssue: true)),
            const SizedBox(width: 12),
            Expanded(child: _modeBtn(isIssue: false)),
          ]),
        ),
        Expanded(
          child: !_movesLoaded
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _people.orderBy('firstName').snapshots(),
                  builder: (ctx, peopleSnap) {
                    if (!peopleSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _tools.snapshots(),
                      builder: (ctx, toolsSnap) {
                        if (!toolsSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return _buildForm(
                            peopleSnap.data!.docs, toolsSnap.data!.docs);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _modeBtn({required bool isIssue}) {
    final active = _isIssue == isIssue;
    final color = isIssue ? Colors.green : Colors.red;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? color : Colors.grey.shade200,
        foregroundColor: active ? Colors.white : Colors.black54,
        elevation: active ? 2 : 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: active ? null : () => _switchMode(isIssue),
      icon: Icon(isIssue ? Icons.upload : Icons.download, size: 18),
      label: Text(isIssue ? widget.t('issueUpper') : widget.t('returnUpper')),
    );
  }

  Widget _buildForm(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> peopleDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> toolsDocs,
  ) {
    // Фильтр людей по режиму
    var filteredPeople = peopleDocs.where((d) {
      final st = (d.data()['status'] ?? 'active').toString();
      if (_isIssue && (st == 'fired' || st == 'completed')) return false;
      return true;
    }).toList();

    if (!_isIssue) {
      filteredPeople = filteredPeople
          .where((p) => _getFilteredTools(p.id, toolsDocs).isNotEmpty)
          .toList();
    }

    if (filteredPeople.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _isIssue ? widget.t('needPeopleFirst') : widget.t('noReturnTool'),
          textAlign: TextAlign.center,
        ),
      ));
    }

    final resolvedPersonId = filteredPeople.any((p) => p.id == _personId)
        ? _personId!
        : filteredPeople.first.id;

    // Инструменты текущего человека
    final allTools = _getFilteredTools(resolvedPersonId, toolsDocs);
    final groupedTools = _buildGroupedTools(allTools);
    var sortedGroups = groupedTools.keys.toList()..sort();

    final resolvedGroup = sortedGroups.contains(_selectedGroupName)
        ? _selectedGroupName!
        : null;

    final currentGroupItems =
        resolvedGroup != null ? (groupedTools[resolvedGroup] ?? []) : <Map<String, String>>[];

    // Имя выбранного человека
    String selectedPersonLabel = '';
    try {
      final pd = filteredPeople.firstWhere((d) => d.id == resolvedPersonId).data();
      final first = (pd['firstName'] ?? '').toString();
      final last = (pd['lastName'] ?? '').toString();
      final pos = (pd['position'] ?? '').toString();
      selectedPersonLabel = pos.isNotEmpty ? '$first $last ($pos)' : '$first $last';
    } catch (_) {}

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // QR-сканер (только для выдачи)
          if (_isIssue) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Сканировать QR'),
              onPressed: () async {
                final rawValue = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const QrScannerPage()),
                );
                if (rawValue == null || !mounted) return;
                String? resolvedId;
                if (rawValue.startsWith('toolkeeper:')) {
                  resolvedId = rawValue.substring('toolkeeper:'.length);
                } else {
                  final snap = await _tools
                      .where('customQr', isEqualTo: rawValue)
                      .limit(1)
                      .get();
                  if (snap.docs.isNotEmpty) resolvedId = snap.docs.first.id;
                }
                if (!mounted) return;
                if (resolvedId == null) {
                  _toast('QR-код не привязан ни к одному инструменту');
                  return;
                }
                Map<String, String>? found;
                try { found = allTools.firstWhere((t) => t['toolId'] == resolvedId); }
                catch (_) {}
                if (found == null) {
                  _toast('Инструмент не найден или уже выдан');
                  return;
                }
                setState(() {
                  _selectedGroupName = found!['toolName'];
                  _checkedToolIds..clear()..add(resolvedId!);
                  _toolExpanded = false;
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          // ── БЛОК ВЫБОРА СОТРУДНИКА ──
          _DropdownBlock(
            label: widget.t('person'),
            selectedLabel: selectedPersonLabel,
            icon: Icons.person,
            color: _modeColor,
            isExpanded: _personExpanded,
            onToggle: () => setState(() => _personExpanded = !_personExpanded),
            searchController: _personSearch,
            searchHint: '${widget.t('person')}...',
            child: Column(
              children: filteredPeople.where((d) {
                final q = _personSearch.text.toLowerCase().trim();
                if (q.isEmpty) return true;
                final p = d.data();
                return '${p['firstName'] ?? ''} ${p['lastName'] ?? ''} ${p['position'] ?? ''}'
                    .toLowerCase()
                    .contains(q);
              }).map((d) {
                final p = d.data();
                final first = (p['firstName'] ?? '').toString();
                final last = (p['lastName'] ?? '').toString();
                final pos = (p['position'] ?? '').toString();
                final type = (p['type'] ?? 'person').toString();
                final typeTag = type == 'object' ? ' [Объект]' : '';
                final label = pos.isNotEmpty
                    ? '$first $last ($pos)$typeTag'
                    : '$first $last$typeTag';
                final isSelected = d.id == resolvedPersonId;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: _modeColor.withOpacity(0.08),
                  selectedColor: _modeColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    type == 'object' ? Icons.location_on : Icons.person,
                    size: 18,
                    color: isSelected ? _modeColor : Colors.grey,
                  ),
                  title: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                  onTap: () => _selectPerson(d.id),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // ── БЛОК ВЫБОРА ИНСТРУМЕНТА ──
          _DropdownBlock(
            label: widget.t('tool'),
            selectedLabel: resolvedGroup ?? '',
            icon: Icons.construction,
            color: _modeColor,
            isExpanded: _toolExpanded,
            onToggle: allTools.isEmpty
                ? null
                : () => setState(() => _toolExpanded = !_toolExpanded),
            searchController: _toolSearch,
            searchHint: '${widget.t('tool')}...',
            emptyLabel: _isIssue ? widget.t('noFreeTool') : widget.t('noReturnTool'),
            isEmpty: allTools.isEmpty,
            child: Column(
              children: () {
                final q = _toolSearch.text.toLowerCase().trim();
                final filtered = sortedGroups
                    .where((name) => q.isEmpty || name.toLowerCase().contains(q))
                    .toList();
                if (filtered.isEmpty) {
                  return [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(widget.t('noResults'),
                          style: TextStyle(color: Colors.grey.shade500),
                          textAlign: TextAlign.center),
                    )
                  ];
                }
                return filtered.map((name) {
                  final count = groupedTools[name]!.length;
                  final isSelected = name == resolvedGroup;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: _modeColor.withOpacity(0.08),
                    selectedColor: _modeColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(Icons.construction,
                        size: 18,
                        color: isSelected ? _modeColor : Colors.grey),
                    title: Text(count > 1 ? '$name  ×$count' : name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                    onTap: () => _selectGroup(name, groupedTools),
                  );
                }).toList();
              }(),
            ),
          ),

          // Чекбоксы для нескольких единиц
          if (currentGroupItems.length > 1) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: currentGroupItems.map((item) {
                  final tid = item['toolId']!;
                  final inv = item['inv']!;
                  return CheckboxListTile(
                    value: _checkedToolIds.contains(tid),
                    dense: true,
                    activeColor: _modeColor,
                    title: Text(inv.isNotEmpty ? inv : tid,
                        style: const TextStyle(fontSize: 14)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) _checkedToolIds.add(tid);
                        else _checkedToolIds.remove(tid);
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── КНОПКА ПОДТВЕРЖДЕНИЯ ──
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _modeColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: (_submitting || _checkedToolIds.isEmpty)
                ? null
                : () => _submit(peopleDocs, toolsDocs, resolvedPersonId, allTools),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _checkedToolIds.length > 1
                        ? '${_isIssue ? widget.t('issueTool') : widget.t('returnTool')} (${_checkedToolIds.length})'
                        : (_isIssue ? widget.t('issueTool') : widget.t('returnTool')),
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }
}

// Виджет выпадающего блока с поиском
class _DropdownBlock extends StatelessWidget {
  final String label;
  final String selectedLabel;
  final IconData icon;
  final Color color;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final TextEditingController searchController;
  final String searchHint;
  final Widget child;
  final String? emptyLabel;
  final bool isEmpty;

  const _DropdownBlock({
    required this.label,
    required this.selectedLabel,
    required this.icon,
    required this.color,
    required this.isExpanded,
    required this.onToggle,
    required this.searchController,
    required this.searchHint,
    required this.child,
    this.emptyLabel,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: isExpanded ? color : Colors.grey.shade300, width: isExpanded ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок блока (нажимаемый)
          InkWell(
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(9))
                : BorderRadius.circular(9),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: isEmpty ? Colors.grey.shade400 : color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: selectedLabel.isNotEmpty
                        ? Text(selectedLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color))
                        : Text(isEmpty ? (emptyLabel ?? label) : label,
                            style: TextStyle(
                                fontSize: 14,
                                color: isEmpty ? Colors.grey.shade400 : Colors.grey.shade600)),
                  ),
                  if (!isEmpty)
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey.shade500, size: 20),
                ],
              ),
            ),
          ),
          // Раскрытая часть
          if (isExpanded && !isEmpty) ...[
            Divider(height: 1, color: color.withOpacity(0.3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: searchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: searchController.clear,
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                ),
              ),
            ),
            child,
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
