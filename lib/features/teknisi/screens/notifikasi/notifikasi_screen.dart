import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/notification_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/notification_service.dart';
import '../tiket_psb/tiket_psb_detail_screen.dart';
import '../tiket_trb/tiket_trb_detail_screen.dart';

class NotifikasiScreen extends StatefulWidget {
  const NotifikasiScreen({super.key});

  @override
  State<NotifikasiScreen> createState() => _NotifikasiScreenState();
}

class _NotifikasiScreenState extends State<NotifikasiScreen>
    with WidgetsBindingObserver {
  late final NotificationService _notificationService;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  Timer? _periodicRefreshTimer;

  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _error;

  int get _unreadCount => _notifications.where((item) => !item.isRead).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationService = NotificationService(context.read<ApiService>());
    _bindRealtimeListener();
    _startPeriodicRefresh();
    unawaited(_loadNotifications(showLoader: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicRefreshTimer?.cancel();
    _fcmSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_loadNotifications(isRealtimeSync: true));
    }
  }

  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _isLoading || _isSyncing) return;
      unawaited(_loadNotifications(isRealtimeSync: true));
    });
  }

  void _bindRealtimeListener() {
    _fcmSubscription = FcmService.onForegroundMessage.listen((_) {
      if (!mounted) return;
      unawaited(_loadNotifications(isRealtimeSync: true));
    });
  }

  Future<void> _loadNotifications({
    bool showLoader = false,
    bool isRealtimeSync = false,
  }) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else if (isRealtimeSync) {
      setState(() {
        _isSyncing = true;
      });
    }

    try {
      final items = await _notificationService.getNotifications();
      if (!mounted) return;

      setState(() {
        _notifications = items;
        _isLoading = false;
        _isSyncing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSyncing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead) return;

    setState(() {
      _notifications = _notifications.map((item) {
        if (item.id == notification.id) {
          return item.copyWith(isRead: true);
        }
        return item;
      }).toList();
    });

    try {
      await _notificationService.markAsRead(notification);
    } catch (_) {
      if (!mounted) return;
      await _loadNotifications();
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      _notifications = _notifications
          .map((item) => item.copyWith(isRead: true))
          .toList();
    });

    try {
      await _notificationService.markAllAsRead();
    } catch (_) {
      if (!mounted) return;
      await _loadNotifications();
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'announcement':
        return Colors.deepPurple;
      case 'new_open_ticket':
      case 'ticket':
      case 'trb_assignment':
      case 'psb_assignment':
        return Colors.blue;
      case 'trb_status_update':
      case 'psb_status_update':
      case 'update':
        return Colors.orange;
      case 'reminder':
        return Colors.deepPurple;
      case 'success':
        return Colors.green;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'announcement':
        return Icons.campaign_outlined;
      case 'new_open_ticket':
      case 'ticket':
      case 'trb_assignment':
      case 'psb_assignment':
        return Icons.assignment_outlined;
      case 'trb_status_update':
      case 'psb_status_update':
      case 'update':
        return Icons.info_outline;
      case 'reminder':
        return Icons.schedule;
      case 'success':
        return Icons.check_circle_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _unreadCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifikasi',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Tandai Semua',
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tidak ada notifikasi',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _loadNotifications(showLoader: true),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (unreadCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$unreadCount notifikasi belum dibaca',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          if (_isSyncing)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ..._notifications.map(
                    (notification) => _buildNotificationCard(notification),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '-';

    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit yang lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam yang lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari yang lalu';

    return DateFormat('dd MMM yyyy, HH:mm', 'id').format(dateTime);
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final isRead = notification.isRead;
    final type = notification.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isRead
            ? Colors.white
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRead
              ? AppColors.cardBorder
              : AppColors.primary.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () async {
          await _markAsRead(notification);
          await _openRelatedScreen(notification);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getNotificationColor(type).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getNotificationIcon(type),
                  size: 20,
                  color: _getNotificationColor(type),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isRead
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(notification.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRelatedScreen(AppNotification notification) async {
    final ticketId = notification.relatedTicketId;
    final ticketType = notification.relatedTicketType;

    if (ticketId == null || ticketType == null) {
      return;
    }

    if (!mounted) return;

    if (ticketType == 'trb') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TiketTrbDetailScreen(ticketId: ticketId),
        ),
      );
      return;
    }

    if (ticketType == 'psb') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TiketPsbDetailScreen(ticketId: ticketId),
        ),
      );
    }
  }
}
