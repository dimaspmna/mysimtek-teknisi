import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/ticket_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/ticket_service.dart';
import 'tiket_trb_detail_screen.dart';

class TiketTrbScreen extends StatefulWidget {
  final int initialIndex;

  const TiketTrbScreen({super.key, this.initialIndex = 0});

  @override
  State<TiketTrbScreen> createState() => _TiketTrbScreenState();
}

class _TiketTrbScreenState extends State<TiketTrbScreen>
    with SingleTickerProviderStateMixin {
  List<Ticket> _tickets = [];
  bool _isLoading = true;
  String? _errorMessage;
  final _searchController = TextEditingController();
  TabController? _tabController;

  static const _statusFilters = [
    ('available', 'Tersedia'),
    ('active', 'Aktif'),
    ('completed', 'Selesai'),
  ];

  static const _finishedStatuses = {'resolved', 'closed', 'done', 'completed'};
  static const _inactiveStatuses = {
    'resolved',
    'closed',
    'done',
    'completed',
    'cancelled',
  };

  TabController get _safeTabController {
    return _tabController ??= TabController(
      length: _statusFilters.length,
      initialIndex: widget.initialIndex,
      vsync: this,
    );
  }

  bool _isFinishedTicket(Ticket ticket) {
    final status = ticket.status.toLowerCase();
    if (_finishedStatuses.contains(status)) return true;

    final label = ticket.statusLabel.toLowerCase();
    return label.contains('selesai');
  }

  bool _isActiveTicket(Ticket ticket, int? userId) {
    if (userId == null || ticket.assignedTo != userId) return false;
    return !_inactiveStatuses.contains(ticket.status.toLowerCase());
  }

  List<Ticket> _ticketsByFilter(String filterStatus, int? userId) {
    switch (filterStatus) {
      case 'active':
        return _tickets
            .where((ticket) => _isActiveTicket(ticket, userId))
            .toList();
      case 'available':
        return _tickets.where((ticket) => ticket.isClaimable).toList();
      case 'completed':
        return _tickets
            .where(
              (ticket) =>
                  ticket.assignedTo == userId && _isFinishedTicket(ticket),
            )
            .toList();
      default:
        return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _fetchTickets();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = StorageService();
      final api = ApiService(storage);
      final ticketService = TicketService(api);

      final tickets = await ticketService.getTrbTickets(
        status: '',
        search: _searchController.text.trim(),
      );

      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return AppColors.success;
      case 'in_progress':
        return AppColors.info;
      case 'resolved':
      case 'closed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getFieldStatusColor(String? fs) {
    switch (fs) {
      case 'on_the_way':
        return AppColors.info;
      case 'working':
        return const Color(0xFF9C27B0);
      case 'fixed':
        return AppColors.success;
      case 'waiting_parts':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatTicketCreatedAt(DateTime createdAt) {
    final local = createdAt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    const monthNames = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final month = monthNames[local.month - 1];
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day $month $year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Tiket TRB',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _fetchTickets(),
              decoration: InputDecoration(
                hintText: 'Cari tiket, pelanggan...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _fetchTickets();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
          ),
          // Status tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: TabBar(
                controller: _safeTabController,
                isScrollable: false,
                labelPadding: EdgeInsets.zero,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorPadding: const EdgeInsets.all(3),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textPrimary,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                tabs: _statusFilters.map((f) => Tab(text: f.$2)).toList(),
              ),
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: TabBarView(
              controller: _safeTabController,
              children: _statusFilters
                  .map(
                    (f) => _buildTicketList(filterStatus: f.$1, userId: userId),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketList({
    required String filterStatus,
    required int? userId,
  }) {
    final visibleTickets = _ticketsByFilter(filterStatus, userId);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (visibleTickets.isEmpty) {
      return _buildEmpty(filterStatus);
    }

    return RefreshIndicator(
      onRefresh: _fetchTickets,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visibleTickets.length,
        itemBuilder: (context, index) {
          final ticket = visibleTickets[index];
          return _buildTicketCard(ticket);
        },
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchTickets,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String filterStatus) {
    String title;
    String subtitle;

    switch (filterStatus) {
      case 'active':
        title = 'Tidak ada tiket aktif';
        subtitle = 'Tiket yang Anda ambil atau ditugaskan akan muncul di sini.';
        break;
      case 'available':
        title = 'Tidak ada tiket tersedia';
        subtitle =
            'Tiket status terbuka yang belum diambil akan muncul di sini.';
        break;
      case 'completed':
        title = 'Tidak ada tiket selesai';
        subtitle =
            'Riwayat tiket yang sudah Anda selesaikan akan muncul di sini.';
        break;
      default:
        title = 'Tidak ada tiket TRB';
        subtitle = 'Tiket akan muncul di sini.';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: AppColors.textSecondary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(Ticket ticket) {
    final statusColor = _getStatusColor(ticket.status);
    final isResolved = _isFinishedTicket(ticket);
    final isClaimable = ticket.isClaimable;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TiketTrbDetailScreen(ticketId: ticket.id),
          ),
        );
        _fetchTickets();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ticket.ticketNumber,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (ticket.ticketType == 'general'
                                  ? AppColors.info
                                  : AppColors.success)
                              .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ticket.ticketTypeLabel ?? 'TRB Pelanggan',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: ticket.ticketType == 'general'
                            ? AppColors.info
                            : AppColors.success,
                      ),
                    ),
                  ),
                  if (isClaimable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'TERSEDIA',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isResolved
                          ? AppColors.success
                          : statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      ticket.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isResolved ? Colors.white : statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Subject
              Text(
                ticket.subject,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Dibuat: ${_formatTicketCreatedAt(ticket.createdAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Customer & field status
              Row(
                children: [
                  if (ticket.customerName != null) ...[
                    const Icon(
                      Icons.person_outline,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ticket.customerName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    const Icon(
                      Icons.build_circle_outlined,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Lokasi perbaikan umum',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (ticket.fieldStatus != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getFieldStatusColor(
                          ticket.fieldStatus,
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ticket.fieldStatusLabel ?? ticket.fieldStatus!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getFieldStatusColor(ticket.fieldStatus),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Claim arrow hint
              if (isClaimable)
                const Text(
                  'Klik untuk melihat detail & mengambil tiket ini →',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
