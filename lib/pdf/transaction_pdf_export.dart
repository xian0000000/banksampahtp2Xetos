// Lapisan ekspor: satu-satunya tempat yang tahu soal platform (share sheet
// vs simpan file) dan satu-satunya yang menyentuh BuildContext/SnackBar.
// Penyusunan dokumennya sendiri ada di transaction_pdf_builder.dart.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/transaction_record.dart';
import '../share_or_download_helper.dart';
import '../utils/formatters.dart';
import 'transaction_pdf_builder.dart';

const String _logoAsset = 'assets/images/logo.png';

// Logo dibaca sekali lalu disimpan — halaman detail bisa dibuka berkali-kali
// dan tidak ada gunanya membaca ulang aset yang sama dari bundle.
Uint8List? _logoCache;
bool _logoGagalDimuat = false;

Future<Uint8List?> _muatLogo() async {
  if (_logoCache != null || _logoGagalDimuat) return _logoCache;
  try {
    final data = await rootBundle.load(_logoAsset);
    _logoCache = data.buffer.asUint8List();
  } catch (_) {
    // Logo cuma hiasan header — kalau asetnya hilang, PDF tetap harus jadi.
    _logoGagalDimuat = true;
  }
  return _logoCache;
}

/// Susun PDF bukti transaksi lalu bagikan (web di HP) atau simpan ke
/// penyimpanan publik (platform lain).
Future<void> exportTransactionPdf({
  required BuildContext context,
  required TransactionRecord tx,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  Uint8List bytes;
  try {
    bytes = await buildTransactionPdf(tx, logoBytes: await _muatLogo());
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyusun PDF: $e')),
      );
    }
    return;
  }

  final fileName = _namaFile(tx);

  // Di browser HP yang mendukung Web Share API dengan lampiran file
  // (Android Chrome, iOS Safari), buka share sheet asli supaya nasabah
  // tidak perlu mencari file di folder Download. Kalau tidak didukung
  // (browser desktop, atau app native), jatuh ke penyimpanan file biasa.
  if (canShareFile(bytes, fileName, mimeType: 'application/pdf')) {
    final shared = await shareFile(
      bytes,
      fileName,
      mimeType: 'application/pdf',
      title: 'Bukti transaksi',
      text: '${tx.labelJenis} — ${formatTanggal(tx.tanggal)}',
    );
    if (shared && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bukti transaksi berhasil dibagikan.')),
      );
    }
    // shared == false berarti user menutup share sheet tanpa memilih apa
    // pun. Sengaja tidak fallback ke simpan file: aneh kalau file tiba-tiba
    // terunduh padahal barusan dibatalkan.
    return;
  }

  try {
    final saved = await downloadFileBytes(
      bytes,
      fileName,
      mimeType: 'application/pdf',
    );
    if (!saved) throw Exception('unduhan ditolak browser');
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bukti transaksi berhasil disimpan.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan PDF: $e')),
      );
    }
  }
}

/// Nama file yang informatif saat mendarat di folder Download atau
/// terkirim lewat WhatsApp: jenis, nama nasabah, dan tanggal.
String _namaFile(TransactionRecord tx) {
  final jenis = tx.isSetor ? 'setor' : (tx.isTarik ? 'penarikan' : 'transaksi');
  final tanggal = tx.tanggal == null
      ? DateTime.now().millisecondsSinceEpoch.toString()
      : '${tx.tanggal!.year}${_dua(tx.tanggal!.month)}${_dua(tx.tanggal!.day)}';
  final nama = _amankan(
    tx.namaNasabah.isEmpty ? (tx.id ?? 'nasabah') : tx.namaNasabah,
  );
  return 'bukti-$jenis-$nama-$tanggal.pdf';
}

String _amankan(String teks) {
  final bersih = teks
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  return bersih.isEmpty ? 'nasabah' : bersih;
}

String _dua(int n) => n.toString().padLeft(2, '0');
