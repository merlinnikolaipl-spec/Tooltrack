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
      setState(() { _loading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() { _loading = false; });
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
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
      setState(() { _loading = false; });
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
  int _tab = 0;
  String? _companyId;
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserCompany();
  }

  Future<void> _loadUserCompany() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // Find company where user is a member
      final companiesSnap = await companiesRef.get();
      for (final doc in companiesSnap.docs) {
        final personSnap = await peopleRef(doc.id)
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (personSnap.docs.isNotEmpty) {
          final personData = personSnap.docs.first.data();
          setState(() {
            _companyId = doc.id;
            _role = personData['role'] ?? 'employee';
            _loading = false;
          });
          return;
        }
      }
      // Check if user owns a company
      final ownedSnap = await companiesRef
          .where('ownerUid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (ownedSnap.docs.isNotEmpty) {
        setState(() {
          _companyId = ownedSnap.docs.first.id;
          _role = 'owner';
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    setState(() { _loading = false; });
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
            _ToolsTab(companyId: _companyId!, role: _role ?? 'employee'),
            IssueTab(
              companyId: _companyId!,
              role: _role ?? 'employee',
              t: (k) => k,
            ),
            _PeopleTab(companyId: _companyId!, role: _role ?? 'employee'),
          ],
        ),
      ),
    );
  }
}

class _NoCompanyPage extends StatelessWidget {
  final User? user;
  const _NoCompanyPage({this.user});

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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Welcome, ${user?.email ?? ''}',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text('No company found. Contact your administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
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
                  final inv = (d.data()['inventoryNumber'] ?? '').toString().toLowerCase();
                  return name.contains(_search) || inv.contains(_search);
                }).toList();
              }
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No tools found', style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data = docs[i].data();
                  final name = data['name'] ?? 'Unknown';
                  final inv = data['inventoryNumber'] ?? '';
                  final status = data['status'] ?? 'available';
                  final assignedTo = data['assignedTo'] ?? '';
                  Color statusColor = Colors.green;
                  if (status == 'issued') statusColor = Colors.orange;
                  if (status == 'repair') statusColor = Colors.red;
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
                'inventoryNumber': invCtrl.text.trim(),
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
            child: Text('No people found', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final name = data['name'] ?? data['email'] ?? 'Unknown';
            final r = data['role'] ?? 'employee';
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
