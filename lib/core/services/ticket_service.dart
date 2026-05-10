import 'dart:io';
import '../models/ticket_model.dart';
import 'api_service.dart';

class TicketService {
  final ApiService _api;

  TicketService(this._api);

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  // ─── TRB Tickets ─────────────────────────────────────────────────────────

  Future<List<Ticket>> getTrbTickets({String? status, String? search}) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (search != null && search.isNotEmpty) query['search'] = search;
    final response = await _api.get(
      '/teknisi/tickets',
      query: query.isEmpty ? null : query,
    );
    if (response['status'] == 'success') {
      final data = response['data'] as List;
      return data.map((json) => Ticket.fromJson(json)).toList();
    }
    throw ApiException(response['message'] ?? 'Gagal mengambil data tiket TRB');
  }

  Future<Ticket> getTrbTicketDetail(int ticketId) async {
    // _parse auto-unwraps { status, data } → returns the ticket map directly
    final response = await _api.get('/teknisi/tickets/$ticketId');
    if (response is Map<String, dynamic>) {
      // Already unwrapped: response IS the ticket
      if (response.containsKey('ticket_number')) {
        return Ticket.fromJson(response);
      }
      // Still wrapped (e.g. stats present)
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ?? _asMap(response['ticket']) ?? response;
        if (payload.containsKey('ticket_number')) {
          return Ticket.fromJson(payload);
        }
        throw ApiException(response['message'] ?? 'Data tiket tidak tersedia');
      }
      throw ApiException(response['message'] ?? 'Gagal mengambil detail tiket');
    }
    throw ApiException('Gagal mengambil detail tiket');
  }

  Future<Ticket> claimTrbTicket(int ticketId) async {
    final response = await _api.post('/teknisi/tickets/$ticketId/claim', {});
    if (response is Map<String, dynamic>) {
      if (response.containsKey('ticket_number'))
        return Ticket.fromJson(response);
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ??
            _asMap(response['ticket']) ??
            _asMap(response['result']);
        if (payload != null && payload.containsKey('ticket_number')) {
          return Ticket.fromJson(payload);
        }
        // Some claim endpoints return success message without full object.
        return getTrbTicketDetail(ticketId);
      }
      throw ApiException(response['message'] ?? 'Gagal mengambil tiket');
    }
    throw ApiException('Gagal mengambil tiket');
  }

  Future<Ticket> startTrb(int ticketId) async {
    final response = await _api.post('/teknisi/tickets/$ticketId/start', {});
    if (response is Map<String, dynamic>) {
      if (response.containsKey('ticket_number'))
        return Ticket.fromJson(response);
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ??
            _asMap(response['ticket']) ??
            _asMap(response['result']);
        if (payload != null && payload.containsKey('ticket_number')) {
          return Ticket.fromJson(payload);
        }
        return getTrbTicketDetail(ticketId);
      }
      throw ApiException(response['message'] ?? 'Gagal memulai TRB');
    }
    throw ApiException('Gagal memulai TRB');
  }

  Future<void> sendTrbFieldReport({
    required int ticketId,
    required String fieldStatus,
    required String fieldNotes,
    required File photo,
    String? photoType,
    String? caption,
  }) async {
    final mappedStatus = fieldStatus == 'fixed' ? 'done' : 'in_progress';
    final fields = {
      'field_status': fieldStatus,
      'field_notes': fieldNotes,
      'status': mappedStatus,
      'field_report': fieldNotes,
      if (photoType != null) 'photo_type': photoType,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    };
    final response = await _api.postMultipart(
      '/teknisi/tickets/$ticketId/field-report',
      fields,
      files: [photo],
      fileField: 'photo',
    );

    if (response is Map) {
      final status = response['status']?.toString().toLowerCase();
      final success = response['success'];
      if (status == 'success' || success == true) {
        return;
      }
      throw ApiException(
        response['message']?.toString() ?? 'Gagal mengirim laporan',
      );
    }

    throw ApiException('Gagal mengirim laporan');
  }

  Future<Map<String, dynamic>> sendTrbMessage(
    int ticketId,
    String message,
  ) async {
    final response = await _api.post('/teknisi/tickets/$ticketId/messages', {
      'message': message,
    });
    // _parse may return the message map directly (auto-unwrapped) or the full envelope
    if (response is Map<String, dynamic>) {
      if (response.containsKey('message') && !response.containsKey('status')) {
        return response; // already the message object
      }
      if (response.containsKey('id')) return response; // message object
      if (response['status'] == 'success') {
        return (response['data'] ?? {}) as Map<String, dynamic>;
      }
      throw ApiException(response['message'] ?? 'Gagal mengirim pesan');
    }
    return {};
  }

  // ─── PSB Tickets ─────────────────────────────────────────────────────────

  Future<List<PsbTicket>> getPsbTickets() async {
    final response = await _api.get('/teknisi/psb-tickets');
    if (response is Map<String, dynamic> && response['status'] == 'success') {
      final data = response['data'] as List;
      return data.map((json) => PsbTicket.fromJson(json)).toList();
    }
    if (response is List) {
      return response.map((json) => PsbTicket.fromJson(json)).toList();
    }
    throw ApiException(response['message'] ?? 'Gagal mengambil data tiket PSB');
  }

  Future<PsbTicket> getPsbTicketDetail(int ticketId) async {
    final response = await _api.get('/teknisi/psb-tickets/$ticketId');
    if (response is Map<String, dynamic>) {
      if (response.containsKey('ticket_number')) {
        return PsbTicket.fromJson(response);
      }
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ??
            _asMap(response['psb_ticket']) ??
            response;
        if (payload.containsKey('ticket_number')) {
          return PsbTicket.fromJson(payload);
        }
        throw ApiException(response['message'] ?? 'Data tiket tidak tersedia');
      }
      throw ApiException(response['message'] ?? 'Gagal mengambil detail tiket');
    }
    throw ApiException('Gagal mengambil detail tiket');
  }

  Future<PsbTicket> claimPsbTicket(int ticketId) async {
    final response = await _api.post(
      '/teknisi/psb-tickets/$ticketId/claim',
      {},
    );
    if (response is Map<String, dynamic>) {
      if (response.containsKey('ticket_number')) {
        return PsbTicket.fromJson(response);
      }
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ??
            _asMap(response['psb_ticket']) ??
            _asMap(response['result']);
        if (payload != null && payload.containsKey('ticket_number')) {
          return PsbTicket.fromJson(payload);
        }
        return getPsbTicketDetail(ticketId);
      }
      throw ApiException(response['message'] ?? 'Gagal mengambil tiket');
    }
    throw ApiException('Gagal mengambil tiket');
  }

  Future<PsbTicket> startPsb(int ticketId) async {
    final response = await _api.post(
      '/teknisi/psb-tickets/$ticketId/start',
      {},
    );
    if (response is Map<String, dynamic>) {
      if (response.containsKey('ticket_number')) {
        return PsbTicket.fromJson(response);
      }
      if (response['status'] == 'success') {
        final payload =
            _asMap(response['data']) ??
            _asMap(response['psb_ticket']) ??
            _asMap(response['result']);
        if (payload != null && payload.containsKey('ticket_number')) {
          return PsbTicket.fromJson(payload);
        }
        return getPsbTicketDetail(ticketId);
      }
      throw ApiException(response['message'] ?? 'Gagal memulai PSB');
    }
    throw ApiException('Gagal memulai PSB');
  }

  Future<void> sendPsbFieldReport({
    required int ticketId,
    required String fieldStatus,
    required String fieldNotes,
    required File photo,
    String? photoType,
    String? caption,
  }) async {
    final mappedStatus = (fieldStatus == 'done' || fieldStatus == 'fixed')
        ? 'done'
        : 'in_progress';
    final fields = {
      'field_status': fieldStatus,
      'field_notes': fieldNotes,
      'status': mappedStatus,
      'field_report': fieldNotes,
      if (photoType != null) 'photo_type': photoType,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    };

    final response = await _api.postMultipart(
      '/teknisi/psb-tickets/$ticketId/field-report',
      fields,
      files: [photo],
      fileField: 'photo',
    );

    if (response is Map) {
      final status = response['status']?.toString().toLowerCase();
      final success = response['success'];
      if (status == 'success' || success == true) {
        return;
      }
      throw ApiException(
        response['message']?.toString() ?? 'Gagal mengirim laporan',
      );
    }

    throw ApiException('Gagal mengirim laporan');
  }

  Future<Map<String, dynamic>> sendPsbMessage(
    int ticketId,
    String message,
  ) async {
    final response = await _api.post(
      '/teknisi/psb-tickets/$ticketId/messages',
      {'message': message},
    );

    if (response is Map<String, dynamic>) {
      if (response.containsKey('message') && !response.containsKey('status')) {
        return response;
      }
      if (response.containsKey('id')) {
        return response;
      }
      if (response['status'] == 'success') {
        return (response['data'] ?? {}) as Map<String, dynamic>;
      }
      throw ApiException(response['message'] ?? 'Gagal mengirim pesan');
    }

    return {};
  }
}
