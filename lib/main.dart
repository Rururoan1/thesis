// lib/main.dart
// Entry point for the Rice Pest Detector Flutter app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/history_screen.dart';
import 'screens/stats_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Restore the last signed-in user (if any) before the first frame.
  await AuthService.instance.restoreSession();

  runApp(const RicePestApp());
}

class RicePestApp extends StatelessWidget {
  const RicePestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rice Pest Detector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

// ── Login gate ─────────────────────────────────────────────────────────────────
// Shows LoginScreen until a user is signed in, then the main app.
// Logging out brings the user back here automatically.

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.instance.userNotifier,
      builder: (_, user, __) {
        if (user == null) return const LoginScreen();
        // ValueKey(user) rebuilds Detect / History / Stats from scratch when a
        // different user signs in, so no data from the previous user is shown.
        return MainNavigation(key: ValueKey(user));
      },
    );
  }
}

// ── Bottom navigation shell ────────────────────────────────────────────────────

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // Order here must match the order of `destinations` below.
  final List<Widget> _screens = const [
    HomeScreen(),
    LibraryScreen(),
    HistoryScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF60AD5E),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt, color: AppTheme.primary),
            label: 'Detect',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: AppTheme.primary),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: AppTheme.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: AppTheme.primary),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}