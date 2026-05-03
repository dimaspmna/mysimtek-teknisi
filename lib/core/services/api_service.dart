import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  final StorageService _storage;

  ApiService(this._storage);

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await _storage.getToken();
      if (token != null) h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> get(String endpoint, {Map<String, String>? query}) async {
    var uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    try {
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    try {
      final res = await http
          .post(
            uri,
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  Future<dynamic> postMultipart(
    String endpoint,
    Map<String, String> fields, {
    List<File>? files,
    String fileField = 'photos[]',
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    try {
      final authHeaders = await _headers();
      authHeaders.remove('Content-Type');
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(authHeaders);
      req.fields.addAll(fields);
      if (files != null && files.isNotEmpty) {
        for (var file in files) {
          req.files.add(
            await http.MultipartFile.fromPath(fileField, file.path),
          );
        }
      }
      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    try {
      final res = await http
          .put(uri, headers: await _headers(), body: jsonEncode(body))
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  Future<dynamic> patch(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    try {
      final res = await http
          .patch(uri, headers: await _headers(), body: jsonEncode(body))
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    try {
      final res = await http
          .delete(uri, headers: await _headers())
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw ApiException('Koneksi timeout. Server tidak merespons.');
    }
  }

  dynamic _parse(http.Response res) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ApiException(
        'Respons server tidak valid (kode ${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Auto-unwrap standard API envelope { "status": ..., "data": ... }
      // But keep the full map when there are extra keys (e.g. "stats")
      if (decoded is Map && decoded.containsKey('data')) {
        final extraKeys = decoded.keys
            .where((k) => k != 'status' && k != 'data' && k != 'message')
            .length;
        if (extraKeys == 0) return decoded['data'];
        return decoded;
      }
      return decoded;
    }
    if (res.statusCode == 401) {
      // Saat login (tanpa token), 401 berarti kredensial salah.
      // Saat endpoint terproteksi, 401 berarti sesi habis.
      final isGuest = res.request?.headers['Authorization'] == null;
      final msg = isGuest
          ? 'Email atau password yang Anda masukkan salah.'
          : 'Sesi habis, silakan login kembali.';
      throw ApiException(msg, statusCode: 401);
    }
    if (res.statusCode == 422) {
      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) {
          throw ApiException(first.first.toString(), statusCode: 422);
        }
      }
    }
    throw ApiException(
      decoded is Map
          ? (decoded['message']?.toString() ?? 'Terjadi kesalahan.')
          : 'Terjadi kesalahan (${res.statusCode}).',
      statusCode: res.statusCode,
    );
  }
}
