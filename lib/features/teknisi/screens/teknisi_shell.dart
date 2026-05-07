import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/gps_tracking_provider.dart';
import 'beranda_screen.dart';
import 'akun_screen.dart';

class TeknisiShell extends StatefulWidget {
  const TeknisiShell({super.key});

  @override
  State<TeknisiShell> createState() => _TeknisiShellState();
}

class _TeknisiShellState extends State<TeknisiShell>
    with WidgetsBindingObserver {
  int _index = 0;

  final _screens = [BerandaScreen(), AkunScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Restore GPS tracking state on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreGpsState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Restore GPS tracking state when app resumes from background
      _restoreGpsState();
    }
  }

  Future<void> _restoreGpsState() async {
    if (!mounted) return;
    await context.read<GpsTrackingProvider>().restoreStateFromBackground();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Akun',
          ),
        ],
      ),
    );
  }
}
