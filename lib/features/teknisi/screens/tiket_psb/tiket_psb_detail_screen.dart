import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/ticket_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/ticket_service.dart';

class TiketPsbDetailScreen extends StatefulWidget {
  final int ticketId;

  const TiketPsbDetailScreen({super.key, required this.ticketId});

  @override
  State<TiketPsbDetailScreen> createState() => _TiketPsbDetailScreenState();
}

class _TiketPsbDetailScreenState extends State<TiketPsbDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TicketService _ticketService;

  PsbTicket? _ticket;
  bool _isLoading = true;
  bool _isActing = false;
  String? _errorMessage;

  String _selectedFieldStatus = 'working';
  final _notesController = TextEditingController();
  final _captionController = TextEditingController();
  File? _selectedPhoto;

  final _scrollController = ScrollController();

  static const _fieldStatusOptions = [
    ('preparing', 'Sedang Persiapan'),
    ('on_the_way', 'Menuju Lokasi'),
    ('working', 'Sedang Dikerjakan'),
    ('fixed', 'SELESAI'),
    ('waiting_parts', 'Menunggu Alat'),
    ('other', 'Lainnya'),
  ];

  String _normalizeFieldStatus(String? status) {
    if (status == null || status.isEmpty) return 'working';
    if (status == 'pending') return 'preparing';
    final available = _fieldStatusOptions.map((opt) => opt.$1).toSet();
    if (available.contains(status)) return status;
    return 'other';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final storage = StorageService();
    _ticketService = TicketService(ApiService(storage));
    _fetchTicket();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    _captionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTicket() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ticket = await _ticketService.getPsbTicketDetail(widget.ticketId);
      setState(() {
        _ticket = ticket;
        _isLoading = false;
        _selectedFieldStatus = _normalizeFieldStatus(ticket.fieldStatus);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _claimTicket() async {
    setState(() => _isActing = true);
    try {
      final updated = await _ticketService.claimPsbTicket(widget.ticketId);
      setState(() {
        _ticket = updated;
        _isActing = false;
      });
      _showSnack(
        'Tiket berhasil diambil. Silakan mulai pekerjaan.',
        isError: false,
      );
    } catch (e) {
      setState(() => _isActing = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _confirmClaimTicket() async {
    if (_isActing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Konfirmasi'),
          content: const Text('Apakah anda yakin mengambil tiket ini?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya, Ambil'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _claimTicket();
    }
  }

  bool _canStartPsb(PsbTicket t) {
    if (t.assignedTo == null) return false;
    const waitingStatuses = {'pending', 'scheduled'};
    return waitingStatuses.contains(t.status);
  }

  Future<void> _startPsb() async {
    setState(() => _isActing = true);
    try {
      final updated = await _ticketService.startPsb(widget.ticketId);
      setState(() {
        _ticket = updated;
        _isActing = false;
      });
      _showSnack('Pekerjaan PSB dimulai.', isError: false);
    } catch (e) {
      setState(() => _isActing = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _submitFieldReport() async {
    final fieldNotes = _notesController.text.trim();
    final caption = _captionController.text.trim();

    if (fieldNotes.length < 10) {
      _showSnack('Laporan minimal 10 karakter.');
      return;
    }
    if (_selectedPhoto == null) {
      _showSnack('Foto bukti wajib dipilih.');
      return;
    }
    if (caption.length > 200) {
      _showSnack('Keterangan foto maksimal 200 karakter.');
      return;
    }

    setState(() => _isActing = true);
    try {
      await _ticketService.sendPsbFieldReport(
        ticketId: widget.ticketId,
        fieldStatus: _selectedFieldStatus,
        fieldNotes: fieldNotes,
        photo: _selectedPhoto!,
        photoType: 'installation',
        caption: caption,
      );
      _notesController.clear();
      _captionController.clear();
      setState(() {
        _selectedPhoto = null;
        _isActing = false;
      });
      _showSnack('Laporan dan foto berhasil disimpan.', isError: false);
      _fetchTicket();
    } catch (e) {
      setState(() => _isActing = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (picked != null) {
      setState(() => _selectedPhoto = File(picked.path));
    }
  }

  Future<void> _pickPhotoFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (picked != null) {
      setState(() => _selectedPhoto = File(picked.path));
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showPhotoPreview(String imageUrl) {
    if (imageUrl.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Foto tidak dapat dimuat',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
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

  Color _fieldStatusColor(String? fs) {
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

  Color _senderLabelColor(TicketMessage msg) {
    final role = msg.senderRole.toLowerCase();
    final name = (msg.userName ?? '').toLowerCase();

    if (role == 'customer' || name.contains('customer')) {
      return const Color(0xFF2E7D32);
    }
    if (role == 'noc' || name.contains('noc')) {
      return const Color(0xFF1565C0);
    }
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _ticket?.ticketNumber ?? 'Detail Tiket PSB',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _fetchTicket,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Info'),
            Tab(
              icon: const Icon(Icons.assignment_outlined, size: 18),
              text: _ticket != null
                  ? 'Laporan (${_ticket!.photos.length})'
                  : 'Laporan',
            ),
            const Tab(
              icon: Icon(Icons.chat_outlined, size: 18),
              text: 'Thread',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(),
                _buildLaporanTab(),
                _buildThreadTab(),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchTicket,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final t = _ticket!;
    return RefreshIndicator(
      onRefresh: _fetchTicket,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (t.isClaimable) _buildClaimBanner(),
          if (_canStartPsb(t)) _buildStartBanner(),
          _buildCustomerCard(t),
          const SizedBox(height: 12),
          _buildStatusCard(t),
          const SizedBox(height: 12),
          _buildDescriptionCard(t),
          const SizedBox(height: 12),
          if ((t.notes ?? '').isNotEmpty) _buildFieldNotesCard(t),
          if ((t.notes ?? '').isNotEmpty) const SizedBox(height: 12),
          _buildTimelineCard(t),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildClaimBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD580)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  size: 20,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tiket Belum Ditugaskan',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7A4F00),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tiket ini tersedia dan belum diambil siapapun.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9D6700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isActing ? null : _confirmClaimTicket,
              icon: _isActing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: const Text('Ambil Tiket Ini'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiket Siap Dikerjakan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Mulai pekerjaan sekarang agar status tiket berpindah ke sedang dikerjakan.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isActing ? null : _startPsb,
              icon: _isActing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Mulai Pekerjaan PSB'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(PsbTicket t) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.customerName ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (t.customerPhone != null)
                        Text(
                          t.customerPhone!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (t.customerAddress != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.home_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.customerAddress!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(PsbTicket t) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _statusRow('Status Tiket', t.statusLabel, _statusColor(t.status)),
          if (t.fieldStatusLabel != null) ...[
            const Divider(height: 16),
            _statusRow(
              'Status Lapangan',
              t.fieldStatusLabel!,
              _fieldStatusColor(t.fieldStatus),
            ),
          ],
          if (t.servicePackage != null) ...[
            const Divider(height: 16),
            _infoRow('Paket Layanan', t.servicePackage!),
          ],
          if (t.scheduledDate != null || t.scheduledTime != null) ...[
            const Divider(height: 16),
            _infoRow(
              'Jadwal',
              '${t.scheduledDate ?? '-'} ${t.scheduledTime ?? ''}'.trim(),
            ),
          ],
          if (t.assignerName != null) ...[
            const Divider(height: 16),
            _infoRow('Ditugaskan oleh', t.assignerName!),
          ],
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionCard(PsbTicket t) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pekerjaan / Catatan',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.subject,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (t.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              t.description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldNotesCard(PsbTicket t) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFF176)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Catatan Lapangan Terakhir',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF827717),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.notes!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF5D4037),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(PsbTicket t) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeline',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _timelineItem('Dibuat', t.createdAt, Colors.grey),
          if (t.technicianDispatchedAt != null)
            _timelineItem(
              'Ditugaskan',
              t.technicianDispatchedAt!,
              AppColors.warning,
            ),
          if (t.resolvedAt != null)
            _timelineItem(
              'Diselesaikan',
              t.resolvedAt!,
              AppColors.success,
              isLast: true,
            ),
        ],
      ),
    );
  }

  Widget _timelineItem(
    String label,
    DateTime dt,
    Color color, {
    bool isLast = false,
  }) {
    final fmt = DateFormat('dd MMM yyyy, HH:mm', 'id');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            if (!isLast)
              Container(width: 1.5, height: 24, color: AppColors.divider),
          ],
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                fmt.format(dt.toLocal()),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLaporanTab() {
    final t = _ticket!;
    final canReport = t.assignedTo != null && !t.isFinished;

    return RefreshIndicator(
      onRefresh: _fetchTicket,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!canReport)
            _buildInfoBanner(
              t.isClaimable
                  ? 'Ambil tiket terlebih dahulu di tab Info untuk bisa mengirim laporan.'
                  : 'Tiket ini sudah diselesaikan.',
              t.isClaimable ? AppColors.warning : AppColors.success,
            ),
          if (canReport) ...[
            _buildFieldReportForm(),
            const SizedBox(height: 16),
          ],
          if (t.photos.isNotEmpty) ...[
            const Text(
              'Foto Dokumentasi',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ...t.photos.map(_buildPhotoCard),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String msg, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldReportForm() {
    final showFixedWarning = _selectedFieldStatus == 'fixed';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kirim Laporan Lapangan',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Status Lapangan *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedFieldStatus,
            items: _fieldStatusOptions
                .map(
                  (opt) => DropdownMenuItem(
                    value: opt.$1,
                    child: Text(opt.$2, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedFieldStatus = v!),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (showFixedWarning) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Dengan mengubah status ini menjadi Selesai, tiket akan ditandai selesai.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            'Keterangan Lapangan *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Jelaskan progres instalasi, tindakan yang diambil...',
              hintStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Foto Bukti *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (_selectedPhoto != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _selectedPhoto!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPhoto = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Kamera', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPhotoFromGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Galeri', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _captionController,
            decoration: InputDecoration(
              hintText: 'Keterangan Foto (opsional)',
              hintStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isActing ? null : _submitFieldReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: _isActing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Kirim Laporan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(TicketPhoto photo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo.photoUrl.isNotEmpty)
            GestureDetector(
              onTap: () => _showPhotoPreview(photo.photoUrl),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    Image.network(
                      photo.photoUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 100,
                        color: AppColors.background,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.open_in_full,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                if (photo.photoType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      photo.photoType!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  DateFormat(
                    'dd MMM, HH:mm',
                    'id',
                  ).format(photo.createdAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (photo.caption != null && photo.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                photo.caption!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadTab() {
    final t = _ticket!;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchTicket,
            child: t.messages.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 140),
                      Center(
                        child: Text(
                          'Belum ada pesan.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: t.messages.length,
                    itemBuilder: (_, i) => _buildMessageBubble(t.messages[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(TicketMessage msg) {
    final isSystem = msg.type == 'system' || msg.type == 'field_report';
    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Text(
                msg.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat(
                  'dd MMM, HH:mm',
                  'id',
                ).format(msg.createdAt.toLocal()),
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isMine = msg.senderRole == 'teknisi';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMine ? 14 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 14),
                ),
                border: isMine ? null : Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMine && msg.userName != null) ...[
                    Text(
                      msg.userName!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _senderLabelColor(msg),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    msg.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: isMine ? Colors.white : AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm', 'id').format(msg.createdAt.toLocal()),
                    style: TextStyle(
                      fontSize: 9,
                      color: isMine
                          ? Colors.white.withOpacity(0.75)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
