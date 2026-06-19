import 'admin_employee_pages.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'billing/plans.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
// import 'package:excel/excel.dart'; // removed - causes Border conflict
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import 'qr_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gps_foreground_service.dart';

final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  try {
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifs.initialize(const InitializationSettings(android: androidSettings));
    final androidImpl = _localNotifs
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'shift_reminders',
      'Reminders',
      description: 'Shift reminders',
      importance: Importance.high,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'shift_gps',
      'GPS Tracking',
      description: 'GPS tracking during shift',
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    ));
    await androidImpl?.requestNotificationsPermission();
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initLocalNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToolKeeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4EFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const CompanyProfilePage();
        }
        return const LoginPage();
      },
    );
  }
}

// ─────────────────────────────── LOGIN PAGE ───────────────────────────────

final _googleSignIn = GoogleSignIn(scopes: ['email']);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _isRegister = false;
  String? _errorMsg;

  Future<void> _signIn() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      if (_isRegister) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _errorMsg = e.message; _loading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      // Always sign out first to force account chooser and prevent crash on re-auth
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() { _loading = false; });
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        // Create or update user document in Firestore so app can find it
        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final userDoc = await userRef.get();
        if (!userDoc.exists) {
          await userRef.set({
            'email': user.email ?? googleUser.email,
            'displayName': user.displayName ?? googleUser.displayName ?? '',
            'photoUrl': user.photoURL ?? googleUser.photoUrl ?? '',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            _loading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(_isRegister ? 'Регистрация' : 'Войти'),
                    ),
                  ),
            const SizedBox(height: 12),
            if (!_loading)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signInWithGoogle,
                  icon: const Icon(Icons.login),
                  label: const Text('Войти через Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (!_loading)
              TextButton(
                onPressed: () => setState(() => _isRegister = !_isRegister),
                child: Text(_isRegister ? 'Есть аккаунт? Войти' : 'Нет аккаунта? Создать'),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────── COMPANY PROFILE PAGE ────────────────────────────

class CompanyProfilePage extends StatefulWidget {
  const CompanyProfilePage({super.key});
  @override
  State<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends State<CompanyProfilePage> {
  String? _companyId;
  String? _companyName;
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final cid = data['companyId'] as String?;
        if (cid != null && cid.isNotEmpty) {
          final compDoc = await FirebaseFirestore.instance
              .collection('companies')
              .doc(cid)
              .get();
          if (!mounted) return;
          setState(() {
            _companyId = cid;
            _companyName = compDoc.data()?['name'] as String? ?? 'Company';
            _role = data['role'] as String? ?? 'worker';
            _loading = false;
          });
          return;
        }
      } else {
        // Create user document if missing (e.g. new Google Sign-In user)
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // Fallback: search via collectionGroup in case user is in people but has no companyId in users doc
      try {
        final peopleQuery = await FirebaseFirestore.instance
            .collectionGroup('people')
            .where('uid', isEqualTo: user.uid)
            .get();
        if (peopleQuery.docs.isNotEmpty && mounted) {
          final pDoc = peopleQuery.docs.first;
          final cid = pDoc.reference.parent.parent!.id;
          final compDoc = await FirebaseFirestore.instance.collection('companies').doc(cid).get();
          if (compDoc.exists && mounted) {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'companyId': cid,
              'role': pDoc.data()['role'] ?? 'worker',
            }, SetOptions(merge: true));
            setState(() {
              _companyId = cid;
              _companyName = compDoc.data()?['name'] ?? 'Компания';
              _role = pDoc.data()['role'] ?? 'worker';
              _loading = false;
            });
            return;
          }
        }
      } catch (_) {}
      setState(() { _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_companyId == null) {
      return _NoCompanyPage(
        user: user!,
        onCompanyJoined: () => setState(() {
          _loading = true;
          _loadUserData();
        }),
      );
    }
    final isOwnerOrAdmin = _role == 'owner' || _role == 'admin';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_companyName ?? 'ToolKeeper'),
          centerTitle: true,
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await _googleSignIn.signOut().catchError((_) {});
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.build), text: 'Инструменты'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Выдача'),
              Tab(icon: Icon(Icons.people), text: 'Сотрудники'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ToolsTab(companyId: _companyId!, isOwnerOrAdmin: isOwnerOrAdmin),
            _IssueReturnTab(companyId: _companyId!, role: _role ?? 'worker'),
            _PeopleTab(companyId: _companyId!, isOwnerOrAdmin: isOwnerOrAdmin),
          ],
        ),
      ),
    );
  }
}

// ────────────────────── NO COMPANY PAGE ──────────────────────────────────

class _NoCompanyPage extends StatefulWidget {
  final User user;
  final VoidCallback onCompanyJoined;
  const _NoCompanyPage({required this.user, required this.onCompanyJoined});
  @override
  State<_NoCompanyPage> createState() => _NoCompanyPageState();
}

class _NoCompanyPageState extends State<_NoCompanyPage> {
  final _companyNameCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  bool _creating = false;
  bool _joining = false;
  String? _errorMsg;

  String get _displayName {
    final user = widget.user;
    if (user.displayName != null && user.displayName!.isNotEmpty) return user.displayName!;
    if (user.email != null) return user.email!;
    return 'User';
  }

  Future<void> _createCompany() async {
    final name = _companyNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() { _creating = true; _errorMsg = null; });
    try {
      final compRef = FirebaseFirestore.instance.collection('companies').doc();
      await compRef.set({
        'name': name,
        'ownerId': widget.user.uid,
        'plan': 'free',
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Add owner to people subcollection
      await compRef.collection('people').add({
        'name': _displayName,
        'email': widget.user.email ?? '',
        'uid': widget.user.uid,
        'role': 'owner',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Update user document
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
        'companyId': compRef.id,
        'role': 'owner',
        'email': widget.user.email ?? '',
        'displayName': _displayName,
      }, SetOptions(merge: true));
      widget.onCompanyJoined();
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _creating = false; });
    }
  }

  Future<void> _joinCompany() async {
    final code = _inviteCodeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _joining = true; _errorMsg = null; });
    try {
      // Search for invite code across all companies
      final codesQuery = await FirebaseFirestore.instance
          .collectionGroup('inviteCodes')
          .where(FieldPath.documentId, isEqualTo: code)
          .get();
      if (codesQuery.docs.isEmpty) {
        setState(() { _errorMsg = 'Invalid invite code.'; _joining = false; });
        return;
      }
      final codeDoc = codesQuery.docs.first;
      final expiry = (codeDoc.data()['expiry'] as Timestamp?)?.toDate();
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        setState(() { _errorMsg = 'Invite code expired.'; _joining = false; });
        return;
      }
      final companyId = codeDoc.data()['companyId'] as String? ?? codeDoc.reference.parent.parent!.id;
      final compRef = FirebaseFirestore.instance.collection('companies').doc(companyId);
      // Add user to people
      await compRef.collection('people').add({
        'name': _displayName,
        'email': widget.user.email ?? '',
        'uid': widget.user.uid,
        'role': 'worker',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Update user document
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
        'companyId': companyId,
        'role': 'worker',
        'email': widget.user.email ?? '',
        'displayName': _displayName,
      }, SetOptions(merge: true));
      widget.onCompanyJoined();
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _joining = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToolKeeper'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _googleSignIn.signOut().catchError((_) {});
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              'Welcome, $_displayName',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text('Create a new company', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _companyNameCtrl,
              decoration: const InputDecoration(
                hintText: 'Company name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 12),
            _creating
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _createCompany,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Create Company'),
                  ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            const Text('Join existing company', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _inviteCodeCtrl,
              decoration: const InputDecoration(
                hintText: 'Invite code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
            const SizedBox(height: 12),
            _joining
                ? const Center(child: CircularProgressIndicator())
                : OutlinedButton(
                    onPressed: _joinCompany,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Join with Invite Code'),
                  ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────── TOOLS TAB ──────────────────────────────────────

class _ToolsTab extends StatefulWidget {
  final String companyId;
  final bool isOwnerOrAdmin;
  const _ToolsTab({required this.companyId, required this.isOwnerOrAdmin});
  @override
  State<_ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<_ToolsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search tools...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('companies')
                .doc(widget.companyId)
                .collection('tools')
                .orderBy('name')
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = (snap.data?.docs ?? []).where((d) {
                final name = (d['name'] as String? ?? '').toLowerCase();
                final inv = (d['inventoryNo'] as String? ?? '').toLowerCase();
                return name.contains(_search) || inv.contains(_search);
              }).toList();
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.build_circle_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No tools yet', style: TextStyle(color: Colors.grey)),
                      if (widget.isOwnerOrAdmin) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showAddTool(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Tool'),
                        ),
                      ],
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final status = d['status'] as String? ?? 'available';
                  final statusColor = status == 'available' ? Colors.green : Colors.orange;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withOpacity(0.2),
                      child: Icon(Icons.build, color: statusColor),
                    ),
                    title: Text(d['name'] as String? ?? 'Tool'),
                    subtitle: Text('No: ${d['inventoryNo'] ?? '-'} · ${status}'),
                    trailing: widget.isOwnerOrAdmin
                        ? IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showEditTool(context, docs[i].id, d),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        if (widget.isOwnerOrAdmin)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddTool(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Tool'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showAddTool(BuildContext context) {
    final nameCtrl = TextEditingController();
    final invCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tool name')),
            TextField(controller: invCtrl, decoration: const InputDecoration(labelText: 'Inventory No')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('companies')
                  .doc(widget.companyId)
                  .collection('tools')
                  .add({
                'name': nameCtrl.text.trim(),
                'inventoryNo': invCtrl.text.trim(),
                'status': 'available',
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditTool(BuildContext context, String toolId, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['name'] as String? ?? '');
    final invCtrl = TextEditingController(text: data['inventoryNo'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tool name')),
            TextField(controller: invCtrl, decoration: const InputDecoration(labelText: 'Inventory No')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('companies')
                  .doc(widget.companyId)
                  .collection('tools')
                  .doc(toolId)
                  .delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('companies')
                  .doc(widget.companyId)
                  .collection('tools')
                  .doc(toolId)
                  .update({
                'name': nameCtrl.text.trim(),
                'inventoryNo': invCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────── ISSUE/RETURN TAB ────────────────────────────────────

class _IssueReturnTab extends StatefulWidget {
  final String companyId;
  final String role;
  const _IssueReturnTab({required this.companyId, required this.role});
  @override
  State<_IssueReturnTab> createState() => _IssueReturnTabState();
}

class _IssueReturnTabState extends State<_IssueReturnTab> {
  bool get _canIssue => widget.role == 'owner' || widget.role == 'admin' || widget.role == 'foreman';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('moves')
          .orderBy('issuedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('No issues/returns yet', style: TextStyle(color: Colors.grey)),
                if (_canIssue) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showIssueDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Issue Tool'),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final isReturned = d['returnedAt'] != null;
                  final toolId = d['toolId'] as String? ?? '';
                  final personId = d['personId'] as String? ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isReturned ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                      child: Icon(
                        isReturned ? Icons.check_circle : Icons.pending,
                        color: isReturned ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(d['toolName'] as String? ?? toolId),
                    subtitle: Text(d['personName'] as String? ?? personId),
                    trailing: isReturned
                        ? const Text('Returned', style: TextStyle(color: Colors.green, fontSize: 12))
                        : _canIssue
                            ? TextButton(
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('companies')
                                      .doc(widget.companyId)
                                      .collection('moves')
                                      .doc(docs[i].id)
                                      .update({'returnedAt': FieldValue.serverTimestamp()});
                                  // Update tool status
                                  if (toolId.isNotEmpty) {
                                    await FirebaseFirestore.instance
                                        .collection('companies')
                                        .doc(widget.companyId)
                                        .collection('tools')
                                        .doc(toolId)
                                        .update({'status': 'available'});
                                  }
                                },
                                child: const Text('Return'),
                              )
                            : const Text('Issued', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  );
                },
              ),
            ),
            if (_canIssue)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showIssueDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Issue Tool'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showIssueDialog(BuildContext context) async {
    // Load tools and people for selection
    final toolsSnap = await FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('tools')
        .where('status', isEqualTo: 'available')
        .get();
    final peopleSnap = await FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('people')
        .where('status', isEqualTo: 'active')
        .get();
    if (!context.mounted) return;
    String? selectedToolId;
    String? selectedPersonId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Issue Tool'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tool'),
                items: toolsSnap.docs.map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d['name'] as String? ?? d.id),
                )).toList(),
                onChanged: (v) => setDlgState(() => selectedToolId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Person'),
                items: peopleSnap.docs.map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d['name'] as String? ?? d.id),
                )).toList(),
                onChanged: (v) => setDlgState(() => selectedPersonId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedToolId != null && selectedPersonId != null
                  ? () async {
                      final toolDoc = toolsSnap.docs.firstWhere((d) => d.id == selectedToolId!);
                      final personDoc = peopleSnap.docs.firstWhere((d) => d.id == selectedPersonId!);
                      await FirebaseFirestore.instance
                          .collection('companies')
                          .doc(widget.companyId)
                          .collection('moves')
                          .add({
                        'toolId': selectedToolId,
                        'toolName': toolDoc['name'],
                        'personId': selectedPersonId,
                        'personName': personDoc['name'],
                        'issuedAt': FieldValue.serverTimestamp(),
                        'returnedAt': null,
                      });
                      await FirebaseFirestore.instance
                          .collection('companies')
                          .doc(widget.companyId)
                          .collection('tools')
                          .doc(selectedToolId)
                          .update({'status': 'issued'});
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('Issue'),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────── PEOPLE TAB ──────────────────────────────────────

class _PeopleTab extends StatefulWidget {
  final String companyId;
  final bool isOwnerOrAdmin;
  const _PeopleTab({required this.companyId, required this.isOwnerOrAdmin});
  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('companies')
          .doc(widget.companyId)
          .collection('people')
          .where('status', isEqualTo: 'active')
          .orderBy('name')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No people yet', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final role = d['role'] as String? ?? 'worker';
            final roleColor = role == 'owner'
                ? Colors.purple
                : role == 'admin'
                    ? Colors.blue
                    : role == 'foreman'
                        ? Colors.orange
                        : Colors.grey;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: roleColor.withOpacity(0.2),
                child: Text(
                  (d['name'] as String? ?? '?').substring(0, 1).toUpperCase(),
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(d['name'] as String? ?? 'Person'),
              subtitle: Text(d['email'] as String? ?? ''),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: roleColor.withOpacity(0.3)),
                ),
                child: Text(role, style: TextStyle(color: roleColor, fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
