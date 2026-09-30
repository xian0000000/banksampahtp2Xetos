// Model transaksi. Node `transactions/<uid>/<txId>` di Realtime Database
// bentuknya tidak seragam: transaksi setor lama menyimpan satu kategori
// langsung di root (kategori/berat_kg/total_rp), sementara yang baru pakai
// list `items`. Selain itu ada transaksi lama yang belum punya
// harga_per_kg. Semua normalisasi itu dikumpulkan di sini supaya UI dan
// generator PDF tidak masing-masing menebak bentuk datanya.

/// Satu baris rincian sampah dalam sebuah transaksi setor.
class TransactionItem {
  final String kategori;
  final double beratKg;
  final double hargaPerKg;
  final double subtotalRp;

  const TransactionItem({
    required this.kategori,
    required this.beratKg,
    required this.hargaPerKg,
    required this.subtotalRp,
  });

  factory TransactionItem.fromMap(Map<dynamic, dynamic> raw) {
    final berat = _toDouble(raw['berat_kg']);
    final hargaTersimpan = _toDouble(raw['harga_per_kg']);
    final subtotalTersimpan = _toDouble(raw['total_rp']);

    // Data lama kadang cuma punya salah satu dari harga_per_kg / total_rp.
    // Turunkan yang hilang dari yang ada supaya baris tabel tetap
    // konsisten dan subtotal-nya benar-benar menjumlah ke total.
    final subtotal = subtotalTersimpan > 0
        ? subtotalTersimpan
        : berat * hargaTersimpan;
    final harga = hargaTersimpan > 0
        ? hargaTersimpan
        : (berat > 0 ? subtotal / berat : 0.0);

    return TransactionItem(
      kategori: (raw['kategori']?.toString().trim().isEmpty ?? true)
          ? 'Lainnya'
          : raw['kategori'].toString().trim(),
      beratKg: berat,
      hargaPerKg: harga,
      subtotalRp: subtotal,
    );
  }
}

enum TransactionKind { setor, tarik, keluarSampah }

/// Transaksi yang sudah dinormalisasi dan siap dirender.
class TransactionRecord {
  final String? id;
  final TransactionKind kind;
  final DateTime? tanggal;
  final String adminPencatat;
  final double totalRp;
  final List<TransactionItem> items;

  /// Identitas nasabah. Tidak tersimpan di node transaksi — diisi oleh
  /// pemanggil dari node `users/<uid>` supaya bukti transaksi punya
  /// keterangan "ini punya siapa".
  final String namaNasabah;
  final String kelasNasabah;

  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.tanggal,
    required this.adminPencatat,
    required this.totalRp,
    required this.items,
    required this.namaNasabah,
    required this.kelasNasabah,
  });

  factory TransactionRecord.fromMap(
    Map<dynamic, dynamic> raw, {
    String? txId,
    String namaNasabah = '',
    String kelasNasabah = '',
  }) {
    final tipe = raw['tipe']?.toString() ?? '';
    final isWasteOut = raw['isWasteOut'] == true ||
        tipe == 'Pengeluaran Sampah';

    final kind = isWasteOut
        ? TransactionKind.keluarSampah
        : (tipe == 'Setor' ? TransactionKind.setor : TransactionKind.tarik);

    return TransactionRecord(
      id: txId,
      kind: kind,
      tanggal: DateTime.tryParse(raw['tanggal']?.toString() ?? ''),
      adminPencatat: raw['admin_pencatat']?.toString().trim().isNotEmpty == true
          ? raw['admin_pencatat'].toString().trim()
          : '-',
      totalRp: _toDouble(raw['total_rp']),
      items: kind == TransactionKind.tarik ? const [] : _parseItems(raw),
      namaNasabah: namaNasabah.trim(),
      kelasNasabah: kelasNasabah.trim(),
    );
  }

  bool get isSetor => kind == TransactionKind.setor;
  bool get isTarik => kind == TransactionKind.tarik;

  double get totalBeratKg =>
      items.fold<double>(0, (sum, item) => sum + item.beratKg);

  /// Jumlah subtotal seluruh baris. Dipakai untuk mendeteksi kalau total
  /// yang tersimpan ternyata tidak cocok dengan rinciannya.
  double get jumlahSubtotal =>
      items.fold<double>(0, (sum, item) => sum + item.subtotalRp);

  /// True kalau rincian tidak menjumlah ke total tersimpan (selisih lebih
  /// dari satu rupiah). Kalau ini terjadi, PDF menampilkan catatan kecil
  /// alih-alih diam-diam menampilkan angka yang saling bertentangan.
  bool get totalTidakCocok =>
      isSetor && items.isNotEmpty && (jumlahSubtotal - totalRp).abs() > 1;

  String get labelJenis {
    switch (kind) {
      case TransactionKind.setor:
        return 'Setor sampah';
      case TransactionKind.tarik:
        return 'Penarikan saldo';
      case TransactionKind.keluarSampah:
        return 'Pengeluaran sampah';
    }
  }

  String get labelBadge {
    switch (kind) {
      case TransactionKind.setor:
        return 'SETOR';
      case TransactionKind.tarik:
        return 'PENARIKAN';
      case TransactionKind.keluarSampah:
        return 'KELUAR';
    }
  }

  static List<TransactionItem> _parseItems(Map<dynamic, dynamic> raw) {
    final rawItems = raw['items'];

    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map(TransactionItem.fromMap)
          .toList();
    }
    if (rawItems is Map) {
      return rawItems.values
          .whereType<Map>()
          .map(TransactionItem.fromMap)
          .toList();
    }

    // Bentuk lama: satu kategori langsung di root transaksi.
    if (raw['kategori'] != null) {
      return [TransactionItem.fromMap(raw)];
    }
    return const [];
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
