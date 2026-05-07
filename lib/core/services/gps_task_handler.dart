import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Entry point for the foreground service isolate.
@pragma('vm:entry-point')
void gpsTaskCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}

class GpsTaskHandler extends TaskHandler {
  int _retryCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _retryCount = 0;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _pushLocation();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  Future<void> _pushLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final ticketId = prefs.getInt('gps_ticket_id');
    final endpoint = prefs.getString('gps_endpoint');
    if (ticketId == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final storage = StorageService();
      final api = ApiService(storage);
      await api.post(endpoint ?? ApiConstants.teknisiTicketLocation(ticketId), {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'heading': pos.heading != 0 ? pos.heading : null,
        'speed': pos.speed > 0 ? pos.speed * 3.6 : null,
      });

      _retryCount = 0;
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      await FlutterForegroundTask.updateService(
        notificationText: 'GPS aktif — diperbarui pukul $timeStr',
      );

      FlutterForegroundTask.sendDataToMain(
        jsonEncode({
          'status': 'active',
          'timestamp': now.toIso8601String(),
          'retry': 0,
        }),
      );
    } catch (_) {
      _retryCount++;
      await FlutterForegroundTask.updateService(
        notificationText: 'Menghubungkan GPS... ($_retryCount)',
      );
      FlutterForegroundTask.sendDataToMain(
        jsonEncode({
          'status': _retryCount >= 10 ? 'error' : 'pending',
          'retry': _retryCount,
        }),
      );
    }
  }
}
