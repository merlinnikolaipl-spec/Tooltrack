import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ---------- Firestore refs ----------
CollectionReference<Map<String, dynamic>> companiesRef =
    FirebaseFirestore.instance.collection('companies');

CollectionReference<Map<String, dynamic>> peopleRef(String cid) =>
    companiesRef.doc(cid).collection('people');

CollectionReference<Map<String, dynamic>> toolsRef(String cid) =>
    companiesRef.doc(cid).collection('tools');

CollectionReference<Map<String, dynamic>> movesRef(String cid) =>
    companiesRef.doc(cid).collection('moves');

enum MoveMode { out, inn }

// =====================================
// ВЫДАЧА / ВОЗВРАТ (ТОЛЬКО ADMIN/OWNER)
// Логика:
// 1) Сначала выбираем режим (ВЫДАТЬ / ВЕРНУТЬ)
// 2) Потом выбираем сотрудника
// 3) Инструменты:
//    - ВЫДАТЬ: только свободные
//    - ВЕРНУТЬ: только те, что на выбранном сотруднике
// =====================================
class IssueTab extends StatefulWidget {
  final String companyId;
  final String role;
  final String Function(String) t;

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
  MoveMode? _mode;

  String? personId;
  String? personName;
  String? personPosition;

  String? toolId;
  String? toolName;
  String? inv;

  bool get canIssue => widget.role == 'owner' || widget.role == 'admin' || widget.role == 'foreman';

  // ---------- helpers ----------
  Map<String, Map<String, dynamic>> _statusByTool(
      QuerySnapshot<Map<String, dynamic>> snap) {
    // We want the LAST action per tool.
    // If moves are ordered desc by createdAt, first occurrence per tool is the last state.
    final map = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final tid = (data['toolId'] ?? '').toString();
      if (tid.isEmpty) continue;
      if (map.containsKey(tid)) continue;

      map[tid] = {
        'type': (data['type'] ?? '').toString(), // 'out' or 'in'
        'personId': (data['personId'] ?? '').toString(),
        'personName': (data['personName'] ?? '').toString(),
        'personPosition': (data['personPosition'] ?? '').toString(),
      };
    }
    return map;
  }

  void _setMode(MoveMode m) {
    setState(() {
      _mode = m;
      // when mode changes, clear tool selection (and for return we also clear tool)
      toolId = null;
      toolName = null;
      inv = null;
      // if switching to return, tool list depends on person; keep person as user asked
    });
  }

  Future<void> _pickPerson() async {
    if (_mode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('selectModeFirst'))),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        String q = '';
        return StatefulBuilder(builder: (c, setS) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: widget.t('searchEmployee'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setS(() => q = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: peopleRef(widget.companyId)
                        .orderBy('firstName')
                        .snapshots(),
                    builder: (_, s) {
                      if (!s.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = s.data!.docs.toList();

                      // Local sort: firstName+lastName (case-insensitive)
                      docs.sort((a, b) {
                        final da = a.data();
                        final db = b.data();
                        final na =
                            '${da['firstName'] ?? ''} ${da['lastName'] ?? ''}'
                                .trim()
                                .toLowerCase();
                        final nb =
                            '${db['firstName'] ?? ''} ${db['lastName'] ?? ''}'
                                .trim()
                                .toLowerCase();
                        return na.compareTo(nb);
                      });

                      return ListView(
                        children: docs.map((d) {
                          final data = d.data();
                          final fn = (data['firstName'] ?? '').toString();
                          final ln = (data['lastName'] ?? '').toString();
                          final pos = (data['position'] ?? '').toString();
                          final full = ('$fn $ln').trim();
                          final fullSafe = full.isEmpty ? "${widget.t('noName')} (${d.id})" : full;

                          if (q.isNotEmpty &&
                              !fullSafe.toLowerCase().contains(q) &&
                              !pos.toLowerCase().contains(q)) {
                            return const SizedBox.shrink();
                          }

                          final status = (data['status'] ?? 'active').toString();
                          final isFired = status == 'fired';

                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(fullSafe),
                            subtitle: pos.isEmpty ? null : Text(pos),
                            enabled: !(_mode == MoveMode.out && isFired),
                            onTap: () {
                              if (_mode == MoveMode.out && isFired) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(widget.t('cannotIssueFired'))),
                                );
                                return;
                              }
                              setState(() {
                                personId = d.id;
                                personName = fullSafe;
                                personPosition = pos;
                                // when person changes, tool selection should reset
                                toolId = null;
                                toolName = null;
                                inv = null;
                              });
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _pickTool() async {
    if (_mode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('selectModeFirst'))),
      );
      return;
    }
    if (_mode == MoveMode.inn && (personId == null || personId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('selectPersonForReturnFirst'))),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        String q = '';
        return StatefulBuilder(builder: (c, setS) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: widget.t('searchTool'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setS(() => q = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    // We need moves to know what's free / on a person
                    stream: movesRef(widget.companyId)
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (_, movesSnap) {
                      if (!movesSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final status = _statusByTool(movesSnap.data!);

                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: toolsRef(widget.companyId)
                            .orderBy('name')
                            .snapshots(),
                        builder: (_, toolsSnap) {
                          if (!toolsSnap.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final docs = toolsSnap.data!.docs.toList();

                          // Filter by mode using status map
                          final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          for (final d in docs) {
                            final data = d.data();
                            final name = (data['name'] ?? '').toString();
                            final i = (data['inv'] ?? '').toString();
                            final toolStatus = (data['status'] ?? 'active').toString();

                            if (_mode == MoveMode.out && toolStatus != 'active') {
                              continue;
                            }

                            if (q.isNotEmpty &&
                                !name.toLowerCase().contains(q) &&
                                !i.toLowerCase().contains(q)) {
                              continue;
                            }

                            final st = status[d.id];
                            final lastType = (st?['type'] ?? '').toString();
                            final holderId = (st?['personId'] ?? '').toString();

                            if (_mode == MoveMode.out) {
                              // show only FREE tools => lastType is NOT 'out'
                              if (lastType == 'out') continue;
                              filtered.add(d);
                            } else {
                              // return: show only tools currently OUT on selected person
                              if (lastType != 'out') continue;
                              if (holderId != (personId ?? '')) continue;
                              filtered.add(d);
                            }
                          }

                          // Sort: name -> inv (case-insensitive)
                          filtered.sort((a, b) {
                            final da = a.data();
                            final db = b.data();
                            final na =
                                (da['name'] ?? '').toString().toLowerCase();
                            final nb =
                                (db['name'] ?? '').toString().toLowerCase();
                            final c1 = na.compareTo(nb);
                            if (c1 != 0) return c1;

                            final ia =
                                (da['inv'] ?? '').toString().toLowerCase();
                            final ib =
                                (db['inv'] ?? '').toString().toLowerCase();
                            return ia.compareTo(ib);
                          });

                          if (filtered.isEmpty) {
                            return Center(
                              child: Text(
                                _mode == MoveMode.out
                                    ? 'Нет свободных инструментов'
                                    : 'У этого сотрудника нет инструментов на руках',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          return ListView(
                            children: filtered.map((d) {
                              final data = d.data();
                              final name = (data['name'] ?? widget.t('noTitle'))
                                  .toString();
                              final i = (data['inv'] ?? '---').toString();
                              return ListTile(
                                leading: const Icon(Icons.build),
                                title: Text(name),
                                subtitle: Text('${widget.t('invShort')}: $i'),
                                onTap: () {
                                  setState(() {
                                    toolId = d.id;
                                    toolName = name;
                                    inv = i;
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _commit() async {
    if (!canIssue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('noRightsIssueReturn'))),
      );
      return;
    }
    if (_mode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('selectModeFirst'))),
      );
      return;
    }
    if (personId == null || toolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.t('selectPersonAndTool'))),
      );
      return;
    }

    final out = _mode == MoveMode.out;

    await movesRef(widget.companyId).add({
      'type': out ? 'out' : 'in',
      'personId': personId,
      'personName': personName,
      'personPosition': personPosition,
      'personPos': personPosition, // compat for old reports

      'toolId': toolId,
      'toolName': toolName,
      'inv': inv,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Keep person, clear tool (as user wants)
    setState(() {
      toolId = null;
      toolName = null;
      inv = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(out ? widget.t('issued') : 'Возвращено')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outSelected = _mode == MoveMode.out;
    final inSelected = _mode == MoveMode.inn;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Mode selector (first step)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: outSelected ? Colors.orange : null,
                    foregroundColor: outSelected ? Colors.white : null,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _setMode(MoveMode.out),
                  icon: const Icon(Icons.output),
                  label: Text(widget.t('issueUpper')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: inSelected ? Colors.green : null,
                    foregroundColor: inSelected ? Colors.white : null,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _setMode(MoveMode.inn),
                  icon: const Icon(Icons.input),
                  label: Text(widget.t('returnUpper')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 2,
            child: ListTile(
              enabled: _mode != null,
              title: Text(personName ?? widget.t('whoField')),
              subtitle: personPosition != null && personPosition!.isNotEmpty
                  ? Text(personPosition!)
                  : null,
              trailing: const Icon(Icons.person_search, color: Colors.blue),
              onTap: _mode == null ? null : _pickPerson,
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            child: ListTile(
              enabled: _mode != null &&
                  (_mode == MoveMode.out ||
                      (_mode == MoveMode.inn && personId != null)),
              title: Text(toolName ??
                  (_mode == MoveMode.inn
                      ? widget.t('whatFieldOnHands')
                      : widget.t('whatFieldFree'))),
              subtitle: inv != null ? Text('${widget.t('invNumber')}: $inv') : null,
              trailing: const Icon(Icons.manage_search, color: Colors.orange),
              onTap: (_mode == null ||
                      (_mode == MoveMode.inn && personId == null))
                  ? null
                  : _pickTool,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: canIssue ? _commit : null,
              child: Text((_mode == MoveMode.inn ? widget.t('confirmReturn') : widget.t('confirmIssue')).toUpperCase()),
            ),
          ),

          if (!canIssue)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                widget.t('noRightsIssueReturn'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
