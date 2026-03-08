import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/verification_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CrashLens',
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthScreen(),
        '/verification': (context) => const VerificationScreen(),
        '/home': (context) => const HomeScreen(),
        '/test': (context) => const TestFirestoreScreen(),
      },
    );
  }
}

class TestFirestoreScreen extends StatelessWidget {
  const TestFirestoreScreen({super.key});

  Future<void> testConnection() async {
    await FirebaseFirestore.instance.collection('test_connection').add({
      'message': 'connected successfully',
      'time': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Firestore')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await testConnection();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Data sent successfully')),
            );
          },
          child: const Text('Test Firebase'),
        ),
      ),
    );
  }
}