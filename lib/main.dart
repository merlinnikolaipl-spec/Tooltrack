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
import 'package:excel/excel.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
        if (snapshot.data != null) {
          return CompanyProfilePage();
        }
        return LoginPage();
      },
    );
  }
}

// ==================== LOGIN PAGE ====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() { _loading = false; });
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _register() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.construction, size: 72, color: Colors.blue),
                const SizedBox(height: 16),
                const Text('ToolKeeper',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                if (_loading)
                  const CircularProgressIndicator()
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Sign In', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _register,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Create Account', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.red),
                      label: const Text('Sign in with Google',
                          style: TextStyle(fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== COMPANY PROFILE PAGE ====================

class CompanyProfilePage extends StatefulWidget {
  const CompanyProfilePage({super.key});
  @override
  State<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends State<CompanyProfilePage> {
  String? _companyId;
  String? _role;
  bool _loading = true;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    try {
      // Primary: read users/{uid} which has companyId and role
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final cid = data['companyId'] as String?;
        final role = data['role'] as String?;
        final name = data['name'] as String?;
        if (cid != null && cid.isNotEmpty) {
          if (mounted) setState(() {
            _companyId = cid;
            _role = role ?? 'worker';
            _userName = name ?? user.displayName ?? user.email;
            _loading = false;
          });
          return;
        }
      }

      // Fallback: search companies/*/people for this uid
      final companiesSnap = await companiesRef.limit(50).get();
      for (final compDoc in companiesSnap.docs) {
        final personSnap = await peopleRef(compDoc.id)
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (personSnap.docs.isNotEmpty) {
          final pd = personSnap.docs.first.data();
          if (mounted) setState(() {
            _companyId = compDoc.id;
            _role = pd['role'] ?? 'worker';
            _userName = pd['name'] ?? user.displayName ?? user.email;
            _loading = false;
          });
          return;
        }
      }
    } catch (e) {
      // ignore errors, show no-company screen
    }
    if (mounted) setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_companyId == null) {
      return _NoCompanyPage(user: user);
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ToolKeeper'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
              tooltip: 'Sign Out',
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.construction), text: 'Tools'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Issue/Return'),
              Tab(icon: Icon(Icons.people), text: 'People'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ToolsTab(companyId: _companyId!, role: _role ?? 'worker'),
            IssueTab(
              companyId: _companyId!,
              role: _role ?? 'worker',
              t: (k) => k,
            ),
            _PeopleTab(companyId: _companyId!, role: _role ?? 'worker'),
          ],
        ),
      ),
    );
  }
}

// ==================== NO COMPANY PAGE ====================

class _NoCompanyPage extends StatefulWidget {
  final User? user;
  const _NoCompanyPage({this.user});
  @override
  State<_NoCompanyPage> createState() => _NoCompanyPageState();
}

class _NoCompanyPageState extends State<_NoCompanyPage> {
  final _companyNameCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  Future<void> _createCompany() async {
    final user = widget.user;
    if (user == null) return;
    final name = _companyNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() { _error = 'Enter company name'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final companyRef = await companiesRef.add({
        'name': name,
        'ownerUid': user.uid,
        'plan': 'free',
        'createdAt': FieldValue.serverTimestamp(),
      });
      final personRef = await peopleRef(companyRef.id).add({
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName ?? user.email,
        'role': 'owner',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'companyId': companyRef.id,
        'role': 'owner',
        'name': user.displayName ?? user.email,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() { _success = 'Company created! Reloading...'; _loading = false; });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CompanyProfilePage()),
      );
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _joinWithCode() async {
    final user = widget.user;
    if (user == null) return;
    final code = _inviteCodeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() { _error = 'Enter invite code'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final codeDoc = await FirebaseFirestore.instance
          .collection('inviteCodes')
          .doc(code)
          .get();
      if (!codeDoc.exists) {
        setState(() { _error = 'Invalid invite code'; _loading = false; });
        return;
      }
      final companyId = codeDoc.data()!['companyId'] as String;
      final expiry = codeDoc.data()!['expiry'];
      if (expiry != null) {
        final expiryDate = (expiry as dynamic).toDate() as DateTime;
        if (DateTime.now().isAfter(expiryDate)) {
          setState(() { _error = 'Invite code expired'; _loading = false; });
          return;
        }
      }
      await peopleRef(companyId).add({
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName ?? user.email,
        'role': 'worker',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'companyId': companyId,
        'role': 'worker',
        'name': user.displayName ?? user.email,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() { _success = 'Joined company! Reloading...'; _loading = false; });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CompanyProfilePage()),
      );
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToolKeeper'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${widget.user?.displayName ?? widget.user?.email ?? ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Text('Create a new company', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _companyNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Company name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _createCompany,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Create Company'),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Join existing company', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loading ? null : _joinWithCode,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Join with Invite Code'),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 16),
              Text(_success!, style: const TextStyle(color: Colors.green)),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== TOOLS TAB ====================

class _ToolsTab extends StatefulWidget {
  final String companyId;
  final String role;
  const _ToolsTab({required this.companyId, required this.role});
  @override
  State<_ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<_ToolsTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  bool get _canEdit =>
      widget.role == 'owner' || widget.role == 'admin';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search tools...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: toolsRef(widget.companyId).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data!.docs;
              if (_search.isNotEmpty) {
                docs = docs.where((d) {
                  final name = (d.data()['name'] ?? '').toString().toLowerCase();
                  final inv = (d.data()['inventoryNo'] ?? d.data()['inventoryNumber'] ?? '').toString().toLowerCase();
                  return name.contains(_search) || inv.contains(_search);
                }).toList();
              }
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No tools yet', style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data = docs[i].data();
                  final name = data['name'] ?? 'Unknown';
                  final inv = data['inventoryNo'] ?? data['inventoryNumber'] ?? '';
                  final status = data['status'] ?? 'available';
                  final assignedTo = data['assignedTo'] ?? data['personName'] ?? '';
                  Color statusColor = Colors.green;
                  if (status == 'issued') statusColor = Colors.orange;
                  if (status == 'repair') statusColor = Colors.red;
                  if (status == 'lost') statusColor = Colors.red.shade900;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.2),
                        child: Icon(Icons.construction, color: statusColor),
                      ),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (inv.isNotEmpty) Text('# $inv'),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(status,
                                  style: TextStyle(
                                      color: statusColor, fontSize: 12)),
                            ),
                            if (assignedTo.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(assignedTo,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                          ]),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_canEdit)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddToolDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Tool'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showAddToolDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final invCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tool name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: invCtrl,
              decoration: const InputDecoration(
                labelText: 'Inventory number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await toolsRef(widget.companyId).add({
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
}

// ==================== PEOPLE TAB ====================

class _PeopleTab extends StatelessWidget {
  final String companyId;
  final String role;
  const _PeopleTab({required this.companyId, required this.role});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: peopleRef(companyId).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('No people yet', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final name = data['name'] ?? data['email'] ?? 'Unknown';
            final r = data['role'] ?? 'worker';
            Color roleColor = Colors.blue;
            if (r == 'owner') roleColor = Colors.purple;
            if (r == 'admin') roleColor = Colors.orange;
            if (r == 'foreman') roleColor = Colors.teal;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: roleColor.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(name),
              subtitle: Text(r),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(r, style: TextStyle(color: roleColor, fontSize: 12)),
              ),
            );
          },
        );
      },
    );
  }
}
