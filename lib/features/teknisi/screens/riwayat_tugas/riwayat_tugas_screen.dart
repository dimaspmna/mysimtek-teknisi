import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/ticket_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/ticket_service.dart';
import '../tiket_psb/tiket_psb_detail_screen.dart';
import '../tiket_trb/tiket_trb_detail_screen.dart';

class RiwayatTugasScreen extends StatefulWidget {
  const RiwayatTugasScreen({super.key});

  @override
  State<RiwayatTugasScreen> createState() => _RiwayatTugasScreenState();
}

class _RiwayatTugasScreenState extends State<RiwayatTugasScreen> {
  List<Ticket> _trbTickets = [];
  List<PsbTicket> _psbTickets = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const _trbFinishedStatuses = {
    'done',
    'resolved',
    'closed',
    'completed',
  };

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  bool _isTrbFinished(Ticket ticket) {
    final status = ticket.status.toLowerCase();
    if (_trbFinishedStatuses.contains(status)) return true;
    return ticket.statusLabel.toLowerCase().contains('selesai');
  }

  List<Ticket> _trbCompletedByUser(List<Ticket> tickets, int? userId) {
    if (userId == null) return [];
    return tickets
        .where(
          (ticket) => ticket.assignedTo == userId && _isTrbFinished(ticket),
        )
        .toList();
  }

  List<PsbTicket> _psbCompletedByUser(List<PsbTicket> tickets, int? userId) {
    if (userId == null) return [];
    return tickets
        .where((ticket) => ticket.assignedTo == userId && ticket.isFinished)
        .toList();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = context.read<AuthProvider>().user?.id;
      final storage = StorageService();
      final api = ApiService(storage);
      final ticketService = TicketService(api);

      final results = await Future.wait([
        ticketService.getTrbTickets(),
        ticketService.getPsbTickets(),
      ]);

      setState(() {
        final trbTickets = results[0] as List<Ticket>;
        final psbTickets = results[1] as List<PsbTicket>;

        _trbTickets = _trbCompletedByUser(trbTickets, userId)
          ..sort((a, b) {
            final aTime =
                a.resolvedAt ?? a.technicianDispatchedAt ?? a.createdAt;
            final bTime =
                b.resolvedAt ?? b.technicianDispatchedAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
        _psbTickets = _psbCompletedByUser(psbTickets, userId)
          ..sort((a, b) {
            final aTime =
                a.resolvedAt ?? a.technicianDispatchedAt ?? a.createdAt;
            final bTime =
                b.resolvedAt ?? b.technicianDispatchedAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trbCount = _trbTickets.length;
    final psbCount = _psbTickets.length;
    final totalTickets = trbCount + psbCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Riwayat Tugas',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gagal memuat data',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
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
            )
          : RefreshIndicator(
              onRefresh: _fetchTickets,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Tiket TRB Selesai',
                          value: trbCount,
                          color: AppColors.error,
                          icon: Icons.build_circle_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Tiket PSB Selesai',
                          value: psbCount,
                          color: AppColors.info,
                          icon: Icons.wifi_tethering_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_trbTickets.isNotEmpty) ...[
                    Text(
                      'TRB (${_trbTickets.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._trbTickets.map((ticket) => _buildTrbTicketCard(ticket)),
                    const SizedBox(height: 16),
                  ],

                  if (_psbTickets.isNotEmpty) ...[
                    Text(
                      'PSB (${_psbTickets.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._psbTickets.map((ticket) => _buildPsbTicketCard(ticket)),
                  ],

                  if (totalTickets == 0) ...[
                    const SizedBox(height: 96),
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 56,
                            color: AppColors.textSecondary.withOpacity(0.4),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada riwayat tugas selesai',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'id').format(dt.toLocal());
  }

  Widget _buildStatCard({
    required String title,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrbTicketCard(Ticket ticket) {
    return _TicketCard(
      type: 'TRB',
      typeColor: AppColors.error,
      ticketNumber: ticket.ticketNumber,
      title: ticket.subject,
      customerName: ticket.customerName,
      dispatchedAt: ticket.technicianDispatchedAt,
      resolvedAt: ticket.resolvedAt,
      formatDateTime: _formatDateTime,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TiketTrbDetailScreen(ticketId: ticket.id),
          ),
        );
        _fetchTickets();
      },
    );
  }

  Widget _buildPsbTicketCard(PsbTicket ticket) {
    return _TicketCard(
      type: 'PSB',
      typeColor: AppColors.info,
      ticketNumber: ticket.ticketNumber,
      title: ticket.servicePackage ?? ticket.subject,
      customerName: ticket.customerName,
      dispatchedAt: ticket.technicianDispatchedAt,
      resolvedAt: ticket.resolvedAt,
      formatDateTime: _formatDateTime,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TiketPsbDetailScreen(ticketId: ticket.id),
          ),
        );
        _fetchTickets();
      },
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.type,
    required this.typeColor,
    required this.ticketNumber,
    required this.title,
    required this.customerName,
    required this.dispatchedAt,
    required this.resolvedAt,
    required this.formatDateTime,
    required this.onTap,
  });

  final String type;
  final Color typeColor;
  final String ticketNumber;
  final String title;
  final String? customerName;
  final DateTime? dispatchedAt;
  final DateTime? resolvedAt;
  final String Function(DateTime?) formatDateTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: ticket number + type badge
                Row(
                  children: [
                    Text(
                      ticketNumber,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: typeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (customerName != null && customerName!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        customerName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                // Divider
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.cardBorder,
                ),
                const SizedBox(height: 10),
                // Time rows
                Row(
                  children: [
                    Expanded(
                      child: _timeInfo(
                        label: 'Diambil',
                        value: formatDateTime(dispatchedAt),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: AppColors.cardBorder,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    Expanded(
                      child: _timeInfo(
                        label: 'Selesai',
                        value: formatDateTime(resolvedAt),
                        valueColor: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
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

  Widget _timeInfo({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
