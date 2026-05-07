class ApiConstants {
  // static const String baseUrl = 'http://127.0.0.1:8000/api';
  // static const String baseUrl = 'http://10.0.2.2:8000/api';
  // static const String baseUrl = "http://192.168.1.33:8000/api";
  // static const String baseUrl = "https://dev-mysimtek.coglinetech.com/api";
  static const String baseUrl = "https://mysimtek.coglinetech.com/api";

  /// Public storage URL (for serving uploaded files)
  static String get storageUrl => baseUrl.replaceFirst('/api', '');

  // Auth
  static const String login = '/login';
  static const String logout = '/logout';
  static const String me = '/me';
  static const String fcmTokenUpdate = '/fcm-token';
  static const String verifyPassword = '/verify-password';
  static const String changePassword = '/change-password';

  // Teknisi endpoints
  static const String teknisiOdp = '/teknisi/odp';
  static const String teknisiJadwal = '/teknisi/jadwal';
  static const String teknisiTickets = '/teknisi/tickets';
  static String teknisiTicketDetail(dynamic id) => '/teknisi/tickets/$id';
  static String teknisiTicketClaim(dynamic id) => '/teknisi/tickets/$id/claim';
  static String teknisiTicketStart(dynamic id) => '/teknisi/tickets/$id/start';
  static String teknisiTicketLocation(dynamic id) =>
      '/teknisi/tickets/$id/location';
  static String teknisiTicketFieldReport(dynamic id) =>
      '/teknisi/tickets/$id/field-report';
  static String teknisiTicketMessages(dynamic id) =>
      '/teknisi/tickets/$id/messages';

  // PSB Tickets
  static const String teknisiPsbTickets = '/teknisi/psb-tickets';
  static String teknisiPsbTicketDetail(dynamic id) =>
      '/teknisi/psb-tickets/$id';
  static String teknisiPsbTicketClaim(dynamic id) =>
      '/teknisi/psb-tickets/$id/claim';
  static String teknisiPsbTicketStart(dynamic id) =>
      '/teknisi/psb-tickets/$id/start';
  static String teknisiPsbTicketLocation(dynamic id) =>
      '/teknisi/psb-tickets/$id/location';
  static String teknisiPsbFieldReport(dynamic id) =>
      '/teknisi/psb-tickets/$id/field-report';
  static String teknisiPsbMessages(dynamic id) =>
      '/teknisi/psb-tickets/$id/messages';

  // Map & Infrastructure
  static const String teknisiMapData = '/teknisi/map-data';

  // Notifications
  static const String teknisiNotifications = '/teknisi/notifications';
  static const String teknisiNotificationsUnreadCount =
      '/teknisi/notifications/unread-count';
  static String teknisiNotificationMarkRead(dynamic id) =>
      '/teknisi/notifications/$id/read';
  static const String teknisiNotificationsReadAll =
      '/teknisi/notifications/read-all';

  // Announcements
  static const String announcements = '/notifications/announcements';
  static String announcementMarkRead(int id) =>
      '/notifications/announcements/$id/read';
}
