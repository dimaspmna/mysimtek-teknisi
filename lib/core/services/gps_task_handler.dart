import 'dart:convert';
import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'debug_event_logger.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Entry point for the foreground service isolate.
@pragma('vm:entry-point')
void gpsTaskCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}

class GpsTaskHandler extends TaskHandler {
  int _retryCount = 0;
  bool _firstPushSent = false;

  Future<({Position? position, String source})> _resolvePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('location_service_disabled');
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('location_permission_denied:$permission');
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          intervalDuration: Duration(seconds: 5),
          forceLocationManager: false,
        ),
      );
      return (position: pos, source: 'current_high');
    } catch (_) {
      // Fallback to a looser low-power fix that often resolves faster.
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          intervalDuration: Duration(seconds: 5),
          forceLocationManager: false,
        ),
      );
      return (position: pos, source: 'current_low');
    } catch (_) {
      // Continue to other fallbacks.
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.medium,
          intervalDuration: Duration(seconds: 5),
          forceLocationManager: true,
        ),
      );
      return (position: pos, source: 'current_android_manager');
    } catch (_) {
      // Continue to stream/last-known fallbacks.
    }

    try {
      final streamPos = await Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          intervalDuration: Duration(seconds: 5),
          distanceFilter: 0,
          forceLocationManager: false,
        ),
      ).first.timeout(const Duration(seconds: 10));
      return (position: streamPos, source: 'stream_first');
    } on TimeoutException {
      // Stream did not yield in time, continue fallback.
    } catch (_) {
      // Continue fallback.
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return (position: lastKnown, source: 'last_known');
    }

    throw Exception('location_unavailable');
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _retryCount = 0;
    _firstPushSent = false;
    DebugEventLogger.log(
      'gps_task_started',
      scope: 'gps_task',
      data: {'starter': starter.name},
    );
    await _pushLocation();
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
      final resolved = await _resolvePosition();
      final pos = resolved.position;
      if (pos == null) throw Exception('location_unavailable');

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

      if (!_firstPushSent) {
        _firstPushSent = true;
        DebugEventLogger.log(
          'gps_first_location_push',
          scope: 'gps_task',
          data: {
            'ticket_id': ticketId,
            'endpoint':
                endpoint ?? ApiConstants.teknisiTicketLocation(ticketId),
            'position_source': resolved.source,
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy': pos.accuracy,
          },
        );
      } else {
        DebugEventLogger.log(
          'gps_location_push',
          scope: 'gps_task',
          data: {
            'ticket_id': ticketId,
            'endpoint':
                endpoint ?? ApiConstants.teknisiTicketLocation(ticketId),
            'position_source': resolved.source,
            'accuracy': pos.accuracy,
          },
        );
      }

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
    } catch (e) {
      _retryCount++;
      DebugEventLogger.log(
        'gps_push_retry',
        scope: 'gps_task',
        data: {
          'ticket_id': ticketId,
          'endpoint': endpoint ?? ApiConstants.teknisiTicketLocation(ticketId),
          'retry_count': _retryCount,
          'error': e.toString(),
          'status': _retryCount >= 10 ? 'error' : 'pending',
        },
      );
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
