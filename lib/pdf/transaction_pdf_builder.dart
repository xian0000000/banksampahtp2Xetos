// Generator dokumen PDF bukti transaksi.
//
// File ini sengaja "murni": data masuk, bytes keluar. Tidak menyentuh
// BuildContext, tidak menampilkan SnackBar, tidak tahu soal share sheet
// atau penyimpanan file — semua itu urusan transaction_pdf_export.dart.
// Konsekuensinya fungsi di sini bisa diuji tanpa widget test.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/transaction_record.dart';
import '../utils/formatters.dart';

/// Palet dokumen. Dikunci di satu tempat supaya header, header tabel, dan
/// blok total tidak pelan-pelan jadi tiga hijau yang berbeda.
class _DocColors {
  static const hijau = PdfColor.fromInt(0xFF23524E);
  static const hijauMuda = PdfColor.fromInt(0xFFEAF5F2);
  static const garis = PdfColor.fromInt(0xFFDDE3E1);
  static const zebra = PdfColor.fromInt(0xFFF7FAF9);
  static const teksRedup = PdfColor.fromInt(0xFF6B7674);
}

/// Skala spasi. Kelipatan tetap, bukan angka karangan per tempat — inilah
/// yang bikin blok-blok dokumen kebaca sebagai kelompok.
class _Spasi {
  static const dalamKelompok = 6.0;
  static const antarBaris = 10.0;
  static const antarKelompok = 20.0;
  static const antarSeksi = 28.0;
}

/// Susun PDF bukti transaksi dan kembalikan bytes-nya.
///
/// [logoBytes] opsional; kalau null, header cukup memakai teks. Bytes-nya
/// dilewatkan dari luar (bukan dibaca lewat rootBundle di sini) supaya
/// fungsi ini tetap bebas dependensi Flutter.
Future<Uint8List> buildTransactionPdf(
  TransactionRecord tx, {
  Uint8List? logoBytes,
}) async {
  final doc = pw.Document(
    title: 'Bukti Transaksi — Resik For School',
    author: 'Resik For School',
    subject: tx.labelJenis,
  );

  final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
      footer: _buildFooter,
      build: (context) => [
        _buildHeader(tx, logo),
        pw.SizedBox(height: _Spasi.antarKelompok),
        _buildIdentitas(tx),
        pw.SizedBox(height: _Spasi.antarSeksi),
        if (tx.isTarik)
          _buildRingkasanTarik(tx)
        else ...[
          _buildRincianSampah(tx),
          pw.SizedBox(height: _Spasi.antarKelompok),
          _buildTotal(tx),
        ],
        if (tx.totalTidakCocok) ...[
          pw.SizedBox(height: _Spasi.antarBaris),
          _buildCatatanSelisih(tx),
        ],
        pw.SizedBox(height: _Spasi.antarSeksi),
        _buildTandaTangan(tx),
      ],
    ),
  );

  return doc.save();
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

pw.Widget _buildHeader(TransactionRecord tx, pw.MemoryImage? logo) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: _DocColors.hijau, width: 1.5),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.SizedBox(
                width: 48,
                height: 48,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Resik For School',
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: _DocColors.hijau,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Bukti transaksi bank sampah sekolah',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: _DocColors.teksRedup,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _DocColors.hijauMuda,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            tx.labelBadge,
            style: pw.TextStyle(
              color: _DocColors.hijau,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Identitas nasabah + metadata transaksi
// ---------------------------------------------------------------------------

pw.Widget _buildIdentitas(TransactionRecord tx) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _kolomIdentitas(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          textAlign: pw.TextAlign.left,
          label: 'Nasabah',
          utama: tx.namaNasabah.isEmpty ? '-' : tx.namaNasabah,
          pendukung: tx.kelasNasabah.isEmpty ? null : 'Kelas ${tx.kelasNasabah}',
        ),
      ),
      pw.Expanded(
        child: _kolomIdentitas(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          textAlign: pw.TextAlign.right,
          label: 'Tanggal',
          utama: formatTanggalJam(tx.tanggal),
          pendukung: tx.id == null ? null : 'No. ${_nomorTransaksi(tx.id!)}',
        ),
      ),
    ],
  );
}

pw.Widget _kolomIdentitas({
  required pw.CrossAxisAlignment crossAxisAlignment,
  required pw.TextAlign textAlign,
  required String label,
  required String utama,
  String? pendukung,
}) {
  return pw.Column(
    crossAxisAlignment: crossAxisAlignment,
    children: [
      pw.Text(
        label,
        textAlign: textAlign,
        style: const pw.TextStyle(fontSize: 8, color: _DocColors.teksRedup),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        utama,
        textAlign: textAlign,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      if (pendukung != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          pendukung,
          textAlign: textAlign,
          style: const pw.TextStyle(fontSize: 9, color: _DocColors.teksRedup),
        ),
      ],
    ],
  );
}

/// ID Firebase itu panjang dan acak (mis. `-Nq8vZ...`). Untuk dicetak,
/// potongan huruf besar tanpa tanda hubung jauh lebih mudah dibacakan
/// kalau nasabah perlu menyebutkannya ke admin.
String _nomorTransaksi(String id) {
  final bersih = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  final potong = bersih.length <= 8
      ? bersih
      : bersih.substring(bersih.length - 8);
  return 'TRX-$potong';
}

// ---------------------------------------------------------------------------
// Rincian sampah
// ---------------------------------------------------------------------------

pw.Widget _buildRincianSampah(TransactionRecord tx) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _judulSeksi('Rincian sampah'),
      pw.SizedBox(height: _Spasi.antarBaris),
      if (tx.items.isEmpty)
        _kosong('Tidak ada rincian kategori pada transaksi ini.')
      else
        pw.TableHelper.fromTextArray(
          headers: const ['Kategori', 'Berat', 'Harga/kg', 'Subtotal'],
          data: tx.items
              .map(
                (item) => [
                  item.kategori,
                  formatKg(item.beratKg),
                  formatAngka(item.hargaPerKg),
                  formatAngka(item.subtotalRp),
                ],
              )
              .toList(),
          columnWidths: const {
            0: pw.FlexColumnWidth(3.4),
            1: pw.FlexColumnWidth(1.8),
            2: pw.FlexColumnWidth(2.1),
            3: pw.FlexColumnWidth(2.4),
          },
          // Kolom angka rata kanan supaya digit ribuan sejajar dan mudah
          // dibandingkan antar baris.
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          headerAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
          ),
          headerDecoration: const pw.BoxDecoration(color: _DocColors.hijau),
          headerPadding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          oddRowDecoration: const pw.BoxDecoration(color: _DocColors.zebra),
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: _DocColors.garis,
              width: 0.5,
            ),
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Total
// ---------------------------------------------------------------------------

pw.Widget _buildTotal(TransactionRecord tx) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: _DocColors.garis, width: 0.5),
      ),
    ),
    padding: const pw.EdgeInsets.only(top: _Spasi.antarBaris),
    child: pw.Column(
      children: [
        if (tx.items.isNotEmpty)
          _barisRingkasan('Total berat', formatKg(tx.totalBeratKg)),
        if (tx.items.isNotEmpty) pw.SizedBox(height: _Spasi.dalamKelompok),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Total diterima',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              formatRupiah(tx.totalRp),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _DocColors.hijau,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _buildRingkasanTarik(TransactionRecord tx) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: _DocColors.hijauMuda,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Nominal penarikan',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          formatRupiah(tx.totalRp),
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: _DocColors.hijau,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _barisRingkasan(String label, String nilai) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 9.5, color: _DocColors.teksRedup),
      ),
      pw.Text(nilai, style: const pw.TextStyle(fontSize: 9.5)),
    ],
  );
}

/// Kalau jumlah subtotal tidak sama dengan total tersimpan, tampilkan
/// selisihnya terang-terangan. Menyembunyikannya justru bikin nasabah
/// curiga saat menjumlah sendiri dan hasilnya beda.
pw.Widget _buildCatatanSelisih(TransactionRecord tx) {
  final selisih = tx.totalRp - tx.jumlahSubtotal;
  return pw.Text(
    'Catatan: jumlah rincian (${formatRupiah(tx.jumlahSubtotal)}) berbeda '
    '${formatRupiah(selisih.abs())} dari total tercatat. '
    'Silakan konfirmasi ke admin bank sampah.',
    style: const pw.TextStyle(fontSize: 8.5, color: _DocColors.teksRedup),
  );
}

// ---------------------------------------------------------------------------
// Tanda tangan & footer
// ---------------------------------------------------------------------------

pw.Widget _buildTandaTangan(TransactionRecord tx) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      _kolomTandaTangan('Dicatat oleh', tx.adminPencatat),
      _kolomTandaTangan(
        'Nasabah',
        tx.namaNasabah.isEmpty ? '-' : tx.namaNasabah,
      ),
    ],
  );
}

pw.Widget _kolomTandaTangan(String peran, String nama) {
  return pw.SizedBox(
    width: 170,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          peran,
          style: const pw.TextStyle(fontSize: 8, color: _DocColors.teksRedup),
        ),
        pw.SizedBox(height: 34),
        pw.Container(
          width: 150,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: _DocColors.garis, width: 0.5),
            ),
          ),
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(nama, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );
}

pw.Widget _buildFooter(pw.Context context) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 14),
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: _DocColors.garis, width: 0.5),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Dokumen ini dibuat otomatis oleh aplikasi Resik For School.',
          style: const pw.TextStyle(
            fontSize: 8,
            color: _DocColors.teksRedup,
          ),
        ),
        pw.Text(
          'Halaman ${context.pageNumber} dari ${context.pagesCount}',
          style: const pw.TextStyle(
            fontSize: 8,
            color: _DocColors.teksRedup,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _judulSeksi(String teks) {
  return pw.Text(
    teks,
    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
  );
}

pw.Widget _kosong(String teks) {
  return pw.Text(
    teks,
    style: const pw.TextStyle(fontSize: 9.5, color: _DocColors.teksRedup),
  );
}
