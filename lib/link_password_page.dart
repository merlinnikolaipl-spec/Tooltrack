import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LinkPasswordPage extends StatefulWidget {
  const LinkPasswordPage({super.key});

  @override
  State<LinkPasswordPage> createState() => _LinkPasswordPageState();
}

class _LinkPasswordPageState extends State<LinkPasswordPage> {
  final passCtrl = TextEditingController();

  bool loading = false;
  String? error;
  String? ok;

  @override
  void dispose() {
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> linkPassword() async {
    setState(() {
      loading = true;
      error = null;
      ok = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Пользователь не найден');
      }

      final email = user.email;
      if (email == null || email.isEmpty) {
        throw Exception('У Google-аккаунта нет email. Напиши мне.');
      }

      final password = passCtrl.text.trim();
      if (password.length < 6) {
        throw Exception('Пароль минимум 6 символов');
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.linkWithCredential(credential);

      setState(() {
        ok =
            'ГОТОВО ✅\n\n'
            'Теперь ты можешь войти на ПК:\n\n'
            'Email: $email\n'
            'Пароль: (тот что задал)';
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        setState(() {
          ok = 'Пароль уже привязан. Можно входить на ПК.';
        });
      } else if (e.code == 'requires-recent-login') {
        setState(() {
          error =
              'Нужно перелогиниться.\n'
              'Выйди → зайди снова через Google → попробуй ещё раз.';
        });
      } else {
        setState(() => error = e.message ?? e.code);
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Привязать пароль')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Ты вошёл как:\n${user?.email}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Задай пароль.\n'
              'После этого сможешь войти на Windows через Email + Пароль.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый пароль (минимум 6 символов)',
              ),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            if (ok != null)
              Text(ok!, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : linkPassword,
                child: Text(loading ? '...' : 'Привязать пароль'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
