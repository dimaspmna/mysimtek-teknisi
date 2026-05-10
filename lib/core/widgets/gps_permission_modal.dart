import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_colors.dart';

/// Shows a modal that requests GPS permission and returns the initial
/// [Position] on success, or null if the user cancelled / permission denied.
Future<Position?> showGpsPermissionModal(BuildContext context) async {
  return showModalBottomSheet<Position?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _GpsPermissionSheet(),
  );
}

class _GpsPermissionSheet extends StatefulWidget {
  const _GpsPermissionSheet();

  @override
  State<_GpsPermissionSheet> createState() => _GpsPermissionSheetState();
}

class _GpsPermissionSheetState extends State<_GpsPermissionSheet>
    with WidgetsBindingObserver {
  bool _resumeRetryPending = false;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_resumeRetryPending ||
        _loading) {
      return;
    }

    _resumeRetryPending = false;
    Future.microtask(_requestGps);
  }

  Future<void> _requestGps() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // 1. Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _errorMessage =
              'Layanan lokasi (GPS) tidak aktif.\nAktifkan GPS di pengaturan perangkat.';
        });
        _resumeRetryPending = true;
        await Geolocator.openLocationSettings();
        return;
      }

      // 2. Request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _errorMessage =
              'Izin lokasi ditolak permanen.\nBuka pengaturan aplikasi untuk mengaktifkan.';
        });
        _resumeRetryPending = true;
        await Geolocator.openAppSettings();
        return;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        setState(() {
          _loading = false;
          _errorMessage = 'Izin lokasi ditolak. Diperlukan untuk monitoring.';
        });
        return;
      }

      // 3. Get initial position with timeout to avoid endless loading.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (!mounted) return;
        // Permission is already granted; allow caller to continue and let
        // background tracking obtain the next available location fix.
        Navigator.pop(context, null);
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, pos);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Tidak bisa mengambil lokasi. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFC8C8C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'GPS Diperlukan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aktifkan GPS untuk monitoring lokasi real-time di NOC saat pekerjaan berlangsung.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _requestGps,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.gps_fixed, size: 18),
              label: Text(_loading ? 'Mengambil lokasi...' : 'Aktifkan GPS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              child: const Text(
                'Batal',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
