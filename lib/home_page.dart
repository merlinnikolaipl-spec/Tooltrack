import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'link_password_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вы вошли как:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(user?.email ?? 'Без email'),
            const SizedBox(height: 24),

            // 🔥 ВОТ ОНА — НУЖНАЯ КНОПКА
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LinkPasswordPage(),
                  ),
                );
              },
              child: const Text('Войти на ПК (привязать пароль)'),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }
}
