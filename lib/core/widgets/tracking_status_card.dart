import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/location_streaming_service.dart';

/// A compact card that shows GPS tracking status.
class TrackingStatusCard extends StatelessWidget {
  final TrackingStatus status;
  final DateTime? lastPush;
  final int retryCount;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;

  const TrackingStatusCard({
    super.key,
    required this.status,
    this.lastPush,
    this.retryCount = 0,
    this.onStop,
    this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      TrackingStatus.active => (
        AppColors.success,
        Icons.gps_fixed,
        'GPS Aktif',
      ),
      TrackingStatus.pending => (
        AppColors.warning,
        Icons.gps_not_fixed,
        'Menghubungkan GPS...',
      ),
      TrackingStatus.error => (
        AppColors.error,
        Icons.gps_off,
        'GPS Error · Coba ulang ${retryCount}x',
      ),
      TrackingStatus.idle => (
        AppColors.textSecondary,
        Icons.gps_off,
        'GPS Tidak Aktif',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (lastPush != null)
                  Text(
                    'Terakhir: ${_formatTime(lastPush!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
          if (status == TrackingStatus.active ||
              status == TrackingStatus.pending)
            if (status == TrackingStatus.active)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
            else
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
          if ((status == TrackingStatus.idle ||
                  status == TrackingStatus.error) &&
              onRestart != null)
            GestureDetector(
              onTap: onRestart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Refresh GPS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt).inSeconds;
    if (diff < 60) return '$diff dtk lalu';
    if (diff < 3600) return '${diff ~/ 60} mnt lalu';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
