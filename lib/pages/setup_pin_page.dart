// SetupPinPage — dipaksa tampil (lewat _PinGate di main.dart) selama
// `users/{uid}/pin` masih kosong. Sebelumnya PIN transaksi dibikinkan admin
// secara acak pas mendaftarkan nasabah baru (lihat web-admin); sekarang PIN
// itu nggak pernah ada sampai nasabah sendiri yang mengaturnya di sini, jadi
// cuma nasabah yang tahu PIN-nya.
//
// Halaman ini sengaja gak dibungkus Navigator.push (dia jadi hasil build
// dari _PinGate, sama seperti LoginPage/NotRegisteredPage) — jadi nggak ada
// tombol back, nasabah nggak bisa "skip" lewatin setup ini.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';

class SetupPinPage extends StatefulWidget {
  final String uid;

  /// Simpan PIN yang sudah divalidasi ke database. Dipisah jadi callback
  /// (bukan manggil writeRtdb langsung) supaya halaman ini nggak perlu
  /// import main.dart cuma buat satu fungsi tulis.
  final Future<void> Function(String uid, String pin) onSubmit;

  /// Opsional — buat nasabah yang salah akun Google dan mau ganti akun
  /// alih-alih lanjut setup PIN di akun ini.
  final Future<void> Function()? onSignOut;

  const SetupPinPage({
    super.key,
    required this.uid,
    required this.onSubmit,
    this.onSignOut,
  });

  @override
  State<SetupPinPage> createState() => _SetupPinPageState();
}

class _SetupPinPageState extends State<SetupPinPage> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePin(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'PIN wajib diisi.';
    // Sama persis dengan aturan di web-admin (isValidPin): 6 digit angka.
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      return 'PIN harus 6 digit angka.';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ulangi PIN wajib diisi.';
    if (v != _pinController.text.trim()) {
      return 'PIN dan ulangi PIN tidak sama.';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      await widget.onSubmit(widget.uid, _pinController.text.trim());
      // Nggak perlu navigasi manual — _PinGate lagi dengerin nilai
      // `users/{uid}/pin` secara live, begitu tersimpan dia otomatis ganti
      // ke NasabahDashboard.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal menyimpan PIN. Cek koneksi lalu coba lagi.\n$e';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: true,
      obscuringCharacter: '•',
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      maxLength: 6,
      style: const TextStyle(fontSize: 22, letterSpacing: 12),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.hijauMuda,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: AppColors.hijau,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Buat PIN Transaksi',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sebelum lanjut, buat dulu PIN 6 digit kamu sendiri. '
                    'PIN ini akan diminta admin setiap kamu melakukan '
                    'penarikan saldo, jadi jangan kasih tahu siapa pun.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.teksRedup),
                  ),
                  const SizedBox(height: 28),
                  _buildPinField(
                    controller: _pinController,
                    label: 'PIN baru (6 digit)',
                    validator: _validatePin,
                  ),
                  const SizedBox(height: 16),
                  _buildPinField(
                    controller: _confirmController,
                    label: 'Ulangi PIN baru',
                    validator: _validateConfirm,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.hijau,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Simpan PIN'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.negatif),
                    ),
                  ],
                  if (widget.onSignOut != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              await widget.onSignOut!();
                            },
                      child: const Text('Salah akun? Ganti akun / Keluar'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
