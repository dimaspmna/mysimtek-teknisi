import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_version.dart';
import '../../../core/providers/attendance_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/gps_tracking_provider.dart';
import 'akun/informasi_akun_screen.dart';
import 'akun/change_password_screen.dart';
import 'akun/webview_screen.dart';

class AkunScreen extends StatefulWidget {
  const AkunScreen({super.key});

  @override
  State<AkunScreen> createState() => _AkunScreenState();
}

class _AkunScreenState extends State<AkunScreen> {
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text(
          'Akun',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Card
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InformasiAkunScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: (user?.photo != null && user!.photo!.isNotEmpty)
                        ? ClipOval(
                            child: Image.network(
                              '${ApiConstants.storageUrl}/storage/${user.photo}',
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 28,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 28,
                            color: AppColors.primary,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Teknisi',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Teknisi',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Consumer<AttendanceProvider>(
                              builder: (_, att, __) {
                                final s = att.status;
                                if (att.loadState ==
                                        AttendanceLoadState.loading ||
                                    s == null) {
                                  return const SizedBox.shrink();
                                }
                                final (label, color) = _resolveAttendance(s);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // About Section
          const Text(
            'Tentang',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildMenuItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Kebijakan Privasi',
            iconBgColor: const Color(0xFF6366F1),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WebViewScreen(
                    title: 'Kebijakan Privasi',
                    url: 'https://teknisi.simtek.co.id/privacy-policy',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.menu_book_outlined,
            title: 'Panduan Teknisi',
            iconBgColor: const Color(0xFF10B981),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WebViewScreen(
                    title: 'Panduan Teknisi',
                    url: 'https://teknisi.simtek.co.id/guide',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.info_outline,
            title: 'Tentang Aplikasi',
            iconBgColor: const Color(0xFF3B82F6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WebViewScreen(
                    title: 'Tentang Aplikasi',
                    url: 'https://teknisi.simtek.co.id/about',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Settings Section
          const Text(
            'Pengaturan',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // GPS Tracking Toggle
          Consumer<GpsTrackingProvider>(
            builder: (context, gps, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      gps.isRunning ? Icons.gps_fixed : Icons.gps_off,
                      size: 20,
                      color: gps.isRunning
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GPS Tracking',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            gps.isRunning
                                ? 'Aktif - Tiket #${gps.activeTicketId ?? "?"}'
                                : 'Nonaktif',
                            style: TextStyle(
                              fontSize: 11,
                              color: gps.isRunning
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: gps.isRunning,
                      onChanged: (value) {
                        if (value) {
                          // Show info that GPS can only be started from ticket detail
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'GPS tracking akan otomatis dimulai saat Anda memulai pekerjaan dari detail tiket.',
                              ),
                              backgroundColor: AppColors.info,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        } else {
                          // Stop GPS
                          _confirmStopGps(context, gps);
                        }
                      },
                      activeColor: AppColors.success,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.lock_outline,
            title: 'Ubah Kata Sandi',
            iconBgColor: const Color(0xFFF59E0B),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChangePasswordScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMenuItem(
            icon: Icons.logout,
            title: 'Keluar',
            textColor: AppColors.error,
            iconBgColor: AppColors.error,
            onTap: () {
              _showLogoutDialog(context);
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'v${AppVersion.version}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    // closing Stack
    if (_loggingOut) {
      return Stack(
        children: [
          IgnorePointer(child: scaffold),
          const ModalBarrier(dismissible: false, color: Colors.black26),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            ),
          ),
        ],
      );
    }
    return scaffold;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    Color iconBgColor = AppColors.primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmStopGps(BuildContext context, GpsTrackingProvider gps) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matikan GPS Tracking?'),
        content: const Text(
          'GPS tracking akan dihentikan. Anda dapat mengaktifkannya kembali saat memulai pekerjaan tiket.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              gps.stopTracking();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('GPS tracking dimatikan.'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Matikan GPS'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loggingOut = true);
              await context.read<AuthProvider>().logout();
              if (mounted) setState(() => _loggingOut = false);
            },
            child: const Text(
              'Keluar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color) _resolveAttendance(String status) {
    switch (status.toLowerCase()) {
      case 'hadir':
        return ('Hadir', Color(0xFF22C55E));
      case 'terlambat':
        return ('Terlambat', Color(0xFFF59E0B));
      case 'izin':
        return ('Izin', Color(0xFF3B82F6));
      case 'sakit':
        return ('Sakit', Color(0xFF8B5CF6));
      case 'libur':
        return ('Libur', Color(0xFF6B7280));
      case 'absent':
        return ('Tidak Hadir', Color(0xFFEF4444));
      default:
        return (status, Color(0xFF6B7280));
    }
  }
}
