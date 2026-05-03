import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/map_data_model.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/map_service.dart';
import '../../../../core/services/storage_service.dart';

class PetaAreaScreen extends StatefulWidget {
  const PetaAreaScreen({super.key});

  @override
  State<PetaAreaScreen> createState() => _PetaAreaScreenState();
}

class _PetaAreaScreenState extends State<PetaAreaScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  TeknisiMapData? _mapData;
  List<MapNode> _searchResults = const [];
  bool _isMapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;

  BaseMapType _baseMapType = BaseMapType.google;

  final Map<LayerType, bool> _layerVisibility = {
    LayerType.pops: true,
    LayerType.otbs: true,
    LayerType.odcUtamas: true,
    LayerType.odcs: true,
    LayerType.nocOdps: true,
    LayerType.customers: true,
    LayerType.cables: true,
  };

  @override
  void initState() {
    super.initState();
    _fetchMapData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _fetchMapData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = StorageService();
      final api = ApiService(storage);
      final service = MapService(api);
      final data = await service.getMapData();

      if (!mounted) return;
      setState(() {
        _mapData = data;
        _isLoading = false;
      });

      _moveToInitialDataPoint();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _moveToInitialDataPoint() {
    final nodes = _mapData?.allNodes ?? const <MapNode>[];
    if (nodes.isEmpty) return;
    final first = nodes.first;
    _moveMapSafely(LatLng(first.latitude, first.longitude), 14);
  }

  void _onMapReady() {
    _isMapReady = true;
    if (_pendingCenter != null && _pendingZoom != null) {
      _mapController.move(_pendingCenter!, _pendingZoom!);
      _pendingCenter = null;
      _pendingZoom = null;
    }
  }

  void _moveMapSafely(LatLng center, double zoom) {
    if (!_isMapReady) {
      _pendingCenter = center;
      _pendingZoom = zoom;
      return;
    }
    _mapController.move(center, zoom);
  }

  void _zoomToVisibleData() {
    final points = <LatLng>[];
    final visibleNodes = _visibleNodes();
    for (final node in visibleNodes) {
      points.add(LatLng(node.latitude, node.longitude));
    }
    if (_layerVisibility[LayerType.cables] == true) {
      for (final cable in _visibleCables()) {
        points
          ..add(LatLng(cable.odpLat, cable.odpLng))
          ..add(LatLng(cable.customerLat, cable.customerLng));
      }
    }

    if (points.isEmpty) return;
    if (points.length == 1) {
      _moveMapSafely(points.first, 16);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latDelta = maxLat - minLat;
    final lngDelta = maxLng - minLng;
    final maxDelta = latDelta > lngDelta ? latDelta : lngDelta;
    final double zoom = maxDelta > 1
        ? 8.5
        : maxDelta > 0.5
        ? 10
        : maxDelta > 0.2
        ? 11.2
        : maxDelta > 0.08
        ? 12.4
        : maxDelta > 0.03
        ? 13.7
        : 15;

    _moveMapSafely(LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2), zoom);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.length < 2) {
      if (_searchResults.isNotEmpty) {
        setState(() => _searchResults = const []);
      }
      return;
    }

    final allNodes = _mapData?.allNodes ?? const <MapNode>[];
    final results = allNodes
        .where((node) {
          final terms = [
            node.name,
            node.code ?? '',
            node.type,
            node.address ?? '',
          ].join(' ').toLowerCase();
          return terms.contains(query);
        })
        .take(12)
        .toList();

    setState(() {
      _searchResults = results;
    });
  }

  List<MapNode> _visibleNodes() {
    final data = _mapData;
    if (data == null) return const [];

    return [
      if (_layerVisibility[LayerType.pops] == true) ...data.pops,
      if (_layerVisibility[LayerType.otbs] == true) ...data.otbs,
      if (_layerVisibility[LayerType.odcUtamas] == true) ...data.odcUtamas,
      if (_layerVisibility[LayerType.odcs] == true) ...data.odcs,
      if (_layerVisibility[LayerType.nocOdps] == true) ...data.nocOdps,
      if (_layerVisibility[LayerType.customers] == true) ...data.customers,
    ];
  }

  List<CablePath> _visibleCables() {
    final data = _mapData;
    if (data == null || _layerVisibility[LayerType.cables] != true) {
      return const [];
    }
    return data.cables;
  }

  void _showNodeDetail(MapNode node) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _layerColor(node.type).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _layerIcon(node.type),
                        color: _layerColor(node.type),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            node.type,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusPill(node.status),
                  ],
                ),
                const SizedBox(height: 14),
                _detailRow('Kode', node.code ?? '-'),
                _detailRow('Alamat', node.address ?? '-'),
                _detailRow('Latitude', node.latitude.toStringAsFixed(6)),
                _detailRow('Longitude', node.longitude.toStringAsFixed(6)),
                if (node.extra['capacity_port'] != null)
                  _detailRow(
                    'Kapasitas',
                    '${node.extra['capacity_port']} port',
                  ),
                if (node.extra['port_used'] != null)
                  _detailRow('Port Terpakai', '${node.extra['port_used']}'),
                if (node.extra['port_available'] != null)
                  _detailRow(
                    'Port Tersedia',
                    '${node.extra['port_available']}',
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openInGoogleMaps(node),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Buka di Google Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openInGoogleMaps(MapNode node) async {
    final lat = node.latitude;
    final lng = node.longitude;
    final encodedLabel = Uri.encodeComponent(node.name);

    // Android-friendly URI to open point directly in maps app.
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
      // Fallback handled below by snackbar.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Maps tidak dapat dibuka di perangkat ini.'),
      ),
    );
  }

  Widget _statusPill(String rawStatus) {
    final text = rawStatus.isEmpty ? '-' : rawStatus.replaceAll('_', ' ');
    final color = _statusColor(rawStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('active') || normalized.contains('installed')) {
      return AppColors.success;
    }
    if (normalized.contains('planned') || normalized.contains('partial')) {
      return AppColors.warning;
    }
    if (normalized.contains('inactive') || normalized.contains('damage')) {
      return AppColors.textSecondary;
    }
    return AppColors.info;
  }

  IconData _layerIcon(String type) {
    switch (type) {
      case 'POP':
        return Icons.router_rounded;
      case 'OTB':
        return Icons.settings_input_component_rounded;
      case 'ODC Utama':
        return Icons.hub_rounded;
      case 'ODC':
        return Icons.device_hub_rounded;
      case 'ODP':
        return Icons.wifi_tethering_rounded;
      default:
        return Icons.person_pin_circle_rounded;
    }
  }

  Color _layerColor(String type) {
    switch (type) {
      case 'POP':
        return const Color(0xFF7C3AED);
      case 'OTB':
        return const Color(0xFF0EA5E9);
      case 'ODC Utama':
        return const Color(0xFFF97316);
      case 'ODC':
        return const Color(0xFF10B981);
      case 'ODP':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  Color _layerColorByKey(LayerType key) {
    switch (key) {
      case LayerType.pops:
        return const Color(0xFF7C3AED);
      case LayerType.otbs:
        return const Color(0xFF0EA5E9);
      case LayerType.odcUtamas:
        return const Color(0xFFF97316);
      case LayerType.odcs:
        return const Color(0xFF10B981);
      case LayerType.nocOdps:
        return const Color(0xFFEF4444);
      case LayerType.customers:
        return const Color(0xFF3B82F6);
      case LayerType.cables:
        return const Color(0xFF22C55E);
    }
  }

  String _layerLabel(LayerType key) {
    switch (key) {
      case LayerType.pops:
        return 'POP';
      case LayerType.otbs:
        return 'OTB';
      case LayerType.odcUtamas:
        return 'ODC Utama';
      case LayerType.odcs:
        return 'ODC';
      case LayerType.nocOdps:
        return 'ODP';
      case LayerType.customers:
        return 'Customer';
      case LayerType.cables:
        return 'Kabel';
    }
  }

  int _layerCount(LayerType key) {
    final data = _mapData;
    if (data == null) return 0;
    switch (key) {
      case LayerType.pops:
        return data.pops.length;
      case LayerType.otbs:
        return data.otbs.length;
      case LayerType.odcUtamas:
        return data.odcUtamas.length;
      case LayerType.odcs:
        return data.odcs.length;
      case LayerType.nocOdps:
        return data.nocOdps.length;
      case LayerType.customers:
        return data.customers.length;
      case LayerType.cables:
        return data.cables.length;
    }
  }

  TileLayer _buildBaseTile() {
    switch (_baseMapType) {
      case BaseMapType.google:
        return TileLayer(
          urlTemplate: 'https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
          maxZoom: 22,
        );
      case BaseMapType.esri:
        return TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          maxZoom: 20,
        );
    }
  }

  TileLayer _buildAreaLabelsOverlay() {
    return TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}{r}.png',
      retinaMode: true,
      subdomains: const ['a', 'b', 'c', 'd'],
      maxZoom: 20,
    );
  }

  Marker _buildMarker(MapNode node) {
    final color = _layerColor(node.type);
    return Marker(
      width: 38,
      height: 38,
      point: LatLng(node.latitude, node.longitude),
      child: GestureDetector(
        onTap: () => _showNodeDetail(node),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(_layerIcon(node.type), color: Colors.white, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleNodes = _visibleNodes();
    final visibleCables = _visibleCables();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Peta Area',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          PopupMenuButton<BaseMapType>(
            tooltip: 'Pilih basemap',
            icon: const Icon(Icons.layers_outlined),
            onSelected: (value) {
              setState(() => _baseMapType = value);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: BaseMapType.google,
                child: Text('Google Satelit'),
              ),
              PopupMenuItem(
                value: BaseMapType.esri,
                child: Text('Esri Satelit'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Muat ulang data',
            onPressed: _fetchMapData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _MapErrorState(message: _errorMessage!, onRetry: _fetchMapData)
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(-6.2088, 106.8456),
                    initialZoom: 12,
                    onMapReady: _onMapReady,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    _buildBaseTile(),
                    _buildAreaLabelsOverlay(),
                    if (visibleCables.isNotEmpty)
                      PolylineLayer(
                        polylines: visibleCables
                            .map(
                              (cable) => Polyline(
                                points: [
                                  LatLng(cable.odpLat, cable.odpLng),
                                  LatLng(cable.customerLat, cable.customerLng),
                                ],
                                color: const Color(0xFF22C55E),
                                strokeWidth: 2,
                              ),
                            )
                            .toList(),
                      ),
                    if (visibleNodes.isNotEmpty)
                      MarkerLayer(
                        markers: visibleNodes.map(_buildMarker).toList(),
                      ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Cari POP, OTB, ODC, ODP, Customer...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchResults = const []);
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _searchResults[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  _layerIcon(item.type),
                                  color: _layerColor(item.type),
                                ),
                                title: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(item.type),
                                onTap: () {
                                  FocusScope.of(context).unfocus();
                                  _moveMapSafely(
                                    LatLng(item.latitude, item.longitude),
                                    17,
                                  );
                                  setState(() {
                                    _searchController.text = item.name;
                                    _searchResults = const [];
                                  });
                                  _showNodeDetail(item);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: LayerType.values.map((layer) {
                        final selected = _layerVisibility[layer] == true;
                        final color = _layerColorByKey(layer);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: selected,
                            label: Text(
                              '${_layerLabel(layer)} (${_layerCount(layer)})',
                              style: TextStyle(
                                fontSize: 12,
                                color: selected ? Colors.white : color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            selectedColor: color,
                            checkmarkColor: Colors.white,
                            side: BorderSide(color: color, width: 1.5),
                            backgroundColor: Colors.white,
                            onSelected: (value) {
                              setState(() {
                                _layerVisibility[layer] = value;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 78,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom-visible',
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.textPrimary,
                        onPressed: _zoomToVisibleData,
                        child: const Icon(Icons.fit_screen_rounded),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'clear-search',
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.textPrimary,
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchResults = const [];
                          });
                        },
                        child: const Icon(Icons.close_fullscreen_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

enum LayerType { pops, otbs, odcUtamas, odcs, nocOdps, customers, cables }

enum BaseMapType { google, esri }

class _MapErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _MapErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gagal memuat peta',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
