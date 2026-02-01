import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

typedef I18nText = String Function(String key);

class IssueTab extends StatefulWidget {
  final String companyId;
  final String role; // owner/admin/worker
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
  bool get canOperateTools => widget.role == 'owner' || widget.role == 'admin' || widget.role == 'foreman';

  // Коллекция истории перемещений
  CollectionReference<Map<String, dynamic>> get _moves =>
      FirebaseFirestore.instance.collection('companies').doc(widget.companyId).collection('moves');

  // ✅ ИСПРАВЛЕНО: Теперь берем сотрудников ТОЛЬКО из твоего созданного списка (первая вкладка)
  CollectionReference<Map<String, dynamic>> get _people =>
      FirebaseFirestore.instance.collection('companies').doc(widget.companyId).collection('people');

  // Коллекция инструментов
  CollectionReference<Map<String, dynamic>> get _tools =>
      FirebaseFirestore.instance.collection('companies').doc(widget.companyId).collection('tools');

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Map<String, Map<String, dynamic>>> _lastMoveByToolId() async {
    final snap = await _moves.orderBy('createdAt', descending: true).get();
    final Map<String, Map<String, dynamic>> lastByTool = {};
    for (final d in snap.docs) {
      final data = d.data();
      final toolId = (data['toolId'] ?? '').toString();
      if (toolId.isEmpty) continue;
      lastByTool.putIfAbsent(toolId, () => data);
    }
    return lastByTool;
  }

  Future<void> _issueOrReturnDialog({required bool isIssue}) async {
    if (!canOperateTools) {
      _toast(widget.t('onlyAdmin'));
      return;
    }

    // Загружаем список твоих сотрудников и инструментов
    final peopleSnap = await _people.orderBy('firstName').get(); 
    print("DEBUG: Загружено документов из коллекции employees: ${peopleSnap.docs.length}");
for (var doc in peopleSnap.docs) {
  print("DEBUG: Человек в списке: ${doc.data()['firstName']} ${doc.data()['lastName']}");
}
    final toolsSnap = await _tools.get();
    final lastByToolId = await _lastMoveByToolId();

    if (peopleSnap.docs.isEmpty) {
      _toast(widget.t('needPeopleFirst'));
      return;
    }
    if (toolsSnap.docs.isEmpty) {
      _toast(widget.t('needToolsFirst'));
      return;
    }

    final toolItems = <Map<String, String>>[];
    for (final d in toolsSnap.docs) {
      final data = d.data();
      final toolId = d.id;
      final toolName = (data['name'] ?? '').toString();
      final inv = (data['inv'] ?? '').toString();
      final status = (data['status'] ?? 'active').toString();
      if (isIssue && status != 'active') continue;

      final last = lastByToolId[toolId];
      final lastType = (last?['type'] ?? '').toString();

      final allowed = isIssue ? (lastType != 'out') : (lastType == 'out');
      if (!allowed) continue;

      toolItems.add({'toolId': toolId, 'toolName': toolName, 'inv': inv});
    }

    if (toolItems.isEmpty) {
      _toast(isIssue ? widget.t('noFreeTool') : widget.t('noReturnTool'));
      return;
    }

    final filteredPeople = peopleSnap.docs.where((d) {
      final st = (d.data()['status'] ?? 'active').toString();
      return !isIssue || st != 'fired';
    }).toList();

    String personId = filteredPeople.first.id;
    Map<String, dynamic> personData = peopleSnap.docs.first.data();

    String toolId = toolItems.first['toolId']!;
    String toolName = toolItems.first['toolName']!;
    String inv = toolItems.first['inv']!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            return AlertDialog(
              title: Text(isIssue ? widget.t('issueTitle') : widget.t('returnTitle')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ВЫБОР ЧЕЛОВЕКА ИЗ ТВОЕГО СПИСКА
                  DropdownButtonFormField<String>(
                    value: personId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: widget.t('person')),
                    items: filteredPeople.map((d) {
                      final p = d.data();
                      final first = (p['firstName'] ?? '').toString();
                      final last = (p['lastName'] ?? '').toString();
                      final pos = (p['position'] ?? '').toString(); // Твоя колонка "Должность"
                      return DropdownMenuItem(
                        value: d.id,
                        child: Text('$first $last ($pos)', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final doc = peopleSnap.docs.firstWhere((x) => x.id == v);
                      setStateSB(() {
                        personId = v;
                        personData = doc.data();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  // ВЫБОР ИНСТРУМЕНТА
                  DropdownButtonFormField<String>(
                    value: toolId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: widget.t('toolInv')),
                    items: toolItems.map((t) {
                      final n = t['toolName']!;
                      final invv = t['inv']!;
                      final id = t['toolId']!;
                      return DropdownMenuItem(value: id, child: Text('$n — $invv', overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final found = toolItems.firstWhere((x) => x['toolId'] == v);
                      setStateSB(() {
                        toolId = v;
                        toolName = found['toolName']!;
                        inv = found['inv']!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(widget.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(widget.t('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final first = (personData['firstName'] ?? '').toString();
    final last = (personData['lastName'] ?? '').toString();
    final pos = (personData['role'] ?? '').toString();
    final personName = ('$first $last').trim();

    // СОХРАНЕНИЕ В ИСТОРИЮ
    await _moves.add({
      'type': isIssue ? 'out' : 'in',
      'personId': personId, 
      'personName': personName,
      'personPos': pos,
      'toolId': toolId,
      'toolName': toolName,
      'inv': inv,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _toast(isIssue ? widget.t('issued') : widget.t('returned'));
  }

  @override
  Widget build(BuildContext context) {
    final centerText = canOperateTools
        ? '${widget.t('issueTool')} / ${widget.t('returnTool')}\n\n'
            widget.t('dateAuto')
        : widget.t('askAdminIssueReturn');

    return Scaffold(
      floatingActionButton: canOperateTools
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'issue',
                  onPressed: () => _issueOrReturnDialog(isIssue: true),
                  icon: const Icon(Icons.upload),
                  label: Text(widget.t('issueTool')),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'return',
                  onPressed: () => _issueOrReturnDialog(isIssue: false),
                  icon: const Icon(Icons.download),
                  label: Text(widget.t('returnTool')),
                ),
              ],
            )
          : null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            centerText,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}