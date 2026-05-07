import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gps_task_handler.dart';

export 'gps_task_handler.dart' show gpsTaskCallback;

enum TrackingStatus { idle, active, pending, error }

typedef StatusCallback =
    void Function(TrackingStatus status, DateTime? lastPush, int retryCount);

class LocationStreamingService {
  final int ticketId;
  final String? locationEndpoint;
  final StatusCallback? onStatusChanged;

  bool _isRunning = false;
  TrackingStatus _status = TrackingStatus.idle;
  DateTime? _lastSuccessfulPush;
  int _retryCount = 0;

  LocationStreamingService({
    required this.ticketId,
    this.locationEndpoint,
    this.onStatusChanged,
  });

  bool get isRunning => _isRunning;
  TrackingStatus get status => _status;

  /// Restore tracking state from background service.
  /// Re-registers callback without starting a new service.
  void restoreFromBackground() {
    if (_isRunning) return; // Already running
    _isRunning = true;
    _status = TrackingStatus.active;

    // Re-register callback to receive updates from background task
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  static void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gps_tracking_channel',
        channelName: 'GPS Tracking',
        channelDescription: 'Tracking lokasi teknisi aktif',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _retryCount = 0;
    _setStatus(TrackingStatus.pending);

    // Store config in SharedPreferences so the task isolate can read it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gps_ticket_id', ticketId);
    if (locationEndpoint != null) {
      await prefs.setString('gps_endpoint', locationEndpoint!);
    } else {
      await prefs.remove('gps_endpoint');
    }

    _initForegroundTask();

    // Register callback to receive status updates from the task isolate
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    ServiceRequestResult? result;
    try {
      result = await FlutterForegroundTask.startService(
        serviceId: 300,
        notificationTitle: 'GPS Tracking Aktif',
        notificationText: 'Memulai tracking lokasi...',
        callback: gpsTaskCallback,
      );
    } catch (e) {
      // SecurityException on Android 14+ if location permission not granted at runtime
      _isRunning = false;
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      _setStatus(TrackingStatus.error);
      return;
    }

    if (result is! ServiceRequestSuccess) {
      _isRunning = false;
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      _setStatus(TrackingStatus.error);
    }
  }

  void _onTaskData(Object data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final statusStr = map['status'] as String;
      final retry = (map['retry'] as num?)?.toInt() ?? 0;
      final tsStr = map['timestamp'] as String?;

      _retryCount = retry;
      if (tsStr != null) _lastSuccessfulPush = DateTime.parse(tsStr);

      final newStatus = switch (statusStr) {
        'active' => TrackingStatus.active,
        'pending' => TrackingStatus.pending,
        _ => TrackingStatus.error,
      };
      _setStatus(newStatus);
    } catch (_) {}
  }

  void _setStatus(TrackingStatus s) {
    _status = s;
    onStatusChanged?.call(s, _lastSuccessfulPush, _retryCount);
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    FlutterForegroundTask.stopService();
    _setStatus(TrackingStatus.idle);
  }

  void dispose() {
    stop();
  }
}
