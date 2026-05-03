import '../constants/api_constants.dart';
import '../models/notification_model.dart';
import 'api_service.dart';

class NotificationService {
  final ApiService _api;

  NotificationService(this._api);

  Future<List<AppNotification>> getNotifications({
    int page = 1,
    int perPage = 50,
    bool onlyUnread = false,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (onlyUnread) 'unread': '1',
      if (onlyUnread) 'unread_only': '1',
    };

    final responses = await Future.wait([
      _api.get(ApiConstants.teknisiNotifications, query: query),
      _api.get(ApiConstants.announcements),
    ]);

    final teknisiNotifications = _extractList(responses[0])
        .map((item) => AppNotification.fromJson(item))
        .where((item) => item.id != 0);

    final announcements = _extractAnnouncements(responses[1])
        .map((item) => AppNotification.fromJson(item))
        .where((item) => item.id != 0)
        .where((item) => !onlyUnread || !item.isRead);

    final merged = [...teknisiNotifications, ...announcements].toList();
    merged.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) return b.id.compareTo(a.id);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return merged;
  }

  Future<int> getUnreadCount() async {
    final responses = await Future.wait([
      _api.get(ApiConstants.teknisiNotificationsUnreadCount),
      _api.get(ApiConstants.announcements),
    ]);

    final response = responses[0];

    var teknisiUnread = 0;
    if (response is int) teknisiUnread = response;
    if (response is num) teknisiUnread = response.toInt();
    if (response is Map) {
      final map = _asMap(response) ?? const <String, dynamic>{};
      final value =
          map['unread_count'] ?? map['unread'] ?? map['count'] ?? map['total'];
      if (value is int) teknisiUnread = value;
      if (value is num) teknisiUnread = value.toInt();
      teknisiUnread = int.tryParse(value?.toString() ?? '') ?? teknisiUnread;
    }

    final announcementUnread = _extractAnnouncements(responses[1])
        .map((item) => AppNotification.fromJson(item))
        .where((item) => !item.isRead)
        .length;

    return teknisiUnread + announcementUnread;
  }

  Future<void> markAsRead(AppNotification notification) async {
    if (notification.type == 'announcement') {
      await _api.post(ApiConstants.announcementMarkRead(notification.id), {});
      return;
    }

    await _api.post(
      ApiConstants.teknisiNotificationMarkRead(notification.id),
      {},
    );
  }

  Future<void> markAllAsRead() async {
    final unreadAnnouncements = (await getNotifications(
      onlyUnread: true,
    )).where((item) => item.type == 'announcement').toList();

    await _api.post(ApiConstants.teknisiNotificationsReadAll, {});

    for (final announcement in unreadAnnouncements) {
      await _api.post(ApiConstants.announcementMarkRead(announcement.id), {});
    }
  }

  List<Map<String, dynamic>> _extractAnnouncements(dynamic response) {
    final list = _extractList(response);
    return list
        .map(
          (item) => {
            ...item,
            'type': 'announcement',
            'message': item['message'] ?? item['content'],
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _extractList(dynamic response) {
    if (response is List) {
      return response
          .map((item) => _asMap(item))
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    final map = _asMap(response);
    if (map == null) return const [];

    final candidates = [
      map['data'],
      map['announcements'],
      map['notifications'],
      map['items'],
      map['results'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate
            .map((item) => _asMap(item))
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      final candidateMap = _asMap(candidate);
      final nestedData = candidateMap?['data'];
      if (nestedData is List) {
        return nestedData
            .map((item) => _asMap(item))
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    }

    return const [];
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }
}
