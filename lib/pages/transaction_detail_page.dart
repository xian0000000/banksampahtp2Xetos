// Halaman detail transaksi. Sebelumnya widget ini tinggal di dalam
// transaction_pdf.dart — file yang namanya soal PDF tapi isinya separuh UI.
// Sekarang dipisah: halaman ini cuma menampilkan data dan memanggil satu
// fungsi ekspor.
//
// Susunan blok di sini sengaja dibikin sama dengan susunan di PDF (identitas
// -> rincian bersubtotal -> total), supaya yang dilihat nasabah di layar
// sama dengan yang dia dapat saat file-nya dibagikan.

import 'package:flutter/material.dart';

import '../models/transaction_record.dart';
import '../pdf/transaction_pdf_export.dart';
import '../utils/app_colors.dart';
import '../utils/formatters.dart';

class TransactionDetailPage extends StatelessWidget {
  final TransactionRecord tx;

  const TransactionDetailPage({super.key, required this.tx});

  /// Konstruktor praktis untuk pemanggil yang masih memegang map mentah
  /// dari Realtime Database.
  factory TransactionDetailPage.fromMap(
    Map<dynamic, dynamic> raw, {
    String? txId,
    String namaNasabah = '',
    String kelasNasabah = '',
  }) {
    return TransactionDetailPage(
      tx: TransactionRecord.fromMap(
        raw,
        txId: txId,
        namaNasabah: namaNasabah,
        kelasNasabah: kelasNasabah,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.latar,
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Bagikan bukti PDF',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => exportTransactionPdf(context: context, tx: tx),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          _buildRingkasan(),
          const SizedBox(height: 14),
          _buildIdentitas(),
          if (!tx.isTarik) ...[
            const SizedBox(height: 14),
            _buildRincian(),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.hijau,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => exportTransactionPdf(context: context, tx: tx),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Bagikan bukti sebagai PDF'),
          ),
        ],
      ),
    );
  }

  Widget _buildRingkasan() {
    final positif = tx.isSetor;
    return _kartu(
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: (positif ? Colors.green : Colors.red)
                .withValues(alpha: 0.1),
            child: Icon(
              positif
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: positif ? Colors.green : Colors.red,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tx.labelJenis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            formatTanggalJam(tx.tanggal),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Text(
            '${positif ? '+' : '-'} ${formatRupiah(tx.totalRp)}',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: positif ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentitas() {
    return _kartu(
      judul: 'Informasi',
      child: Column(
        children: [
          if (tx.namaNasabah.isNotEmpty)
            _baris('Nasabah', tx.namaNasabah),
          if (tx.kelasNasabah.isNotEmpty)
            _baris('Kelas', tx.kelasNasabah),
          _baris('Tanggal', formatTanggalJam(tx.tanggal)),
          _baris('Jenis', tx.labelJenis),
          _baris('Dicatat oleh', tx.adminPencatat),
          if (tx.id != null) _baris('ID transaksi', tx.id!),
        ],
      ),
    );
  }

  Widget _buildRincian() {
    if (tx.items.isEmpty) {
      return _kartu(
        judul: 'Rincian sampah',
        child: Text(
          'Tidak ada rincian kategori pada transaksi ini.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }

    return _kartu(
      judul: 'Rincian sampah',
      child: Column(
        children: [
          for (final item in tx.items) _barisItem(item),
          const Divider(height: 22),
          _baris('Total berat', formatKg(tx.totalBeratKg)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Total diterima',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  formatRupiah(tx.totalRp),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.hijau,
                  ),
                ),
              ],
            ),
          ),
          if (tx.totalTidakCocok)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Jumlah rincian berbeda dari total tercatat. '
                'Silakan konfirmasi ke admin bank sampah.',
                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
    );
  }

  /// Satu baris rincian: kategori di kiri dengan keterangan berat x harga
  /// di bawahnya, subtotal rata kanan — bentuk yang sama dengan tabel di PDF
  /// supaya nasabah bisa menjumlah sendiri.
  Widget _barisItem(TransactionItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.kategori,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatKg(item.beratKg)} × '
                  '${formatRupiah(item.hargaPerKg)}/kg',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              formatRupiah(item.subtotalRp),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baris(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              nilai,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartu({String? judul, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (judul != null) ...[
            Text(
              judul,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
          ],
          child,
        ],
      ),
    );
  }
}
