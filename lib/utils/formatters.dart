// Formatter angka/tanggal yang dipakai bersama oleh UI (main.dart) dan
// generator PDF (lib/pdf/). Sebelumnya logika ini ada dua kali — sekali di
// main.dart sebagai formatRupiah(), sekali lagi di transaction_pdf.dart
// sebagai _pdfRp() — dan sempat beda hasil untuk nilai desimal.

/// Angka dengan pemisah ribuan gaya Indonesia, tanpa prefix mata uang.
///
/// Nilai dibulatkan dulu supaya hasil perkalian berat desimal x harga
/// (mis. 2.4 * 3000 = 7200.000000000001) tidak bocor ke tampilan.
String formatAngka(num? value) {
  final safe = value ?? 0;
  final digits = safe
      .round()
      .abs()
      .toString()
      .replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
  return safe < 0 ? '-$digits' : digits;
}

/// Nominal rupiah lengkap dengan prefix, mis. `Rp 15.600`.
String formatRupiah(num? value) => 'Rp ${formatAngka(value)}';

/// Berat dalam kilogram dengan koma desimal (gaya Indonesia), maksimal dua
/// angka di belakang koma dan tanpa nol yang tidak perlu: 2.4 -> `2,4 kg`,
/// 5.0 -> `5 kg`.
String formatKg(num? value) {
  final rounded = ((value ?? 0) * 100).round() / 100;
  final text = rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
  return '${text.isEmpty ? '0' : text} kg';
}

/// Tanggal + jam, mis. `15/09/2026 09:24`. Menerima String ISO maupun
/// DateTime; kalau tidak bisa di-parse, nilai aslinya dikembalikan apa
/// adanya supaya tidak menyembunyikan data yang rusak.
String formatTanggalJam(dynamic raw) {
  final date = _parseDate(raw);
  if (date == null) return raw?.toString() ?? '-';
  return '${_two(date.day)}/${_two(date.month)}/${date.year} '
      '${_two(date.hour)}:${_two(date.minute)}';
}

/// Tanggal saja tanpa jam, mis. `15/09/2026`.
String formatTanggal(dynamic raw) {
  final date = _parseDate(raw);
  if (date == null) return raw?.toString() ?? '-';
  return '${_two(date.day)}/${_two(date.month)}/${date.year}';
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  return DateTime.tryParse(raw.toString())?.toLocal();
}

String _two(int n) => n.toString().padLeft(2, '0');
