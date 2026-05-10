import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/gps_tracking_provider.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/ticket_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/debug_event_logger.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/ticket_service.dart';
import '../../../../core/services/location_streaming_service.dart';
import '../../../../core/widgets/gps_permission_modal.dart';
import '../../../../core/widgets/tracking_status_card.dart';

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
  bool _hasActiveTicket = false;
  String? _activeTicketNumber;
  List<TechnicianAssignment> _technicianOptions = const [];
  Set<int> _selectedSupportIds = <int>{};
  bool _isLoadingTechnicianOptions = false;
  bool _isSavingSupportMembers = false;
  bool _showSupportMembersForm = false;

  String _selectedFieldStatus = 'working';
  final _notesController = TextEditingController();
  final _captionController = TextEditingController();
  File? _selectedPhoto;

  // GPS Tracking
  bool _isStartingTracking = false;
  double _startSliderValue = 0;

  final _scrollController = ScrollController();

  static const _fieldStatusOptions = [
    ('preparing', 'Sedang Persiapan'),
    ('on_the_way', 'Menuju Lokasi Pemasangan'),
    ('working', 'Sedang Dikerjakan'),
    ('done', 'Pemasangan Selesai'),
    ('waiting_parts', 'Menunggu Alat'),
    ('other', 'Lainnya'),
  ];

  String _normalizeFieldStatus(String? status) {
    if (status == null || status.isEmpty) return 'working';
    if (status == 'pending') return 'preparing';
    if (status == 'fixed') return 'done'; // legacy mapping
    final available = _fieldStatusOptions.map((opt) => opt.$1).toSet();
    if (available.contains(status)) return status;
    return 'other';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      await _checkActiveTickets();
      _syncSupportSelectionFromTicket(ticket);
      setState(() {
        _ticket = ticket;
        _isLoading = false;
        _selectedFieldStatus = _normalizeFieldStatus(ticket.fieldStatus);
      });
      if (ticket.isPic) {
        await _loadTechnicianOptions(ticket: ticket);
      }
      _ensureGpsRunning(ticket);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _syncSupportSelectionFromTicket(PsbTicket ticket) {
    _selectedSupportIds = ticket.supportTechnicians.map((m) => m.id).toSet();
  }

  Future<void> _loadTechnicianOptions({PsbTicket? ticket}) async {
    if (_isLoadingTechnicianOptions) return;
    final targetTicket = ticket ?? _ticket;
    if (targetTicket == null || !targetTicket.isPic) return;

    setState(() => _isLoadingTechnicianOptions = true);
    try {
      final technicians = await _ticketService.getTechnicianOptions();
      if (!mounted) return;

      final filtered = technicians
          .where((tech) => tech.id != (targetTicket.assignedTo ?? -1))
          .toList();

      setState(() {
        _technicianOptions = filtered;
        _isLoadingTechnicianOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingTechnicianOptions = false);
    }
  }

  Future<void> _checkActiveTickets() async {
    try {
      final storage = StorageService();
      final api = ApiService(storage);
      final ticketService = TicketService(api);

      // Get all TRB and PSB tickets
      final trbTickets = await ticketService.getTrbTickets();
      final psbTickets = await ticketService.getPsbTickets();

      // Get user ID from auth
      final user = context.read<AuthProvider>().user;
      final userId = user?.id;

      if (userId == null) return;

      // Check for active TRB tickets
      final activeTrb = trbTickets.where((t) {
        if (t.assignedTo != userId) return false;
        final status = t.status.toLowerCase();
        return !const {
          'resolved',
          'closed',
          'done',
          'completed',
          'cancelled',
        }.contains(status);
      }).toList();

      // Check for active PSB tickets
      final activePsb = psbTickets.where((t) {
        if (t.id == widget.ticketId) return false; // Skip current ticket
        if (t.assignedTo != userId) return false;
        return !t.isFinished && t.status.toLowerCase() != 'cancelled';
      }).toList();

      if (activeTrb.isNotEmpty) {
        setState(() {
          _hasActiveTicket = true;
          _activeTicketNumber = activeTrb.first.ticketNumber;
        });
      } else if (activePsb.isNotEmpty) {
        setState(() {
          _hasActiveTicket = true;
          _activeTicketNumber = activePsb.first.ticketNumber;
        });
      } else {
        setState(() {
          _hasActiveTicket = false;
          _activeTicketNumber = null;
        });
      }
    } catch (e) {
      // Silently fail - don't block the main flow
    }
  }

  /// Auto-start GPS tracking if ticket is in_progress, permission granted, and not already tracking.
  Future<void> _ensureGpsRunning(PsbTicket ticket) async {
    final isActive =
        ticket.isPic &&
        ticket.assignedTo != null &&
        ticket.fieldStatus != null &&
        ticket.fieldStatus != 'pending' &&
        ticket.fieldStatus != 'done' &&
        !ticket.isFinished;
    if (!isActive) return;

    final gps = context.read<GpsTrackingProvider>();
    final expectedEndpoint = ApiConstants.teknisiPsbTicketLocation(
      widget.ticketId,
    );
    if (gps.isRunning &&
        gps.activeTicketId == widget.ticketId &&
        gps.activeEndpoint == expectedEndpoint)
      return;

    // Only auto-start if permission is already granted — don't prompt silently
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse)
      return;

    await gps.startTrackingSafely(
      widget.ticketId,
      endpoint: ApiConstants.teknisiPsbTicketLocation(widget.ticketId),
      retries: 1,
    );
  }

  Future<bool> _canUseGps({bool requestIfNeeded = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (requestIfNeeded && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
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

    // Check if user already has active ticket
    if (_hasActiveTicket) {
      _showSnack(
        'Anda sudah memiliki tiket aktif ($_activeTicketNumber). Selesaikan tiket tersebut terlebih dahulu.',
      );
      return;
    }

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

  Future<void> _joinTicket() async {
    setState(() => _isActing = true);
    try {
      final updated = await _ticketService.joinPsbTicket(widget.ticketId);
      setState(() {
        _ticket = updated;
        _isActing = false;
      });
      _showSnack('Berhasil bergabung sebagai teknisi anggota.', isError: false);
      _fetchTicket();
    } catch (e) {
      setState(() => _isActing = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _saveSupportMembers() async {
    final ticket = _ticket;
    if (ticket == null || !ticket.isPic || _isSavingSupportMembers) return;

    setState(() => _isSavingSupportMembers = true);
    try {
      final selected = _selectedSupportIds.toList()..sort();
      final updated = await _ticketService.updatePsbSupportMembers(
        ticketId: widget.ticketId,
        supportTechnicianIds: selected,
      );

      if (!mounted) return;
      _syncSupportSelectionFromTicket(updated);
      setState(() {
        _ticket = updated;
        _isSavingSupportMembers = false;
      });
      _showSnack('Daftar teknisi anggota berhasil diperbarui.', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingSupportMembers = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _confirmJoinTicket() async {
    if (_isActing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Tiket'),
        content: const Text(
          'Gabung sebagai teknisi anggota? Anda hanya bisa memantau dan berdiskusi, update progres tetap oleh teknisi penanggungjawab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Gabung'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _joinTicket();
    }
  }

  /// Manual GPS refresh — requests permission via modal then (re)starts tracking.
  Future<void> _refreshGps() async {
    if (!(_ticket?.isPic ?? false)) {
      _showSnack('GPS tracking hanya tersedia untuk teknisi penanggungjawab.');
      return;
    }

    if (!mounted) return;
    await showGpsPermissionModal(context);

    final canStartTracking = await _canUseGps(requestIfNeeded: true);

    if (!canStartTracking) {
      _showSnack('Izin lokasi diperlukan untuk tracking GPS.');
      return;
    }

    if (!mounted) return;
    final gps = context.read<GpsTrackingProvider>();
    final gpsRunning = await gps.startTrackingSafely(
      widget.ticketId,
      endpoint: ApiConstants.teknisiPsbTicketLocation(widget.ticketId),
      retries: 2,
    );

    if (!gpsRunning) {
      _showSnack('GPS belum aktif. Periksa izin lokasi dan baterai perangkat.');
      return;
    }

    _showSnack('GPS berhasil diaktifkan ulang.', isError: false);
  }

  Future<void> _startPsbWithTracking() async {
    if (!(_ticket?.isPic ?? false)) {
      _showSnack(
        'Mulai pekerjaan dengan GPS hanya untuk teknisi penanggungjawab.',
      );
      return;
    }

    if (_isStartingTracking) return;
    setState(() => _isStartingTracking = true);

    DebugEventLogger.log(
      'psb_ticket_start_requested',
      scope: 'ticket_start',
      data: {'ticket_id': widget.ticketId},
    );

    Position? initialPos;
    if (mounted) {
      initialPos = await showGpsPermissionModal(context);
    }

    final canStartTracking = await _canUseGps(requestIfNeeded: true);
    DebugEventLogger.log(
      'psb_gps_permission_checked',
      scope: 'ticket_start',
      data: {
        'ticket_id': widget.ticketId,
        'can_start_tracking': canStartTracking,
        'has_initial_pos': initialPos != null,
      },
    );

    try {
      final storage = StorageService();
      final api = ApiService(storage);

      final body = <String, dynamic>{'gps_enabled': canStartTracking};
      if (initialPos != null) {
        body['latitude'] = initialPos.latitude;
        body['longitude'] = initialPos.longitude;
        body['accuracy'] = initialPos.accuracy;
      }

      await api.post(ApiConstants.teknisiPsbTicketStart(widget.ticketId), body);
      DebugEventLogger.log(
        'psb_ticket_start_api_success',
        scope: 'ticket_start',
        data: {
          'ticket_id': widget.ticketId,
          'gps_enabled': canStartTracking,
          'has_initial_pos': initialPos != null,
        },
      );

      // Refresh full ticket after start
      final updatedTicket = await _ticketService.getPsbTicketDetail(
        widget.ticketId,
      );
      setState(() {
        _ticket = updatedTicket;
        _isStartingTracking = false;
        _startSliderValue = 0;
      });

      var gpsRunning = false;
      if (canStartTracking) {
        final gps = context.read<GpsTrackingProvider>();
        gpsRunning = await gps.startTrackingSafely(
          widget.ticketId,
          endpoint: ApiConstants.teknisiPsbTicketLocation(widget.ticketId),
          retries: 1,
        );
        DebugEventLogger.log(
          'psb_gps_start_result',
          scope: 'ticket_start',
          data: {
            'ticket_id': widget.ticketId,
            'success': gpsRunning,
            'gps_status': gps.status.name,
            'retry_count': gps.retryCount,
          },
        );
      }

      final startMessage = !canStartTracking
          ? 'Pekerjaan PSB dimulai tanpa GPS. Aktifkan izin lokasi lalu tekan refresh GPS.'
          : gpsRunning
          ? (initialPos != null
                ? 'Pekerjaan PSB dimulai! GPS tracking aktif.'
                : 'Pekerjaan PSB dimulai! GPS aktif, menunggu titik lokasi awal.')
          : 'Pekerjaan PSB dimulai, tetapi tracking GPS belum aktif. Tekan refresh GPS.';

      _showSnack(startMessage, isError: !canStartTracking);

      _fetchTicket();
    } catch (e, st) {
      DebugEventLogger.log(
        'psb_ticket_start_failed',
        scope: 'ticket_start',
        data: {
          'ticket_id': widget.ticketId,
          'error': e.toString(),
          'stack': st.toString(),
        },
      );
      setState(() {
        _isStartingTracking = false;
        _startSliderValue = 0;
      });
      _showSnack(e.toString());
    }
  }

  void _onStartSliderChanged(double value) {
    if (_isStartingTracking) return;
    setState(() => _startSliderValue = value);
  }

  Future<void> _onStartSliderReleased(double value) async {
    if (_isStartingTracking) return;
    if (value >= 0.95) {
      await _startPsbWithTracking();
    }
    if (!mounted) return;
    setState(() => _startSliderValue = 0);
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
        photoType: 'progress',
        caption: caption,
      );
      _notesController.clear();
      _captionController.clear();
      setState(() {
        _selectedPhoto = null;
        _isActing = false;
      });
      _showSnack('Laporan dan foto berhasil disimpan.', isError: false);

      // Auto-stop GPS and show dialog when work is marked as done
      if (_selectedFieldStatus == 'done') {
        if (mounted) context.read<GpsTrackingProvider>().stopTracking();
        if (mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pekerjaan Selesai!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'GPS tracking telah dinonaktifkan secara otomatis. Terima kasih.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          );
        }
      }

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

  Future<void> _openInGoogleMaps({
    required double lat,
    required double lng,
    required String label,
  }) async {
    final encodedLabel = Uri.encodeComponent(label);
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedLabel)');
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      final openedGeo = await launchUrl(
        geoUri,
        mode: LaunchMode.externalApplication,
      );
      if (openedGeo) return;

      final openedWeb = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (openedWeb) return;
    } catch (_) {
      // Fallback handled below with snackbar.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Maps tidak dapat dibuka di perangkat ini.'),
      ),
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
      case 'done':
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
      case 'done':
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
            const Tab(
              icon: Icon(Icons.assignment_outlined, size: 18),
              text: 'Laporan',
            ),
            Tab(
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              text: _ticket != null
                  ? 'Bukti (${_ticket!.photos.length})'
                  : 'Bukti',
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
                _buildBuktiFotoTab(),
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
          if (t.canJoin) _buildJoinBanner(),
          if (!t.isClaimable &&
              t.isPic &&
              (t.fieldStatus == null || t.fieldStatus == 'pending'))
            _buildStartBanner(),
          // GPS Tracking status card
          if (t.isPic &&
              t.fieldStatus != null &&
              t.fieldStatus != 'pending' &&
              t.fieldStatus != 'done' &&
              !t.isFinished) ...[
            const SizedBox(height: 8),
            Consumer<GpsTrackingProvider>(
              builder: (_, gps, __) {
                final expectedEndpoint = ApiConstants.teknisiPsbTicketLocation(
                  widget.ticketId,
                );
                final isActive =
                    gps.isRunning &&
                    gps.activeTicketId == widget.ticketId &&
                    gps.activeEndpoint == expectedEndpoint;
                return TrackingStatusCard(
                  status: isActive ? gps.status : TrackingStatus.idle,
                  lastPush: gps.activeTicketId == widget.ticketId
                      ? gps.lastPush
                      : null,
                  retryCount: gps.activeTicketId == widget.ticketId
                      ? gps.retryCount
                      : 0,
                  onRestart: _refreshGps,
                );
              },
            ),
          ],
          if (t.isPic) _buildProgressTracking(t),
          if (t.isPic) const SizedBox(height: 12),
          _buildCustomerCard(t),
          const SizedBox(height: 12),
          _buildTeamMembersCard(t),
          if (t.isPic) const SizedBox(height: 12),
          if (t.isPic) _buildSupportMembersEditorCard(t),
          if (t.isSupport) const SizedBox(height: 12),
          if (t.isSupport) _buildPicTechnicianInfoCard(t),
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

  Widget _buildPicTechnicianInfoCard(PsbTicket t) {
    final picName = t.picTechnician?.name ?? 'Belum ditetapkan';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.badge_outlined, size: 18, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teknisi Penanggungjawab',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  picName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Akun anggota tidak mengaktifkan GPS tracking.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimBanner() {
    if (_hasActiveTicket) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.block_outlined,
                color: Colors.red.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tiket Aktif Terdeteksi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Anda sudah memiliki tiket aktif ($_activeTicketNumber). Selesaikan tiket tersebut terlebih dahulu sebelum mengambil tiket baru.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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

  Widget _buildJoinBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiket Sudah Ada Penanggungjawab',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Anda bisa bergabung sebagai teknisi anggota untuk support. Hak update progres, GPS, dan laporan tetap di teknisi penanggungjawab.',
            style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isActing ? null : _confirmJoinTicket,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Gabung Tiket'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Button StartJobTicketing
  Widget _buildStartBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC)),
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
                  color: AppColors.success.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_circle_outline,
                  size: 20,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Siap Memulai Pekerjaan?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF14532D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Geser tombol di bawah untuk memulai GPS.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isStartingTracking
                      ? 'Memulai pekerjaan...'
                      : 'Geser tombol ke kanan untuk mulai',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const handleWidth = 68.0;
                      const handleHeight = 44.0;
                      final maxLeft = (constraints.maxWidth - handleWidth)
                          .clamp(0.0, double.infinity);
                      final handleLeft = maxLeft * _startSliderValue;

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Geser untuk mulai',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: (56 - handleHeight) / 2,
                            left: handleLeft,
                            child: GestureDetector(
                              onHorizontalDragUpdate: _isStartingTracking
                                  ? null
                                  : (details) {
                                      if (maxLeft <= 0) return;
                                      final nextValue =
                                          (_startSliderValue +
                                                  (details.delta.dx / maxLeft))
                                              .clamp(0.0, 1.0);
                                      _onStartSliderChanged(nextValue);
                                    },
                              onHorizontalDragEnd: _isStartingTracking
                                  ? null
                                  : (_) => _onStartSliderReleased(
                                      _startSliderValue,
                                    ),
                              child: Container(
                                width: handleWidth,
                                height: handleHeight,
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(PsbTicket t) {
    final hasCoordinate =
        t.customerLat != null &&
        t.customerLng != null &&
        t.customerLat != 0 &&
        t.customerLng != 0;

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
          if (hasCoordinate)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _openInGoogleMaps(
                      lat: t.customerLat!,
                      lng: t.customerLng!,
                      label: t.customerName ?? 'Lokasi Perbaikan',
                    );
                  },
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Maps'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.info,
                    side: const BorderSide(color: AppColors.info),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamMembersCard(PsbTicket t) {
    final hasPic = t.picTechnician != null;
    final hasSupport = t.supportTechnicians.isNotEmpty;

    if (!hasPic && !hasSupport) {
      return const SizedBox.shrink();
    }

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
            child: const Row(
              children: [
                Icon(Icons.group, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tim Teknisi',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PIC Member
                if (hasPic) ...[
                  const Text(
                    'Penanggungjawab',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.picTechnician!.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PIC',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasSupport) const SizedBox(height: 14),
                ],
                // Support Members
                if (hasSupport) ...[
                  const Text(
                    'Anggota Tim',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: t.supportTechnicians.asMap().entries.map((entry) {
                      final isLast =
                          entry.key == t.supportTechnicians.length - 1;
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.value.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
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
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Anggota',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isLast) const SizedBox(height: 8),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportMembersEditorCard(PsbTicket t) {
    final currentSupportIds = t.supportTechnicians.map((m) => m.id).toSet();
    final hasChanges =
        currentSupportIds.length != _selectedSupportIds.length ||
        !currentSupportIds.containsAll(_selectedSupportIds);
    final selectedCount = _selectedSupportIds.length;

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
            'Kelola Teknisi Anggota',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pilih anggota tim yang membantu tiket ini. Boleh dikosongkan jika tidak ada anggota.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedCount == 0
                      ? 'Belum ada anggota dipilih.'
                      : '$selectedCount anggota dipilih',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(
                    () => _showSupportMembersForm = !_showSupportMembersForm,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  _showSupportMembersForm
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  _showSupportMembersForm ? 'Tutup' : 'Tambah Tim',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          if (_showSupportMembersForm) ...[
            const SizedBox(height: 12),
            if (_isLoadingTechnicianOptions)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_technicianOptions.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Text(
                  'Tidak ada teknisi lain yang tersedia untuk dipilih.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _technicianOptions.map((tech) {
                  final isSelected = _selectedSupportIds.contains(tech.id);
                  return FilterChip(
                    label: Text(tech.name),
                    selected: isSelected,
                    onSelected: _isSavingSupportMembers
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _selectedSupportIds.add(tech.id);
                              } else {
                                _selectedSupportIds.remove(tech.id);
                              }
                            });
                          },
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingSupportMembers || !hasChanges
                    ? null
                    : _saveSupportMembers,
                icon: _isSavingSupportMembers
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _isSavingSupportMembers
                      ? 'Menyimpan...'
                      : 'Simpan Anggota Tim',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
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
            _infoRow('Ditugaskan ke', t.assignerName!),
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
    final canReport =
        t.isPic &&
        t.status != 'done' &&
        t.status != 'resolved' &&
        t.status != 'closed' &&
        !t.isFinished;

    return RefreshIndicator(
      onRefresh: _fetchTicket,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!canReport)
            _buildInfoBanner(
              t.isClaimable
                  ? 'Ambil tiket terlebih dahulu di tab Info untuk bisa mengirim laporan.'
                  : (t.isSupport
                        ? 'Anda tergabung sebagai anggota. Laporan hanya bisa dikirim oleh teknisi penanggungjawab.'
                        : 'Tiket ini sudah diselesaikan.'),
              t.isClaimable ? AppColors.warning : AppColors.success,
            ),
          if (canReport) ...[_buildFieldReportForm()],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBuktiFotoTab() {
    final t = _ticket!;

    return RefreshIndicator(
      onRefresh: _fetchTicket,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (t.photos.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Belum ada foto dokumentasi.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...t.photos.map(_buildPhotoCard),
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
    final showDoneWarning = _selectedFieldStatus == 'done';

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
          const SizedBox(height: 10),
          _buildFieldStatusCards(),
          const SizedBox(height: 14),
          if (showDoneWarning) ...[
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

  Widget _buildProgressTracking(PsbTicket t) {
    final fieldStepByStatus = <String, int>{
      'preparing': 1,
      'on_the_way': 2,
      'working': 3,
      'done': 4,
      'fixed': 4,
    };
    final currentFieldStep = fieldStepByStatus[t.fieldStatus];

    final steps = [
      (label: 'Tiket Diambil', done: true),
      (
        label: 'Persiapan',
        done: currentFieldStep != null && currentFieldStep >= 1,
      ),
      (
        label: 'Menuju Lokasi Pelanggan',
        done: currentFieldStep != null && currentFieldStep >= 2,
      ),
      (
        label: 'Pemasangan',
        done: currentFieldStep != null && currentFieldStep >= 3,
      ),
      (
        label: 'Selesai',
        done: currentFieldStep != null && currentFieldStep >= 4,
      ),
    ];

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
            'Progress Pekerjaan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: steps[i].done
                              ? AppColors.success
                              : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: steps[i].done
                            ? const Icon(
                                Icons.check,
                                size: 15,
                                color: Colors.white,
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xFFCBD5E1),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        steps[i].label,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: (steps[i].done && steps[i + 1].done)
                          ? AppColors.success.withOpacity(0.35)
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldStatusCards() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _fieldStatusOptions.map((option) {
        final isSelected = _selectedFieldStatus == option.$1;
        IconData icon;
        Color color;

        switch (option.$1) {
          case 'preparing':
            icon = Icons.content_paste_outlined;
            color = const Color(0xFF9C27B0);
            break;
          case 'on_the_way':
            icon = Icons.two_wheeler;
            color = AppColors.info;
            break;
          case 'working':
            icon = Icons.build_outlined;
            color = const Color(0xFFFF9800);
            break;
          case 'done':
            icon = Icons.check_circle_outlined;
            color = AppColors.success;
            break;
          case 'waiting_parts':
            icon = Icons.access_time_outlined;
            color = AppColors.warning;
            break;
          case 'other':
            icon = Icons.more_horiz_outlined;
            color = AppColors.textSecondary;
            break;
          default:
            icon = Icons.help_outline;
            color = AppColors.textSecondary;
        }

        return InkWell(
          onTap: () {
            setState(() {
              _selectedFieldStatus = option.$1;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.12) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? color : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  option.$2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
