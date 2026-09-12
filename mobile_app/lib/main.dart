import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'screens/NavBar/nav_bar.dart';
import 'screens/vehicle/add_vehicle_screen.dart';
import 'screens/admin/admin_debug_entry_screen.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: ".env");
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/auth',
      routes: {
        '/home': (context) => const AppBottomNav(),
        '/auth': (context) => const AuthScreen(),
        '/addVehicle': (context) => const AddVehicleScreen(),
        // TEMPORARY: testing-only entry point for the admin Case Review /
        // Claim Details screens, until real admin auth/gating and the
        // Cases/Claims list pages (built separately) exist.
        '/admin': (context) => const AdminDebugEntryScreen(),
      },
    );
  }
}