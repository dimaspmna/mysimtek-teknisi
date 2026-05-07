import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_streaming_service.dart';

/// Singleton provider that holds the active GPS tracking service.
/// Keeps tracking alive even when the detail screen is popped.
class GpsTrackingProvider extends ChangeNotifier {
  LocationStreamingService? _service;

  TrackingStatus _status = TrackingStatus.idle;
  DateTime? _lastPush;
  int _retryCount = 0;
  int? _activeTicketId;

  TrackingStatus get status => _status;
  DateTime? get lastPush => _lastPush;
  int get retryCount => _retryCount;
  int? get activeTicketId => _activeTicketId;
  bool get isRunning => _service != null && _service!.isRunning;

  /// Restore GPS tracking state from background service if still running.
  /// Call this when app resumes from background.
  Future<void> restoreStateFromBackground() async {
    // Check if foreground service is still running
    final isServiceRunning = await FlutterForegroundTask.isRunningService;
    if (!isServiceRunning) {
      // Service not running, ensure state is clean
      if (_service != null) {
        _service = null;
        _activeTicketId = null;
        _status = TrackingStatus.idle;
        _lastPush = null;
        _retryCount = 0;
        notifyListeners();
      }
      return;
    }

    // Service is running, restore state from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final ticketId = prefs.getInt('gps_ticket_id');
      final endpoint = prefs.getString('gps_endpoint');

      if (ticketId == null) {
        // No ticket ID stored, service is orphaned - stop it
        await FlutterForegroundTask.stopService();
        _service = null;
        _activeTicketId = null;
        _status = TrackingStatus.idle;
        _lastPush = null;
        _retryCount = 0;
        notifyListeners();
        return;
      }

      // Re-create service instance and re-register callback
      _activeTicketId = ticketId;
      _service = LocationStreamingService(
        ticketId: ticketId,
        locationEndpoint: endpoint,
        onStatusChanged: (status, lastPush, retryCount) {
          _status = status;
          _lastPush = lastPush;
          _retryCount = retryCount;
          notifyListeners();
        },
      );

      // Mark as running and restore to service
      _service!.restoreFromBackground();
      _status = TrackingStatus.active; // Assume active until callback updates
      notifyListeners();
    } catch (e) {
      // Error restoring state, clean up
      _service = null;
      _activeTicketId = null;
      _status = TrackingStatus.idle;
      _lastPush = null;
      _retryCount = 0;
      notifyListeners();
    }
  }

  /// Restart tracking for the same ticket (e.g. after app was killed).
  Future<void> restartTracking() async {
    final ticketId = _activeTicketId;
    final endpoint = _service?.locationEndpoint;
    if (ticketId == null) return;

    if (_service != null) {
      _service!.stop();
      _service = null;
    }

    await startTracking(ticketId, endpoint: endpoint);
  }

  Future<void> startTracking(int ticketId, {String? endpoint}) async {
    // If already tracking this ticket, do nothing
    if (_service != null &&
        _service!.isRunning &&
        _activeTicketId == ticketId) {
      return;
    }

    // Stop any previous service first (different ticket or stale)
    if (_service != null) {
      _service!.stop();
      _service = null;
    }

    _activeTicketId = ticketId;
    _service = LocationStreamingService(
      ticketId: ticketId,
      locationEndpoint: endpoint,
      onStatusChanged: (status, lastPush, retryCount) {
        _status = status;
        _lastPush = lastPush;
        _retryCount = retryCount;
        notifyListeners();
      },
    );

    _status = TrackingStatus.pending;
    notifyListeners();

    await _service!.start();
  }

  void stopTracking() {
    if (_service == null) return;
    _service!.stop();
    _service = null;
    _activeTicketId = null;
    _status = TrackingStatus.idle;
    _lastPush = null;
    _retryCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.stop();
    super.dispose();
  }
}
