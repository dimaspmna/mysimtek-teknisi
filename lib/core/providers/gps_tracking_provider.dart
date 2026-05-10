import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/debug_event_logger.dart';
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
  String? get activeEndpoint => _service?.locationEndpoint;
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
    DebugEventLogger.log(
      'gps_start_requested',
      scope: 'gps_provider',
      data: {'ticket_id': ticketId, 'endpoint': endpoint ?? ''},
    );

    // If already tracking this ticket + endpoint, do nothing.
    // Endpoint is important to prevent PSB/TRB collisions when IDs overlap.
    if (_service != null &&
        _service!.isRunning &&
        _activeTicketId == ticketId) {
      final currentEndpoint = _service!.locationEndpoint ?? '';
      final targetEndpoint = endpoint ?? '';
      if (currentEndpoint == targetEndpoint) {
        DebugEventLogger.log(
          'gps_start_skipped_same_target',
          scope: 'gps_provider',
          data: {'ticket_id': ticketId, 'endpoint': targetEndpoint},
        );
        return;
      }
    }

    // Stop any previous service first (different ticket or stale)
    if (_service != null) {
      DebugEventLogger.log(
        'gps_previous_service_stopped',
        scope: 'gps_provider',
        data: {'old_ticket_id': _activeTicketId},
      );
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
        DebugEventLogger.log(
          'gps_status_changed',
          scope: 'gps_provider',
          data: {
            'ticket_id': ticketId,
            'endpoint': endpoint ?? '',
            'status': status.name,
            'retry_count': retryCount,
            'last_push': lastPush?.toIso8601String(),
          },
        );
        notifyListeners();
      },
    );

    _status = TrackingStatus.pending;
    notifyListeners();

    await _service!.start();
    DebugEventLogger.log(
      'gps_start_invoked',
      scope: 'gps_provider',
      data: {
        'ticket_id': ticketId,
        'endpoint': endpoint ?? '',
        'status': _status.name,
      },
    );
  }

  bool isTrackingHealthy(int ticketId, {String? endpoint}) {
    if (!isRunning || _activeTicketId != ticketId) return false;

    final expectedEndpoint = endpoint ?? '';
    final currentEndpoint = _service?.locationEndpoint ?? '';
    if (currentEndpoint != expectedEndpoint) return false;

    return _status != TrackingStatus.error;
  }

  Future<bool> startTrackingSafely(
    int ticketId, {
    String? endpoint,
    int retries = 1,
    Duration settleDuration = const Duration(milliseconds: 1400),
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      DebugEventLogger.log(
        'gps_start_attempt',
        scope: 'gps_provider',
        data: {
          'ticket_id': ticketId,
          'endpoint': endpoint ?? '',
          'attempt': attempt + 1,
          'max_attempts': retries + 1,
        },
      );

      await startTracking(ticketId, endpoint: endpoint);

      if (isTrackingHealthy(ticketId, endpoint: endpoint)) {
        DebugEventLogger.log(
          'gps_start_success',
          scope: 'gps_provider',
          data: {
            'ticket_id': ticketId,
            'endpoint': endpoint ?? '',
            'attempt': attempt + 1,
          },
        );
        return true;
      }

      final settleUntil = DateTime.now().add(settleDuration);
      while (DateTime.now().isBefore(settleUntil)) {
        if (isTrackingHealthy(ticketId, endpoint: endpoint)) {
          return true;
        }

        if (_status == TrackingStatus.error) {
          DebugEventLogger.log(
            'gps_start_wait_break_error',
            scope: 'gps_provider',
            data: {
              'ticket_id': ticketId,
              'endpoint': endpoint ?? '',
              'attempt': attempt + 1,
              'retry_count': _retryCount,
            },
          );
          break;
        }

        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (attempt < retries) {
        DebugEventLogger.log(
          'gps_start_retry_scheduled',
          scope: 'gps_provider',
          data: {
            'ticket_id': ticketId,
            'endpoint': endpoint ?? '',
            'next_attempt': attempt + 2,
          },
        );
        stopTracking();
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }

    final healthy = isTrackingHealthy(ticketId, endpoint: endpoint);
    DebugEventLogger.log(
      healthy ? 'gps_start_success_final' : 'gps_start_failed',
      scope: 'gps_provider',
      data: {
        'ticket_id': ticketId,
        'endpoint': endpoint ?? '',
        'retry_count': _retryCount,
        'status': _status.name,
      },
    );
    return healthy;
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
