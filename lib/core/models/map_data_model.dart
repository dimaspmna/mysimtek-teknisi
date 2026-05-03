class MapNode {
  final int? id;
  final String type;
  final String? code;
  final String name;
  final String? address;
  final String status;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> extra;

  MapNode({
    this.id,
    required this.type,
    this.code,
    required this.name,
    this.address,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.extra = const {},
  });

  factory MapNode.fromJson(Map<String, dynamic> json, {required String type}) {
    return MapNode(
      id: _toInt(json['id']),
      type: type,
      code: _toNullableString(json['code']),
      name:
          _toNullableString(json['name']) ??
          _toNullableString(json['nama']) ??
          '-',
      address: _toNullableString(json['address']),
      status: (_toNullableString(json['status']) ?? 'active').toLowerCase(),
      latitude: _toDouble(json['latitude']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? 0,
      extra: Map<String, dynamic>.from(json),
    );
  }

  bool get hasValidCoordinate => latitude != 0 && longitude != 0;
}

class CablePath {
  final int? id;
  final String? odpName;
  final String? customerName;
  final double odpLat;
  final double odpLng;
  final double customerLat;
  final double customerLng;

  CablePath({
    this.id,
    this.odpName,
    this.customerName,
    required this.odpLat,
    required this.odpLng,
    required this.customerLat,
    required this.customerLng,
  });

  factory CablePath.fromJson(Map<String, dynamic> json) {
    return CablePath(
      id: _toInt(json['id']),
      odpName: _toNullableString(json['odp_name']),
      customerName:
          _toNullableString(json['cust_name']) ??
          _toNullableString(json['customer_name']),
      odpLat: _toDouble(json['odp_lat']) ?? 0,
      odpLng: _toDouble(json['odp_lng']) ?? 0,
      customerLat: _toDouble(json['cust_lat']) ?? 0,
      customerLng: _toDouble(json['cust_lng']) ?? 0,
    );
  }

  bool get hasValidCoordinate {
    return odpLat != 0 && odpLng != 0 && customerLat != 0 && customerLng != 0;
  }
}

class TeknisiMapData {
  final List<MapNode> pops;
  final List<MapNode> otbs;
  final List<MapNode> odcUtamas;
  final List<MapNode> odcs;
  final List<MapNode> nocOdps;
  final List<MapNode> customers;
  final List<CablePath> cables;

  TeknisiMapData({
    required this.pops,
    required this.otbs,
    required this.odcUtamas,
    required this.odcs,
    required this.nocOdps,
    required this.customers,
    required this.cables,
  });

  factory TeknisiMapData.fromJson(Map<String, dynamic> json) {
    List<MapNode> parseNodes(String key, String type) {
      final list = _asList(json[key]);
      return list
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map((item) => MapNode.fromJson(item, type: type))
          .where((item) => item.hasValidCoordinate)
          .toList();
    }

    final cableList = _asList(json['cables'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(CablePath.fromJson)
        .where((cable) => cable.hasValidCoordinate)
        .toList();

    return TeknisiMapData(
      pops: parseNodes('pops', 'POP'),
      otbs: parseNodes('otbs', 'OTB'),
      odcUtamas: parseNodes('odc_utamas', 'ODC Utama'),
      odcs: parseNodes('odcs', 'ODC'),
      nocOdps: parseNodes('noc_odps', 'ODP'),
      customers: parseNodes('customers', 'Customer'),
      cables: cableList,
    );
  }

  List<MapNode> get allNodes => [
    ...pops,
    ...otbs,
    ...odcUtamas,
    ...odcs,
    ...nocOdps,
    ...customers,
  ];
}

List<dynamic> _asList(dynamic raw) {
  if (raw is List) return raw;
  return const [];
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

String? _toNullableString(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty || value.toLowerCase() == 'null') return null;
  return value;
}

double? _toDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

int? _toInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}
