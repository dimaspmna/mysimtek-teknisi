import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/attendance_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/gps_tracking_provider.dart';
import '../../../core/services/location_streaming_service.dart';
import '../../../core/widgets/tracking_status_card.dart';
import '../../../core/models/ticket_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/ticket_service.dart';
import 'tiket_trb/tiket_trb_screen.dart';
import 'tiket_trb/tiket_trb_detail_screen.dart';
import 'tiket_psb/tiket_psb_screen.dart';
import 'tiket_psb/tiket_psb_detail_screen.dart';
import 'peta_area/peta_area_screen.dart';
import 'riwayat_tugas/riwayat_tugas_screen.dart';
import 'notifikasi/notifikasi_screen.dart';

class BerandaScreen extends StatefulWidget {
  const BerandaScreen({super.key});

  @override
  State<BerandaScreen> createState() => _BerandaScreenState();
}

class _BerandaScreenState extends State<BerandaScreen> {
  List<Ticket> _trbTickets = [];
  List<PsbTicket> _psbTickets = [];
  bool _isLoading = true;
  int _unreadNotificationCount = 0;

  late final NotificationService _notificationService;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  Timer? _periodicRefreshTimer;

  static const _completedStatuses = {'resolved', 'closed', 'completed', 'done'};
  static const _inactiveStatuses = {
    'resolved',
    'closed',
    'completed',
    'done',
    'cancelled',
  };

  bool _isTrbActiveForUser(Ticket ticket, int? userId) {
    if (userId == null || ticket.assignedTo != userId) return false;
    final status = ticket.status.toLowerCase();
    return !_inactiveStatuses.contains(status);
  }

  bool _isPsbFinished(PsbTicket ticket) {
    return ticket.isFinished;
  }

  int _getTrbAvailableCount() {
    return _trbTickets.where((ticket) => ticket.isClaimable).length;
  }

  int _getPsbAvailableCount() {
    return _psbTickets.where((ticket) => ticket.isClaimable).length;
  }

  int _getCompletedTakenCount(int? userId) {
    final trbCompleted = _trbTickets.where((ticket) {
      final status = ticket.status.toLowerCase();
      return ticket.assignedTo == userId && _completedStatuses.contains(status);
    }).length;

    final psbCompleted = _psbTickets.where((ticket) {
      return ticket.assignedTo == userId && _isPsbFinished(ticket);
    }).length;

    return trbCompleted + psbCompleted;
  }

  Future<void> _pushAndRefresh(BuildContext context, Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );

    if (!mounted) return;
    await _fetchTickets();
  }

  Color _getTrbStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return AppColors.success;
      case 'confirmed':
      case 'in_progress':
        return AppColors.info;
      case 'done':
      case 'resolved':
      case 'closed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getPsbStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
      case 'open':
        return AppColors.success;
      case 'scheduled':
        return AppColors.warning;
      case 'in_progress':
      case 'on_site':
        return AppColors.info;
      case 'completed':
      case 'activated':
      case 'closed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      _BerandaLifecycleObserver(
        onResume: () {
          if (!mounted) return;
          unawaited(_fetchUnreadNotificationCount());
          unawaited(_fetchTickets());
        },
      ),
    );
    _notificationService = NotificationService(context.read<ApiService>());
    _bindNotificationRealtime();
    _startPeriodicRefresh();
    unawaited(_fetchUnreadNotificationCount());
    _fetchTickets();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAttendance());
  }

  @override
  void dispose() {
    _periodicRefreshTimer?.cancel();
    _fcmSubscription?.cancel();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _isLoading) return;
      unawaited(_fetchUnreadNotificationCount());
      unawaited(_silentRefreshTickets());
    });
  }

  Future<void> _silentRefreshTickets() async {
    try {
      final storage = StorageService();
      final api = ApiService(storage);
      final ticketService = TicketService(api);
      final results = await Future.wait([
        ticketService.getTrbTickets(),
        ticketService.getPsbTickets(),
      ]);
      if (!mounted) return;
      setState(() {
        _trbTickets = results[0] as List<Ticket>;
        _psbTickets = results[1] as List<PsbTicket>;
      });
    } catch (_) {}
  }

  void _bindNotificationRealtime() {
    _fcmSubscription = FcmService.onForegroundMessage.listen((_) {
      if (!mounted) return;
      unawaited(_fetchUnreadNotificationCount());
      unawaited(_silentRefreshTickets());
    });
  }

  Future<void> _fetchUnreadNotificationCount() async {
    try {
      final count = await _notificationService.getUnreadCount();
      if (!mounted) return;
      setState(() {
        _unreadNotificationCount = count;
      });
    } catch (_) {}
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final storage = StorageService();
      final api = ApiService(storage);
      final ticketService = TicketService(api);

      final results = await Future.wait([
        ticketService.getTrbTickets(),
        ticketService.getPsbTickets(),
      ]);

      setState(() {
        _trbTickets = results[0] as List<Ticket>;
        _psbTickets = results[1] as List<PsbTicket>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _fetchAttendance() {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null || email.isEmpty) return;
    context.read<AttendanceProvider>().fetchToday(email);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final userId = user?.id;
    final activeTrbTickets = _trbTickets
        .where((ticket) => _isTrbActiveForUser(ticket, userId))
        .toList();
    final activePsbTickets = _psbTickets
        .where(
          (ticket) => ticket.assignedTo == userId && !_isPsbFinished(ticket),
        )
        .toList();
    final availableTrbTickets = _trbTickets
        .where((ticket) => ticket.isClaimable)
        .take(2)
        .toList();
    final availablePsbTickets = _psbTickets
        .where((ticket) => ticket.isClaimable)
        .take(2)
        .toList();
    final hasActiveTickets =
        activeTrbTickets.isNotEmpty || activePsbTickets.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/logo/app_landscape.png',
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.textPrimary,
                ),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotifikasiScreen(),
                ),
              );

              if (!mounted) return;
              await _fetchUnreadNotificationCount();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTickets,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Welcome Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.engineering, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Teknisi ',
                        style: const TextStyle(fontWeight: FontWeight.w400),
                        children: [
                          TextSpan(
                            text: user?.name ?? 'Teknisi',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                  Consumer<AttendanceProvider>(
                    builder: (_, attendance, __) {
                      if (attendance.status == null)
                        return const SizedBox.shrink();
                      return _AttendanceBadge(status: attendance.status!);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Statistics Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatRow(
                    title: 'Tiket TRB Tersedia',
                    count: _isLoading ? '-' : '${_getTrbAvailableCount()}',
                    countColor: AppColors.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatRow(
                    title: 'Tiket PSB Tersedia',
                    count: _isLoading ? '-' : '${_getPsbAvailableCount()}',
                    countColor: AppColors.info,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatRow(
                    title: 'Riwayat Tugas',
                    count: _isLoading
                        ? '-'
                        : '${_getCompletedTakenCount(userId)}',
                    countColor: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // GPS Tracking status (visible when GPS is active for any ticket)
            Consumer<GpsTrackingProvider>(
              builder: (_, gps, __) {
                if (gps.activeTicketId == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TrackingStatusCard(
                    status: gps.isRunning ? gps.status : TrackingStatus.idle,
                    lastPush: gps.lastPush,
                    retryCount: gps.retryCount,
                    onRestart: () => gps.restartTracking(),
                  ),
                );
              },
            ),

            // // Menu Grid
            // const Text(
            //   'Menu Utama',
            //   style: TextStyle(
            //     fontSize: 16,
            //     fontWeight: FontWeight.w600,
            //     color: AppColors.textPrimary,
            //   ),
            // ),
            // const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMenuCard(
                    icon: Icons.build_circle_outlined,
                    title: 'Tiket\nTRB',
                    color: Colors.red,
                    onTap: () {
                      _pushAndRefresh(context, const TiketTrbScreen());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMenuCard(
                    icon: Icons.electrical_services_rounded,
                    title: 'Tiket\nPSB',
                    color: Colors.blue,
                    onTap: () {
                      _pushAndRefresh(context, const TiketPsbScreen());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMenuCard(
                    icon: Icons.map,
                    title: 'Peta\nArea',
                    color: Colors.yellow.shade700,
                    onTap: () {
                      _pushAndRefresh(context, const PetaAreaScreen());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMenuCard(
                    icon: Icons.history,
                    title: 'Riwayat\nTugas',
                    color: Colors.green,
                    onTap: () {
                      _pushAndRefresh(context, const RiwayatTugasScreen());
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasActiveTickets) ...[
              const SizedBox(height: 12),
              if (activeTrbTickets.isNotEmpty) ...[
                _buildSectionHeader(title: 'Tiket Aktif Saat Ini'),
                const SizedBox(height: 10),
                ...activeTrbTickets.map(
                  (ticket) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildActiveTrbTicketCard(
                      ticket: ticket,
                      onTap: () {
                        _pushAndRefresh(
                          context,
                          TiketTrbDetailScreen(ticketId: ticket.id),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (activePsbTickets.isNotEmpty) ...[
                _buildSectionHeader(title: 'Tiket Aktif Saat Ini'),
                const SizedBox(height: 10),
                ...activePsbTickets.map(
                  (ticket) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildActivePsbTicketCard(
                      ticket: ticket,
                      onTap: () {
                        _pushAndRefresh(
                          context,
                          TiketPsbDetailScreen(ticketId: ticket.id),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ] else ...[
              _buildSectionHeader(
                title: 'Tiket TRB Tersedia',
                onSeeAll: () {
                  _pushAndRefresh(
                    context,
                    const TiketTrbScreen(initialIndex: 0),
                  );
                },
              ),
              const SizedBox(height: 10),
              if (availableTrbTickets.isEmpty)
                _buildEmptyTicketCard('Tidak ada tiket TRB tersedia saat ini.')
              else
                _buildTicketSlider(
                  children: availableTrbTickets
                      .map(
                        (ticket) => _buildTrbTicketCard(
                          ticket: ticket,
                          label: 'Tersedia',
                          onTap: () {
                            _pushAndRefresh(
                              context,
                              TiketTrbDetailScreen(ticketId: ticket.id),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 20),
              _buildSectionHeader(
                title: 'Tiket PSB Tersedia',
                onSeeAll: () {
                  _pushAndRefresh(
                    context,
                    const TiketPsbScreen(initialIndex: 0),
                  );
                },
              ),
              const SizedBox(height: 10),
              if (availablePsbTickets.isEmpty)
                _buildEmptyTicketCard('Tidak ada tiket PSB tersedia saat ini.')
              else
                _buildTicketSlider(
                  children: availablePsbTickets
                      .map(
                        (ticket) => _buildPsbTicketCard(
                          ticket: ticket,
                          label: 'Tersedia',
                          onTap: () {
                            _pushAndRefresh(
                              context,
                              TiketPsbDetailScreen(ticketId: ticket.id),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required String title,
    required String count,
    required Color countColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text.rich(
        TextSpan(
          text: '$title ',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: countColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('Lihat lainnya')),
      ],
    );
  }

  Widget _buildTicketSlider({required List<Widget> children}) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }

  Widget _buildActiveTrbTicketCard({
    required Ticket ticket,
    required VoidCallback onTap,
  }) {
    final details = <MapEntry<String, String>>[
      MapEntry('Pelanggan', ticket.customerName ?? '-'),
      MapEntry('Status', ticket.statusLabel),
      MapEntry('Alamat', ticket.customerAddress ?? '-'),
      MapEntry(
        'Deskripsi',
        ticket.description.isEmpty ? '-' : ticket.description,
      ),
    ];

    if ((ticket.fieldStatusLabel ?? '').isNotEmpty) {
      details.insert(2, MapEntry('Status Lapangan', ticket.fieldStatusLabel!));
    }

    return _buildActiveTicketCard(
      accentColor: Colors.red,
      badgeColor: _getTrbStatusColor(ticket.status),
      ticketNumber: ticket.ticketNumber,
      title: ticket.subject,
      statusLabel: ticket.statusLabel,
      details: details,
      onTap: onTap,
    );
  }

  Widget _buildActivePsbTicketCard({
    required PsbTicket ticket,
    required VoidCallback onTap,
  }) {
    final details = <MapEntry<String, String>>[
      MapEntry('Pelanggan', ticket.customerName ?? '-'),
      MapEntry('Status', ticket.statusLabel),
      if ((ticket.scheduledDate ?? '').isNotEmpty ||
          (ticket.scheduledTime ?? '').isNotEmpty)
        MapEntry(
          'Jadwal',
          '${ticket.scheduledDate ?? '-'} ${ticket.scheduledTime ?? ''}'.trim(),
        ),
      MapEntry('Alamat', ticket.customerAddress ?? '-'),
      MapEntry(
        'Deskripsi',
        ticket.description.isEmpty
            ? (ticket.notes?.isNotEmpty == true ? ticket.notes! : '-')
            : ticket.description,
      ),
    ];

    if ((ticket.fieldStatusLabel ?? '').isNotEmpty) {
      details.insert(2, MapEntry('Status Lapangan', ticket.fieldStatusLabel!));
    }

    return _buildActiveTicketCard(
      accentColor: Colors.blue,
      badgeColor: _getPsbStatusColor(ticket.status),
      ticketNumber: ticket.ticketNumber,
      title: ticket.servicePackage ?? ticket.subject,
      statusLabel: ticket.statusLabel,
      details: details,
      onTap: onTap,
    );
  }

  Widget _buildActiveTicketCard({
    required Color accentColor,
    required Color badgeColor,
    required String ticketNumber,
    required String title,
    required String statusLabel,
    required List<MapEntry<String, String>> details,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ticketNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Aktif',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...details.map(
                (detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          detail.key,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Text(
                        ': ',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          detail.value,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Lihat detail',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: accentColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTicketCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildTrbTicketCard({
    required Ticket ticket,
    required String label,
    required VoidCallback onTap,
  }) {
    return _buildTicketPreviewCard(
      accentColor: Colors.red,
      badgeColor: _getTrbStatusColor(ticket.status),
      ticketNumber: ticket.ticketNumber,
      title: ticket.subject,
      subtitle: ticket.customerName ?? 'Pelanggan tidak tersedia',
      description: ticket.customerAddress ?? ticket.description,
      statusLabel: ticket.statusLabel,
      label: label,
      onTap: onTap,
    );
  }

  Widget _buildPsbTicketCard({
    required PsbTicket ticket,
    required String label,
    required VoidCallback onTap,
  }) {
    final customerName = (ticket.customerName ?? '').isNotEmpty
        ? ticket.customerName!
        : 'Pelanggan tidak tersedia';
    final servicePackage = (ticket.servicePackage ?? '').isNotEmpty
        ? ticket.servicePackage!
        : 'Paket tidak tersedia';

    final description = [
      if ((ticket.customerAddress ?? '').isNotEmpty) ticket.customerAddress!,
      if ((ticket.scheduledDate ?? '').isNotEmpty ||
          (ticket.scheduledTime ?? '').isNotEmpty)
        'Jadwal: ${ticket.scheduledDate ?? '-'} ${ticket.scheduledTime ?? ''}'
            .trim(),
    ].join(' • ');

    return _buildTicketPreviewCard(
      accentColor: Colors.blue,
      badgeColor: _getPsbStatusColor(ticket.status),
      ticketNumber: ticket.ticketNumber,
      title: customerName,
      subtitle: servicePackage,
      description: description.isEmpty ? ticket.description : description,
      statusLabel: ticket.statusLabel,
      label: label,
      onTap: onTap,
    );
  }

  Widget _buildTicketPreviewCard({
    required Color accentColor,
    required Color badgeColor,
    required String ticketNumber,
    required String title,
    required String subtitle,
    required String description,
    required String statusLabel,
    required String label,
    required VoidCallback onTap,
  }) {
    final labelColor = label.toLowerCase() == 'tersedia'
        ? AppColors.success
        : accentColor;

    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ticketNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: labelColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    description.isEmpty ? '-' : description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.grey.shade100,
      splashColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight lifecycle observer used by [_BerandaScreenState] to detect app resume.
class _BerandaLifecycleObserver extends WidgetsBindingObserver {
  _BerandaLifecycleObserver({required this.onResume});
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

/// Badge status kehadiran untuk welcome card.
class _AttendanceBadge extends StatelessWidget {
  const _AttendanceBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  static (String, Color) _resolve(String status) {
    switch (status.toLowerCase()) {
      case 'hadir':
        return ('Hadir', const Color(0xFF22C55E));
      case 'terlambat':
        return ('Terlambat', const Color(0xFFF59E0B));
      case 'izin':
        return ('Izin', const Color(0xFF60A5FA));
      case 'sakit':
        return ('Sakit', const Color(0xFFC084FC));
      case 'libur':
        return ('Libur', const Color(0xFF9CA3AF));
      case 'absent':
        return ('Tidak Hadir', const Color(0xFFFC8181));
      default:
        return (status, const Color(0xFF9CA3AF));
    }
  }
}
