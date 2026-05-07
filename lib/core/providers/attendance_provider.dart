import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Status kehadiran hari ini dari sistem absensi.
enum AttendanceLoadState { idle, loading, loaded, error }

class AttendanceProvider extends ChangeNotifier {
  final ApiService _api;

  AttendanceProvider(this._api);

  AttendanceLoadState _loadState = AttendanceLoadState.idle;
  String?
  _status; // e.g. 'hadir', 'terlambat', 'izin', 'sakit', 'libur', 'absent'

  AttendanceLoadState get loadState => _loadState;
  String? get status => _status;

  /// Fetch kehadiran hari ini untuk [email] teknisi.
  Future<void> fetchToday(String email) async {
    if (_loadState == AttendanceLoadState.loading) return;
    _loadState = AttendanceLoadState.loading;
    notifyListeners();

    try {
      final res = await _api.get(
        '/mobile/technician/attendance/today',
        query: {'email': email},
      );
      if (res is Map) {
        final data = res['data'];
        _status = (data is Map) ? data['status'] as String? : null;
      } else {
        _status = null;
      }
      _loadState = AttendanceLoadState.loaded;
    } catch (_) {
      _status = null;
      _loadState = AttendanceLoadState.error;
    }

    notifyListeners();
  }

  /// Reset saat logout.
  void reset() {
    _status = null;
    _loadState = AttendanceLoadState.idle;
    notifyListeners();
  }
}
