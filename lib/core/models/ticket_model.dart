import '../constants/api_constants.dart';

double? _toNullableDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();

  final text = raw.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null' || text == '-') {
    return null;
  }

  return double.tryParse(text);
}

String? _toNullableString(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

class TicketMessage {
  final int id;
  final String message;
  final String senderRole;
  final String type;
  final String? userName;
  final DateTime createdAt;

  TicketMessage({
    required this.id,
    required this.message,
    required this.senderRole,
    required this.type,
    this.userName,
    required this.createdAt,
  });

  factory TicketMessage.fromJson(Map<String, dynamic> json) {
    return TicketMessage(
      id: json['id'] as int,
      message: json['message'] as String? ?? '',
      senderRole: json['sender_role'] as String? ?? '',
      type: json['type'] as String? ?? 'normal',
      // API returns flat 'user_name', not nested 'user.name'
      userName:
          json['user_name'] as String? ?? json['user']?['name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class TicketPhoto {
  final int id;
  final String photoUrl;
  final String? photoType;
  final String? caption;
  final String? uploaderName;
  final DateTime createdAt;

  TicketPhoto({
    required this.id,
    required this.photoUrl,
    this.photoType,
    this.caption,
    this.uploaderName,
    required this.createdAt,
  });

  factory TicketPhoto.fromJson(Map<String, dynamic> json) {
    final rawPhotoUrl =
        (json['photo_url'] ??
                json['url'] ??
                json['photo'] ??
                json['path'] ??
                json['photo_path'])
            ?.toString();

    return TicketPhoto(
      id: json['id'] as int,
      photoUrl: _resolvePhotoUrl(rawPhotoUrl),
      photoType: json['photo_type'] as String?,
      caption: json['caption'] as String?,
      // API may return 'uploader' nested or not at all
      uploaderName: json['uploader']?['name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static String _resolvePhotoUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';

    final baseUri = Uri.parse(ApiConstants.storageUrl);
    var url = rawUrl.trim().replaceAll('\\', '/');

    if (url.startsWith('//')) {
      return '${baseUri.scheme}:$url';
    }

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      // Prefer https for same host to avoid Android cleartext blocks.
      if (parsed.scheme == 'http' && parsed.host == baseUri.host) {
        return parsed.replace(scheme: 'https').toString();
      }
      return parsed.toString();
    }

    if (url.startsWith('www.')) {
      return 'https://$url';
    }

    final looksLikeDomain = RegExp(
      r'^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$',
    ).hasMatch(url);
    if (looksLikeDomain) {
      return 'https://$url';
    }

    if (url.startsWith('./')) {
      url = url.substring(2);
    }

    if (url.startsWith('/public/storage/')) {
      url = '/storage/${url.substring('/public/storage/'.length)}';
    } else if (url.startsWith('public/storage/')) {
      url = '/storage/${url.substring('public/storage/'.length)}';
    } else if (url.startsWith('storage/')) {
      url = '/$url';
    } else if (!url.startsWith('/')) {
      url = '/$url';
    }

    return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}$url';
  }
}

class Ticket {
  final int id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String status;
  final String statusLabel;
  final String? fieldStatus;
  final String? fieldStatusLabel;
  final String? fieldNotes;
  final String? resolution;
  final int? assignedTo;
  final String? assignerName;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final double? customerLat;
  final double? customerLng;
  final String? category;
  final String? categoryLabel;
  final String? priority;
  final String? priorityLabel;
  final String? source;
  final String? sourceLabel;
  final String? odpName;
  final DateTime? technicianDispatchedAt;
  final DateTime? resolvedAt;
  final bool gpsEnabled;
  final DateTime? startedAt;
  final List<TicketMessage> messages;
  final List<TicketPhoto> photos;
  final DateTime createdAt;

  Ticket({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.status,
    required this.statusLabel,
    this.fieldStatus,
    this.fieldStatusLabel,
    this.fieldNotes,
    this.resolution,
    this.assignedTo,
    this.assignerName,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.customerLat,
    this.customerLng,
    this.category,
    this.categoryLabel,
    this.priority,
    this.priorityLabel,
    this.source,
    this.sourceLabel,
    this.odpName,
    this.technicianDispatchedAt,
    this.resolvedAt,
    this.gpsEnabled = false,
    this.startedAt,
    this.messages = const [],
    this.photos = const [],
    required this.createdAt,
  });

  bool get isClaimable => status == 'open' && assignedTo == null;

  factory Ticket.fromJson(Map<String, dynamic> json) {
    final msgList =
        (json['messages'] as List?)
            ?.map((m) => TicketMessage.fromJson(m))
            .toList() ??
        [];
    final photoList =
        (json['photos'] as List?)
            ?.map((p) => TicketPhoto.fromJson(p))
            .toList() ??
        [];
    return Ticket(
      id: json['id'] as int,
      ticketNumber: json['ticket_number'] as String,
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String,
      statusLabel: (json['status'] as String) == 'open'
          ? 'OPEN TICKET'
          : json['status_label'] as String,
      fieldStatus: json['field_status'] as String?,
      fieldStatusLabel: json['field_status_label'] as String?,
      fieldNotes: json['field_notes'] as String?,
      resolution: json['resolution'] as String?,
      assignedTo: json['assigned_to'] as int?,
      assignerName: json['assigner']?['name'] as String?,
      customerName: _toNullableString(json['customer']?['name']),
      customerPhone: _toNullableString(json['customer']?['phone']),
      customerAddress: _toNullableString(json['customer']?['address']),
      customerLat:
          _toNullableDouble(json['customer']?['latitude']) ??
          _toNullableDouble(json['customer_latitude']) ??
          _toNullableDouble(json['latitude']),
      customerLng:
          _toNullableDouble(json['customer']?['longitude']) ??
          _toNullableDouble(json['customer_longitude']) ??
          _toNullableDouble(json['longitude']),
      category: json['category'] as String?,
      categoryLabel: json['category_label'] as String?,
      priority: json['priority'] as String?,
      priorityLabel: json['priority_label'] as String?,
      source: json['source'] as String?,
      sourceLabel: json['source_label'] as String?,
      odpName: json['odp']?['name'] as String?,
      technicianDispatchedAt: json['technician_dispatched_at'] != null
          ? DateTime.tryParse(json['technician_dispatched_at'] as String)
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'] as String)
          : null,
      gpsEnabled: json['gps_enabled'] == true || json['gps_enabled'] == 1,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      messages: msgList,
      photos: photoList,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class PsbTicket {
  final int id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String status;
  final String statusLabel;
  final String? fieldStatus;
  final String? fieldStatusLabel;
  final String? servicePackage;
  final String? notes;
  final int? assignedTo;
  final String? assignerName;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final double? customerLat;
  final double? customerLng;
  final String? scheduledDate;
  final String? scheduledTime;
  final DateTime? technicianDispatchedAt;
  final DateTime? resolvedAt;
  final List<TicketMessage> messages;
  final List<TicketPhoto> photos;
  final DateTime createdAt;

  PsbTicket({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.status,
    required this.statusLabel,
    this.fieldStatus,
    this.fieldStatusLabel,
    this.servicePackage,
    this.notes,
    this.assignedTo,
    this.assignerName,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.customerLat,
    this.customerLng,
    this.scheduledDate,
    this.scheduledTime,
    this.technicianDispatchedAt,
    this.resolvedAt,
    this.messages = const [],
    this.photos = const [],
    required this.createdAt,
  });

  bool get isClaimable {
    return assignedTo == null && status == 'open';
  }

  bool get isFinished {
    const finishedStatuses = {'done', 'closed'};
    return finishedStatuses.contains(status);
  }

  factory PsbTicket.fromJson(Map<String, dynamic> json) {
    final msgList =
        (json['messages'] as List?)
            ?.map((m) => TicketMessage.fromJson(m))
            .toList() ??
        [];
    final photoList =
        (json['photos'] as List?)
            ?.map((p) => TicketPhoto.fromJson(p))
            .toList() ??
        [];

    return PsbTicket(
      id: json['id'] as int,
      ticketNumber: json['ticket_number'] as String,
      subject: (json['subject'] ?? json['service_package'] ?? 'Tiket PSB')
          .toString(),
      description: (json['description'] ?? json['notes'] ?? '').toString(),
      status: json['status'] as String,
      statusLabel: (json['status'] as String) == 'open'
          ? 'OPEN TICKET'
          : json['status_label'] as String,
      fieldStatus: json['field_status'] as String?,
      fieldStatusLabel: json['field_status_label'] as String?,
      servicePackage: json['service_package'] as String?,
      notes: json['notes'] as String?,
      assignedTo: json['assigned_to'] as int?,
      assignerName: json['assigner']?['name'] as String?,
      customerName: _toNullableString(json['customer']?['name']),
      customerPhone: _toNullableString(json['customer']?['phone']),
      customerAddress: _toNullableString(json['customer']?['address']),
      customerLat:
          _toNullableDouble(json['customer']?['latitude']) ??
          _toNullableDouble(json['customer_latitude']) ??
          _toNullableDouble(json['latitude']),
      customerLng:
          _toNullableDouble(json['customer']?['longitude']) ??
          _toNullableDouble(json['customer_longitude']) ??
          _toNullableDouble(json['longitude']),
      scheduledDate: json['scheduled_date'] as String?,
      scheduledTime: json['scheduled_time'] as String?,
      technicianDispatchedAt: json['technician_dispatched_at'] != null
          ? DateTime.tryParse(json['technician_dispatched_at'] as String)
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'] as String)
          : null,
      messages: msgList,
      photos: photoList,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
