import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/auth_provider.dart';

enum _CheckState { none, loading, valid, invalid }

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _currentFocus = FocusNode();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _loading = false;
  bool _newTouched = false;
  bool _confirmTouched = false;
  _CheckState _checkState = _CheckState.none;

  @override
  void initState() {
    super.initState();
    _currentFocus.addListener(_onCurrentFocusChange);
  }

  void _onCurrentFocusChange() {
    if (!_currentFocus.hasFocus && _currentCtrl.text.isNotEmpty) {
      _verifyCurrentPassword();
    }
  }

  Future<void> _verifyCurrentPassword() async {
    final password = _currentCtrl.text;
    if (password.isEmpty) return;

    setState(() => _checkState = _CheckState.loading);
    try {
      final valid = await context.read<AuthProvider>().verifyPassword(password);
      if (!mounted) return;
      setState(
        () => _checkState = valid ? _CheckState.valid : _CheckState.invalid,
      );
    } catch (_) {
      if (mounted) setState(() => _checkState = _CheckState.none);
    }
  }

  @override
  void dispose() {
    _currentFocus.removeListener(_onCurrentFocusChange);
    _currentFocus.dispose();
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_checkState != _CheckState.valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verifikasi kata sandi lama terlebih dahulu.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final error = await context.read<AuthProvider>().changePassword(
        _currentCtrl.text,
        _newCtrl.text,
      );

      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kata sandi berhasil diubah.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Ganti Kata Sandi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kata sandi baru minimal 8 karakter.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Masukkan Kata Sandi Lama',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  controller: _currentCtrl,
                  focusNode: _currentFocus,
                  obscureText: !_showCurrent,
                  onChanged: (_) {
                    if (_checkState != _CheckState.none) {
                      setState(() => _checkState = _CheckState.none);
                    }
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Wajib diisi';
                    if (_checkState == _CheckState.invalid) {
                      return 'Kata sandi lama tidak sesuai';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Kata Sandi Lama',
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _checkState == _CheckState.valid
                            ? AppColors.success
                            : _checkState == _CheckState.invalid
                            ? AppColors.error
                            : AppColors.cardBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _checkState == _CheckState.valid
                            ? AppColors.success
                            : _checkState == _CheckState.invalid
                            ? AppColors.error
                            : AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    helperText: _checkState == _CheckState.valid
                        ? 'Kata sandi sesuai'
                        : _checkState == _CheckState.invalid
                        ? 'Kata sandi tidak sesuai'
                        : null,
                    helperStyle: TextStyle(
                      fontSize: 12,
                      color: _checkState == _CheckState.valid
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_checkState == _CheckState.loading)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        else if (_checkState == _CheckState.valid)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 20,
                            ),
                          )
                        else if (_checkState == _CheckState.invalid)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.cancel,
                              color: AppColors.error,
                              size: 20,
                            ),
                          ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _showCurrent = !_showCurrent),
                          icon: Icon(
                            _showCurrent
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Masukkan Kata Sandi Baru',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildField(
                      controller: _newCtrl,
                      label: 'Kata Sandi Baru',
                      show: _showNew,
                      onToggle: () => setState(() => _showNew = !_showNew),
                      helperText: _newTouched ? 'Minimal 8 karakter' : null,
                      onChanged: (_) {
                        if (!_newTouched) setState(() => _newTouched = true);
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Wajib diisi';
                        if (v.length < 8) return 'Minimal 8 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _confirmCtrl,
                      label: 'Konfirmasi Kata Sandi Baru',
                      show: _showConfirm,
                      onToggle: () =>
                          setState(() => _showConfirm = !_showConfirm),
                      helperText: _confirmTouched ? 'Minimal 8 karakter' : null,
                      onChanged: (_) {
                        if (!_confirmTouched) {
                          setState(() => _confirmTouched = true);
                        }
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Wajib diisi';
                        if (v != _newCtrl.text) {
                          return 'Konfirmasi tidak cocok';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Ganti Kata Sandi',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required bool show,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    String? helperText,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !show,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        helperText: helperText,
        helperStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
