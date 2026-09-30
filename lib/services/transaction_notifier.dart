import 'dart:async';

import 'local_notifications.dart';
import '../utils/formatters.dart';

/// Mendengarkan transaksi nasabah lewat RTDB (`transactions/{uid}`) dan
/// menampilkan notifikasi lokal setiap kali ada transaksi BARU masuk
/// (Setor maupun Tarik) — dipakai di dashboard nasabah supaya nasabah
/// langsung tahu tiap kali admin mencatat transaksi untuknya.
///
/// Baseline: daftar transaksi yang SUDAH ADA saat `start()` dipanggil
/// tidak dianggap "baru" (supaya tidak muncul notifikasi banjir untuk
/// histori lama begitu dashboard dibuka). Hanya transaksi yang muncul
/// SETELAH baseline pertama yang memicu notifikasi.
class TransactionNotifier {
  TransactionNotifier({
    required this.uid,
    required this.watch,
  });

  final String uid;
  final Stream<dynamic> Function(String path) watch;

  StreamSubscription<dynamic>? _sub;
  Set<String> _knownTxIds = <String>{};
  bool _baselineSet = false;

  // ID notifikasi dibuat unik per instance supaya tidak bentrok dengan
  // notifikasi lain di aplikasi (mis. kalau nanti ada jenis notifikasi
  // lain yang pakai id kecil).
  int _notifId = 5000;

  void start() {
    _sub?.cancel();
    _baselineSet = false;
    _knownTxIds = <String>{};
    _sub = watch('transactions/$uid').listen(
      _onData,
      onError: (_) {
        // Diamkan error stream di sini — halaman dashboard sendiri sudah
        // menampilkan pesan error yang relevan untuk pengguna. Notifier
        // cuma efek samping, tidak boleh ikut menjatuhkan UI.
      },
    );
  }

  void _onData(dynamic value) {
    if (value is! Map) {
      _baselineSet = true;
      return;
    }

    final entries =
        value.entries.map((e) => MapEntry(e.key.toString(), e.value)).toList();

    if (!_baselineSet) {
      // Baseline pertama: catat semua txId yang sudah ada, jangan kirim
      // notifikasi untuk histori lama yang sudah tercatat sebelum app
      // dibuka.
      _knownTxIds = entries.map((e) => e.key).toSet();
      _baselineSet = true;
      return;
    }

    for (final entry in entries) {
      final txId = entry.key;
      if (_knownTxIds.contains(txId)) continue;
      _knownTxIds.add(txId);

      final tx = entry.value;
      if (tx is! Map) continue;
      _notifyNewTransaction(Map<String, dynamic>.from(tx));
    }
  }

  void _notifyNewTransaction(Map<String, dynamic> tx) {
    final bool isSetor = tx['tipe'] == 'Setor';
    final String amount = formatRupiah(tx['total_rp'] as num?);

    final String title =
        isSetor ? 'Setoran sampah tercatat' : 'Penarikan saldo tercatat';
    final String body = isSetor
        ? 'Setor ${formatKg((tx['berat_kg'] as num?) ?? 0)} — saldo bertambah $amount.'
        : 'Saldo berkurang $amount.';

    LocalNotifications.show(
      id: _notifId++,
      title: title,
      body: body,
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
