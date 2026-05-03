class AppNotification {
  final int id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;
  final int? relatedTicketId;
  final String? relatedTicketType;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.payload = const {},
    this.relatedTicketId,
    this.relatedTicketType,
  });

  AppNotification copyWith({
    int? id,
    String? title,
    String? message,
    String? type,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? payload,
    int? relatedTicketId,
    String? relatedTicketType,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      payload: payload ?? this.payload,
      relatedTicketId: relatedTicketId ?? this.relatedTicketId,
      relatedTicketType: relatedTicketType ?? this.relatedTicketType,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? json['subject'] ?? 'Notifikasi')
        .toString()
        .trim();
    final message = (json['message'] ?? json['body'] ?? json['content'] ?? '')
        .toString()
        .trim();
    final type = (json['type'] ?? json['category'] ?? 'general')
        .toString()
        .toLowerCase();

    final readRaw = json['is_read'] ?? json['isRead'] ?? json['read'];
    final readAt = json['read_at'] ?? json['readAt'];
    final payload = _toMap(json['data']) ?? const <String, dynamic>{};
    final merged = _mergeMeta(json, payload);

    final rawTicketType =
        merged['ticket_type'] ?? merged['type_ticket'] ?? merged['ticket'];
    final fallbackType = type.contains('psb')
        ? 'psb'
        : (type.contains('trb') ? 'trb' : null);
    final ticketType = _normalizeTicketType(rawTicketType) ?? fallbackType;

    final ticketId =
        _toNullableInt(
          merged['ticket_id'] ??
              merged['id_ticket'] ??
              merged['trb_ticket_id'] ??
              merged['psb_ticket_id'] ??
              merged['reference_id'] ??
              merged['target_id'],
        ) ??
        _extractTicketIdFromText('$title $message');

    var isRead = false;
    if (readRaw is bool) {
      isRead = readRaw;
    } else if (readRaw != null) {
      final lower = readRaw.toString().toLowerCase();
      isRead = lower == '1' || lower == 'true';
    } else {
      isRead = readAt != null;
    }

    return AppNotification(
      id: _asInt(json['id']),
      title: title,
      message: message,
      type: type,
      isRead: isRead,
      createdAt: _parseDate(
        json['created_at'] ??
            json['createdAt'] ??
            json['timestamp'] ??
            json['sent_at'],
      ),
      payload: payload,
      relatedTicketId: ticketId,
      relatedTicketType: ticketType,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _normalizeTicketType(dynamic value) {
    if (value == null) return null;
    final text = value.toString().toLowerCase().trim();
    if (text.isEmpty) return null;
    if (text.contains('psb')) return 'psb';
    if (text.contains('trb')) return 'trb';
    return null;
  }

  static int? _extractTicketIdFromText(String value) {
    final regex = RegExp(r'#(?:TRB|PSB)-\d{4}-(\d+)');
    final match = regex.firstMatch(value.toUpperCase());
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static Map<String, dynamic> _mergeMeta(
    Map<String, dynamic> root,
    Map<String, dynamic> payload,
  ) {
    return {...root, ...payload};
  }

  static Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }
}
