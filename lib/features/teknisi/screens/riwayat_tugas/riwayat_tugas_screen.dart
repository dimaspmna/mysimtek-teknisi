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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $value',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrbTicketCard(Ticket ticket) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.ticketNumber,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.subject,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.customerName ?? '-',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTimeRow(
                      icon: Icons.login,
                      label: 'Diambil',
                      value: _formatDateTime(ticket.technicianDispatchedAt),
                    ),
                    const SizedBox(height: 4),
                    _buildTimeRow(
                      icon: Icons.check_circle_outline,
                      label: 'Selesai',
                      value: _formatDateTime(ticket.resolvedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    'TRB',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPsbTicketCard(PsbTicket ticket) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TiketPsbDetailScreen(ticketId: ticket.id),
            ),
          );
          _fetchTickets();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.ticketNumber,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.servicePackage ?? ticket.subject,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.customerName ?? '-',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTimeRow(
                      icon: Icons.login,
                      label: 'Diambil',
                      value: _formatDateTime(ticket.technicianDispatchedAt),
                    ),
                    const SizedBox(height: 4),
                    _buildTimeRow(
                      icon: Icons.check_circle_outline,
                      label: 'Selesai',
                      value: _formatDateTime(ticket.resolvedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    'PSB',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
