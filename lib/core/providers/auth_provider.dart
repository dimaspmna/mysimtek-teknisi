import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final ApiService _api;
  final StorageService _storage;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _error;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isTeknisi => _user?.role == 'teknisi';

  AuthProvider(this._api, this._storage);

  Future<void> checkAuth() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final token = await _storage.getToken();
      if (token == null) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      final res = await _api.get(ApiConstants.me);
      final userData = (res is Map && res.containsKey('user'))
          ? res['user'] as Map<String, dynamic>
          : res as Map<String, dynamic>;
      _user = UserModel.fromJson(userData);

      // Only allow teknisi role
      if (_user?.role != 'teknisi') {
        await logout();
        _error = 'Akun ini bukan untuk teknisi';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      _status = AuthStatus.authenticated;

      // Sync FCM token now that the user is authenticated.
      FcmService.syncToken().ignore();
    } catch (_) {
      await _storage.clearAll();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.post(ApiConstants.login, {
        'email': email,
        'password': password,
        'device_name': 'MySimtek_Teknisi',
      }, auth: false);
      final token = res['token']?.toString() ?? '';
      final user = UserModel.fromJson(res['user'] as Map<String, dynamic>);
      final role = user.role.toLowerCase().trim();

      // Only allow teknisi role
      if (role != 'teknisi') {
        _error =
            'Akun ini bukan untuk teknisi. '
            'Aplikasi ini khusus untuk teknisi.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      await _storage.saveToken(token);
      _user = user;
      await _storage.saveRole(role);

      _status = AuthStatus.authenticated;
      notifyListeners();
      // Sync FCM token after successful login
      FcmService.syncToken().ignore();
    } on ApiException catch (e) {
      _error = e.message;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _error = 'Terjadi kesalahan: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiConstants.logout, {});
    } catch (_) {}
    await FcmService.clearToken().catchError((_) {});
    await _storage.clearAll();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _error = null;
    notifyListeners();
  }

  Future<bool> verifyPassword(String password) async {
    try {
      await _api.post(ApiConstants.verifyPassword, {'password': password});
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 422) return false;
      rethrow;
    }
  }

  Future<String?> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      await _api.post(ApiConstants.changePassword, {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': newPassword,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Terjadi kesalahan: ${e.toString()}';
    }
  }
}
